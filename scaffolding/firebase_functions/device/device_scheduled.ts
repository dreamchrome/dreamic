/**
 * Optional scheduled functions for DeviceService operations.
 *
 * These are templates for common scheduled tasks that consuming apps
 * can adapt to their needs. They are NOT exported by default.
 *
 * @packageVersion dreamic ^0.4.0
 * @description Optional scheduled function templates for DeviceService
 *
 * ## Usage
 *
 * To use these templates:
 * 1. Copy the functions you need to your project
 * 2. Customize the logic for your specific requirements
 * 3. Export them from your main index.ts
 *
 * ## Required Indexes
 *
 * The scheduled functions require these Firestore indexes:
 *
 * - Collection group index on `devices`:
 *   - `timezoneOffsetMinutes` (ASC) + `lastActiveAt` (ASC)
 *   - For time-window queries
 *
 * - Collection on `users/{uid}/devices`:
 *   - `lastActiveAt` (ASC)
 *   - For stale device cleanup
 */

import { onSchedule } from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";
import {
  getDevicesInLocalTimeWindow,
  groupByUserMostRecentDevice,
  LocalTimeTarget,
} from "./device_time_queries";

/**
 * Example: Send morning reminder notifications at 9:00 AM local time.
 *
 * This runs every 15 minutes and finds devices where it's approximately
 * 9:00 AM in their local timezone.
 *
 * **Customize this function for your specific notification needs.**
 *
 * @example Export in your index.ts:
 * ```typescript
 * export { sendMorningNotifications } from "./device/device_scheduled";
 * ```
 */
export const sendMorningNotifications = onSchedule(
  {
    // Run every 15 minutes
    schedule: "every 15 minutes",
    // Recommended: Set appropriate timeout and memory
    timeoutSeconds: 540, // 9 minutes
    memory: "512MiB",
    // Optional: Set region
    // region: "us-central1",
  },
  async () => {
    const db = admin.firestore();

    // Target time: 9:00 AM local
    const target: LocalTimeTarget = { hour: 9, minute: 0 };

    // Find devices where it's approximately 9 AM
    const devices = await getDevicesInLocalTimeWindow(db, target, {
      windowMinutes: 7, // +/- 7 minutes (covers 15-min schedule interval)
      requireToken: true, // Only devices with push tokens
      activeWithinDays: 60, // Only recently active devices
    });

    if (devices.length === 0) {
      console.log("No eligible devices for morning notification");
      return;
    }

    console.log(`Found ${devices.length} eligible devices`);

    // Group by user and get most recently active device per user
    const userDevices = groupByUserMostRecentDevice(devices);

    console.log(`Sending notifications to ${userDevices.size} users`);

    // Send notifications
    const messaging = admin.messaging();
    const results = { success: 0, failed: 0 };

    for (const [uid, device] of userDevices) {
      if (!device.fcmToken) {
        continue;
      }

      try {
        await messaging.send({
          token: device.fcmToken,
          notification: {
            title: "Good Morning!",
            body: "Start your day with a quick check-in.",
          },
          data: {
            type: "morning_reminder",
            userId: uid,
            deviceId: device.deviceId,
          },
          // Platform-specific options
          android: {
            priority: "high",
          },
          apns: {
            headers: {
              "apns-priority": "10",
            },
          },
        });
        results.success++;
      } catch (error) {
        console.error(`Failed to send to ${uid}/${device.deviceId}:`, error);
        results.failed++;

        // Optional: Handle invalid tokens by clearing them
        // if (isInvalidTokenError(error)) {
        //   await clearInvalidToken(device);
        // }
      }
    }

    console.log(
      `Morning notifications complete: ${results.success} sent, ${results.failed} failed`
    );
  }
);

/**
 * Example: Clean up stale device documents.
 *
 * Removes devices that haven't been active in the configured number of days.
 * Default is 90 days, but this should be adjusted based on your app's usage patterns.
 *
 * **Important:** This is a destructive operation. Test thoroughly before deploying.
 *
 * @example Export in your index.ts:
 * ```typescript
 * export { cleanupStaleDevices } from "./device/device_scheduled";
 * ```
 */
