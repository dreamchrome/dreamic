/**
 * Optional Firestore triggers for DeviceService.
 *
 * These are templates for common trigger-based tasks that consuming apps
 * can adapt to their needs. They are NOT exported by default.
 *
 * @packageVersion dreamic ^0.4.0
 * @description Optional Firestore trigger templates for DeviceService
 *
 * ## Usage
 *
 * To use these templates:
 * 1. Copy the functions you need to your project
 * 2. Customize the logic for your specific requirements
 * 3. Export them from your main index.ts
 */

import {
  onDocumentCreated,
  onDocumentUpdated,
  onDocumentDeleted,
} from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";

/**
 * Document path pattern for device documents.
 */
const DEVICE_DOC_PATH = "users/{uid}/devices/{deviceId}";

/**
 * Example: Log timezone changes for analytics.
 *
 * Triggered when a device document is updated, this function
 * detects timezone changes and logs them for analytics.
 *
 * Use cases:
 * - Track user travel patterns
 * - Detect potential timezone-related issues
 * - Audit device state changes
 *
 * @example Export in your index.ts:
 * ```typescript
 * export { onDeviceTimezoneChange } from "./device/device_triggers";
 * ```
 */
export const onDeviceTimezoneChange = onDocumentUpdated(
  DEVICE_DOC_PATH,
  async (event) => {
    const beforeData = event.data?.before.data();
    const afterData = event.data?.after.data();

    if (!beforeData || !afterData) {
      console.warn("Missing before or after data in device update");
      return;
    }

    const { uid, deviceId } = event.params;

    // Check if timezone changed
    const oldTimezone = beforeData.timezone;
    const newTimezone = afterData.timezone;

    if (oldTimezone === newTimezone) {
      // No timezone change, nothing to do
      return;
    }

    console.log(
      `Timezone changed for ${uid}/${deviceId}: ${oldTimezone} -> ${newTimezone}`
    );

    // Optional: Log to analytics collection
    const db = admin.firestore();

    await db.collection("analytics/devices/timezone_changes").add({
      uid,
      deviceId,
      oldTimezone,
      newTimezone,
      oldOffset: beforeData.timezoneOffsetMinutes,
      newOffset: afterData.timezoneOffsetMinutes,
      platform: afterData.platform,
      timestamp: admin.firestore.Timestamp.now(),
    });

    // Optional: Trigger downstream processes
    // - Update user's "primary timezone" if this is their main device
    // - Send welcome message for new location
    // - Update any scheduled reminders for this user
  }
);

/**
 * Example: Handle new device registration.
 *
 * Triggered when a new device document is created.
 * Can be used to:
 * - Send welcome push notification to new device
 * - Update user's device count
 * - Trigger first-time setup workflows
 *
 * @example Export in your index.ts:
 * ```typescript
 * export { onDeviceCreated } from "./device/device_triggers";
 * ```
 */
export const onDeviceCreated = onDocumentCreated(
  DEVICE_DOC_PATH,
  async (event) => {
    const data = event.data?.data();

    if (!data) {
      console.warn("No data in created device document");
      return;
    }

    const { uid, deviceId } = event.params;

    console.log(`New device registered: ${uid}/${deviceId}`);
    console.log(`Platform: ${data.platform}, Timezone: ${data.timezone}`);

    // Optional: Count user's devices
    const db = admin.firestore();
    const devicesSnapshot = await db
      .collection(`users/${uid}/devices`)
      .count()
      .get();

    const deviceCount = devicesSnapshot.data().count;

    console.log(`User ${uid} now has ${deviceCount} device(s)`);

    // Optional: Update user document with device count
    // await db.doc(`users/${uid}`).update({
    //   deviceCount,
    //   lastDeviceRegistration: admin.firestore.Timestamp.now(),
    // });

    // Optional: Send welcome notification to the new device
    // if (data.fcmToken) {
    //   await admin.messaging().send({
    //     token: data.fcmToken,
    //     notification: {
    //       title: "Device Registered",
    //       body: "This device is now connected to your account.",
    //     },
    //   });
    // }
  }
);

/**
 * Example: Handle device deletion/unregistration.
 *
 * Triggered when a device document is deleted (user logged out).
 * Can be used to:
 * - Clean up related data
 * - Update user's device count
 * - Send notification to other devices
 *
 * @example Export in your index.ts:
 * ```typescript
 * export { onDeviceDeleted } from "./device/device_triggers";
 * ```
 */
export const onDeviceDeleted = onDocumentDeleted(
  DEVICE_DOC_PATH,
  async (event) => {
    const data = event.data?.data();

    if (!data) {
      console.warn("No data in deleted device document");
      return;
    }

    const { uid, deviceId } = event.params;

    console.log(`Device unregistered: ${uid}/${deviceId}`);
    console.log(`Platform: ${data.platform}`);

    // Optional: Update user's device count
    const db = admin.firestore();
    const devicesSnapshot = await db
      .collection(`users/${uid}/devices`)
      .count()
      .get();

    const remainingDevices = devicesSnapshot.data().count;

    console.log(`User ${uid} now has ${remainingDevices} device(s)`);

    // Optional: If user has no more devices, handle accordingly
    // if (remainingDevices === 0) {
    //   console.log(`User ${uid} has no registered devices`);
    //   // Maybe schedule account cleanup, send email, etc.
    // }
  }
);

/**
 * Example: Detect and handle FCM token changes.
 *
 * Triggered when a device document is updated, this function
 * detects FCM token changes and can handle token rotation.
 *
 * Use cases:
 * - Log token rotation for debugging
 * - Update any external systems that track tokens
 * - Invalidate cached token mappings
 *
 * @example Export in your index.ts:
 * ```typescript
 * export { onDeviceTokenChange } from "./device/device_triggers";
 * ```
 */
export const onDeviceTokenChange = onDocumentUpdated(
  DEVICE_DOC_PATH,
  async (event) => {
    const beforeData = event.data?.before.data();
    const afterData = event.data?.after.data();

    if (!beforeData || !afterData) {
      return;
    }

    const oldToken = beforeData.fcmToken;
    const newToken = afterData.fcmToken;

    // Check if token actually changed
    if (oldToken === newToken) {
      return;
    }

    const { uid, deviceId } = event.params;

    if (oldToken && !newToken) {
      console.log(`FCM token cleared for ${uid}/${deviceId}`);
      // Token was cleared (user disabled notifications or logged out)
    } else if (!oldToken && newToken) {
      console.log(`FCM token added for ${uid}/${deviceId}`);
      // Token was added (user enabled notifications)
    } else {
      console.log(`FCM token rotated for ${uid}/${deviceId}`);
      // Token was rotated (normal FCM behavior)
    }

    // Optional: Log to analytics
    // const db = admin.firestore();
    // await db.collection("analytics/devices/token_changes").add({
    //   uid,
    //   deviceId,
    //   changeType: !oldToken ? "added" : !newToken ? "cleared" : "rotated",
    //   platform: afterData.platform,
    //   timestamp: admin.firestore.Timestamp.now(),
    // });
  }
);
