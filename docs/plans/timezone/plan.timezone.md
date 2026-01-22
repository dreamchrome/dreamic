# Device Service & Timezone Tracking Plan

## Overview

Create a `DeviceService` that tracks device-level information, with timezone as the primary initial use case. This service will be independent of, but complementary to, the existing notification/FCM token management.

## Goals

1. Track device timezone independently of notification permissions
2. Keep timezone data fresh in Firestore for backend use
3. Support multi-device users with per-device timezone awareness
4. Provide a foundation for future device-level features
5. Enable backend systems to make timezone-aware decisions (notifications, scheduled jobs, analytics)

## Non-Goals (for initial implementation)

- Replacing or modifying FCM token management (that stays in NotificationService)
- User-level "primary timezone" (can be added later)
- Timezone history/audit trail

---

## Data Model

### Firestore Structure

```
users/{uid}/devices/{deviceId}
  ├── timezone: string              // IANA format, e.g., "America/New_York"
  ├── timezoneOffsetMinutes: int    // Current UTC offset in minutes (for quick queries)
  ├── lastActiveAt: Timestamp       // Last time this device was active
  ├── createdAt: Timestamp          // When device was first registered
  ├── platform: string              // "ios", "android", "web"
  ├── appVersion: string            // App version on this device
  └── deviceInfo: map (optional)    // Additional device metadata
      ├── model: string
      ├── osVersion: string
      └── ...
```

### Device ID Strategy

Options:
1. **Generated UUID stored locally** - Persists across app reinstalls on iOS (Keychain), less reliable on Android
2. **Firebase Installation ID** - Built-in, but can change on reinstall
3. **Composite key** - Combine platform + some stable identifier

**Recommendation**: Use Firebase Installation ID (`firebase_app_installations` package) as it's already integrated with Firebase and provides reasonable stability.

---

## Service Interface

```dart
abstract class DeviceServiceInt {
  /// Registers or updates the current device in Firestore.
  /// Should be called on app startup after authentication.
  Future<Either<RepositoryFailure, Unit>> registerDevice();

  /// Updates just the timezone if it has changed.
  /// Returns true if timezone was updated, false if unchanged.
  Future<Either<RepositoryFailure, bool>> updateTimezoneIfChanged();

  /// Gets the current device's ID.
  Future<String> getDeviceId();

  /// Gets the current device's timezone.
  Future<String> getCurrentTimezone();

  /// Marks this device as active (updates lastActiveAt).
  Future<Either<RepositoryFailure, Unit>> touchDevice();

  /// Removes the current device registration.
  /// Called on logout to clean up device data.
  Future<Either<RepositoryFailure, Unit>> unregisterDevice();

  /// Gets all devices for the current user.
  Future<Either<RepositoryFailure, List<DeviceInfo>>> getMyDevices();
}
```

---

## Implementation Details

### When to Update Timezone

| Event | Action |
|-------|--------|
| App launch (after auth) | `registerDevice()` - creates or updates device |
| App resume from background | `updateTimezoneIfChanged()` - lightweight check |
| User travels (timezone changes) | Detected on next app resume |
| Logout | `unregisterDevice()` - optional, could also just leave stale |

### Timezone Change Detection

```dart
class DeviceServiceImpl implements DeviceServiceInt {
  String? _cachedTimezone;

  @override
  Future<Either<RepositoryFailure, bool>> updateTimezoneIfChanged() async {
    final currentTimezone = await FlutterTimezone.getLocalTimezone();

    if (_cachedTimezone == currentTimezone) {
      return right(false); // No change
    }

    // Update Firestore
    await _updateDeviceTimezone(currentTimezone);
    _cachedTimezone = currentTimezone;

    return right(true);
  }
}
```

### Integration with AuthService

The `DeviceService` should be initialized after authentication:

```dart
// In AuthServiceImpl.handleAuthStateChanges or via callback
if (fbUser != null) {
  // User just authenticated
  await deviceService.registerDevice();
}

// On logout
await deviceService.unregisterDevice(); // or leave for history
```

### Integration with NotificationService

The `NotificationService` can optionally store a reference to the device:

```
users/{uid}/fcmTokens/{tokenHash}
  ├── token: string
  ├── deviceId: string  // <-- Reference to devices collection
  ├── ...
```

This allows backend to:
1. Look up FCM token
2. Get associated deviceId
3. Query device document for timezone

---

## Backend Considerations

### Querying Devices by Timezone

For scheduling notifications at "9am local time":

