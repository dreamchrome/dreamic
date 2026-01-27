/**
 * Unified device callable for DeviceService operations.
 *
 * This callable handles all client-facing device operations:
 * - `register`: Create or update device with timezone, platform, etc.
 * - `touch`: Update lastActiveAt timestamp
 * - `updateToken`: Update FCM push token (with uniqueness cleanup)
 * - `unregister`: Delete device document
 * - `getMyDevices`: Retrieve all devices for the authenticated user
 *
 * @packageVersion dreamic ^0.4.0
 * @description Device registration callable for DeviceService
 *
 * ## Security
 *
 * - All operations require authentication (Firebase Auth)
 * - Users can only modify their own devices (uid from auth context)
 * - Input validation prevents injection and data corruption
 * - Consider enabling App Check for additional security
 *
 * ## Firestore Structure
 *
 * ```
 * users/{uid}/devices/{deviceId}
 *   ├── timezone: string              // IANA format
 *   ├── timezoneOffsetMinutes: int    // Current UTC offset
 *   ├── lastActiveAt: Timestamp       // Last activity
 *   ├── fcmToken: string?             // Push token (nullable)
 *   ├── fcmTokenUpdatedAt: Timestamp? // Token update timestamp
 *   ├── createdAt: Timestamp          // Document creation
 *   ├── updatedAt: Timestamp          // Last update
 *   ├── platform: string              // ios/android/web/macos/windows/linux
 *   ├── appVersion: string            // App version string
 *   └── deviceInfo: map?              // Optional metadata
 * ```
 *
 * ## Required Firestore Indexes
 *
 * - Collection group index on `devices.fcmToken` (for uniqueness cleanup)
 * - Collection group index on `devices.timezoneOffsetMinutes` + `devices.lastActiveAt`
 *   (for scheduled notification queries)
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { isValidIanaTimezone, validateOffsetMinutes } from "./timezone_utils";

/**
 * Valid device actions.
 */
type DeviceAction =
  | "register"
  | "touch"
  | "unregister"
  | "updateToken"
  | "getMyDevices";

/**
 * Valid platform identifiers.
 */
type DevicePlatform =
  | "ios"
  | "android"
  | "web"
  | "macos"
  | "windows"
  | "linux";

/**
 * Request payload for the deviceAction callable.
 */
interface DeviceActionRequest {
  /** The action to perform */
  action: DeviceAction;
  /** Device ID (UUIDv4, required for all actions) */
  deviceId: string;
  /** IANA timezone identifier (required for register) */
  timezone?: string;
  /** UTC offset in minutes (required for register) */
  timezoneOffsetMinutes?: number;
  /** Device platform (required for register) */
  platform?: DevicePlatform;
  /** App version string (required for register) */
  appVersion?: string;
  /** FCM push token (optional for register, required for updateToken) */
  fcmToken?: string | null;
  /** Optional device metadata */
  deviceInfo?: {
    model?: string;
    osVersion?: string;
  };
}

/**
 * Response payload from the deviceAction callable.
 */
interface DeviceActionResponse {
  /** Whether the operation succeeded */
  success: boolean;
  /** Whether timezone changed (register action) */
  timezoneChanged?: boolean;
  /** Whether timezone offset changed (register action) */
  timezoneOffsetChanged?: boolean;
  /** Previous timezone if changed (register action) */
  previousTimezone?: string;
  /** List of devices (getMyDevices action) */
  devices?: Array<Record<string, unknown>>;
}

/**
 * Validates that a string is a valid UUIDv4.
 *
 * @param value - The string to validate
 * @returns true if valid UUIDv4 format
 */
function isValidUuidV4(value: unknown): boolean {
  if (typeof value !== "string") {
    return false;
  }

  // UUIDv4 regex: 8-4-4-4-12 hex digits with version 4 indicator
  const uuidV4Regex =
    /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

  return uuidV4Regex.test(value);
}

/**
 * Validates the platform string.
 *
 * @param platform - The platform to validate
 * @returns true if valid platform identifier
 */
