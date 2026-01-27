/**
 * Device time-window query utilities for DeviceService backend scheduling.
 *
 * This module provides DST-safe time-window queries for scheduled notifications.
 * It's the single source of truth for all "send at X:XX local time" logic.
 *
 * @packageVersion dreamic ^0.4.0
 * @description Time-window query utilities for device-based scheduling
 *
 * ## Key Concepts
 *
 * **Candidate vs Authoritative checks:**
 * - `queryDeviceCandidatesByLocalTime()` uses `timezoneOffsetMinutes` (cached, may be stale)
 *   to efficiently query Firestore. It intentionally over-fetches to handle DST staleness.
 * - `isNowInLocalTimeWindow()` uses the IANA `timezone` string to compute the
 *   authoritative local time. This is the final gate before sending.
 *
 * **Why this two-stage approach?**
 * - Firestore can't query by computed values, so we use the cached offset for indexing.
 * - If a device's offset is stale (e.g., DST changed but app wasn't opened), the
 *   candidate query's buffer ensures we still fetch it.
 * - The authoritative check prevents sending at the wrong time.
 */

import * as admin from "firebase-admin";
import {
  getLocalMinutesOfDay,
  isValidIanaTimezone,
} from "./timezone_utils";

/**
 * Target local time specification (hour and minute).
 */
export interface LocalTimeTarget {
  /** Target hour (0-23) */
  hour: number;
  /** Target minute (0-59) */
  minute: number;
}

/**
 * Options for local time window queries.
 */
export interface LocalTimeWindowQueryOptions {
  /** UTC instant to use for calculations (defaults to now) */
  nowUtc?: Date;
  /** Window size in minutes on each side of target (e.g., 15 = +/- 15 min) */
  windowMinutes: number;
  /** Buffer for stale offset data due to DST (defaults to 60 minutes) */
  offsetQueryBufferMinutes?: number;
  /** Optional platform filter */
  platforms?: Array<"ios" | "android" | "web" | "macos" | "windows" | "linux">;
  /** Optional: only include devices active within this many days (defaults to 60) */
  activeWithinDays?: number;
  /** Optional: require non-null fcmToken */
  requireToken?: boolean;
}

/**
 * Minimal device document shape returned from queries.
 *
 * The actual Firestore documents may contain additional fields;
 * this represents what the query utilities need.
 */
export interface DeviceDoc {
  /** User ID (from document path) */
  uid: string;
  /** Device ID (document ID) */
  deviceId: string;
  /** IANA timezone identifier (source of truth) */
  timezone: string;
  /** Cached timezone offset in minutes */
  timezoneOffsetMinutes?: number;
  /** Device platform */
  platform?: string;
  /** Last activity timestamp */
  lastActiveAt?: admin.firestore.Timestamp;
  /** FCM push token (nullable) */
  fcmToken?: string | null;
}

/**
 * Represents a computed offset range for Firestore querying.
 *
 * Due to midnight wrap-around, a single time window may require
 * two offset ranges (before and after midnight).
 */
interface OffsetRange {
  min: number;
  max: number;
}

/**
 * Minutes in a day (24 * 60).
 */
const MINUTES_PER_DAY = 1440;

/**
 * Computes the offset ranges needed to query devices whose local time
 * might be within the target window.
 *
 * @param target - Target local time (hour:minute)
 * @param nowUtc - Current UTC time
 * @param windowMinutes - Window size (+/- this many minutes from target)
 * @param bufferMinutes - Additional buffer for stale offsets (DST safety)
 * @returns Array of 1-2 offset ranges to query
 *
 * @internal
 */