export const cleanupStaleDevices = onSchedule(
  {
    // Run daily at 3:00 AM UTC
    schedule: "0 3 * * *",
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async () => {
    const db = admin.firestore();

    // Configure staleness threshold (90 days by default)
    const staleDays = 90;
    const cutoffDate = new Date();
    cutoffDate.setDate(cutoffDate.getDate() - staleDays);

    console.log(
      `Cleaning up devices not active since: ${cutoffDate.toISOString()}`
    );

    // Query stale devices using collection group
    // NOTE: This requires an index on lastActiveAt
    const staleDevices = await db
      .collectionGroup("devices")
      .where(
        "lastActiveAt",
        "<",
        admin.firestore.Timestamp.fromDate(cutoffDate)
      )
      .limit(500) // Process in batches to avoid timeouts
      .get();

    if (staleDevices.empty) {
      console.log("No stale devices to clean up");
      return;
    }

    console.log(`Found ${staleDevices.size} stale devices to delete`);

    // Delete in batches of 500 (Firestore batch limit)
    const batch = db.batch();
    let deleteCount = 0;

    for (const doc of staleDevices.docs) {
      batch.delete(doc.ref);
      deleteCount++;
    }

    await batch.commit();

    console.log(`Deleted ${deleteCount} stale device documents`);

    // If we hit the limit, there may be more to clean up
    // The next run will handle them
    if (staleDevices.size === 500) {
      console.log(
        "More stale devices may exist; they will be cleaned up in the next run"
      );
    }
  }
);

/**
 * Example: Weekly device activity report.
 *
 * Generates a summary of device activity for monitoring and analytics.
 * Results can be written to a Firestore collection, sent via email, etc.
 *
 * @example Export in your index.ts:
 * ```typescript
 * export { weeklyDeviceReport } from "./device/device_scheduled";
 * ```
 */
export const weeklyDeviceReport = onSchedule(
  {
    // Run every Monday at 6:00 AM UTC
    schedule: "0 6 * * 1",
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async () => {
    const db = admin.firestore();

    // Calculate date ranges
    const now = new Date();
    const weekAgo = new Date(now);
    weekAgo.setDate(weekAgo.getDate() - 7);

    // Count active devices by platform
    const activeDevicesSnapshot = await db
      .collectionGroup("devices")
      .where(
        "lastActiveAt",
        ">=",
        admin.firestore.Timestamp.fromDate(weekAgo)
      )
      .get();

    const platformCounts: Record<string, number> = {
      ios: 0,
      android: 0,
      web: 0,
      macos: 0,
      windows: 0,
      linux: 0,
      unknown: 0,
    };

    const uniqueUsers = new Set<string>();

    for (const doc of activeDevicesSnapshot.docs) {
      const data = doc.data();
      const platform = data.platform || "unknown";

      if (platform in platformCounts) {
        platformCounts[platform]++;
      } else {
        platformCounts.unknown++;
      }

      // Extract uid from path: users/{uid}/devices/{deviceId}
      const pathParts = doc.ref.path.split("/");
      if (pathParts.length >= 2) {
        uniqueUsers.add(pathParts[1]);
      }
    }

    const report = {
      generatedAt: admin.firestore.Timestamp.now(),
      periodStart: admin.firestore.Timestamp.fromDate(weekAgo),
      periodEnd: admin.firestore.Timestamp.fromDate(now),
      totalActiveDevices: activeDevicesSnapshot.size,
      uniqueActiveUsers: uniqueUsers.size,
      devicesByPlatform: platformCounts,
    };

    console.log("Weekly device report:", JSON.stringify(report, null, 2));

    // Optional: Write report to Firestore
    await db.collection("analytics/devices/weekly_reports").add(report);

    console.log("Weekly device report saved");
  }
);
