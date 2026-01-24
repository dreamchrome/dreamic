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

### Important Constraints

- **DST-safe**: The system must keep `timezoneOffsetMinutes` accurate even when the IANA timezone string does not change (DST transitions).
- **Efficient**: Avoid unnecessary writes on frequent app resume events; only sync when needed and throttle background “touch” calls.
- **Robust**: Offline or transient backend failures must not block the app; sync should be best-effort with retries on later lifecycle events.

---

## Data Model

### Firestore Structure

```
users/{uid}/devices/{deviceId}
  ├── timezone: string              // IANA format, e.g., "America/New_York"
  ├── timezoneOffsetMinutes: int    // Current UTC offset in minutes (supports half/45-min offsets)
  ├── lastActiveAt: Timestamp       // Last time this device was active
  ├── createdAt: Timestamp          // When device was first registered
  ├── updatedAt: Timestamp          // Last time this device doc was updated
  ├── platform: string              // "ios", "android", "web"
  ├── appVersion: string            // App version on this device
  └── deviceInfo: map (optional)    // Additional device metadata
      ├── model: string
      ├── osVersion: string
      └── ...

Notes:
- `timezone` is the **semantic** value (DST rules, names, etc). `timezoneOffsetMinutes` is denormalized for efficient queries.
- `timezoneOffsetMinutes` MUST be refreshed even when `timezone` is unchanged (DST).
```

### Device ID Strategy

Options:
1. **Generated UUID stored locally** - Persists across app reinstalls on iOS (Keychain), less reliable on Android
2. **Firebase Installation ID** - Built-in, but can change on reinstall
3. **Composite key** - Combine platform + some stable identifier

**Recommendation**: Use Firebase Installation ID (`firebase_app_installations` package) as it's already integrated with Firebase and provides reasonable stability.

#### Web Considerations (deviceId stability)

Web storage can be cleared more often, so treat `deviceId` as “best effort” on web.

Recommended strategy:
1. **Prefer** Firebase Installation ID when available.
2. If unavailable/unstable on web, **fallback to a locally persisted UUID** (e.g., localStorage).
3. Accept that web “device identity” may reset; backend should handle multiple device docs per user and prune stale devices.

#### Web `deviceId` decision matrix

Web is inherently less stable than mobile because users can clear site data, use private browsing, rotate profiles, or block storage. Treat web `deviceId` as “best effort” and design for duplicates/staleness.

| Option | Stability (web) | Survives reload | Survives browser restart | Survives “Clear site data” | Privacy posture | Notes |
|---|---:|---:|---:|---:|---|---|
| Firebase Installation ID | Medium | Yes | Usually | No | Good | Best default when Firebase is already in use; can reset on storage clears/reinstall-like events. |
| localStorage UUID | Medium | Yes | Yes | No | Good | Simple fallback; generate once and store; resets when storage cleared or blocked. |
| IndexedDB UUID | Medium | Yes | Yes | No | Good | Similar to localStorage; sometimes more resilient depending on browser settings. |
| Cookie UUID | Low–Medium | Yes | Yes | Usually no (unless cookies cleared) | Medium | Cookies may be blocked (3rd-party contexts), shortened lifetimes, or cleared; adds complexity. |
| “Fingerprint” (UA/canvas/etc) | High (but brittle) | Yes | Yes | N/A | Poor | Do NOT use; privacy-invasive, increasingly blocked, and risky for policy/compliance. |
| Composite (platform + userId) | Low | Yes | Yes | N/A | Good | Not a real device identifier; cannot distinguish multiple browsers/devices; only useful as a fallback key for “per-user” storage. |

Recommendation for v1:
- **Use Firebase Installation ID on all platforms where available**.
- **On web, fallback to a locally persisted UUID** (localStorage or IndexedDB) if Installation ID is unavailable.
- If both are unavailable (storage disabled), generate an **ephemeral session UUID**; accept that it will create short-lived device docs.

