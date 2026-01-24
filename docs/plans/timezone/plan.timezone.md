# Device Service & Timezone Tracking Plan

## Overview

Create a `DeviceService` that tracks device-level information, with timezone as the primary initial use case. This service will be independent of, but complementary to, the existing notification/FCM token management.

Update (v1 direction): use a **single canonical Firestore document per install/profile** (`users/{uid}/devices/{deviceId}`) to store both:
- device state needed for timezone-aware logic (`timezone`, `timezoneOffsetMinutes`, `lastActiveAt`), and
- the *current* push token (when available) needed to deliver notifications.

`NotificationService` still owns **permission prompting + token acquisition**. `DeviceService` owns **device identity + timezone/active tracking**. The backend uses the *device doc* as the authoritative “deliverable endpoint” when it has a non-null `fcmToken`.

## Goals

1. Track device timezone independently of notification permissions
2. Keep timezone data fresh in Firestore for backend use
3. Support multi-device users with per-device timezone awareness
4. Provide a foundation for future device-level features
5. Enable backend systems to make timezone-aware decisions (notifications, scheduled jobs, analytics)

## Non-Goals (for initial implementation)

- Replacing or modifying notification permission UX or FCM/APNs token acquisition (that stays in `NotificationService`)
- Maintaining a full token history/audit trail (optional v2)
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
  ├── fcmToken: string?             // Current push token for this install/profile (nullable)
  ├── fcmTokenUpdatedAt: Timestamp? // Last time the token field was updated (server timestamp)
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
- `fcmToken` is the *current* deliverable token for this install/profile. It is intentionally stored on the device doc so scheduled jobs can pick the user’s active device and send without joins.

Definitions (v1):
- **Device doc**: one document per app install/profile (UUID `deviceId` persisted locally).
- **Deliverable endpoint**: a device doc with a non-null `fcmToken` and `lastActiveAt` within an “active window” (e.g., 30–90 days).
- **Active device** (per user): the deliverable endpoint with the greatest `lastActiveAt`.

