# Device Service Guide

## Overview

The Dreamic Device Service provides a comprehensive, production-ready system for tracking device-level information with timezone as the primary use case. It maintains a canonical Firestore document per app install/profile, enabling:

- **Timezone-aware notifications**: Send notifications at specific local times (e.g., "9 AM local")
- **Multi-device support**: Track all of a user's devices independently
- **Activity tracking**: Know which devices are recently active for targeting
- **Push token management**: Single source of truth for FCM tokens per device

**This feature is completely optional.** Your app will not require device tracking unless you follow these setup steps.

## Why Use This Service?

### Before: Scattered Device Data

Without this service, apps typically:
- Store timezone only at login (becomes stale when user travels)
- Have no awareness of DST transitions
- Scatter FCM tokens across multiple collections
- Lack per-device activity tracking
- Cannot query "devices where it's 9 AM local time"

### After: Unified Device Management

```dart
// In your app initialization
await deviceService.connectToAuthService();

// That's it! Device registration, timezone updates, and activity
// tracking are now automatic based on auth and app lifecycle events.
```

Everything else is handled automatically:
- Device registered on login
- Timezone updated when user travels
- Offset updated on DST transitions
- Activity tracked on app resume
- Device unregistered on logout

## Getting Started

### 1. Dependencies

The dependencies are already included in Dreamic's `pubspec.yaml`:
- `uuid: ^4.5.1` - Device ID generation
- `flutter_timezone: ^1.0.8` - Already in use
- `shared_preferences` - Already in use

### 2. Backend Setup (Required)

The DeviceService requires Firebase Functions for all backend operations. Copy the scaffolding to your project:

1. Copy `scaffolding/firebase_functions/device/` to your functions `src/` directory
2. Install dependencies:
   ```bash
   cd functions
   npm install luxon
   npm install -D @types/luxon
   ```
3. Export from your `functions/src/index.ts`:
   ```typescript
   export * from "./device";
   ```
4. Deploy:
   ```bash
   firebase deploy --only functions
   ```

See `scaffolding/firebase_functions/device/README.md` for complete setup instructions including Firestore indexes and security rules.

### 3. Initialize the Service

In your app initialization, after setting up dependency injection:

```dart
import 'package:dreamic/dreamic.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Set up dependency injection
  final deviceService = DeviceServiceImpl();
  GetIt.instance.registerSingleton<DeviceServiceInt>(deviceService);

  // Connect to auth service - enables automatic lifecycle management
  await deviceService.connectToAuthService();

  runApp(MyApp());
}
```

**That's it!** Your app now has full device tracking. The service automatically handles:
- Registering devices on login
- Updating timezone when it changes
- Tracking device activity on resume
- Unregistering devices on logout

### 4. Integration with NotificationService

For apps using push notifications, forward token changes to DeviceService:

```dart
await deviceService.connectToAuthService();

// NotificationService auto-detects DeviceService in GetIt
// and forwards token changes automatically
await notificationService.connectToAuthService();
```

Or with explicit wiring:

```dart
await notificationService.connectToAuthService(
  onTokenChanged: (newToken, oldToken) async {
    await deviceService.updateFcmToken(fcmToken: newToken);
  },
);
```

## Firestore Data Structure

Devices are stored at `users/{uid}/devices/{deviceId}`:

```
users/{uid}/devices/{deviceId}
  ├── timezone: string              // IANA format, e.g., "America/New_York"
  ├── timezoneOffsetMinutes: int    // Current UTC offset in minutes
  ├── lastActiveAt: Timestamp       // Last time device was active
  ├── fcmToken: string?             // Current push token (nullable)
  ├── fcmTokenUpdatedAt: Timestamp? // Last token update time
  ├── createdAt: Timestamp          // When device was first registered
  ├── updatedAt: Timestamp          // Last document update
  ├── platform: string              // "ios", "android", "web", "macos", etc.
  ├── appVersion: string            // App version on this device
  └── deviceInfo: map (optional)    // Additional device metadata
      ├── model: string
      └── osVersion: string
```

### Key Fields