```javascript
// Cloud Function example
const devices = await db.collectionGroup('devices')
  .where('timezoneOffsetMinutes', '>=', targetOffsetMin)
  .where('timezoneOffsetMinutes', '<=', targetOffsetMax)
  .get();
```

Note: `timezoneOffsetMinutes` is denormalized for query efficiency. The IANA timezone string is the source of truth for DST handling.

### Stale Device Cleanup

Devices not seen in X days could be:
- Marked inactive
- Cleaned up by a scheduled Cloud Function
- Ignored when sending notifications

---

## Migration from Current Implementation

### Current State
- Timezone is passed during `loginAnonymously` and `accessCodeCheck`
- Stored in SharedPreferences with key `dreamic_timezone`
- Not systematically tracked after initial auth

### Migration Steps
1. Add `DeviceService` without removing existing code
2. Call `registerDevice()` after auth in parallel with existing flows
3. Deprecate timezone passing in auth callables (or keep for redundancy)
4. Remove SharedPreferences timezone storage once Firestore is reliable

---

## File Structure

```
lib/data/
├── models/
│   └── device_info.dart           // DeviceInfo model with JSON serialization
├── repos/
│   ├── device_service_int.dart    // Interface
│   └── device_service_impl.dart   // Implementation
```

---

## Dependencies

```yaml
dependencies:
  firebase_app_installations: ^x.x.x  # For device ID
  flutter_timezone: ^x.x.x            # Already used
  device_info_plus: ^x.x.x            # For device metadata (optional)
```

---

## Open Questions

1. **Device cleanup on logout**: Should we delete the device document or just leave it stale? Leaving it preserves history but creates orphaned data.

2. **Offline handling**: What if timezone update fails due to no network? Queue for retry?

3. **Web platform**: How stable is device ID for web? Should we use a different strategy?

4. **Privacy considerations**: Is storing device model/OS version necessary? Could be useful for debugging but might raise privacy concerns.

5. **Rate limiting**: Should we throttle timezone updates to avoid excessive writes (e.g., max once per hour)?

---

## Success Criteria

- [ ] Device timezone is accurately tracked in Firestore
- [ ] Timezone updates when user travels to new timezone
- [ ] Multi-device users have separate device records
- [ ] Backend can query devices by timezone for scheduling
- [ ] Works independently of notification permissions
- [ ] Minimal battery/network impact from update checks

---

## Scaffolding Strategy

The DeviceService requires both Flutter code (in this package) and Firebase Functions (in consuming apps). Backend functions will be provided as templates in the existing `scaffolding/` folder.

**Note:** No Firestore security rules needed - all device writes go through Firebase Functions (server-side), not direct client writes.

### Scaffolding Structure

```
scaffolding/
└── firebase_functions/
    └── device/
        ├── device_callable.ts      # Client-facing callables (required)
        ├── device_scheduled.ts     # Scheduled jobs (optional)
        ├── device_triggers.ts      # Firestore triggers (optional)
        ├── timezone_utils.ts       # Timezone helpers
        ├── index.ts                # Barrel export
        └── README.md               # Setup instructions
```

### Configurable Function Names

The Flutter `DeviceService` will use configurable function names (matching existing `AppConfigBase` pattern):

```dart
// In AppConfigBase
static String deviceRegisterFunction = 'deviceRegister';
static String deviceUnregisterFunction = 'deviceUnregister';
static String deviceTouchFunction = 'deviceTouch';
```

### Version Compatibility

Include a comment in each scaffolding file:
```typescript
/**
 * @packageVersion dreamic ^0.4.0
 * @description Device registration callable for DeviceService
 */
```

### Setup Instructions (for README.md)

```markdown
## Device Functions Setup

1. Copy contents of `device/` to your functions `src/` directory
2. Add exports to your main `index.ts`:
   ```typescript
   export * from './device';
   ```
3. Install dependencies (if using luxon for timezone):
   ```bash
   npm install luxon @types/luxon
   ```
4. Deploy:
   ```bash
   firebase deploy --only functions
   ```
```

### Open Questions

1. Should the scaffolding include test files for the functions?
2. Should there be a "minimal" (just callable) vs "full" (scheduled + triggers) version?
3. How do we communicate breaking changes in the scaffolding to consuming apps?

---

## Documentation

Create a new documentation file explaining the DeviceService for consuming apps:

### File: `docs/device_service.md`