Robustness rule (token rotation / stale mappings):
- Token updates are written by overwriting `fcmToken` on the *same* device doc.
- To prevent a token from lingering on multiple device docs due to offline failures, the backend should (best-effort) enforce uniqueness by clearing the same `fcmToken` from any other device docs found via `collectionGroup('devices').where('fcmToken', '==', token)` (rare path; runs only on token update).
```

### Device ID Strategy

#### Purpose and uniqueness requirements

The `deviceId` exists to provide a stable (idempotent) identifier for the *current app install/profile* so repeated calls to `registerDevice()` and `touchDevice()` update the same backend document:

`users/{uid}/devices/{deviceId}`

Uniqueness requirements:

- **Required**: unique per user (because it is namespaced by `uid` in the Firestore path).
- **Recommended**: globally unique format (UUIDv4) to minimize accidental collisions and to simplify debugging.

Stability requirements (v1 / “tier 1”):

- **Stable across app restarts** for a given install/profile.
- **Not required** to survive uninstall/reinstall (mobile/desktop) or “Clear site data” (web).
- Must tolerate duplicates/stale docs, cleaned up by `lastActiveAt`.

#### Recommendation (v1)

- Generate a **random UUIDv4** once and **persist it locally**.
- Treat web `deviceId` as **best-effort** (storage can be cleared/blocked).

This design models devices as “active endpoints (installs)”, which aligns with notification/timezone freshness use cases.

#### Web Considerations (deviceId stability)

Web storage can be cleared more often, so treat `deviceId` as “best effort” on web.

Recommended strategy:
1. **Prefer** a locally persisted UUID (IndexedDB or localStorage).
2. If storage is unavailable/blocked, generate an **ephemeral session UUID**.
3. Accept that web “device identity” may reset; backend should handle multiple device docs per user and prune stale devices.

Decision (v1):

- **DeviceId format:** UUIDv4.
- **Mobile/desktop persistence:** persist locally via the platform’s standard app storage.
- **Web persistence (priority order):**
  1. **IndexedDB** (preferred when available)
  2. **localStorage** (fallback)
  3. **In-memory session UUID** if persistent storage is unavailable/blocked/throws
- **Explicit non-goals:** do **not** use cookies for identity, and do **not** use fingerprinting.

Rationale:
- IndexedDB/localStorage UUIDs are “good enough” stability for the intended semantics (an *install/profile endpoint*).
- Ephemeral fallback keeps the app functional in private/blocked-storage scenarios, while accepting duplicate short-lived device docs.

Backend expectations:
- Multiple device docs per user are normal on web.
- Prune devices by `lastActiveAt` (and optionally `platform == 'web'`) to keep the collection clean.

Appendix: Web `deviceId` option matrix (background)

Web is inherently less stable than mobile because users can clear site data, use private browsing, rotate profiles, or block storage. This matrix is included as background for the v1 decision above.

| Option | Stability (web) | Survives reload | Survives browser restart | Survives “Clear site data” | Privacy posture | Notes |
|---|---:|---:|---:|---:|---|---|
| localStorage UUID | Medium | Yes | Yes | No | Good | Simple fallback; generate once and store; resets when storage cleared or blocked. |
| IndexedDB UUID | Medium | Yes | Yes | No | Good | Similar to localStorage; sometimes more resilient depending on browser settings. |
| Cookie UUID | Low–Medium | Yes | Yes | Usually no (unless cookies cleared) | Medium | Cookies may be blocked (3rd-party contexts), shortened lifetimes, or cleared; adds complexity. |
| “Fingerprint” (UA/canvas/etc) | High (but brittle) | Yes | Yes | N/A | Poor | Do NOT use; privacy-invasive, increasingly blocked, and risky for policy/compliance. |
| Composite (platform + userId) | Low | Yes | Yes | N/A | Good | Not a real device identifier; cannot distinguish multiple browsers/devices; only useful as a fallback key for “per-user” storage. |

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

  /// Updates the current device doc with the latest push token.
  ///
  /// This is called by NotificationService when:
  /// - a token is first obtained
  /// - a token rotates/refreshes
  /// - a token is deleted/unavailable (pass null)
  ///
  /// IMPORTANT: This does NOT prompt for permission; it only persists state.
  Future<Either<RepositoryFailure, Unit>> updateFcmToken({
    required String? fcmToken,
  });

  /// Removes the current device registration.
  ///
  /// Called BEFORE logout while still authenticated.
  /// Hooked into AuthServiceInt.addOnAboutToLogOutCallback.
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
| Push token obtained/rotated/deleted | `updateFcmToken(fcmToken: ...)` (called by NotificationService; best-effort) |
| About-to-logout (while still authed) | `unregisterDevice()` (best-effort, timeboxed) |

Notes:
- `registerDevice()` should also set `_cachedTimezone` / `_cachedOffsetMinutes` on success.
- `touchDevice()` should not assume the doc exists (it should be an upsert server-side).
- For efficiency, these actions may be coalesced into a single backend `upsertDevice` call when they occur close together (common on app startup/login).

#### Throttling discussion (pick v1 defaults)

We need specific values, but they should be chosen based on expected app usage patterns (resume frequency), acceptable Firestore write volume, and how aggressively we want to recover from missed DST transitions.

Clarifying terms (why questions #2 and #3 can feel redundant):

- **Unchanged min interval (resume throttle)**: “If nothing changed, don’t write more often than once every X.” This prevents spam on frequent resumes.
- **Unchanged max interval (forced refresh)**: “Even if nothing changed, ensure we write at least once every Y.” This is a safety net for DST transitions if the app isn’t opened near the transition.

If we set both values to the same duration (e.g., 48h), they effectively collapse into a single rule: “write unchanged at most once every 48h.”

Candidate starting points (not decisions):

- `updateTimezoneOrOffsetIfChanged()` throttle when unchanged: 5–30 minutes (common choice: 15)
- Forced refresh even if unchanged: 12–48 hours (common choice: 24)
  - Purpose: catch DST offset changes if the app wasn’t opened near the transition.
- `touchDevice()` throttle: 15–120 minutes (common choice: 60)
- `unregisterDevice()` timebox: 1–3 seconds best-effort (common choice: 2)

Decision needed:
- What are our v1 defaults for each throttle/timebox?

v1 decision (package defaults; all should be configurable by consuming apps):

- Always bypass throttles when timezone OR offset changed: **yes**
- `updateTimezoneOrOffsetIfChanged()` unchanged min interval (resume throttle): **48 hours**
- `updateTimezoneOrOffsetIfChanged()` unchanged max interval (forced refresh): **48 hours**
  - Note: this matches the desire to avoid unnecessary writes while still eventually updating offset for DST.
- `touchDevice()` throttle: **60 minutes**
- `unregisterDevice()` timebox: handled by existing auth “about-to-logout” hook timeout (see app config)

Configuration approach (plan-only):

- Add Remote Config / `AppConfigBase`-exposed settings for these values so consuming apps can tune based on:
  - how frequently the app resumes
  - whether backend jobs rely on `lastActiveAt` freshness
  - acceptable write volume

Tuning guidance for consuming apps (especially if backend relies on `lastActiveAt`):

- If backend scheduled jobs/analytics treat “active device” as `lastActiveAt >= now - X`, choose `touchDevice()` throttle such that typical users will still refresh `lastActiveAt` within that window during normal usage.
  - Example: if your backend filters to “active in last 24h”, a 60-minute touch throttle is usually fine.
  - If your backend needs tighter guarantees (e.g., “active in last 2h”), reduce the touch throttle accordingly.
- Keep timezone/offset sync much less frequent when unchanged (e.g., 48h) unless your backend makes near-real-time decisions from `timezoneOffsetMinutes`.
- When in doubt, prefer conservative writes (battery/network) and let backend logic tolerate staleness by widening candidate queries and validating by IANA timezone at send-time.

Suggested Remote Config keys (names TBD; these are placeholders):
- `deviceTimezoneUnchangedSyncMinMinutes` (default: 2880)
- `deviceTimezoneUnchangedSyncMaxMinutes` (default: 2880)
- `deviceTouchThrottleMinutes` (default: 60)

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

Goal: mirror `NotificationService`’s “self-wiring” auth integration so consuming apps do not need to manually call `registerDevice()` / `unregisterDevice()`.

#### Recommended pattern (v1): `DeviceService.connectToAuthService()`

Provide a single entrypoint that wires `DeviceService` into `AuthServiceInt`’s existing callback arrays:
- `addOnAuthenticatedCallback(...)` → calls `registerDevice()` (best-effort)
- `addOnRefreshedCallback(...)` → calls `registerDevice()` or a lightweight “ensure upsert” (best-effort)
- `addOnAboutToLogOutCallback(...)` → calls `unregisterDevice()` while still authenticated (best-effort)

This matches how `NotificationService.connectToAuthService()` abstracts auth lifecycle wiring.

Plan-level API sketch:

```dart
Future<void> connectToAuthService({
  AuthServiceInt? authService,
  // Optional overrides for consuming apps that want custom behavior.
  Future<void> Function(String? uid)? onAuthenticated,
  Future<void> Function()? onRefreshed,
  Future<void> Function()? onAboutToLogOut,
})
```

Behavior details (v1):
- If `authService` is null, attempt to resolve `AuthServiceInt` from GetIt (guarded; if not registered, log and no-op).
- Store the registered callbacks internally so repeated calls to `connectToAuthService()` are idempotent (remove old callbacks before adding new ones).
- Default handlers:
  - onAuthenticated: `registerDevice()` and (optionally) `touchDevice()`
  - onRefreshed: `registerDevice()` (keeps timezone/token metadata fresh when auth refresh occurs)
  - onAboutToLogOut: `unregisterDevice()`

Customization model:
- Consuming apps can override any of the three handlers for unusual flows.
- The default should be “works out of the box” with no configuration.

#### Account switching on same device

Default behavior:
- On logout, `unregisterDevice()` attempts to remove the current user’s device doc (via about-to-logout callback).
- If it fails (offline/timeout), proceed with logout; backend cleanup handles staleness.
- On next login (possibly different user), `registerDevice()` registers the device for the new user.

### Integration with NotificationService

Goal: keep notification delivery (push tokens) and timezone awareness (device docs) compatible **without coupling timezone tracking to notification permission**.

Recommended consuming-app setup (v1):
- Call `deviceService.connectToAuthService()` once during app startup (or enable auto-connect via config if you add such a flag).
- Call `notificationService.connectToAuthService(...)` once during app startup (do NOT remove this wiring; it still handles permission + token acquisition + local cleanup).
- Configure `NotificationService` so token lifecycle changes are forwarded to `DeviceService.updateFcmToken(fcmToken: ...)` (single backend writer).

Plan-level example:

```dart
await deviceService.connectToAuthService();