| Field | Purpose |
|-------|---------|
| `timezone` | IANA timezone string - authoritative source for local time calculations |
| `timezoneOffsetMinutes` | Cached UTC offset - enables efficient Firestore queries |
| `lastActiveAt` | Activity tracking - determines "active" devices for targeting |
| `fcmToken` | Push delivery - nullable when notifications unavailable |

### Device ID Strategy

The `deviceId` is a UUIDv4 generated once per app install and persisted locally:
- **Mobile/Desktop**: SharedPreferences (survives app restarts, not reinstalls)
- **Web**: IndexedDB/localStorage with in-memory fallback

This provides stable identification without requiring platform-specific device IDs or fingerprinting.

## Usage Examples

### Basic Usage

After calling `connectToAuthService()`, most operations happen automatically. For manual control:

```dart
// Force device registration (usually automatic on login)
final result = await deviceService.registerDevice();

// Check current timezone
final timezone = await deviceService.getCurrentTimezone();
print('Device timezone: $timezone'); // "America/New_York"

// Get device ID
final deviceId = await deviceService.getDeviceId();
print('Device ID: $deviceId'); // "550e8400-e29b-41d4-a716-446655440000"
```

### Listing User's Devices

Display a "My Devices" settings screen:

```dart
final result = await deviceService.getMyDevices();
result.fold(
  (failure) => showError('Could not load devices'),
  (devices) {
    for (final device in devices) {
      print('${device.platform}: ${device.timezone}');
      print('  Last active: ${device.lastActiveAt}');
      print('  Has push: ${device.fcmToken != null}');
    }
  },
);
```

### Manual Token Updates

If not using NotificationService integration:

```dart
// Token obtained
await deviceService.updateFcmToken(fcmToken: newToken);

// Token cleared (user revoked permission)
await deviceService.updateFcmToken(fcmToken: null);
```

### Force Activity Update

Usually automatic on app resume, but can be called manually:

```dart
await deviceService.touchDevice();
```

## Automatic Behavior

### On Authentication Events

| Event | Action |
|-------|--------|
| Login | `registerDevice()` - creates/updates device document |
| Auth refresh | `registerDevice()` - keeps metadata fresh |
| Logout (before sign out) | `unregisterDevice()` - deletes device document |

### On App Lifecycle Events

| Event | Action |
|-------|--------|
| App resume | `updateTimezoneOrOffsetIfChanged()` - syncs if changed |
| App resume | `touchDevice()` - updates lastActiveAt (throttled) |

### Throttling

To minimize network usage and Firestore writes:

| Operation | Default Throttle | Remote Config Key |
|-----------|------------------|-------------------|
| Timezone unchanged | 48 hours | `dreamic_device_timezone_unchanged_sync_min_minutes` |
| Timezone changed | 10 min debounce | `dreamic_device_timezone_change_debounce_minutes` |
| Touch (activity) | 60 minutes | `dreamic_device_touch_throttle_minutes` |
| Pending retry backoff | 15 minutes | `dreamic_device_pending_backoff_minutes` |

These can be tuned via Remote Config or `AppConfigBase`:

```dart
// In your app initialization
AppConfigBase.deviceTouchThrottleMinutes = 30; // More frequent activity tracking
```

## Offline Handling

The service is designed for resilience across flaky networks:

1. **Best-Effort Operations**: All device operations are non-blocking
2. **Pending Payload**: Failed updates are stored locally and retried
3. **Merge Semantics**: Multiple pending changes are coalesced
4. **Automatic Retry**: Pending data is flushed on next lifecycle event

```dart
// No special handling needed - offline resilience is automatic
await deviceService.registerDevice(); // Stores pending if offline

// On next auth event or app resume, pending data is flushed
```

### Pending Payload Rules

- **Per-field last-write-wins**: Latest value for each field is kept
- **Sticky touch flag**: Once true, stays true until successful sync
- **Backoff bypass**: Changed fields (timezone, token) bypass backoff

## Backend Integration (Cloud Functions)

### Scheduled Notifications at Local Time

The scaffolding provides utilities for "9 AM local time" notifications:

```typescript
import { getDevicesInLocalTimeWindow } from "./device";

// Run every 15 minutes via Cloud Scheduler
export const sendMorningReminders = onSchedule("every 15 minutes", async () => {
  const devices = await getDevicesInLocalTimeWindow(
    getFirestore(),
    { hour: 9, minute: 0 },
    {
      windowMinutes: 15,
      requireToken: true,
      activeWithinDays: 60,
    }
  );

  // Group by user, pick most recent device per user
  const grouped = groupByUserMostRecentDevice(devices);

  for (const device of grouped) {
    await admin.messaging().send({
      token: device.fcmToken!,
      notification: { title: "Good morning!" },
    });
  }
});
```

### DST Safety

The time-window queries use a two-stage approach:

1. **Candidate Query**: Uses cached `timezoneOffsetMinutes` for efficient indexed queries
2. **Authoritative Filter**: Uses IANA `timezone` string for DST-safe validation

This ensures correct delivery even when:
- DST transitions occur
- The app wasn't opened near a DST transition
- Cached offsets are stale (up to 60 min buffer)

### Querying Active Devices

```typescript
// Devices active in last 60 days
const devices = await db.collectionGroup('devices')
  .where('lastActiveAt', '>', sixtyDaysAgo)
  .get();

// Devices in specific timezone offset range (for local time queries)
const devices = await db.collectionGroup('devices')
  .where('timezoneOffsetMinutes', '>=', offsetMin)
  .where('timezoneOffsetMinutes', '<=', offsetMax)
  .get();
```

## Configuration Options

### AppConfigBase Settings

| Setting | Default | Description |
|---------|---------|-------------|
| `deviceActionFunction` | `"deviceAction"` | Firebase callable function name |
| `deviceTimezoneUnchangedSyncMinMinutes` | 2880 (48h) | Min interval for unchanged timezone sync |
| `deviceTimezoneUnchangedSyncMaxMinutes` | 2880 (48h) | Max interval (forced refresh) |
| `deviceTimezoneChangeDebounceMinutes` | 10 | Debounce for changed timezone |
| `deviceTouchThrottleMinutes` | 60 | Touch operation throttle |
| `devicePendingBackoffMinutes` | 15 | Retry backoff for pending payload |

### Remote Config Keys

All settings can be overridden via Firebase Remote Config:
- `dreamic_device_timezone_unchanged_sync_min_minutes`
- `dreamic_device_timezone_unchanged_sync_max_minutes`
- `dreamic_device_timezone_change_debounce_minutes`
- `dreamic_device_touch_throttle_minutes`
- `dreamic_device_pending_backoff_minutes`

## Privacy Considerations

### What Data is Collected