Backend expectations:
- Multiple device docs per user are normal on web.
- Prune devices by `lastActiveAt` (and optionally `platform == 'web'`) to keep the collection clean.

---

## Service Interface

```dart
abstract class DeviceServiceInt {
  /// Registers or updates the current device in Firestore.
  ///
  /// Called on login/auth refresh (reactive hookup similar to NotificationService).
  ///
  /// This is best-effort and should not block the app startup.
  Future<Either<RepositoryFailure, Unit>> registerDevice();

  /// Updates timezone/offset if needed.
  ///
  /// Returns true if server was updated, false if unchanged (or throttled).
  ///
  /// IMPORTANT: Must update when either:
  /// - IANA timezone changes (travel)
  /// - UTC offset changes (DST) even if IANA timezone is unchanged
  Future<Either<RepositoryFailure, bool>> updateTimezoneOrOffsetIfChanged();

  /// Gets the current device's ID.
  Future<String> getDeviceId();

  /// Gets the current device's timezone.
  Future<String> getCurrentTimezone();

  /// Marks this device as active (updates lastActiveAt).
  Future<Either<RepositoryFailure, Unit>> touchDevice();

  /// Removes the current device registration.
  ///
  /// Called BEFORE logout while still authenticated.
  /// Hooked into AuthServiceImpl._onAboutToLogOutCallbacks.
  Future<Either<RepositoryFailure, Unit>> unregisterDevice();

  /// Gets all devices for the current user.
  Future<Either<RepositoryFailure, List<DeviceInfo>>> getMyDevices();
}
```

---

## Implementation Details

### When to Sync Device State

| Event | Action |
|-------|--------|
| Login / auth refresh | `registerDevice()` (creates/updates device) |
| App resume from background | `updateTimezoneOrOffsetIfChanged()` (lightweight check + throttled) |
| Periodic “keepalive” while app is used | `touchDevice()` (throttled; best-effort) |
| About-to-logout (while still authed) | `unregisterDevice()` (best-effort, timeboxed) |

Notes:
- `registerDevice()` should also set `_cachedTimezone` / `_cachedOffsetMinutes` on success.
- `touchDevice()` should not assume the doc exists (it should be an upsert server-side).

### Timezone / Offset Change Detection (DST-safe)

```dart
class DeviceServiceImpl implements DeviceServiceInt {
  String? _cachedTimezone;
  int? _cachedOffsetMinutes;
  DateTime? _lastServerSyncAt;
  DateTime? _lastTouchAt;

  @override
  Future<Either<RepositoryFailure, bool>> updateTimezoneOrOffsetIfChanged() async {
    // Fast local checks (no network)
    final currentTimezone = (await FlutterTimezone.getLocalTimezone()).identifier;
    final currentOffsetMinutes = DateTime.now().timeZoneOffset.inMinutes;

    // Throttle server writes to avoid resume spam.
    // Still allow immediate sync if timezone/offset changed.
    final now = DateTime.now();
    final recentlySynced = _lastServerSyncAt != null && now.difference(_lastServerSyncAt!) < const Duration(minutes: 15);

    final didChange = _cachedTimezone != currentTimezone || _cachedOffsetMinutes != currentOffsetMinutes;
    if (!didChange && recentlySynced) {
      return right(false);
    }

    // Update server (best-effort)
    await _syncDeviceTimezoneAndOffset(
      timezone: currentTimezone,
      timezoneOffsetMinutes: currentOffsetMinutes,
    );

    _cachedTimezone = currentTimezone;
    _cachedOffsetMinutes = currentOffsetMinutes;
    _lastServerSyncAt = now;

    return right(true);
  }
}

Guidance:
- Use `DateTime.now().timeZoneOffset.inMinutes` to compute offset; it naturally supports half-hour and 45-minute offsets.
- DST transitions are handled because `timeZoneOffset` changes even if the IANA timezone string doesn’t.
- The throttle window is a tunable constant (e.g., 15 minutes). You can also add a “force refresh once per day” to recover from missed DST events when the app isn’t opened around the transition.
```