await notificationService.connectToAuthService(
  // IMPORTANT: delegate backend token persistence to DeviceService.
  // NotificationService still manages getting/deleting the token locally.
  onTokenChanged: (newToken, oldToken) async {
    await deviceService.updateFcmToken(fcmToken: newToken);
  },
);
```

Logout note (avoid duplicate backend calls):
- Backend cleanup should be driven by `DeviceService.unregisterDevice()` via `AuthServiceInt.addOnAboutToLogOutCallback`.
- If `NotificationService.connectToAuthService()` performs a backend unregistration callback on logout, that callback should either be disabled in this mode or delegate to `DeviceService.updateFcmToken(fcmToken: null)` only if you explicitly want to clear the token before deletion.

#### Avoiding duplicate backend calls (v1)

Because timezone/active tracking and push token tracking overlap, v1 should avoid having both services independently write to Firestore/Functions.

Decision (v1):
- **All backend persistence goes through a single “upsert device” path owned by `DeviceService`.**
- `NotificationService` never writes device/token state to the backend directly; it only acquires/deletes tokens and forwards token changes to `DeviceService.updateFcmToken(...)`.

This ensures:
- only one canonical document is updated (`users/{uid}/devices/{deviceId}`), and
- token + timezone + activity updates can be **coalesced** into a single backend call when they happen close together (common on app start/login).

Recommended implementation approach (plan-only):
- Provide a backend callable (name TBD) like `upsertDevice` that upserts `users/{uid}/devices/{deviceId}`.
- The callable accepts optional fields so callers can send “what they know now” without requiring multiple calls:
  - required: `deviceId`
  - optional: `timezone`, `timezoneOffsetMinutes`, `platform`, `appVersion`, `deviceInfo`
  - optional: `fcmToken` (nullable)
  - optional: `touch: true` to update `lastActiveAt`
- `DeviceService` maintains a short-lived in-memory “pending payload” and a debounce window (e.g., 250–1000ms) to merge:
  - `registerDevice()`
  - `updateTimezoneOrOffsetIfChanged()`
  - `touchDevice()`
  - `updateFcmToken()`
  into a single `upsertDevice` call when triggered by the same lifecycle event.

Notes:
- Coalescing is an optimization; correctness does not depend on it.
- If coalescing feels too magical for v1, keep it simple but still follow the key rule: NotificationService forwards token state to DeviceService so only one service writes.

#### Canonical collection (v1)

Store everything required to (a) pick the user’s current active device and (b) deliver to it in one place:

```
users/{uid}/devices/{deviceId}
  ├── timezone: string
  ├── timezoneOffsetMinutes: int
  ├── lastActiveAt: Timestamp
  ├── platform: string
  ├── fcmToken: string?             // nullable when notifications are unavailable/disabled
  ├── fcmTokenUpdatedAt: Timestamp?
  └── ... (minimal device metadata)