function isValidPlatform(platform: unknown): platform is DevicePlatform {
  return (
    typeof platform === "string" &&
    ["ios", "android", "web", "macos", "windows", "linux"].includes(platform)
  );
}

/**
 * Validates the app version string.
 *
 * @param version - The version string to validate
 * @returns true if valid version format
 */
function isValidAppVersion(version: unknown): boolean {
  if (typeof version !== "string") {
    return false;
  }

  // Allow semantic versioning and common formats
  // Examples: "1.0.0", "1.0.0+1", "1.0.0-beta.1"
  // Max length 50 to prevent abuse
  return version.length > 0 && version.length <= 50;
}

/**
 * Sanitizes optional device info to prevent injection.
 *
 * @param deviceInfo - The device info object to sanitize
 * @returns Sanitized device info or undefined
 */
function sanitizeDeviceInfo(
  deviceInfo: unknown
): { model?: string; osVersion?: string } | undefined {
  if (!deviceInfo || typeof deviceInfo !== "object") {
    return undefined;
  }

  const info = deviceInfo as Record<string, unknown>;
  const result: { model?: string; osVersion?: string } = {};

  // Sanitize model: string, max 100 chars
  if (typeof info.model === "string" && info.model.length <= 100) {
    result.model = info.model.trim();
  }

  // Sanitize osVersion: string, max 50 chars
  if (typeof info.osVersion === "string" && info.osVersion.length <= 50) {
    result.osVersion = info.osVersion.trim();
  }

  return Object.keys(result).length > 0 ? result : undefined;
}

/**
 * Unified device callable with action parameter.
 *
 * Called by DeviceService methods with action-specific payloads.
 *
 * @example
 * ```typescript
 * // Register a device
 * const result = await httpsCallable(functions, "deviceAction")({
 *   action: "register",
 *   deviceId: "550e8400-e29b-41d4-a716-446655440000",
 *   timezone: "America/New_York",
 *   timezoneOffsetMinutes: -300,
 *   platform: "ios",
 *   appVersion: "1.0.0",
 * });
 * ```
 */
export const deviceAction = onCall<DeviceActionRequest>(
  {
    // Recommended: Enable App Check for additional security
    // enforceAppCheck: true,

    // Optional: Set memory and timeout as needed
    // memory: "256MiB",
    // timeoutSeconds: 60,
  },
  async (request): Promise<DeviceActionResponse> => {
    // ============================================================
    // Authentication Check
    // ============================================================
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "Must be logged in to manage devices"
      );
    }

    const uid = request.auth.uid;
    const { action, deviceId } = request.data;

    // ============================================================
    // Basic Input Validation
    // ============================================================
    if (!action || typeof action !== "string") {
      throw new HttpsError("invalid-argument", "action is required");
    }

    if (!deviceId) {
      throw new HttpsError("invalid-argument", "deviceId is required");
    }

    if (!isValidUuidV4(deviceId)) {
      throw new HttpsError(
        "invalid-argument",
        "deviceId must be a valid UUIDv4"
      );
    }

    // ============================================================
    // Action Routing
    // ============================================================
    const db = getFirestore();
    const deviceRef = db.doc(`users/${uid}/devices/${deviceId}`);

    switch (action) {
      case "register": {
        return handleRegister(request.data, deviceRef);
      }

      case "touch": {
        return handleTouch(deviceRef);
      }

      case "updateToken": {
        return handleUpdateToken(request.data, deviceRef);
      }

      case "unregister": {
        return handleUnregister(deviceRef);
      }

      case "getMyDevices": {
        return handleGetMyDevices(uid, db);
      }

      default:
        throw new HttpsError(
          "invalid-argument",
          `Unknown action: ${action}. Valid actions: register, touch, updateToken, unregister, getMyDevices`
        );
    }
  }
);

/**
 * Handles the "register" action: creates or updates a device document.
 */