### Integration with AuthService

The `DeviceService` should be initialized after authentication.

#### Reactive hookup pattern (mirror NotificationService)

Rather than requiring consumers to call the service in perfect order, provide a `connectToAuthService()` (or similar) entrypoint that:
- Registers an “on authenticated” callback to call `registerDevice()`.
- Registers an “about to logout” callback to call `unregisterDevice()` while still authenticated.
- Avoids throwing when called in unauthenticated state (no-op / typed failure).

```dart
// In AuthServiceImpl.handleAuthStateChanges or via callback
if (fbUser != null) {
  // User just authenticated
  await deviceService.registerDevice();
}

// On logout
await deviceService.unregisterDevice(); // MUST happen before signOut (best-effort)
```

#### Account switching on same device

Default behavior:
- On logout, `unregisterDevice()` attempts to remove the current user’s device doc (via about-to-logout callback).
- If it fails (offline/timeout), proceed with logout; backend cleanup handles staleness.
- On next login (possibly different user), `registerDevice()` registers the device for the new user.

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

### Single Source of Truth: Backend Time-Window Query Module

To avoid duplicating tricky time math across multiple scheduled jobs / callables, define a single backend module responsible for:

1. Computing the *candidate* Firestore query (based on `timezoneOffsetMinutes`) for “devices whose local time is within X minutes of Y:Z”.
2. Performing the *authoritative* local-time check using the device’s IANA `timezone` at decision time.
3. Handling DST/offline staleness by widening candidate queries (so we don’t miss devices whose `timezoneOffsetMinutes` is stale).

Recommended scaffolding module (consuming app Firebase Functions):

```
scaffolding/
└── firebase_functions/
    └── device/
        ├── device_time_queries.ts   # <-- single source of truth for time-window queries
        ├── timezone_utils.ts        # timezone helpers (IANA validation, offset computation)
        └── ...
```

#### Key rule: `timezone` is authoritative; `timezoneOffsetMinutes` is a query hint

- Backend must treat the IANA `timezone` string as the source of truth for correctness.
- `timezoneOffsetMinutes` exists primarily to make Firestore queries feasible.
- Scheduled jobs must **validate final eligibility** (e.g., “is it ~9:00 local time?”) using the IANA timezone at send-time.

This prevents “wrong-time sends” if the app wasn’t opened around a DST transition.

#### Recommended API surface (TypeScript)

```ts
// device_time_queries.ts

export type LocalTimeTarget = {
  hour: number;   // 0-23
  minute: number; // 0-59
};

export type LocalTimeWindowQueryOptions = {
  nowUtc?: Date;                 // default: new Date()
  windowMinutes: number;         // e.g. 15
  offsetQueryBufferMinutes?: number; // default: 60 (DST-safe widening)
  platforms?: Array<'ios' | 'android' | 'web'>;
};

export type DeviceDoc = {
  uid: string;
  deviceId: string;
  timezone: string;
  timezoneOffsetMinutes?: number;
  platform?: string;
  lastActiveAt?: FirebaseFirestore.Timestamp;
  // plus whatever else you store
};

/**
 * Returns candidate device docs whose *cached offsets* suggest their local time
 * may be in the target window.
 *
 * IMPORTANT: Candidates must be validated with `isNowInLocalTimeWindow()` using
 * the device's IANA timezone before sending notifications.
 */
export async function queryDeviceCandidatesByLocalTime(
  target: LocalTimeTarget,
  options: LocalTimeWindowQueryOptions,
): Promise<DeviceDoc[]>;

/**
 * Authoritative check: computes local time from IANA timezone at `nowUtc`.
 * This is the final gate before sending.
 */
export function isNowInLocalTimeWindow(
  timezone: string,
  target: LocalTimeTarget,
  nowUtc: Date,
  windowMinutes: number,
): boolean;
```

#### Standard timezone library recommendation

To keep time math consistent across functions and Node runtimes, standardize on a single timezone implementation.

**Recommendation (v1):** use `luxon`.