```

Ownership rules (v1):
- `DeviceService` owns: `deviceId` generation, `timezone`/`timezoneOffsetMinutes`, `lastActiveAt`, and minimal device metadata.
- `NotificationService` owns: permission prompting and acquiring/deleting the push token.
- `NotificationService` informs `DeviceService` via `updateFcmToken(fcmToken: ...)`.

Robustness rules (v1):
- Token rotation is handled by overwriting `devices/{deviceId}.fcmToken`.
- Backend scheduled jobs MUST read the token from the chosen active device doc at send time (no stale token lists).
- On token update, backend should (best-effort) enforce “token appears on at most one device doc” using a `collectionGroup('devices')` equality query and clearing stale references.

#### Network call minimization (v1)

To keep accuracy while reducing calls:
- Prefer a **single backend callable** that upserts the device doc and accepts:
  - `deviceId`, `timezone`, `timezoneOffsetMinutes`, `platform`, `appVersion`
  - optional `fcmToken` (when available)
  - optional `touch` flag to update `lastActiveAt`
- When notifications are disabled/unavailable: call the same callable without `fcmToken`.

This keeps timezone tracking independent of notification permission while still allowing “active device in local time” notifications.

#### Logout / account switching (robustness)

On logout, both “stop sending pushes for this user” and “stop considering this device active for this user” must happen while still authenticated.

Decision (v1): use the existing AuthService “about-to-logout” hook to trigger a single coordinated cleanup step:
- `DeviceService.unregisterDevice()` deletes `users/{uid}/devices/{deviceId}` (best-effort).
- `NotificationService` deletes the local FCM token (best-effort) so that even if backend cleanup fails, any remaining server-side sends to that token will start failing.

Important ordering / race note:
- If these happen concurrently, that’s acceptable.
- If deletion fails (offline), staleness cleanup still applies, but deleting the local token reduces the risk of cross-account notification leakage on shared devices.

#### Optional v2 (only if needed): token-centric docs

If a consuming app later needs token history/audit, token-level staleness pruning, or truly token-centric `collectionGroup('fcmTokens')` scheduling, add a token subcollection:

```
users/{uid}/devices/{deviceId}/fcmTokens/{tokenHash}
  ├── token: string
  ├── createdAt: Timestamp
  ├── updatedAt: Timestamp
  ├── lastSeenAt: Timestamp
  └── ...