function computeOffsetRanges(
  target: LocalTimeTarget,
  nowUtc: Date,
  windowMinutes: number,
  bufferMinutes: number
): OffsetRange[] {
  // Current UTC minutes-of-day
  const utcMinutes = nowUtc.getUTCHours() * 60 + nowUtc.getUTCMinutes();

  // Target local minutes-of-day
  const targetMinutes = target.hour * 60 + target.minute;

  // Total window including buffer (on each side)
  const totalWindow = windowMinutes + bufferMinutes;

  // We want devices where:
  //   local_time is within [targetMinutes - totalWindow, targetMinutes + totalWindow]
  //
  // Since local_time = (utc_time + offset) mod 1440
  // We solve for offset: offset = (local_time - utc_time) mod 1440
  //
  // The offset range is:
  //   [(targetMinutes - totalWindow - utcMinutes), (targetMinutes + totalWindow - utcMinutes)]
  // normalized to the valid offset range.

  const windowStart = targetMinutes - totalWindow;
  const windowEnd = targetMinutes + totalWindow;

  // Compute the raw offset range
  const offsetMin = windowStart - utcMinutes;
  const offsetMax = windowEnd - utcMinutes;

  // Real-world offsets range from -840 (UTC-14) to +840 (UTC+14)
  const MIN_OFFSET = -840;
  const MAX_OFFSET = 840;

  // Clamp and potentially split the range
  const ranges: OffsetRange[] = [];

  // The computed offsets may need day-wrapping adjustment
  // For simplicity, we handle the common case where the range
  // doesn't need wrapping (fits within valid offset bounds)
  if (offsetMin >= MIN_OFFSET && offsetMax <= MAX_OFFSET) {
    ranges.push({ min: offsetMin, max: offsetMax });
  } else if (offsetMax > MAX_OFFSET && offsetMin < MIN_OFFSET) {
    // Range spans the entire valid offset space - query everything
    ranges.push({ min: MIN_OFFSET, max: MAX_OFFSET });
  } else if (offsetMax > MAX_OFFSET) {
    // Range wraps on the high end
    // This can happen near midnight when targeting late hours
    // Split: [offsetMin, MAX_OFFSET] and [MIN_OFFSET, adjusted]
    ranges.push({ min: Math.max(offsetMin, MIN_OFFSET), max: MAX_OFFSET });
    const overflow = offsetMax - MAX_OFFSET;
    // The overflow represents devices in early UTC+ zones
    // For safety, include a range at the low end
    if (MIN_OFFSET + overflow <= MAX_OFFSET) {
      ranges.push({ min: MIN_OFFSET, max: MIN_OFFSET + overflow });
    }
  } else if (offsetMin < MIN_OFFSET) {
    // Range wraps on the low end
    ranges.push({ min: MIN_OFFSET, max: Math.min(offsetMax, MAX_OFFSET) });
    const underflow = MIN_OFFSET - offsetMin;
    if (MAX_OFFSET - underflow >= MIN_OFFSET) {
      ranges.push({ min: MAX_OFFSET - underflow, max: MAX_OFFSET });
    }
  }

  return ranges.length > 0
    ? ranges
    : [{ min: MIN_OFFSET, max: MAX_OFFSET }]; // Fallback: query all
}

/**
 * Queries Firestore for device documents that are *candidates* for being
 * within the target local time window.
 *
 * **IMPORTANT:** This query uses cached `timezoneOffsetMinutes` which may be
 * stale due to DST transitions. The `offsetQueryBufferMinutes` parameter widens
 * the query to catch devices with stale offsets.
 *
 * **After calling this function, you MUST filter the results using
 * `isNowInLocalTimeWindow()` with each device's IANA timezone.**
 *
 * @param firestore - Firestore instance
 * @param target - Target local time (e.g., { hour: 9, minute: 0 } for 9:00 AM)
 * @param options - Query options including window size and filters
 * @returns Promise resolving to array of candidate device documents
 *
 * @example
 * ```typescript
 * // Find devices where it's approximately 9:00 AM local time
 * const candidates = await queryDeviceCandidatesByLocalTime(
 *   admin.firestore(),
 *   { hour: 9, minute: 0 },
 *   { windowMinutes: 15 }
 * );
 *
 * // Filter to authoritative matches
 * const nowUtc = new Date();
 * const eligible = candidates.filter(device =>
 *   isNowInLocalTimeWindow(device.timezone, { hour: 9, minute: 0 }, nowUtc, 15)
 * );
 * ```
 */