| Data | Purpose | Can Disable |
|------|---------|-------------|
| Device ID (UUID) | Document identifier | No (required for service) |
| Timezone (IANA) | Local time calculations | No (core feature) |
| Offset (minutes) | Efficient queries | No (required for queries) |
| Platform | Analytics, targeting | Yes (don't send in deviceInfo) |
| App Version | Compatibility tracking | Yes (don't send in deviceInfo) |
| FCM Token | Push notifications | Yes (don't call updateFcmToken) |
| Last Active | Activity tracking | Inherent in updates |

### Minimal Schema by Default

The `deviceInfo` map (containing model, osVersion, etc.) is opt-in. The default implementation only sends platform and appVersion.

### Data Retention

- Device documents persist until explicitly deleted (logout) or cleaned up
- Recommended: Set up scheduled cleanup for devices inactive >90 days
- See `scaffolding/firebase_functions/device/device_scheduled.ts` for examples

### User Control

Users can view their devices via `getMyDevices()` and indirectly remove them by logging out.

## Separation of Concerns

### DeviceService Owns

- Device identity (deviceId generation/persistence)
- Timezone and offset tracking
- Activity tracking (lastActiveAt)
- FCM token persistence to Firestore
- Backend communication for device operations

### NotificationService Owns

- Permission prompting
- Token acquisition (Firebase Messaging API)
- Local token lifecycle
- Forwarding token changes to DeviceService

### AuthService Provides

- Authentication lifecycle callbacks
- User identity (uid for Firestore paths)
- About-to-logout hook for cleanup

## Error Handling

All service methods return `Either<RepositoryFailure, T>`:

```dart
final result = await deviceService.registerDevice();
result.fold(
  (failure) {
    switch (failure) {
      case RepositoryFailure.networkError:
        // Stored in pending payload for retry
        break;
      case RepositoryFailure.notAuthorizedToRead:
        // User not authenticated
        break;
      default:
        // Logged but not surfaced to user
        break;
    }
  },
  (_) => print('Device registered'),
);
```

In practice, most consuming apps can ignore failures since:
- Operations are best-effort
- Pending payload handles retries
- Backend staleness cleanup handles orphaned docs

## Testing

For unit tests, mock the service interface:

```dart
class MockDeviceService implements DeviceServiceInt {
  String _deviceId = 'test-device-id';
  String _timezone = 'America/New_York';

  @override
  Future<String> getDeviceId() async => _deviceId;

  @override
  Future<String> getCurrentTimezone() async => _timezone;

  @override
  Future<Either<RepositoryFailure, Unit>> registerDevice() async {
    return const Right(unit);
  }

  // ... implement other methods
}

// In tests
GetIt.instance.registerSingleton<DeviceServiceInt>(MockDeviceService());
```

## Troubleshooting

### Device not registering

1. Ensure `connectToAuthService()` was called
2. Check that AuthService is registered in GetIt
3. Verify the user is authenticated
4. Check Firebase Functions logs for errors

### Timezone not updating

1. Verify the app resumed from background (not cold start)
2. Check throttle settings - unchanged timezone only syncs every 48h
3. For testing, reduce throttle: `AppConfigBase.deviceTimezoneUnchangedSyncMinMinutes = 1`

### FCM token not syncing

1. Ensure NotificationService is forwarding token changes
2. Check if user is authenticated when token is received
3. Verify pending payload isn't stuck in backoff

### Backend callable fails

1. Check function deployment: `firebase functions:list`
2. Verify function name matches `AppConfigBase.deviceActionFunction`
3. Check Firestore indexes are created
4. Review Firebase Functions logs

### "Missing index" errors

Run:
```bash
firebase firestore:indexes
```

And create any missing indexes. See `scaffolding/firebase_functions/device/README.md` for required indexes.

## Migration from Existing Implementation

If your app currently passes timezone during auth:

1. Add DeviceService without removing existing code
2. Call `connectToAuthService()` to enable parallel tracking
3. Verify device documents are being created
4. Deprecate old timezone passing in auth callables
5. Remove old SharedPreferences timezone storage

```dart
// Phase 1: Run both in parallel
await deviceService.connectToAuthService();
await authService.loginWithTimezone(timezone); // Keep existing

// Phase 2: After verification, remove old code
await deviceService.connectToAuthService();
await authService.login(); // Remove timezone passing
```

## API Reference

For detailed API documentation, see the dartdoc comments in:
- `DeviceServiceInt` - Interface with comprehensive method documentation
- `DeviceServiceImpl` - Implementation with usage examples
- `DeviceInfo` - Device document model
- `DevicePlatform` - Platform enumeration

## FAQ

**Q: Do I need the backend functions if I just want timezone tracking?**
A: Yes. All device writes go through Firebase Functions for security. Direct client writes are denied.

**Q: Can I use this without NotificationService?**
A: Yes! DeviceService is independent. Just don't call `updateFcmToken()` if you're not tracking push tokens.

**Q: What happens if the user switches accounts on the same device?**
A: On logout, the old user's device doc is deleted. On login, a new device doc is created for the new user.

**Q: How do I handle multiple Firebase projects (dev/prod)?**
A: The service uses `AppConfigBase.firebaseFunctionCallable()` which respects your Firebase configuration.

**Q: Can I add custom fields to the device document?**
A: Yes. Extend the `deviceInfo` map in your backend callable and send additional data in the request.

## Support

For issues or questions:
1. Check the [troubleshooting section](#troubleshooting)
2. Review the backend scaffolding README
3. Check Firebase Functions logs for backend errors
4. Open an issue on GitHub
