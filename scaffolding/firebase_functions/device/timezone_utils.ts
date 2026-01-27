/**
 * Timezone utilities for DeviceService backend operations.
 *
 * This module provides DST-safe timezone handling for device scheduling.
 * Uses Luxon for reliable IANA timezone support.
 *
 * @packageVersion dreamic ^0.4.0
 * @description Timezone utilities for DeviceService backend
 *
 * ## Installation
 * ```bash
 * npm install luxon
 * npm install -D @types/luxon
 * ```
 */

import { DateTime } from "luxon";

/**
 * Validates that a string is a valid IANA timezone identifier.
 *
 * Uses Luxon's timezone validation which properly handles all IANA zones
 * including edge cases like "America/Indiana/Knox".
 *
 * @param timezone - The timezone string to validate (e.g., "America/New_York")
 * @returns true if the timezone is valid, false otherwise
 *
 * @example
 * ```typescript
 * isValidIanaTimezone("America/New_York") // true
 * isValidIanaTimezone("Invalid/Zone") // false
 * isValidIanaTimezone("UTC") // true
 * isValidIanaTimezone("Asia/Kolkata") // true (India, +5:30)
 * isValidIanaTimezone("Asia/Kathmandu") // true (Nepal, +5:45)
 * ```
 */
export function isValidIanaTimezone(timezone: string): boolean {
  if (!timezone || typeof timezone !== "string") {
    return false;
  }

  // Luxon returns an invalid DateTime for unknown zones
  const dt = DateTime.utc().setZone(timezone);
  return dt.isValid;
}

/**
 * Gets the UTC offset in minutes for a given IANA timezone at a specific UTC instant.
 *
 * This is DST-safe: the offset is computed for the exact moment specified,
 * correctly accounting for any DST rules in effect at that time.
 *
 * @param timezone - Valid IANA timezone identifier
 * @param nowUtc - The UTC instant to compute the offset for
 * @returns The offset from UTC in minutes (positive = east of UTC, negative = west)
 * @throws Error if the timezone is invalid
 *
 * @example
 * ```typescript
 * // During EST (standard time)
 * getOffsetMinutesAtUtcInstant("America/New_York", new Date("2024-01-15T12:00:00Z"))
 * // Returns: -300 (UTC-5)
 *
 * // During EDT (daylight saving time)
 * getOffsetMinutesAtUtcInstant("America/New_York", new Date("2024-06-15T12:00:00Z"))
 * // Returns: -240 (UTC-4)
 *
 * // Half-hour offset (India)
 * getOffsetMinutesAtUtcInstant("Asia/Kolkata", new Date("2024-01-15T12:00:00Z"))
 * // Returns: 330 (UTC+5:30)
 *
 * // 45-minute offset (Nepal)
 * getOffsetMinutesAtUtcInstant("Asia/Kathmandu", new Date("2024-01-15T12:00:00Z"))
 * // Returns: 345 (UTC+5:45)
 * ```
 */
export function getOffsetMinutesAtUtcInstant(
  timezone: string,
  nowUtc: Date
): number {
  const dt = DateTime.fromJSDate(nowUtc, { zone: "utc" }).setZone(timezone);

  if (!dt.isValid) {
    throw new Error(`Invalid timezone: ${timezone}`);
  }

  return dt.offset; // Luxon's offset is already in minutes
}

/**
 * Gets the local time as minutes-of-day (0-1439) for a given timezone at a UTC instant.
 *
 * This is the foundational function for time-window scheduling: it converts
 * a UTC instant to "what time is it locally" expressed as total minutes since midnight.
 *
 * @param timezone - Valid IANA timezone identifier
 * @param nowUtc - The UTC instant to convert
 * @returns Minutes since local midnight (0-1439)
 * @throws Error if the timezone is invalid
 *
 * @example
 * ```typescript
 * // If it's 9:30 AM local time
 * getLocalMinutesOfDay("America/New_York", someUtcDate)
 * // Returns: 570 (9 * 60 + 30)
 *
 * // If it's 11:45 PM local time
 * getLocalMinutesOfDay("Europe/London", someUtcDate)
 * // Returns: 1425 (23 * 60 + 45)
 * ```
 */
export function getLocalMinutesOfDay(timezone: string, nowUtc: Date): number {
  const dt = DateTime.fromJSDate(nowUtc, { zone: "utc" }).setZone(timezone);

  if (!dt.isValid) {
    throw new Error(`Invalid timezone: ${timezone}`);
  }

  return dt.hour * 60 + dt.minute;
}

/**
 * Gets the current local hour (0-23) in a given timezone.
 *
 * Convenience function for simple hour-based scheduling.
 *
 * @param timezone - Valid IANA timezone identifier
 * @param nowUtc - The UTC instant to convert (defaults to now)
 * @returns The local hour (0-23)
 * @throws Error if the timezone is invalid
 */