Contents should include:
- **Overview**: What the DeviceService does and why it exists
- **Setup**: How to initialize and integrate with your app
- **Usage Examples**: Common patterns for using the service
- **Firestore Structure**: Document schema for backend developers
- **Integration with NotificationService**: How the two services complement each other
- **Backend Integration**: How to query device data from Cloud Functions
- **Privacy Considerations**: What data is collected and why
- **Troubleshooting**: Common issues and solutions

### Code Documentation

- Comprehensive dartdoc comments on `DeviceServiceInt` interface
- Implementation notes in `DeviceServiceImpl`
- Example usage in class-level documentation

---

## Firebase Callable Functions (Client-Facing)

These are the callable functions that the Flutter `DeviceService` will invoke. They should be included in consuming apps' Firebase Functions.

### File: `docs/examples/firebase_functions/device_callable.ts`

```typescript
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, FieldValue } from "firebase-admin/firestore";

interface RegisterDeviceRequest {
  deviceId: string;
  timezone: string;           // IANA format, e.g., "America/New_York"
  platform: "ios" | "android" | "web";
  appVersion: string;
  deviceModel?: string;
  osVersion?: string;
}

interface RegisterDeviceResponse {
  success: boolean;
  timezoneChanged: boolean;
  previousTimezone?: string;
}

/**
 * Registers or updates a device for the authenticated user.
 * Called by DeviceService.registerDevice() on app startup.
 *
 * This function:
 * 1. Validates the request data
 * 2. Calculates timezoneOffsetMinutes from IANA timezone
 * 3. Creates or updates the device document
 * 4. Returns whether timezone changed (useful for client-side logic)
 */
export const deviceRegister = onCall<RegisterDeviceRequest>(async (request) => {
  // Require authentication
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be logged in");
  }

  const uid = request.auth.uid;
  const { deviceId, timezone, platform, appVersion, deviceModel, osVersion } = request.data;

  // Validate required fields
  if (!deviceId || !timezone || !platform || !appVersion) {
    throw new HttpsError("invalid-argument", "Missing required fields");
  }

  // Validate timezone is a valid IANA timezone
  if (!isValidIANATimezone(timezone)) {
    throw new HttpsError("invalid-argument", "Invalid timezone format");
  }

  const db = getFirestore();
  const deviceRef = db.doc(`users/${uid}/devices/${deviceId}`);

  // Get existing device to check if timezone changed
  const existingDevice = await deviceRef.get();
  const previousTimezone = existingDevice.exists
    ? existingDevice.data()?.timezone
    : null;
  const timezoneChanged = previousTimezone !== null && previousTimezone !== timezone;

  // Calculate current UTC offset for query efficiency
  const timezoneOffsetMinutes = getTimezoneOffsetMinutes(timezone);

  // Prepare device data
  const deviceData = {
    timezone,
    timezoneOffsetMinutes,
    platform,
    appVersion,
    lastActiveAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    ...(deviceModel && { deviceModel }),
    ...(osVersion && { osVersion }),
  };

  if (existingDevice.exists) {
    // Update existing device
    await deviceRef.update(deviceData);
  } else {
    // Create new device
    await deviceRef.set({
      ...deviceData,
      createdAt: FieldValue.serverTimestamp(),
    });
  }

  const response: RegisterDeviceResponse = {
    success: true,
    timezoneChanged,
    ...(timezoneChanged && { previousTimezone }),
  };

  return response;
});

/**
 * Unregisters a device for the authenticated user.
 * Called by DeviceService.unregisterDevice() on logout.
 */
export const deviceUnregister = onCall<{ deviceId: string }>(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be logged in");
  }

  const uid = request.auth.uid;
  const { deviceId } = request.data;

  if (!deviceId) {
    throw new HttpsError("invalid-argument", "deviceId is required");
  }

  const db = getFirestore();
  await db.doc(`users/${uid}/devices/${deviceId}`).delete();

  return { success: true };
});

/**
 * Lightweight endpoint to update just lastActiveAt timestamp.
 * Called periodically or on app resume to keep device "fresh".
 */
export const deviceTouch = onCall<{ deviceId: string }>(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be logged in");
  }

  const uid = request.auth.uid;
  const { deviceId } = request.data;

  if (!deviceId) {
    throw new HttpsError("invalid-argument", "deviceId is required");
  }

  const db = getFirestore();
  await db.doc(`users/${uid}/devices/${deviceId}`).update({
    lastActiveAt: FieldValue.serverTimestamp(),
  });

  return { success: true };
});

// Helper functions (see timezone_utils.ts for full implementations)
function isValidIANATimezone(tz: string): boolean {
  try {
    Intl.DateTimeFormat(undefined, { timeZone: tz });
    return true;
  } catch {
    return false;
  }
}

function getTimezoneOffsetMinutes(ianaTimezone: string): number {
  const now = new Date();
  const formatter = new Intl.DateTimeFormat("en-US", {
    timeZone: ianaTimezone,
    timeZoneName: "shortOffset",
  });
  // Parse offset from formatted string (e.g., "GMT-5" -> -300)
  const parts = formatter.formatToParts(now);
  const tzPart = parts.find(p => p.type === "timeZoneName")?.value || "";
  // ... parsing logic
  return offsetMinutes;
}
```