Why:
- Handles IANA timezones + DST correctly.
- Simple API for “convert UTC instant to local time in zone”.
- Avoids fragile `Intl.DateTimeFormat(...).formatToParts(...)` parsing.

Install (in consuming app Firebase Functions):

```bash
npm install luxon
npm install -D @types/luxon
```

#### Canonical implementation approach (Luxon)

The goal is that every backend job uses the same core helpers.

```ts
// timezone_utils.ts
import { DateTime } from 'luxon';

export function isValidIanaTimezone(timezone: string): boolean {
  // Luxon returns an invalid DateTime for unknown zones.
  return DateTime.utc().setZone(timezone).isValid;
}

export function getOffsetMinutesAtUtcInstant(timezone: string, nowUtc: Date): number {
  const dt = DateTime.fromJSDate(nowUtc, { zone: 'utc' }).setZone(timezone);
  if (!dt.isValid) throw new Error(`Invalid timezone: ${timezone}`);
  return dt.offset; // minutes
}

export function getLocalMinutesOfDay(timezone: string, nowUtc: Date): number {
  const dt = DateTime.fromJSDate(nowUtc, { zone: 'utc' }).setZone(timezone);
  if (!dt.isValid) throw new Error(`Invalid timezone: ${timezone}`);
  return dt.hour * 60 + dt.minute;
}
```

```ts
// device_time_queries.ts
import { getLocalMinutesOfDay } from './timezone_utils';

export function isNowInLocalTimeWindow(
  timezone: string,
  target: { hour: number; minute: number },
  nowUtc: Date,
  windowMinutes: number,
): boolean {
  const localNow = getLocalMinutesOfDay(timezone, nowUtc);
  const targetMinutes = target.hour * 60 + target.minute;

  // Circular distance on a 24h clock.
  const diff = Math.abs(localNow - targetMinutes);
  const circularDiff = Math.min(diff, 1440 - diff);
  return circularDiff <= windowMinutes;
}
```

Notes:
- Keep `nowUtc` explicit and pass it through all helpers to avoid accidental reliance on server local timezone.
- Use a “circular distance” check so windows around midnight work correctly.
- Treat invalid timezones as data-quality errors (skip device / log), not fatal for the entire batch.

#### Candidate query algorithm (offset-range selection)

We want “devices whose *local* time is within a window around $(H:M)$”.

- Let $u$ be the current UTC minutes-of-day (0–1439).
- Let $t$ be the target local minutes-of-day, $t = 60H + M$.
- Let the local-time window be $[t - w, t + w]$ in minutes (wraps across midnight).
- Local minutes-of-day is $(u + o) \bmod 1440$, where $o$ is `timezoneOffsetMinutes`.

To query via Firestore, compute 1–2 offset ranges for `timezoneOffsetMinutes` that could satisfy the window.

DST/offline staleness: widen the offset window by `offsetQueryBufferMinutes` (recommend default 60) so devices with stale cached offsets still become candidates.

After fetching candidates by offset range(s), always apply `isNowInLocalTimeWindow(device.timezone, ...)` to filter down to the truly eligible set.

Notes:
- Offset ranges can split into two due to midnight wrap. The module should hide this complexity.
- If `timezoneOffsetMinutes` is missing for some docs, either:
  - exclude them from the indexed query (preferred), or
  - include a fallback slow-path only for small populations.

#### Usage pattern (all scheduled jobs)

Any function that needs “devices where it’s currently ~X o’clock” should:

1. Call `queryDeviceCandidatesByLocalTime()`.
2. Filter candidates using `isNowInLocalTimeWindow()`.
3. Group by user/token as needed and send.

This ensures *every job* uses the same DST-safe logic and staleness buffers.

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

IMPORTANT: Since `timezoneOffsetMinutes` changes on DST transitions even when `timezone` does not, the client must periodically refresh it (see throttling notes above). Backend scheduled tasks can also tolerate some staleness by using wider windows and/or validating the IANA timezone at send-time.