export function getLocalHour(
  timezone: string,
  nowUtc: Date = new Date()
): number {
  const dt = DateTime.fromJSDate(nowUtc, { zone: "utc" }).setZone(timezone);

  if (!dt.isValid) {
    throw new Error(`Invalid timezone: ${timezone}`);
  }

  return dt.hour;
}

/**
 * Checks if a given hour is currently occurring in a timezone.
 *
 * @param hour - The target hour (0-23)
 * @param timezone - Valid IANA timezone identifier
 * @param nowUtc - The UTC instant to check (defaults to now)
 * @returns true if the local hour matches the target hour
 */
export function isHourInTimezone(
  hour: number,
  timezone: string,
  nowUtc: Date = new Date()
): boolean {
  if (hour < 0 || hour > 23 || !Number.isInteger(hour)) {
    return false;
  }

  try {
    return getLocalHour(timezone, nowUtc) === hour;
  } catch {
    return false;
  }
}

/**
 * Converts a local time in a specific timezone to a UTC Date.
 *
 * Useful for scheduling: "I want to do something at 9am in this user's timezone."
 *
 * @param hour - Local hour (0-23)
 * @param minute - Local minute (0-59)
 * @param timezone - Valid IANA timezone identifier
 * @param referenceDate - Reference date for the conversion (defaults to today)
 * @returns The UTC Date representing that local time
 * @throws Error if the timezone is invalid or time components are out of range
 */
export function localTimeToUtc(
  hour: number,
  minute: number,
  timezone: string,
  referenceDate: Date = new Date()
): Date {
  if (hour < 0 || hour > 23 || !Number.isInteger(hour)) {
    throw new Error(`Invalid hour: ${hour}. Must be 0-23.`);
  }
  if (minute < 0 || minute > 59 || !Number.isInteger(minute)) {
    throw new Error(`Invalid minute: ${minute}. Must be 0-59.`);
  }

  // Get the date components in the target timezone
  const refDt = DateTime.fromJSDate(referenceDate, { zone: "utc" }).setZone(
    timezone
  );

  if (!refDt.isValid) {
    throw new Error(`Invalid timezone: ${timezone}`);
  }

  // Create a DateTime at the target local time
  const localDt = refDt.set({ hour, minute, second: 0, millisecond: 0 });

  // Convert back to UTC
  return localDt.toUTC().toJSDate();
}

/**
 * Type-safe representation of a timezone offset validation result.
 */
export interface OffsetValidationResult {
  /** Whether the offset is valid */
  isValid: boolean;
  /** Error message if invalid */
  error?: string;
}

/**
 * Validates a timezone offset in minutes.
 *
 * Valid offsets range from UTC-14 (-840 minutes) to UTC+14 (+840 minutes).
 * This covers all real-world timezones including:
 * - UTC-12 (Baker Island)
 * - UTC-11 (American Samoa)
 * - UTC+14 (Line Islands, Kiribati)
 *
 * Half-hour (30 min) and quarter-hour (45 min) offsets are valid:
 * - India: UTC+5:30 (+330 minutes)
 * - Nepal: UTC+5:45 (+345 minutes)
 * - Newfoundland: UTC-3:30 (-210 minutes)
 *
 * @param offsetMinutes - The offset to validate
 * @returns Validation result with isValid boolean and optional error message
 */
export function validateOffsetMinutes(
  offsetMinutes: unknown
): OffsetValidationResult {
  if (offsetMinutes === null || offsetMinutes === undefined) {
    return { isValid: false, error: "Offset is required" };
  }

  if (typeof offsetMinutes !== "number") {
    return { isValid: false, error: "Offset must be a number" };
  }

  if (!Number.isFinite(offsetMinutes)) {
    return { isValid: false, error: "Offset must be a finite number" };
  }

  if (!Number.isInteger(offsetMinutes)) {
    return { isValid: false, error: "Offset must be an integer" };
  }

  // Valid range: UTC-14 to UTC+14 (840 minutes = 14 hours)
  const maxOffset = 14 * 60; // +840
  const minOffset = -14 * 60; // -840

  if (offsetMinutes < minOffset || offsetMinutes > maxOffset) {
    return {
      isValid: false,
      error: `Offset must be between ${minOffset} and ${maxOffset} minutes (UTC-14 to UTC+14)`,
    };
  }

  return { isValid: true };
}

/**
 * Formats a timezone offset in minutes to a human-readable string.
 *
 * @param offsetMinutes - The offset in minutes
 * @returns Formatted string like "UTC+5:30" or "UTC-8"
 */
export function formatOffset(offsetMinutes: number): string {
  const sign = offsetMinutes >= 0 ? "+" : "-";
  const absMinutes = Math.abs(offsetMinutes);
  const hours = Math.floor(absMinutes / 60);
  const minutes = absMinutes % 60;

  if (minutes === 0) {
    return `UTC${sign}${hours}`;
  }

  return `UTC${sign}${hours}:${minutes.toString().padStart(2, "0")}`;
}