async function handleRegister(
  data: DeviceActionRequest,
  deviceRef: FirebaseFirestore.DocumentReference
): Promise<DeviceActionResponse> {
  const { timezone, timezoneOffsetMinutes, platform, appVersion, fcmToken, deviceInfo } =
    data;

  // ============================================================
  // Validate Required Fields for Register
  // ============================================================
  if (!timezone) {
    throw new HttpsError(
      "invalid-argument",
      "timezone is required for register action"
    );
  }

  if (!isValidIanaTimezone(timezone)) {
    console.error(`Invalid IANA timezone received: ${timezone}`);
    throw new HttpsError(
      "invalid-argument",
      "Invalid IANA timezone format. Example: America/New_York"
    );
  }

  if (timezoneOffsetMinutes === undefined || timezoneOffsetMinutes === null) {
    throw new HttpsError(
      "invalid-argument",
      "timezoneOffsetMinutes is required for register action"
    );
  }

  const offsetValidation = validateOffsetMinutes(timezoneOffsetMinutes);
  if (!offsetValidation.isValid) {
    throw new HttpsError(
      "invalid-argument",
      `Invalid timezoneOffsetMinutes: ${offsetValidation.error}`
    );
  }

  if (!platform) {
    throw new HttpsError(
      "invalid-argument",
      "platform is required for register action"
    );
  }

  if (!isValidPlatform(platform)) {
    throw new HttpsError(
      "invalid-argument",
      "Invalid platform. Must be: ios, android, web, macos, windows, or linux"
    );
  }

  if (!appVersion) {
    throw new HttpsError(
      "invalid-argument",
      "appVersion is required for register action"
    );
  }

  if (!isValidAppVersion(appVersion)) {
    throw new HttpsError(
      "invalid-argument",
      "Invalid appVersion format (must be 1-50 characters)"
    );
  }

  // ============================================================
  // Check for Existing Device
  // ============================================================
  const existingDevice = await deviceRef.get();
  const existingData = existingDevice.exists ? existingDevice.data() : null;

  const previousTimezone = existingData?.timezone;
  const previousOffset = existingData?.timezoneOffsetMinutes;

  const timezoneChanged =
    previousTimezone !== undefined && previousTimezone !== timezone;
  const timezoneOffsetChanged =
    previousOffset !== undefined && previousOffset !== timezoneOffsetMinutes;

  // ============================================================
  // Build Device Data
  // ============================================================
  const deviceData: Record<string, unknown> = {
    timezone,
    timezoneOffsetMinutes,
    platform,
    appVersion,
    lastActiveAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };

  // Add optional device info if provided and sanitized
  const sanitizedInfo = sanitizeDeviceInfo(deviceInfo);
  if (sanitizedInfo) {
    deviceData.deviceInfo = sanitizedInfo;
  }

  // Add FCM token if provided
  if (fcmToken !== undefined) {
    deviceData.fcmToken = fcmToken;
    deviceData.fcmTokenUpdatedAt = FieldValue.serverTimestamp();
  }

  // ============================================================
  // Write to Firestore
  // ============================================================
  if (existingDevice.exists) {
    await deviceRef.update(deviceData);
  } else {
    await deviceRef.set({
      ...deviceData,
      createdAt: FieldValue.serverTimestamp(),
    });
  }

  // ============================================================
  // Build Response
  // ============================================================
  const response: DeviceActionResponse = {
    success: true,
    timezoneChanged,
    timezoneOffsetChanged,
  };

  if (timezoneChanged) {
    response.previousTimezone = previousTimezone;
  }

  return response;
}

/**
 * Handles the "touch" action: updates lastActiveAt timestamp.
 *
 * Uses merge:true to create the document if it doesn't exist (upsert).
 */