### Flutter DeviceService Integration

The `DeviceServiceImpl` will call these functions:

```dart
// In DeviceServiceImpl
HttpsCallable _deviceCallable = AppConfigBase.firebaseFunctionCallable('deviceRegister');

@override
Future<Either<RepositoryFailure, bool>> registerDevice() async {
  try {
    final deviceId = await getDeviceId();
    final timezone = await FlutterTimezone.getLocalTimezone();
    final packageInfo = await PackageInfo.fromPlatform();

    final result = await _deviceCallable.call({
      'deviceId': deviceId,
      'timezone': timezone,
      'platform': Platform.operatingSystem,
      'appVersion': packageInfo.version,
    });

    _cachedTimezone = timezone;
    return right(result.data['timezoneChanged'] as bool);
  } catch (e) {
    loge(e);
    return left(RepositoryFailure.unexpected);
  }
}
```

---

## Example Firebase Functions (Backend Use)

Create example Cloud Functions to demonstrate backend usage of device data. These serve as templates for consuming apps.

### File: `docs/examples/firebase_functions/device_functions.ts`

```typescript
// Example functions to include:

/**
 * Callable function to get user's devices with timezones
 * Useful for admin dashboards or user settings screens
 */
export const getUserDevices = onCall(async (request) => {
  // Implementation example
});

/**
 * Scheduled function: Send notifications at 9am local time
 * Demonstrates querying devices by timezone offset
 */
export const sendMorningNotifications = onSchedule("every 15 minutes", async () => {
  // Query devices where local time is ~9am
  // Group by FCM token
  // Send batch notifications
});

/**
 * Scheduled function: Clean up stale devices
 * Removes devices not seen in 90+ days
 */
export const cleanupStaleDevices = onSchedule("every 24 hours", async () => {
  // Query devices with lastActiveAt > 90 days ago
  // Delete or mark inactive
});

/**
 * Firestore trigger: On device timezone change
 * Example: Log timezone changes for analytics or trigger workflows
 */
export const onDeviceTimezoneChange = onDocumentUpdated(
  "users/{uid}/devices/{deviceId}",
  async (event) => {
    // Compare before/after timezone
    // Log to analytics, update user's primary timezone, etc.
  }
);

/**
 * Helper: Get devices in a specific timezone window
 * Reusable query for time-based scheduling
 */
async function getDevicesInTimezoneWindow(
  targetHour: number,
  windowMinutes: number = 15
): Promise<DeviceDoc[]> {
  // Calculate offset range for target hour
  // Query devices collection group
  // Return matching devices
}
```

### File: `docs/examples/firebase_functions/timezone_utils.ts`

```typescript
/**
 * Utility functions for timezone handling on the backend
 */

/**
 * Convert IANA timezone to current UTC offset in minutes
 * Handles DST correctly
 */
export function getTimezoneOffsetMinutes(ianaTimezone: string): number;

/**
 * Check if a given hour (0-23) is currently occurring in a timezone
 */
export function isHourInTimezone(hour: number, ianaTimezone: string): boolean;

/**
 * Get all IANA timezones where it's currently a specific hour
 */
export function getTimezonesAtHour(hour: number): string[];

/**
 * Calculate the next occurrence of a specific local time
 */
export function getNextLocalTime(
  hour: number,
  minute: number,
  ianaTimezone: string
): Date;
```

### Documentation for Functions

Each example function should include:
- Purpose and use case
- Required Firestore indexes
- Rate limiting considerations
- Error handling patterns
- Testing approach

---

## Future Enhancements

- User-level "home timezone" derived from most common device timezone
- Timezone change notifications (webhook when user travels)
- Device groups/families for household scenarios
- Last N timezones for travel pattern analysis