**Updated guidance (preferred):** backend scheduled tasks should always validate the final send decision using the IANA `timezone` (authoritative). Use `timezoneOffsetMinutes` only to fetch candidates efficiently.

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

### Proposed answers (to make v1 implementation-ready)

1. **Device cleanup on logout**: Try to delete the device doc using `AuthServiceImpl._onAboutToLogOutCallbacks` (best-effort, timeboxed). If it fails, do not block logout; stale cleanup happens server-side.
2. **Offline handling**: Treat all server sync as best-effort. Persist a small local “pending sync” state (timezone, offset, last attempted time) and retry on next resume/login.
3. **Web deviceId**: Prefer Firebase Installation ID; fallback to localStorage UUID; accept resets.
4. **Rate limiting**: Use throttled `touchDevice()` and throttled `updateTimezoneOrOffsetIfChanged()`. Always bypass throttle when timezone/offset changed.

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

**Note:** Device writes go through Firebase Functions (server-side) and should NOT be done via direct client Firestore writes.

Recommended Firestore rules guidance for consuming apps:
- Deny client writes to `users/{uid}/devices/{deviceId}`.
- Allow reads only if you want client UI to list devices (or expose a callable to read instead).

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
  timezoneOffsetMinutes: number; // Client computed: DateTime.now().timeZoneOffset.inMinutes
  platform: "ios" | "android" | "web";
  appVersion: string;
  deviceInfo?: {
    model?: string;
    osVersion?: string;
  };
}

interface RegisterDeviceResponse {
  success: boolean;
  timezoneChanged: boolean;
  timezoneOffsetChanged: boolean;
  previousTimezone?: string;
}

/**
 * Registers or updates a device for the authenticated user.
 * Called by DeviceService.registerDevice() on app startup.
 *
 * This function:
 * 1. Validates the request data
 * 2. Uses client-provided timezoneOffsetMinutes (DST-safe, avoids fragile parsing)
 * 3. Creates or updates the device document
 * 4. Returns whether timezone or offset changed (useful for client-side logic)
 */
export const deviceRegister = onCall<RegisterDeviceRequest>(async (request) => {
  // Require authentication
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be logged in");
  }

  const uid = request.auth.uid;
  const { deviceId, timezone, timezoneOffsetMinutes, platform, appVersion, deviceInfo } = request.data;

  // Validate required fields
  if (!deviceId || !timezone || timezoneOffsetMinutes === undefined || !platform || !appVersion) {
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

  // timezoneOffsetMinutes is provided by the client.
  // It supports half/45-minute offsets and updates on DST transitions.
  if (!Number.isFinite(timezoneOffsetMinutes) || Math.abs(timezoneOffsetMinutes) > 14 * 60) {
    throw new HttpsError("invalid-argument", "Invalid timezoneOffsetMinutes");
  }

  // Prepare device data
  const deviceData = {
    timezone,
    timezoneOffsetMinutes,
    platform,
    appVersion,
    lastActiveAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    ...(deviceInfo && { deviceInfo }),
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
    timezoneOffsetChanged:
      previousTimezone !== null && existingDevice.exists
        ? existingDevice.data()?.timezoneOffsetMinutes !== timezoneOffsetMinutes
        : false,
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
  // Use merge=true to avoid failing if the doc doesn't exist yet.
  await db.doc(`users/${uid}/devices/${deviceId}`).set(
    {
      lastActiveAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

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
    final timezone = (await FlutterTimezone.getLocalTimezone()).identifier;
    final offsetMinutes = DateTime.now().timeZoneOffset.inMinutes;
    final packageInfo = await PackageInfo.fromPlatform();

    final result = await _deviceCallable.call({
      'deviceId': deviceId,
      'timezone': timezone,
      'timezoneOffsetMinutes': offsetMinutes,
      'platform': Platform.operatingSystem,
      'appVersion': packageInfo.version,
    });

    _cachedTimezone = timezone;
    _cachedOffsetMinutes = offsetMinutes;
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