export async function queryDeviceCandidatesByLocalTime(
  firestore: admin.firestore.Firestore,
  target: LocalTimeTarget,
  options: LocalTimeWindowQueryOptions
): Promise<DeviceDoc[]> {
  const nowUtc = options.nowUtc ?? new Date();
  const bufferMinutes = options.offsetQueryBufferMinutes ?? 60;
  const activeWithinDays = options.activeWithinDays ?? 60;

  // Validate target
  if (
    target.hour < 0 ||
    target.hour > 23 ||
    target.minute < 0 ||
    target.minute > 59
  ) {
    throw new Error(
      `Invalid target time: ${target.hour}:${target.minute}. ` +
        `Hour must be 0-23, minute must be 0-59.`
    );
  }

  // Compute offset ranges
  const offsetRanges = computeOffsetRanges(
    target,
    nowUtc,
    options.windowMinutes,
    bufferMinutes
  );

  // Calculate the active window cutoff
  const activeWindowCutoff = new Date(nowUtc);
  activeWindowCutoff.setDate(activeWindowCutoff.getDate() - activeWithinDays);

  const results: DeviceDoc[] = [];

  // Execute queries for each offset range
  for (const range of offsetRanges) {
    let query = firestore
      .collectionGroup("devices")
      .where("timezoneOffsetMinutes", ">=", range.min)
      .where("timezoneOffsetMinutes", "<=", range.max);

    // Apply lastActiveAt filter for active window
    query = query.where(
      "lastActiveAt",
      ">=",
      admin.firestore.Timestamp.fromDate(activeWindowCutoff)
    );

    // Note: Additional filters like platform or fcmToken require composite indexes.
    // We apply these filters in-memory after fetching to avoid index complexity.

    const snapshot = await query.get();

    for (const doc of snapshot.docs) {
      const data = doc.data();

      // Extract uid from document path: users/{uid}/devices/{deviceId}
      const pathParts = doc.ref.path.split("/");
      const uid = pathParts[1];
      const deviceId = doc.id;

      // Apply platform filter if specified
      if (
        options.platforms &&
        options.platforms.length > 0 &&
        !options.platforms.includes(data.platform)
      ) {
        continue;
      }

      // Apply token filter if specified
      if (options.requireToken && !data.fcmToken) {
        continue;
      }

      results.push({
        uid,
        deviceId,
        timezone: data.timezone,
        timezoneOffsetMinutes: data.timezoneOffsetMinutes,
        platform: data.platform,
        lastActiveAt: data.lastActiveAt,
        fcmToken: data.fcmToken,
      });
    }
  }

  // Deduplicate in case offset ranges overlap
  const seen = new Set<string>();
  return results.filter((device) => {
    const key = `${device.uid}/${device.deviceId}`;
    if (seen.has(key)) {
      return false;
    }
    seen.add(key);
    return true;
  });
}

/**
 * Authoritative check: determines if the current UTC instant falls within
 * the target local time window for a given timezone.
 *
 * This uses the IANA timezone string (not cached offset) to compute the
 * exact local time, ensuring DST transitions are handled correctly.
 *
 * **This is the final gate before sending a notification.**
 *
 * @param timezone - IANA timezone identifier (e.g., "America/New_York")
 * @param target - Target local time
 * @param nowUtc - Current UTC instant
 * @param windowMinutes - Window size (+/- this many minutes from target)
 * @returns true if the local time is within the window, false otherwise
 *
 * @example
 * ```typescript
 * // Check if it's 9:00 AM +/- 15 minutes in New York
 * const eligible = isNowInLocalTimeWindow(
 *   "America/New_York",
 *   { hour: 9, minute: 0 },
 *   new Date(),
 *   15
 * );
 * ```
 */