```

This preserves “one canonical device doc” while allowing multi-token edge cases without introducing a second peer collection.

---

## Backend Considerations

### Scheduling query unit (v1): devices

For v1, scheduled notification jobs should query **device docs** and send to the token stored on the chosen active device.

Recommendation (v1):
- Query `collectionGroup('devices')` by `timezoneOffsetMinutes` (with an offset buffer) and any optional filters like `platform` and `lastActiveAt`.
- Validate final eligibility using the device’s IANA `timezone` at send-time.
- Choose per-user delivery policy (e.g., “most recent active device”) by ranking on `lastActiveAt`.
- Send to `device.fcmToken` for the selected device.

This avoids joins and avoids maintaining separate token docs while remaining DST-safe.

### Notification targeting patterns (industry defaults)

FCM/APNs do not automatically choose “the right device”. They deliver to the token(s) you target. The backend must decide which token set is eligible.

Common patterns (all should be supported by this data model):
- **Send to all active devices**: simplest and most common. Good for critical/transactional notifications. Requires good staleness cleanup.
- **Send to most-recently-active device only**: reduces noise for multi-device users. Common for “daily reminder” style notifications.
- **Send to N most-recent devices**: compromise between reliability and noise.
- **Platform preference / fallback**: e.g., prefer mobile over web.
- **Quiet hours / local-time windows**: use timezone to align with user context.

Recommended v1 defaults (configurable by consuming apps):
- Default delivery policy for “reminders” (like 9am local time): **send to most-recently-active device**, with an optional fallback to “send to all active devices” if no device has been active recently.
- Default delivery policy for critical alerts: **send to all active devices**.

Data needed to support these policies efficiently:
- `users/{uid}/devices/{deviceId}.lastActiveAt` to rank devices by recency.
- `users/{uid}/devices/{deviceId}.fcmToken` to deliver to the chosen active device.
- `platform` on device docs to support platform preference.

Platform preference guidance (v1):
- Store `platform` on **device docs** because scheduled sending starts from device docs in v1.
- Prefer applying platform preference in-memory after your primary candidate query (typically by timezone offset/time window). Adding extra Firestore `where` clauses for platform is usually not worth the index/write complexity unless your scale demands it.

Efficiency note (9am local time scheduling):
- Scheduled jobs query candidate devices by offset/time window, pick per-user winners (most recent), then send to the token on that device doc.

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
  uuid: ^x.x.x                        # For deviceId generation
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

### Discussion (work these into v1 decisions)

#### v1 selections so far (based on discussion)

- **(1) Device cleanup on logout**: Choose **A: Delete on logout (best-effort)**.
  - Use the existing AuthService “about-to-logout” hook (with its timeout) to call `unregisterDevice()` before sign-out.
- **(2) Offline handling**: Choose **B: Best-effort + persist pending sync**.
  - Persist a minimal “pending sync” payload and retry on next resume/login.
- **(3) Web platform (deviceId stability)**: Choose **A: Best-effort persisted UUID + ephemeral fallback**.
  - Duplicates are acceptable; staleness cleanup via `lastActiveAt` should naturally prune over time.
- **(4) Privacy**: Choose **A: Minimal schema by default**.
  - Device tracking must remain **independent of notification permission** (timezone/device registration should not require notification permission).

1. **Device cleanup on logout**

Options:
- **A: Delete on logout (best-effort)**: call `unregisterDevice()` before sign-out.
  - Pros: fewer stale docs, simpler “active devices” semantics.
  - Cons: deletion might fail (offline); also loses “recent device” history unless backend captures it elsewhere.
- **B: Never delete; rely on staleness**: keep device docs and let `lastActiveAt` determine active vs inactive.
  - Pros: preserves history/debugging; fewer failure cases on logout.
  - Cons: devices collection grows; requires cleanup/ignore logic.
- **C: Soft-delete**: set `disabledAt`/`loggedOutAt` instead of deleting.
  - Pros: keeps history while marking inactive.
  - Cons: more schema + logic, and still needs cleanup.

Decision prompts:
- Do we want device docs to represent “current endpoints” (A) or “known endpoints” (B/C)?
- If we keep docs (B/C), what is the canonical staleness threshold for “active” (e.g., 30/60/90 days)?

v1 decision:
- Use **A: Delete on logout (best-effort)** using `AuthServiceInt.addOnAboutToLogOutCallback` (timeboxed by existing hook).

Plan invariants (required for Option A correctness + safety):
- Logout cleanup is **best-effort** and **timeboxed**; it must never block logout or make logout fail.
- Backend must treat “deliverable endpoints” as **eligible only when** `fcmToken != null` **and** `lastActiveAt` is within an “active window” (e.g., 30–90 days). This rule must be enforced by all scheduled jobs/callables regardless of logout behavior.
- Deleting the device doc is an optimization, not a correctness dependency: if deletion fails offline, backend eligibility rules + staleness handling must still prevent long-term sends.
- On logout, `NotificationService` should still delete the **local** push token (best-effort) to reduce cross-account notification risk even if backend cleanup fails.

2. **Offline handling**

Options:
- **A: Best-effort only**: if a sync fails, do nothing; next lifecycle event tries again naturally.
  - Pros: simplest.
  - Cons: may take longer to recover if app resumes frequently but always throttles “unchanged” cases.
- **B: Best-effort + persist pending sync**: store the last attempted payload and retry on next resume/login.
  - Pros: better eventual consistency.
  - Cons: adds a little local state and backoff rules.
- **C: Background retry**: schedule retries in the background (platform-dependent).
  - Pros: fastest eventual consistency.
  - Cons: complexity; background execution constraints.

Decision prompts:
- Is “eventual update when user opens app again” acceptable (A), or do we want a small pending-sync mechanism (B)?
- If we do pending-sync, what’s the simplest backoff rule (e.g., max once per resume, minimum 10–15 minutes between attempts)?

v1 decision:
- Use **B: Best-effort + persist pending sync**.

Plan details (v1: minimal pending-sync spec):
- Persist a single **pending upsert payload** locally (overwrite/merge in place; not a queue) so the system converges without unbounded growth.
- Payload shape (minimal; fields optional unless noted):
  - required: `deviceId`
  - optional: `timezone`, `timezoneOffsetMinutes`, `fcmToken` (nullable), `touch` (bool)
  - metadata: `pendingUpdatedAt` (local timestamp), `lastAttemptAt` (local timestamp)
- Merge rules when new intent arrives:
  - Per-field last-write-wins for `timezone`, `timezoneOffsetMinutes`, `fcmToken`.
  - `touch` is sticky: once true, it stays true until a successful flush.
  - Allow `fcmToken: null` to represent explicit clearing (e.g., token deleted/rotated away).
- Flush triggers (best-effort; should not block UI flows):
  - On any lifecycle entrypoint that already exists in the plan: login/auth refresh (`registerDevice()`), resume (`updateTimezoneOrOffsetIfChanged()`), periodic keepalive (`touchDevice()`), and token changes (`updateFcmToken(...)`).
  - Additionally: if a flush is skipped due to backoff, keep the pending payload and retry on the next trigger.
- Backoff / rate limiting (keep it simple):
  - Enforce a minimum time between flush attempts (recommend starting point: 10–15 minutes) using `lastAttemptAt`.
  - Bypass backoff when timezone, offset, or token changed (i.e., pending payload represents a correctness-relevant change, not just a touch).
- Success / failure semantics:
  - On successful backend ack: clear the pending payload.
  - On failure (offline, timeout, transient errors): keep the pending payload, update `lastAttemptAt`, and return without surfacing an error to the user.
  - Never allow pending-sync failures to block login/logout/resume flows; they are strictly “eventual consistency”.
- Auth precondition:
  - If not authenticated when an update intent occurs, store pending and flush on next authenticated event.

3. **Web platform (deviceId stability)**

Options:
- **A: Best-effort persisted UUID** (localStorage/IndexedDB) + ephemeral fallback when storage unavailable.
- **B: Session-only device identity** (always ephemeral).
  - Pros: simplest + privacy-forward.
  - Cons: creates many short-lived device docs; noisy.

Decision prompts:
- Is it acceptable that web creates duplicate docs sometimes (A), assuming backend cleanup by staleness?
- Do we want to special-case web cleanup thresholds (e.g., shorter retention)?

v1 decision:
- Use **A: Best-effort persisted UUID + ephemeral fallback**.
- Accept duplicates; rely on staleness cleanup over time.

4. **Privacy considerations**

Options:
- **A: Minimal schema by default**: only timezone/offset/platform/appVersion + timestamps.
- **B: Add `deviceInfo` (opt-in)**: model/osVersion for debugging.

Decision prompts:
- Should `deviceInfo` be collected by default, or only when consuming apps explicitly enable it?
- Any compliance constraints we need to respect in this package’s defaults/documentation?

v1 decision:
- Use **A: Minimal schema by default**.
- Keep device tracking independent of notification permission (no coupling to notification opt-in).

5. **Rate limiting**

Key design questions:
- How often does the app typically resume in real usage?
- How costly is an extra write vs the risk of stale offsets around DST?

Decision prompts:
- Choose v1 defaults for throttles/timeboxes (see “Throttling discussion” above).
- Confirm the “always bypass throttle on timezone OR offset change” rule.
- Do we want a forced refresh cadence (e.g., every 24h) to recover from missed DST transitions?

v1 decision:
- Always bypass throttle on timezone OR offset change: **yes**
- Set unchanged sync intervals to **48 hours** (and expose via Remote Config / `AppConfigBase` for consuming apps).
- Set `touchDevice()` throttle default to **60 minutes** (configurable via Remote Config / `AppConfigBase`).

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

````markdown
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
````

### Open Questions

1. Should the scaffolding include test files for the functions?
2. Should there be a "minimal" (just callable) vs "full" (scheduled + triggers) version?
3. How do we communicate breaking changes in the scaffolding to consuming apps?

### Discussion (scaffolding)

1. Should the scaffolding include test files for the functions?

Options:
- **A: Minimal tests included** (recommended if we want confidence): unit tests for `timezone_utils` and the local-time window math.
- **B: No tests** (simpler scaffolding): consumers add tests if/when they adopt.

Decision prompt:
- Do we want this package to ship “reference tests” as part of the template?

2. Should there be a "minimal" (just callable) vs "full" (scheduled + triggers) version?

Options:
- **A: One folder, optional files**: `device_callable.ts` required; scheduled/triggers optional; README describes both installs.
- **B: Two folders**: `device_minimal/` and `device_full/`.

Decision prompt:
- Which is easier for consuming apps to adopt correctly without copy/paste mistakes?

3. How do we communicate breaking changes in the scaffolding to consuming apps?

Options:
- **A: Header comment only**: `@packageVersion` + short guidance.
- **B: Add a template changelog**: e.g., `scaffolding/firebase_functions/device/CHANGELOG.md` and/or “Upgrade notes” section in README.

Decision prompt:
- Do we want to treat scaffolding changes as semver-governed (recommended), and if so, where do we document required fields/indexes?

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