async function handleTouch(
  deviceRef: FirebaseFirestore.DocumentReference
): Promise<DeviceActionResponse> {
  await deviceRef.set(
    {
      lastActiveAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  return { success: true };
}

/**
 * Handles the "updateToken" action: updates FCM token with uniqueness cleanup.
 *
 * When a token is provided (not null), this function also:
 * 1. Searches for other device documents with the same token
 * 2. Clears the token from those documents
 *
 * This prevents the same token from existing on multiple device documents,
 * which can happen if a user switches accounts on the same device while offline.
 */
async function handleUpdateToken(
  data: DeviceActionRequest,
  deviceRef: FirebaseFirestore.DocumentReference
): Promise<DeviceActionResponse> {
  const { fcmToken } = data;

  // fcmToken must be explicitly provided (but can be null for clearing)
  if (fcmToken === undefined) {
    throw new HttpsError(
      "invalid-argument",
      "fcmToken is required for updateToken action (use null to clear)"
    );
  }

  // Validate token format if provided (not null)
  if (fcmToken !== null) {
    if (typeof fcmToken !== "string" || fcmToken.length === 0) {
      throw new HttpsError(
        "invalid-argument",
        "fcmToken must be a non-empty string or null"
      );
    }

    // FCM tokens are typically 150-200 chars, but allow up to 500 for safety
    if (fcmToken.length > 500) {
      throw new HttpsError(
        "invalid-argument",
        "fcmToken exceeds maximum length (500 characters)"
      );
    }
  }

  // ============================================================
  // Update the Token
  // ============================================================
  await deviceRef.set(
    {
      fcmToken,
      fcmTokenUpdatedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  // ============================================================
  // Uniqueness Cleanup (best-effort)
  // ============================================================
  if (fcmToken) {
    try {
      await cleanupDuplicateTokens(fcmToken, deviceRef);
    } catch (error) {
      // Log but don't fail the main operation
      console.error("Token uniqueness cleanup failed:", error);
    }
  }

  return { success: true };
}

/**
 * Clears the given token from any other device documents.
 *
 * This is a best-effort operation - failures are logged but don't
 * fail the main updateToken operation.
 *
 * @param token - The FCM token to deduplicate
 * @param currentDeviceRef - Reference to the current device (excluded from cleanup)
 */
async function cleanupDuplicateTokens(
  token: string,
  currentDeviceRef: FirebaseFirestore.DocumentReference
): Promise<void> {
  const db = getFirestore();

  // Query all devices with this token using collection group
  // NOTE: This requires a collection group index on the 'devices' collection
  // for the 'fcmToken' field.
  const duplicates = await db
    .collectionGroup("devices")
    .where("fcmToken", "==", token)
    .get();

  if (duplicates.empty) {
    return;
  }

  const batch = db.batch();
  let hasWrites = false;

  for (const doc of duplicates.docs) {
    // Skip the current device
    if (doc.ref.path === currentDeviceRef.path) {
      continue;
    }

    // Clear the token from this document
    batch.update(doc.ref, {
      fcmToken: null,
      fcmTokenUpdatedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    hasWrites = true;

    console.log(
      `Clearing duplicate token from device: ${doc.ref.path}`
    );
  }

  if (hasWrites) {
    await batch.commit();
  }
}

/**
 * Handles the "unregister" action: deletes the device document.
 */
async function handleUnregister(
  deviceRef: FirebaseFirestore.DocumentReference
): Promise<DeviceActionResponse> {
  await deviceRef.delete();
  return { success: true };
}

/**
 * Handles the "getMyDevices" action: retrieves all devices for the user.
 *
 * Returns devices ordered by lastActiveAt (most recent first).
 */
async function handleGetMyDevices(
  uid: string,
  db: FirebaseFirestore.Firestore
): Promise<DeviceActionResponse> {
  const snapshot = await db
    .collection(`users/${uid}/devices`)
    .orderBy("lastActiveAt", "desc")
    .get();

  const devices = snapshot.docs.map((doc) => {
    const data = doc.data();

    // Convert Firestore Timestamps to ISO strings for JSON serialization
    return {
      id: doc.id,
      timezone: data.timezone,
      timezoneOffsetMinutes: data.timezoneOffsetMinutes,
      platform: data.platform,
      appVersion: data.appVersion,
      fcmToken: data.fcmToken ?? null,
      deviceInfo: data.deviceInfo,
      lastActiveAt: data.lastActiveAt?.toDate?.()?.toISOString() ?? null,
      fcmTokenUpdatedAt:
        data.fcmTokenUpdatedAt?.toDate?.()?.toISOString() ?? null,
      createdAt: data.createdAt?.toDate?.()?.toISOString() ?? null,
      updatedAt: data.updatedAt?.toDate?.()?.toISOString() ?? null,
    };
  });

  return {
    success: true,
    devices,
  };
}