export function isNowInLocalTimeWindow(
  timezone: string,
  target: LocalTimeTarget,
  nowUtc: Date,
  windowMinutes: number
): boolean {
  // Validate timezone first
  if (!isValidIanaTimezone(timezone)) {
    // Invalid timezone - cannot determine local time, skip this device
    console.warn(
      `isNowInLocalTimeWindow: Invalid timezone "${timezone}", returning false`
    );
    return false;
  }

  // Get actual local minutes using authoritative timezone
  let localNow: number;
  try {
    localNow = getLocalMinutesOfDay(timezone, nowUtc);
  } catch {
    // Should not happen if isValidIanaTimezone passed, but be defensive
    console.error(
      `isNowInLocalTimeWindow: Failed to compute local time for "${timezone}"`
    );
    return false;
  }

  const targetMinutes = target.hour * 60 + target.minute;

  // Calculate circular distance on a 24-hour clock
  // This handles midnight wrap correctly (e.g., 23:50 to 00:10 is a 20-minute window)
  const diff = Math.abs(localNow - targetMinutes);
  const circularDiff = Math.min(diff, MINUTES_PER_DAY - diff);

  return circularDiff <= windowMinutes;
}

/**
 * Convenience function that queries candidates and filters to authoritative matches.
 *
 * This is the recommended function for most scheduling use cases as it handles
 * both the efficient Firestore query and the authoritative filtering.
 *
 * @param firestore - Firestore instance
 * @param target - Target local time
 * @param options - Query options
 * @returns Promise resolving to array of verified eligible devices
 *
 * @example
 * ```typescript
 * // Get all devices where it's 9:00 AM +/- 15 minutes
 * const devices = await getDevicesInLocalTimeWindow(
 *   admin.firestore(),
 *   { hour: 9, minute: 0 },
 *   {
 *     windowMinutes: 15,
 *     requireToken: true, // Only devices with push tokens
 *   }
 * );
 *
 * // Send notifications to these devices
 * for (const device of devices) {
 *   await sendNotification(device.fcmToken!, ...);
 * }
 * ```
 */
export async function getDevicesInLocalTimeWindow(
  firestore: admin.firestore.Firestore,
  target: LocalTimeTarget,
  options: LocalTimeWindowQueryOptions
): Promise<DeviceDoc[]> {
  const nowUtc = options.nowUtc ?? new Date();

  // Get candidates using offset-based query
  const candidates = await queryDeviceCandidatesByLocalTime(
    firestore,
    target,
    options
  );

  // Filter to authoritative matches using IANA timezone
  return candidates.filter((device) =>
    isNowInLocalTimeWindow(
      device.timezone,
      target,
      nowUtc,
      options.windowMinutes
    )
  );
}

/**
 * Groups devices by user ID, returning the most recently active device per user.
 *
 * Useful for "send to most active device" delivery patterns.
 *
 * @param devices - Array of device documents
 * @returns Map of uid to most recently active device
 */
export function groupByUserMostRecentDevice(
  devices: DeviceDoc[]
): Map<string, DeviceDoc> {
  const userDevices = new Map<string, DeviceDoc>();

  for (const device of devices) {
    const existing = userDevices.get(device.uid);

    if (!existing) {
      userDevices.set(device.uid, device);
      continue;
    }

    // Compare lastActiveAt timestamps
    const existingTime = existing.lastActiveAt?.toMillis() ?? 0;
    const deviceTime = device.lastActiveAt?.toMillis() ?? 0;

    if (deviceTime > existingTime) {
      userDevices.set(device.uid, device);
    }
  }

  return userDevices;
}

/**
 * Groups devices by user ID, returning all devices per user.
 *
 * Useful for "send to all devices" delivery patterns.
 *
 * @param devices - Array of device documents
 * @returns Map of uid to array of devices
 */
export function groupByUserAllDevices(
  devices: DeviceDoc[]
): Map<string, DeviceDoc[]> {
  const userDevices = new Map<string, DeviceDoc[]>();

  for (const device of devices) {
    const existing = userDevices.get(device.uid) ?? [];
    existing.push(device);
    userDevices.set(device.uid, existing);
  }

  return userDevices;
}
