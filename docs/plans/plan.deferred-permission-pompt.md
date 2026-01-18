# Plan: Deferred FCM Notification Permission Prompt

## Problem
Currently, `AuthServiceImpl.initFCM()` is called automatically in `handleTokenChanges()` when a user authenticates (line 166). This triggers the iOS/Android notification permission dialog immediately on login, which may not be ideal UX.

**Additional Problem:** FCM token registration code is embedded in `AuthServiceImpl` (lines 1698-1803), but there's already a dedicated `NotificationService` at `lib/notifications/notification_service.dart`. This creates:
- **Duplicate concerns**: Both services deal with FCM/notifications
- **Unclear ownership**: Where should new notification features go?
- **Coupling**: Auth service shouldn't know about FCM tokens

## Goal
Allow consuming apps to:
1. Delay the permission prompt until a more appropriate time
2. Trigger the permission request manually when ready
3. **Consolidate FCM token management into the existing `NotificationService`** - remove it from `AuthServiceImpl`

## Plan Adjustments from Code Review ✅ INCORPORATED

All adjustments have been incorporated into the plan:

| Adjustment | Status | Where Addressed |
|------------|--------|-----------------|
| **Single owner for permission prefs** | ✅ | Step 0 (lines 69-151): Migration to `dreamic_`-prefixed keys, `NotificationPermissionHelper` owns all permission keys, `NotificationService` delegates |
| **Settings opening + lifecycle** | ✅ | "Automatic Resume Handling" section (lines 1307-1358): Uses `AppLifecycleService.lifecycleStream` with guarded listener |
| **Preserve enum compatibility** | ✅ | Reuses existing `NotificationPermissionStatus` model (no new permission-status enum; “permanent denial” is derived for flow decisions), new result enums are separate types |
| **FCM web default clarity** | ✅ | Section 1a (lines 449-529): `useFCMWeb` defaults to `false` (requires VAPID setup), explicit enable via `useFCMWebDefault = true`. **Deliberate breaking change**: web FCM becomes opt-in; call out in changelog + migration docs. |
| **FCM token key migration** | ✅ | Lines 86-92, 227-241: Uses `dreamic_fcm_token`, migrates from `commonSharedKeyFcmToken`, clears both on sign-out |

<details>
<summary>Original adjustment requirements (for reference)</summary>

- **Single owner for permission prefs:** Move all permission counters/timestamps into `NotificationPermissionHelper` with `dreamic_`-prefixed keys; have `NotificationService` delegate to the helper instead of keeping its own keys. Add a migration that reads the legacy `notification_*` keys and clears them after copy.
- **Settings opening + lifecycle:** Use `permission_handler` `openAppSettings()` for the go-to-settings step, and wire a guarded listener to `AppLifecycleService.lifecycleStream` to re-check permission status after returning from settings (initialize the lifecycle service before subscribing).
- **Preserve enum compatibility:** Reuse the existing `NotificationPermissionStatus` enum (authorized/denied/notDetermined/provisional). If new result enums are added (e.g., flow/init results), keep the permission status type shared so `NotificationPermissionBuilder` continues to work.
- **FCM web default clarity:** Keep current behavior (FCM on by default except iOS simulator). If adding `useFCMWeb`, default it to match today to avoid silent web regressions; document any override flags explicitly.
- **FCM token key migration:** Introduce `dreamic_fcm_token` while reading the legacy `commonSharedKeyFcmToken`; migrate on first read/refresh and clear both on sign-out. When moving token logic into `NotificationService`, reuse the same migration to avoid token loss.
</details>

## Proposed Solution

### 0. Consolidate FCM Token Management into NotificationService

**Current State - Code Duplication:**

| Concern | AuthServiceImpl | NotificationService | NotificationPermissionHelper |
|---------|-----------------|---------------------|------------------------------|
| FCM permission request | `initFCM()` line 1705 | `requestPermissions()` line 591 | ❌ Delegates to service |
| FCM token retrieval | `initFCM()` line 1743 | ❌ Not handled | ❌ Not handled |
| Token refresh listener | `initFCM()` line 1761 | ❌ Not handled | ❌ Not handled |
| Server token sync | `_updateTokenOnServer()` | ❌ Not handled | ❌ Not handled |
| Permission tracking | ❌ Not handled | `_trackPermissionRequest/Denial()` | `trackPermissionRequest()`, `getPermissionRequestCount()`, `getPermissionDenialCount()` |
| APNS token handling | `initFCM()` lines 1718-1735 | ❌ Not handled | ❌ Not handled |
| Permission status checks | ❌ Not handled | `getPermissionStatus()` | `isPermissionGranted()`, `isPermissionDenied()`, `isPermissionNotDetermined()` |
| Should show rationale | ❌ Not handled | ❌ Not handled | `shouldShowPermissionRationale()` |
| Can prompt for permission | ❌ Not handled | ❌ Not handled | `canPromptForPermission()` |
| Should show settings | ❌ Not handled | ❌ Not handled | `shouldShowSettingsPrompt()` |
| Periodic reminders | ❌ Not handled | `shouldShowPeriodicReminder()` | `shouldShowPeriodicReminder()` |
| Optimal context suggestion | ❌ Not handled | ❌ Not handled | `getOptimalContext()` |

**Existing Asset: `NotificationPermissionHelper`**

There's already a `NotificationPermissionHelper` class at `lib/notifications/notification_permission_helper.dart` that provides much of the permission flow logic we need. Rather than creating parallel functionality, we should **enhance this helper** and integrate it more tightly with `NotificationService`.

**Current `NotificationPermissionHelper` capabilities:**
- ✅ Permission status checks (`isPermissionGranted()`, `isPermissionDenied()`, `isPermissionNotDetermined()`)
- ✅ Platform-aware logic (`canPromptForPermission()` - knows iOS can't re-prompt after denial)
- ✅ Rationale detection (`shouldShowPermissionRationale()` - Android-specific)
- ✅ Settings prompt logic (`shouldShowSettingsPrompt()` - after 2+ denials on Android)
- ✅ Request/denial tracking (`getPermissionRequestCount()`, `getPermissionDenialCount()`)
- ✅ Periodic reminders (`shouldShowPeriodicReminder()`)
- ✅ Optimal timing suggestions (`getOptimalContext()`)
- ✅ Request tracking (`trackPermissionRequest()`, `updateLastReminderDate()`)

**Gaps to fill in `NotificationPermissionHelper`:**
- ❌ `NotificationDenialInfo` class structure (currently separate int fields)
- ❌ `GoToSettingsPromptInfo` tracking
- ❌ `requestAttemptCount` vs `denialCount` distinction (for blocked request detection)
- ❌ `lastRequestWasBlocked` tracking
- ❌ Auto-clear when permission detected as granted
- ❌ High-level flow orchestration (`runNotificationPermissionFlow()`)

**Migration Plan:**

#### Step 0: Fix SharedPreferences Key Duplication (PREREQUISITE)

**Current Problem:** Both `NotificationService` (lines 112-115) and `NotificationPermissionHelper` (lines 16-19) define **identical** keys without a unique prefix:

```dart
// CURRENT - BOTH files have these IDENTICAL keys (BAD)
static const String _keyPermissionRequestCount = 'notification_permission_request_count';
static const String _keyPermissionDenialCount = 'notification_permission_denial_count';
static const String _keyLastPermissionRequest = 'notification_last_permission_request';
static const String _keyLastReminderDate = 'notification_last_reminder_date';
```

**Fix:** All Dreamic SharedPreferences keys MUST use the `dreamic_` prefix to avoid collisions with consuming apps. The only file currently using this prefix is `network_utils.dart` (`dreamic_firebase_emulator_host_address`).

**New Key Ownership After Migration:**

| Key | Owner | Purpose |
|-----|-------|---------|
| `dreamic_fcm_token` | NotificationService | Cached FCM token |
| `dreamic_notification_denial_info` | NotificationPermissionHelper | JSON with denial tracking |
| `dreamic_notification_settings_prompt_info` | NotificationPermissionHelper | JSON with go-to-settings tracking |
| `dreamic_notification_has_requested` | NotificationPermissionHelper | Boolean for Android permanent denial detection |
| `dreamic_notification_last_reminder_date` | NotificationPermissionHelper | Timestamp for periodic reminder logic |

**Migration Code (add to NotificationPermissionHelper):**

```dart
/// Migrates old SharedPreferences keys to new dreamic_ prefixed keys.
/// Call this once during initialization. Safe to call multiple times.
Future<void> _migrateOldKeys() async {
  final prefs = await SharedPreferences.getInstance();

  // Old keys (without prefix)
  const oldKeys = {
    'notification_permission_request_count': 'requestCount',
    'notification_permission_denial_count': 'denialCount',
    'notification_last_permission_request': 'lastRequest',
    'notification_last_reminder_date': 'lastReminder',
  };

  // Check if migration already done
  if (prefs.getBool('dreamic_notification_keys_migrated') == true) {
    return;
  }

  // Read old values
  final oldRequestCount = prefs.getInt('notification_permission_request_count');
  final oldDenialCount = prefs.getInt('notification_permission_denial_count');
  final oldLastRequest = prefs.getInt('notification_last_permission_request');
  final oldLastReminder = prefs.getInt('notification_last_reminder_date');

  // If any old data exists, migrate to new structure
  if (oldDenialCount != null && oldDenialCount > 0) {
    final denialInfo = NotificationDenialInfo(
      lastDenialTime: oldLastRequest != null
          ? DateTime.fromMillisecondsSinceEpoch(oldLastRequest)
          : DateTime.now(),
      denialCount: oldDenialCount,
      isPermanent: false, // Conservative - will be updated on next status check
      requestAttemptCount: oldRequestCount ?? oldDenialCount,
    );
    await prefs.setString('dreamic_notification_denial_info', jsonEncode(denialInfo.toJson()));
  }

  if (oldLastReminder != null) {
    await prefs.setInt('dreamic_notification_last_reminder_date', oldLastReminder);
  }

  // Clean up old keys
  for (final oldKey in oldKeys.keys) {
    await prefs.remove(oldKey);
  }

  // Mark migration complete
  await prefs.setBool('dreamic_notification_keys_migrated', true);
  logd('Migrated notification permission keys to dreamic_ prefix');
}
```

**Remove duplicate keys from NotificationService:**
- Delete lines 112-115 (the `_key*` constants)
- Update all methods that use these keys to delegate to `NotificationPermissionHelper`

#### Step 1: Move FCM token management to NotificationService

**Add to `lib/notifications/notification_service.dart`:**

```dart
// New fields
String? _cachedFcmToken;
StreamSubscription<String>? _tokenRefreshSubscription;

// Callback for server sync (injected by consuming app)
/// Callback invoked when a token should be registered/updated, or unregistered.
///
/// - If [newToken] is non-null: register/update mapping on backend.
/// - If [newToken] is null: unregister [oldToken] on backend (best-effort).
Future<void> Function(String? newToken, String? oldToken)? _onTokenChanged;

/// Initializes FCM token management and syncs with server.
///
/// Call this after user is authenticated. The service will:
/// 1. Get the current FCM token
/// 2. Sync it to the server via [onTokenChanged]
/// 3. Listen for token refreshes and sync automatically
///
/// [onTokenChanged] is called when the token changes. Use this to sync
/// the token to your backend server.
Future<void> initializeFcmToken({
  required Future<void> Function(String? newToken, String? oldToken) onTokenChanged,
}) async {
  _onTokenChanged = onTokenChanged;

  // Handle APNS token for iOS/macOS
  if (!kIsWeb && (Platform.isIOS || Platform.isMacOS)) {
    await _waitForApnsToken();
  }

  // Get initial token
  try {
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      final oldToken = await _getStoredToken();
      // Prefer the persisted token as the source of truth for “old token”
      // (cached in-memory values may be null on cold start).
      if (token != oldToken) {
        await _onTokenChanged!(token, oldToken);
        await _storeToken(token);
      }
      _cachedFcmToken = token;
    }
  } catch (e) {
    loge('Failed to get FCM token: $e');
    return; // Non-critical, don't propagate
  }

  // Listen for token refreshes
  _tokenRefreshSubscription = FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
    final oldToken = await _getStoredToken();
    try {
      await _onTokenChanged!(newToken, oldToken);
      await _storeToken(newToken);
      _cachedFcmToken = newToken;
    } catch (e) {
      loge('Error syncing refreshed token: $e');
    }
  });
}

Future<void> _waitForApnsToken() async {
  int retries = 0;
  String? apnsToken;
  while (apnsToken == null && retries < 30) {
    apnsToken = await FirebaseMessaging.instance.getAPNSToken();
    if (apnsToken == null) {
      await Future.delayed(const Duration(milliseconds: 250));
      retries++;
    }
  }
  if (apnsToken == null) {
    loge('APNS token not available after waiting');
  }
}

/// Legacy key from AuthServiceImpl - migrate on first read
static const String _legacyFcmTokenKey = 'commonSharedKeyFcmToken';
static const String _fcmTokenKey = 'dreamic_fcm_token';

Future<String?> _getStoredToken() async {
  final prefs = await SharedPreferences.getInstance();

  // Try new key first
  var token = prefs.getString(_fcmTokenKey);

  // Migrate from legacy key if new key is empty
  if (token == null) {
    final legacyToken = prefs.getString(_legacyFcmTokenKey);
    if (legacyToken != null) {
      logd('Migrating FCM token from legacy key to dreamic_ prefix');
      await prefs.setString(_fcmTokenKey, legacyToken);
      await prefs.remove(_legacyFcmTokenKey);
      token = legacyToken;
    }
  }

  return token;
}

Future<void> _storeToken(String token) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_fcmTokenKey, token);
  // Also remove legacy key if it exists (in case of upgrade during active session)
  if (prefs.containsKey(_legacyFcmTokenKey)) {
    await prefs.remove(_legacyFcmTokenKey);
  }
}

/// Clears the stored FCM token. Call this on sign out.
/// Clears both new and legacy keys to ensure clean state.
Future<void> clearFcmToken() async {
  _cachedFcmToken = null;
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_fcmTokenKey);
  await prefs.remove(_legacyFcmTokenKey);  // Clear legacy key too
}
```

#### Step 2: Remove FCM code from AuthServiceImpl

**Remove from `lib/data/repos/auth_service_impl.dart`:**

- `useFirebaseFCM` field (line 39)
- `_hasInitializedFCM` field (line 46)
- `sharedPrefKeyFcmToken` constant (line 26)
- FCM initialization in `handleTokenChanges()` (lines 163-170)
- `initFCM()` method (lines 1698-1779)
- `_updateTokenOnServer()` method (lines 1781-1803)

**Keep in AuthServiceImpl:**
- `isLoggedInStream` - NotificationService will subscribe to this

#### Step 3: Update consuming app integration

> **Architecture Note:** `NotificationService` subscribes to `AuthService.isLoggedInStream` (not vice versa).
> This is the correct direction of dependency: notifications depend on auth state, but auth should not know about notifications.
>
> **Good news:** `isLoggedInStream` is already defined in `AuthServiceInt` interface (line 13), so no interface changes needed.

**⚠️ BREAKING CHANGE: `useFirebaseFCM` parameter removed**

The `useFirebaseFCM` constructor parameter is being removed from `AuthServiceImpl`. Consuming apps MUST update their code.

**Before (deprecated - will cause compile error):**
```dart
// OLD WAY - AuthServiceImpl handled FCM internally
final authService = AuthServiceImpl(
  firebaseApp: app,
  useFirebaseFCM: true,  // ❌ This parameter is REMOVED
);
```

**After (new API):**
```dart
// NEW WAY - Auth service has no FCM knowledge
final authService = AuthServiceImpl(firebaseApp: app);

// Notification service - owns all FCM
final notificationService = NotificationService();
await notificationService.initialize(...);

// NotificationService subscribes to auth events (NOT the other way around)
authService.isLoggedInStream.listen((isLoggedIn) async {
  if (isLoggedIn) {
    await notificationService.initializeFcmToken(
      onTokenChanged: (newToken, oldToken) async {
        // Call your backend to sync the token
        await myBackendService.updateFcmToken(newToken, oldToken);
      },
    );
  } else {
    await notificationService.clearFcmToken();
  }
});
```

**Migration Checklist for Consuming Apps:**
- [ ] Remove `useFirebaseFCM: true` from `AuthServiceImpl` constructor
- [ ] Call `NotificationService.initialize()` during app startup (required) — it now auto-wires auth if available
- [ ] Provide `onTokenChanged` only if you need custom backend wiring; otherwise the default callable sync is used
- [ ] If you cannot register auth in GetIt or need delayed wiring, use `connectToAuthService` manually
- [ ] Update tests that mock `AuthServiceImpl` with `useFirebaseFCM` parameter

#### Step 4: Auth wiring + token sync defaults (updated)

- `NotificationService.initialize(...)` gains optional auth input; if not provided, it attempts to resolve auth from GetIt (guarded: only when registered; otherwise it logs and skips). When an auth stream is found, it subscribes to `isLoggedInStream` to init/clear tokens automatically.
- `onTokenChanged` becomes optional. If not supplied, NotificationService uses the configured Cloud Function(s) from `AppConfigBase` (`notificationsUpdateFcmTokenFunction` or grouped function/action) to sync `newToken`/`oldToken`. Supplying `onTokenChanged` overrides this default (for custom REST, headers, etc.).
- `connectToAuthService` remains available for apps that prefer manual or delayed wiring.
- Logout handling (required, **pre-logout unregister**): before the client drops auth, NotificationService must unregister the current token while the user is still authenticated. Sequence: (1) on logout intent, call backend unregister using the default callable/action (or custom `_onTokenChanged(newToken: null, oldToken: lastToken)`), (2) then sign out, stop token refresh subscriptions, (3) call `FirebaseMessaging.deleteToken()`, (4) clear stored tokens for both `dreamic_fcm_token` and legacy `commonSharedKeyFcmToken`. This avoids a scenario where the backend rejects the unregister due to missing auth after sign-out.
- Logout timing + resilience (clarification):
  - Sign-out path should invoke a `NotificationService.preLogoutCleanup()` (or equivalent) that runs before the auth session is torn down. This method should be awaited by default but must not block sign-out completion forever; add a short timeout and log on failure.
  - Steps inside pre-logout cleanup: best-effort backend unregister (with auth) using default callable/action or custom `_onTokenChanged(newToken: null, oldToken: lastToken)`; stop token refresh subscription; call `FirebaseMessaging.deleteToken()`; clear cached tokens (new + legacy).
  - If backend unregister fails (offline/server error), still proceed to sign-out and delete the local token to prevent future delivery. The server may still hold a stale mapping, but the deleted token will fail on send; server-side should already handle invalid-token cleanup on send failures.

**Important:** This plan intentionally allows token unregister semantics via a nullable `newToken`. If the package prefers avoiding nullable callbacks, replace this with an explicit `unregisterFcmToken(oldToken)` API and keep `onTokenChanged(String newToken, String? oldToken)` strictly non-null.

**App-level notification toggle (enable/disable):**
- New APIs on `NotificationService`:
  - `Future<void> disableNotifications()` → best-effort server unregister while authed, stop token refresh listener, call `FirebaseMessaging.deleteToken()`, clear cached token(s), set app-level flag to false.
  - `Future<NotificationInitResult> enableNotifications()` → thin wrapper that reuses the existing init flow (`initializeNotifications()` / `runNotificationPermissionFlow`) to re-check permission, request if needed, fetch a fresh token, sync to backend, restart refresh listener, then set the app-level flag to true.
  - `Future<bool> isNotificationsEnabled()` → returns the app-level preference flag (default true) so UI can gate notification surfaces; stored in SharedPreferences under `dreamic_notifications_enabled`.
- Behavior: disabling is preference-level (not OS permission). If the user re-enables, there is no extra system prompt unless they revoked permission in device settings. If server unregister fails (offline), we still delete the local token; server should prune stale tokens on send failures.

### Architecture: NotificationService + NotificationPermissionHelper

**Separation of concerns:**

| Component | Responsibility |
|-----------|----------------|
| `NotificationService` | FCM token management, displaying notifications, high-level flow orchestration |
| `NotificationPermissionHelper` | Permission state tracking, timing logic, platform-specific rules |

**Relationship:**
- `NotificationService` owns a `NotificationPermissionHelper` instance
- `NotificationService` exposes helper methods as convenience wrappers
- Consuming apps can access the helper directly via `notificationService.permissionHelper` for advanced use cases
- The helper remains focused on pure permission logic (no FCM token concerns)

```dart
// NotificationService owns the helper
class NotificationService {
  late final NotificationPermissionHelper _permissionHelper;

  NotificationPermissionHelper get permissionHelper => _permissionHelper;

  Future<void> initialize(...) async {
    // ... existing initialization ...
    _permissionHelper = NotificationPermissionHelper(notificationService: this);
  }

  // Convenience wrappers delegate to helper
  Future<NotificationDenialInfo?> getNotificationDenialInfo() =>
      _permissionHelper.getNotificationDenialInfo();

  Future<void> clearNotificationDenialInfo() =>
      _permissionHelper.clearNotificationDenialInfo();

  // High-level flow uses helper for logic
  Future<NotificationFlowResult> runNotificationPermissionFlow(
    BuildContext context, {
    NotificationFlowConfig config = const NotificationFlowConfig(),
  }) async {
    // Use helper to determine current state and what to do
    final status = await getPermissionStatus();

    if (status == NotificationPermissionStatus.authorized) {
      return NotificationFlowResult.alreadyGranted;
    }

    if (await _permissionHelper.shouldShowSettingsPrompt()) {
      // ... show settings prompt ...
    }

    // etc.
  }
}
```

**Why keep them separate:**
1. `NotificationPermissionHelper` can be used standalone (without full NotificationService setup)
2. Testing is easier - mock the helper to test flow logic
3. Helper's logic is reusable for custom flows that don't use the built-in dialogs
4. Clear ownership: helper manages SharedPreferences state, service manages FCM

### 1. Add Configuration Options in AppConfigBase

**File:** `lib/app/app_config_base.dart`

#### 1a. Add `useFCMWeb` (web-specific FCM toggle)

> **Web FCM Default: OFF (Breaking Change)**
>
> Web FCM requires VAPID key and service worker setup (documented in `docs/NOTIFICATION_SETUP.md` lines 485-492).
> Since most apps won't have this configured, `useFCMWeb` defaults to `false` to avoid errors.
>
> This is a behavior change from previous “FCM enabled by default” expectations. It must be communicated as a breaking change (CHANGELOG + migration notes). Consuming apps that want web push must explicitly opt in.
>
> Apps that have configured web push should explicitly enable it:
> - Set `AppConfigBase.useFCMWebDefault = true` in code, or
> - Use `--dart-define USE_FCM_WEB=true` at build time

> **VAPID Key Note:** The VAPID key is already documented in `docs/NOTIFICATION_SETUP.md` (lines 485-492).
> Currently, consuming apps pass the VAPID key directly to `FirebaseMessaging.instance.getToken(vapidKey: ...)`.
>
> **Decision:** Keep VAPID key as documentation-only (no AppConfigBase property) because:
> 1. It's a one-time setup value that doesn't change at runtime
> 2. It's already handled in `NotificationService.initializeFcmToken()` when calling `getToken()`
> 3. Adding it to AppConfigBase would add complexity without clear benefit
>
> If centralized configuration is needed later, add:
> ```dart
> static String? _fcmVapidKey;
> static String? get fcmVapidKey => _fcmVapidKey;
> static set fcmVapidKeyDefault(String? key) => _fcmVapidKey = key;
> ```

```dart
// FCM for Web (default: false - requires VAPID key + service worker setup)
// Set to true only if you've configured web push notifications
static bool? _useFCMWebDefault;
static set useFCMWebDefault(bool value) => _useFCMWebDefault = value;
static bool? _useFCMWeb;
static bool get useFCMWeb {
  _useFCMWeb ??= const String.fromEnvironment('USE_FCM_WEB', defaultValue: '').isNotEmpty
      ? const String.fromEnvironment('USE_FCM_WEB', defaultValue: 'false') == 'true'
      : (_useFCMWebDefault ?? false);  // Default FALSE - web FCM requires extra setup
  return _useFCMWeb!;
}
```

**Note:** The existing `_getDefaultFCMValue()` method (lines 618-624) already handles iOS simulator detection:
```dart
// EXISTING CODE in AppConfigBase:
static bool _getDefaultFCMValue() {
  // Default to false if running on iOS simulator, true otherwise
  if (isIOSSimulator == true) {
    return false;
  }
  return true;
}
```

Update `_getDefaultFCMValue()` to **also** check `useFCMWeb` on web (preserving existing iOS simulator logic):

```dart
static bool _getDefaultFCMValue() {
  // Web uses separate config flag (defaults false - requires VAPID setup)
  if (kIsWeb) {
    return useFCMWeb;
  }
  // Default to false if running on iOS simulator, true otherwise
  if (isIOSSimulator == true) {
    return false;
  }
  return true;
}
```

**Usage in consuming app:**
```dart
void main() async {
  // Enable FCM on web (only if VAPID key is configured)
  AppConfigBase.useFCMWebDefault = true;
  // ... rest of initialization
}
```

Or via build flag:
```bash
flutter build web --dart-define USE_FCM_WEB=true
```

#### 1b. Add `fcmAutoInitialize` (deferred permission prompt)

```dart
// FCM auto-initialization (default: true for backward compatibility)
static bool? _fcmAutoInitializeDefault;
static set fcmAutoInitializeDefault(bool value) => _fcmAutoInitializeDefault = value;
static bool? _fcmAutoInitialize;
static bool get fcmAutoInitialize {
  _fcmAutoInitialize ??= const String.fromEnvironment('FCM_AUTO_INITIALIZE', defaultValue: '').isNotEmpty
      ? const String.fromEnvironment('FCM_AUTO_INITIALIZE', defaultValue: 'true') == 'true'
      : (_fcmAutoInitializeDefault ?? true);
  return _fcmAutoInitialize!;
}
```

### 2. Add Enums and Methods to NotificationService

**File:** `lib/notifications/notification_service.dart` (or new file `lib/notifications/notification_types.dart`)

Add enums:
```dart
/// Result of initializing notifications
enum NotificationInitResult {
  /// Successfully initialized and permission granted
  success,
  /// User denied notification permission (may be able to request again)
  permissionDenied,
  /// Permission permanently denied - must direct user to system settings
  /// (iOS after first denial, Android after "Don't ask again")
  permissionPermanentlyDenied,
  /// Permission request was blocked by the system (OEM restriction, etc.)
  /// The user never saw the dialog - don't count as a denial
  permissionRequestBlocked,
  /// FCM is disabled in this AuthService instance
  fcmDisabledInstance,
  /// FCM is disabled in AppConfigBase
  fcmDisabledConfig,
  /// Already initialized
  alreadyInitialized,
  /// Initialization failed due to an error
  error,
}

// NOTE: Do NOT introduce a new permission-status enum.
// The package already defines `NotificationPermissionStatus` (authorized/denied/notDetermined/provisional)
// and existing widgets/helpers depend on it.
//
// For “permanently denied” decisions in the flow, derive it as:
//   isPermanentDenied := (status == denied) && !(await permissionHelper.canPromptForPermission())
// (with platform-specific exceptions, e.g., web).
```

Add method signatures to NotificationService:
```dart
/// Initialize FCM and request notification permissions.
/// Call this when your app is ready to show the permission dialog.
Future<NotificationInitResult> initializeNotifications();

/// Check current notification permission status without prompting the user.
/// (Enhances existing getPermissionStatus() method)
/// Use this to decide whether to show an in-app prompt explaining why
/// notifications are valuable before calling initializeNotifications().
///
/// **Auto-clear behavior:** If permission is detected as `authorized` and there
/// is stored denial/settings-prompt info, it will be automatically cleared.
/// This handles the case where user enabled notifications via system settings.
/// Note: This builds on the existing getPermissionStatus() method in NotificationService.
Future<NotificationPermissionStatus> getPermissionStatus();  // Enhanced existing method

/// Open the system settings page for this app.
/// Use this when permission is effectively “permanently denied” (derived) or on web.
/// Returns true if settings were opened successfully.
Future<bool> openNotificationSettings();

/// Get metadata about previous notification permission denials.
/// Useful for implementing "ask again after X days" or "ask again after Y launches" logic.
Future<NotificationDenialInfo?> getNotificationDenialInfo();

/// Clear stored denial info (e.g., after user grants permission via settings).
Future<void> clearNotificationDenialInfo();

/// Get metadata about previous "go to settings" prompts.
/// Useful for apps that want custom logic for when to show the settings prompt.
Future<GoToSettingsPromptInfo?> getGoToSettingsPromptInfo();

/// Clear stored "go to settings" prompt info (e.g., after user grants permission via settings).
Future<void> clearGoToSettingsPromptInfo();
```

Add denial tracking class:
```dart
/// Information about when/how notification permission was denied
class NotificationDenialInfo {
  /// When the user last denied permission
  final DateTime lastDenialTime;
  /// Total number of times permission was denied by the user
  final int denialCount;
  /// Whether this was a permanent denial (user must go to settings)
  final bool isPermanent;

  /// Total number of times we attempted to request permission
  /// (may be higher than denialCount if some requests were blocked)
  final int requestAttemptCount;
  /// When we last attempted to request permission
  final DateTime? lastRequestAttemptTime;
  /// Whether the last request was blocked by the system (no dialog shown)
  final bool lastRequestWasBlocked;

  const NotificationDenialInfo({
    required this.lastDenialTime,
    required this.denialCount,
    required this.isPermanent,
    this.requestAttemptCount = 0,
    this.lastRequestAttemptTime,
    this.lastRequestWasBlocked = false,
  });
}

/// Information about "go to settings" prompts shown to user
class GoToSettingsPromptInfo {
  /// When the user was last shown the "go to settings" prompt
  final DateTime lastPromptTime;
  /// Total number of times the prompt was shown
  final int promptCount;
  /// Whether user declined (false) or opened settings (true) last time
  final bool lastActionWasOpenSettings;

  const GoToSettingsPromptInfo({
    required this.lastPromptTime,
    required this.promptCount,
    required this.lastActionWasOpenSettings,
  });
}
```

### 3. Implement in NotificationService

**File:** `lib/notifications/notification_service.dart`

Add method to handle auto-initialization when connecting to auth stream (in `connectToAuthService()`):
```dart
// Inside connectToAuthService(), when user logs in:
if (AppConfigBase.useFCM) {
  if (AppConfigBase.fcmAutoInitialize) {
    // Always auto-initialize (original behavior)
    await initializeFcmToken(onTokenChanged: onTokenChanged);
  } else {
    // Check if permission was already granted previously
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      // Permission already granted - safe to initialize silently (no dialog)
      logd('FCM auto-init disabled, but permission already granted - initializing silently');
      await initializeFcmToken(onTokenChanged: onTokenChanged);
    } else {
      // No permission yet - wait for manual trigger
      logd('FCM auto-initialization disabled, call runNotificationPermissionFlow() when ready');
    }
  }
}
```

**Key insight:** When permission is already granted, `requestPermission()` returns immediately without showing a dialog. So we can safely initialize on subsequent launches.

Add public method for manual notification initialization:
```dart
/// Initialize notifications manually. Returns the result of the initialization.
/// Use this when fcmAutoInitialize is false and you want to trigger notification
/// setup at a specific point in your app flow.
Future<NotificationInitResult> initializeNotifications() async {
  if (!AppConfigBase.useFCM) {
    logd('initializeNotifications: FCM is disabled in AppConfigBase');
    return NotificationInitResult.fcmDisabledConfig;
  }
  if (_hasInitializedFCM) {
    logd('initializeNotifications: Already initialized');
    return NotificationInitResult.alreadyInitialized;
  }
  try {
    // Request permission and initialize FCM
    final permissionResult = await requestPermissions();
    if (permissionResult == NotificationPermissionStatus.authorized ||
        permissionResult == NotificationPermissionStatus.provisional) {
      // Permission granted - initialize FCM token if callback is set
      if (_onTokenChanged != null) {
        await initializeFcmToken(onTokenChanged: _onTokenChanged!);
      }
      return NotificationInitResult.success;
    } else if (permissionResult == NotificationPermissionStatus.denied) {
      return NotificationInitResult.permissionDenied;
    } else {
      return NotificationInitResult.permissionPermanentlyDenied;
    }
  } catch (e) {
    loge('initializeNotifications failed: $e');
    return NotificationInitResult.error;
  }
}
```

## Files to Modify

1. **lib/app/app_config_base.dart** - Add config options:
   - `useFCMWeb` - web-specific FCM toggle (default: `false`)
   - `fcmAutoInitialize` - deferred permission prompt toggle
   - Update `_getDefaultFCMValue()` to check `useFCMWeb` on web

2. **lib/notifications/notification_permission_helper.dart** - ENHANCE existing helper:
   - **Refactor existing tracking to use structured classes:**
     - Replace separate `_keyPermissionRequestCount` / `_keyPermissionDenialCount` with `NotificationDenialInfo` JSON
     - Add `GoToSettingsPromptInfo` tracking
   - **Add new tracking fields:**
     - `requestAttemptCount` (distinct from `denialCount` - for blocked request detection)
     - `lastRequestWasBlocked` flag
     - `lastRequestAttemptTime`
   - **Add new methods:**
     - `getNotificationDenialInfo()` - returns structured `NotificationDenialInfo`
     - `clearNotificationDenialInfo()` - clears all denial tracking
     - `getGoToSettingsPromptInfo()` - returns structured `GoToSettingsPromptInfo`
     - `clearGoToSettingsPromptInfo()` - clears settings prompt tracking
     - `recordDenial(isPermanent: bool)` - track a denial with structured data
     - `recordBlockedRequest()` - track when system blocked the request
     - `recordGoToSettingsPrompt(openedSettings: bool)` - track settings prompt
     - `autoClearIfGranted()` - check status and clear tracking if now granted
   - **Enhance existing methods:**
     - `shouldShowSettingsPrompt()` - add timing/count limits from `NotificationFlowConfig`
     - `shouldRequestPermissions()` - integrate with `NotificationFlowConfig` limits
   - **Migrate SharedPreferences keys** (from existing to `dreamic_` prefix):
     - `notification_permission_request_count` → incorporated into `dreamic_notification_denial_info`
     - `notification_permission_denial_count` → incorporated into `dreamic_notification_denial_info`
     - `notification_last_permission_request` → incorporated into `dreamic_notification_denial_info`
     - `notification_last_reminder_date` → `dreamic_notification_last_reminder_date`
     - NEW: `dreamic_notification_denial_info` - JSON with full denial tracking
     - NEW: `dreamic_notification_settings_prompt_info` - JSON with go-to-settings tracking
     - NEW: `dreamic_notification_has_requested` - Boolean flag for Android permanent denial detection
   - **IMPORTANT - Deduplicate keys:** Currently both `NotificationService` (lines 112-115) and `NotificationPermissionHelper` (lines 16-19) define the same SharedPreferences keys. After this migration:
     - Helper owns ALL permission-related keys (denial info, request tracking, reminder dates)
     - Service owns ONLY FCM token key (`dreamic_fcm_token`)
     - Remove duplicate key definitions from `NotificationService`

3. **lib/notifications/notification_service.dart** - Add FCM token management, delegate permission logic to helper:
   - **FCM Token Management (moved from AuthServiceImpl):**
     - `initializeFcmToken()` - get token and sync to server
     - `clearFcmToken()` - clear on logout
     - `connectToAuthService()` - convenience method for auth integration
     - Token refresh listener
     - APNS token handling for iOS/macOS
   - **Permission Flow (delegates to NotificationPermissionHelper):**
     - `runNotificationPermissionFlow()` - high-level flow with dialogs (uses helper for logic)
     - `get permissionHelper` - expose the helper for direct access
     - Convenience wrappers that delegate to helper:
       - `getNotificationDenialInfo()` → `_permissionHelper.getNotificationDenialInfo()`
       - `clearNotificationDenialInfo()` → `_permissionHelper.clearNotificationDenialInfo()`
       - `getGoToSettingsPromptInfo()` → `_permissionHelper.getGoToSettingsPromptInfo()`
       - `clearGoToSettingsPromptInfo()` → `_permissionHelper.clearGoToSettingsPromptInfo()`
     - `openNotificationSettings()` - open system settings (uses `permission_handler`)
   - **REMOVE duplicate permission tracking methods** (now in helper):
     - Remove `_trackPermissionRequest()` (line 655)
     - Remove `_trackPermissionDenial()` (line 667)
     - Remove `getPermissionRequestCount()` (line 678)
     - Remove `getPermissionDenialCount()` (line 689)
     - Remove `shouldShowPeriodicReminder()` (line 700)
     - Remove `updateLastReminderDate()` (line 720)
     - Remove duplicate SharedPreferences keys (lines 112-115)
     - Update `requestPermissions()` to use helper for tracking
   - **Address existing TODO** (line 615):
     - Current: `// TODO: Notify AuthServiceImpl if permissions were granted`
     - Action: REMOVE this TODO - AuthService should NOT know about notifications
     - The direction of dependency is NotificationService → AuthService (via `isLoggedInStream`)
   - **New Types (add to `lib/notifications/notification_types.dart`):**
     - `NotificationInitResult` enum
     - `NotificationDenialInfo` class (with JSON serialization)
     - `GoToSettingsPromptInfo` class (with JSON serialization)
     - `NotificationFlowResult` enum
     - `NotificationFlowStrings` class
     - `NotificationFlowConfig` class
   - **SharedPreferences keys for FCM token** (prefixed with `dreamic_`):
     - `dreamic_fcm_token` - cached FCM token

4. **lib/data/repos/auth_service_impl.dart** - REMOVE FCM code:
   - Remove `useFirebaseFCM` field and constructor parameter
   - Remove `_hasInitializedFCM` field
   - Remove `sharedPrefKeyFcmToken` constant
   - Remove FCM initialization in `handleTokenChanges()` (lines 163-170)
   - Remove `initFCM()` method (lines 1698-1779)
   - Remove `_updateTokenOnServer()` method (lines 1781-1803)
   - Keep `isLoggedInStream` for NotificationService to subscribe to

5. **lib/data/repos/auth_service_int.dart** - NO CHANGES NEEDED ✅
   - `isLoggedInStream` already exists in interface (line 13)
   - All notification types and methods now go in NotificationService
   - Auth interface stays focused on authentication only
   - NotificationService will use the existing `isLoggedInStream` from this interface

6. **lib/presentation/helpers/notification_permission_dialogs.dart** (NEW) - Built-in dialogs:
   - `showNotificationValuePropositionDialog()`
   - `showNotificationGoToSettingsDialog()`
   - `showNotificationAskAgainDialog()`

7. **pubspec.yaml** - No changes needed
   - `permission_handler` is already in pubspec.yaml
   - `adaptive_dialog` is already in pubspec.yaml

8. **docs/DREAMIC_FEATURES_GUIDE.md** - Update Notifications section:
   - Add new notification permission methods to NotificationService documentation
   - Document `initializeFcmToken()`, `connectToAuthService()`, etc.
   - Add `runNotificationPermissionFlow()` high-level API examples
   - Document `fcmAutoInitialize` and `useFCMWeb` config options
   - Document migration from AuthServiceImpl FCM to NotificationService

9. **docs/NOTIFICATION_GUIDE.md** - Major updates:
   - Add new "Deferred Permission Prompt" section explaining the feature
   - Update "Permission Request Strategies" with the new high-level flow
   - Add "Go-to-Settings Configuration" section with examples
   - Document platform-specific behavior (iOS, Android 13+, Web)
   - Add "Defensive Error Handling" guidance for OEM variations
   - Update troubleshooting section with new edge cases

10. **docs/NOTIFICATION_SETUP.md** - Updates:
    - Document `fcmAutoInitialize` and `useFCMWeb` configuration options
    - Add Android 13+ permission flow details (two denials = permanent)
    - Update iOS section with first-denial-is-permanent behavior
    - Add web-specific instructions for denied state (browser lock icon)
    - Update testing checklist with new verification steps

11. **test/notification_permission/** (NEW directory) - Unit tests:
    - `notification_denial_info_test.dart` - Serialization/deserialization tests
    - `go_to_settings_prompt_info_test.dart` - Serialization/deserialization tests
    - `should_ask_again_test.dart` - Logic tests with various timing/count scenarios
    - `should_show_go_to_settings_test.dart` - Logic tests
    - `notification_flow_config_test.dart` - Config defaults and custom values
    - `notification_permission_helper_test.dart` - Tests for enhanced helper:
      - `recordDenial()` tracking
      - `recordBlockedRequest()` vs `recordDenial()` distinction
      - `autoClearIfGranted()` behavior
      - Migration from old SharedPreferences keys to new structure
      - Platform-specific logic (`canPromptForPermission()`, `shouldShowSettingsPrompt()`)

12. **test/notification_permission/notification_permission_flow_test.dart** (NEW) - Flow tests:
    - Mock permission states and verify flow behavior
    - Test blocked request detection (status unchanged after request)
    - Test graceful fallback to settings when re-request fails
    - Test denial count vs request attempt count tracking
    - Test all `NotificationFlowResult` outcomes
    - Test web-specific behavior (instructions dialog instead of settings)

13. **test/notification_permission/integration/** (NEW directory) - Integration tests:
    - `notification_permission_integration_test.dart`:
      - Test SharedPreferences persistence of denial info
      - Test SharedPreferences persistence of go-to-settings prompt info
      - Test auto-clearing of tracking data when permission detected as granted
      - Test fresh status retrieval (no stale cache)
      - Test app resume flow after returning from settings

## Built-in Permission Flow (High-Level API)

### 4. Add Flow Configuration and Result Types

**File:** `lib/notifications/notification_types.dart` (NEW - as referenced in Files to Modify #3)

```dart
/// Result of running the full notification permission flow
enum NotificationFlowResult {
  /// Permission granted (newly or already had it)
  granted,
  /// Permission was already granted, FCM initialized silently
  alreadyGranted,
  /// User declined at value proposition dialog
  declinedValueProposition,
  /// User denied the system permission request
  deniedPermission,
  /// User denied permanently (iOS or Android "Don't ask again")
  deniedPermanently,
  /// User chose not to ask again after previous denial (denied state)
  skippedAskAgain,
  /// Skipped go-to-settings prompt due to config (showGoToSettingsPrompt=false,
  /// or timing/count limits reached)
  skippedGoToSettings,
  /// User declined to go to settings when prompted
  declinedGoToSettings,
  /// User was directed to settings (may or may not enable there)
  openedSettings,
  /// FCM is disabled in configuration
  fcmDisabled,
  /// An error occurred
  error,
}

/// Strings for the notification permission flow dialogs
/// Provide localized versions of these for your app
class NotificationFlowStrings {
  // Value proposition dialog (shown first time)
  final String valuePropositionTitle;
  final String valuePropositionMessage;
  final String valuePropositionAcceptButton;
  final String valuePropositionDeclineButton;

  // Go to settings dialog (shown when permanently denied)
  final String goToSettingsTitle;
  final String goToSettingsMessage;
  final String goToSettingsButton;
  final String goToSettingsCancelButton;

  // Ask again dialog (shown after previous denial, when can retry)
  final String askAgainTitle;
  final String askAgainMessage;
  final String askAgainAcceptButton;
  final String askAgainDeclineButton;

  const NotificationFlowStrings({
    this.valuePropositionTitle = 'Enable Notifications',
    this.valuePropositionMessage = 'Stay updated with important alerts and messages.',
    this.valuePropositionAcceptButton = 'Enable',
    this.valuePropositionDeclineButton = 'Not Now',
    this.goToSettingsTitle = 'Notifications Disabled',
    this.goToSettingsMessage = 'To receive notifications, please enable them in your device settings.',
    this.goToSettingsButton = 'Open Settings',
    this.goToSettingsCancelButton = 'Cancel',
    this.askAgainTitle = 'Enable Notifications?',
    this.askAgainMessage = 'You previously declined notifications. Would you like to enable them now?',
    this.askAgainAcceptButton = 'Yes, Enable',
    this.askAgainDeclineButton = 'No Thanks',
  });
}

/// Configuration for the notification permission flow
class NotificationFlowConfig {
  //
  // Re-ask configuration (when permission denied but can still show system dialog)
  //

  /// How long to wait before asking again after denial
  final Duration askAgainAfter;

  /// Maximum number of times to ask after denials (0 = never ask again)
  final int maxAskCount;

  //
  // Go-to-settings configuration (when permanently denied)
  //

  /// Whether to show the "go to settings" prompt at all when permanently denied.
  /// Set to false if your app should never prompt users to change settings.
  /// Default: true
  final bool showGoToSettingsPrompt;

  /// How long to wait before showing the "go to settings" prompt again.
  /// Only applies if user previously declined to go to settings.
  /// Default: 30 days (or Duration.zero to never ask again after first decline)
  final Duration goToSettingsAskAgainAfter;

  /// Maximum number of times to show the "go to settings" prompt.
  /// 0 = never show, 1 = show once only, null = unlimited (respects duration only)
  /// Default: null (unlimited, respects duration)
  final int? goToSettingsMaxAskCount;

  //
  // Strings and custom builders
  //

  /// Strings for built-in dialogs (for localization)
  final NotificationFlowStrings strings;

  /// Custom builder for value proposition dialog
  /// Return true to proceed with permission request, false to cancel
  /// If null, uses built-in dialog with [strings]
  final Future<bool> Function(BuildContext context)? valuePropositionBuilder;

  /// Custom builder for go-to-settings dialog
  /// Return true to open settings, false to cancel
  /// If null, uses built-in dialog with [strings]
  /// Note: If [showGoToSettingsPrompt] is false, this is never called.
  final Future<bool> Function(BuildContext context)? goToSettingsBuilder;

  /// Custom builder for ask-again dialog
  /// Return true to ask again, false to skip
  /// If null, uses built-in dialog with [strings]
  final Future<bool> Function(BuildContext context, NotificationDenialInfo info)? askAgainBuilder;

  const NotificationFlowConfig({
    // Re-ask defaults
    this.askAgainAfter = const Duration(days: 7),
    this.maxAskCount = 3,
    // Go-to-settings defaults
    this.showGoToSettingsPrompt = true,
    this.goToSettingsAskAgainAfter = const Duration(days: 30),
    this.goToSettingsMaxAskCount, // null = unlimited
    // Strings and builders
    this.strings = const NotificationFlowStrings(),
    this.valuePropositionBuilder,
    this.goToSettingsBuilder,
    this.askAgainBuilder,
  });
}
```

### 5. Add High-Level Flow Method to NotificationService

**File:** `lib/notifications/notification_service.dart`

```dart
/// Run the complete notification permission flow with built-in dialogs.
///
/// This handles the entire flow:
/// 1. If already granted → initialize silently
/// 2. If not determined → show value proposition → request permission
/// 3. If denied (can retry) → check timing → maybe show ask-again dialog
/// 4. If permanently denied → show go-to-settings dialog
///
/// [context] is required for showing dialogs.
/// [config] allows customization of strings, timing, and dialog builders.
Future<NotificationFlowResult> runNotificationPermissionFlow(
  BuildContext context, {
  NotificationFlowConfig config = const NotificationFlowConfig(),
});
```

### 6. Implement Flow in NotificationService

**File:** `lib/notifications/notification_service.dart`

```dart
Future<NotificationFlowResult> runNotificationPermissionFlow(
  BuildContext context, {
  NotificationFlowConfig config = const NotificationFlowConfig(),
}) async {
  // Check FCM enabled
  if (!AppConfigBase.useFCM) {
    return NotificationFlowResult.fcmDisabled;
  }

  final status = await getPermissionStatus();
  final canPromptAgain = await _permissionHelper.canPromptForPermission();
  final isPermanentDenied =
      status == NotificationPermissionStatus.denied && !canPromptAgain && !kIsWeb;

  switch (status) {
    case NotificationPermissionStatus.authorized:
    case NotificationPermissionStatus.provisional:
      // Already have permission - just initialize
      await initializeNotifications();
      return NotificationFlowResult.alreadyGranted;

    case NotificationPermissionStatus.notDetermined:
      // Show value proposition first
      final shouldProceed = config.valuePropositionBuilder != null
          ? await config.valuePropositionBuilder!(context)
          : await _showValuePropositionDialog(context, config.strings);

      if (!shouldProceed) {
        return NotificationFlowResult.declinedValueProposition;
      }

      // Request permission
      final result = await initializeNotifications();
      return _mapInitResultToFlowResult(result);

    case NotificationPermissionStatus.denied:
      // If effectively permanent, route to go-to-settings path.
      if (isPermanentDenied) {
        // (handled below as “go to settings”)
      }
      // Check if we should ask again
      final denialInfo = await getNotificationDenialInfo();
      if (!_shouldAskAgain(denialInfo, config)) {
        return NotificationFlowResult.skippedAskAgain;
      }

      // Show ask-again dialog
      final shouldAsk = config.askAgainBuilder != null
          ? await config.askAgainBuilder!(context, denialInfo!)
          : await _showAskAgainDialog(context, config.strings, denialInfo!);

      if (!shouldAsk) {
        return NotificationFlowResult.skippedAskAgain;
      }

      final result = await initializeNotifications();
      return _mapInitResultToFlowResult(result);

    // NOTE: “Permanently denied” is a derived state.
    // Handle it by checking `isPermanentDenied` when status is denied.
    default:
      // Permanently denied (derived) or other edge cases
      if (!config.showGoToSettingsPrompt) {
        return NotificationFlowResult.skippedGoToSettings;
      }

      // Check timing/count limits for go-to-settings prompt
      final settingsPromptInfo = await getGoToSettingsPromptInfo();
      if (!_shouldShowGoToSettingsPrompt(settingsPromptInfo, config)) {
        return NotificationFlowResult.skippedGoToSettings;
      }

      // Show the prompt (with web-specific handling)
      final shouldOpenSettings = await _showGoToSettingsPromptWithTracking(
        context, config, settingsPromptInfo,
      );

      if (!shouldOpenSettings) {
        return NotificationFlowResult.declinedGoToSettings;
      }

      await openNotificationSettings();
      return NotificationFlowResult.openedSettings;
  }
}

bool _shouldShowGoToSettingsPrompt(
  GoToSettingsPromptInfo? info,
  NotificationFlowConfig config,
) {
  if (info == null) return true; // Never shown before

  // Check max count
  if (config.goToSettingsMaxAskCount != null &&
      info.promptCount >= config.goToSettingsMaxAskCount!) {
    return false;
  }

  // Check timing
  final timeSinceLastPrompt = DateTime.now().difference(info.lastPromptTime);
  return timeSinceLastPrompt >= config.goToSettingsAskAgainAfter;
}

bool _shouldAskAgain(NotificationDenialInfo? info, NotificationFlowConfig config) {
  if (info == null) return true;
  if (info.isPermanent) return false;
  if (info.denialCount >= config.maxAskCount) return false;

  final timeSinceDenial = DateTime.now().difference(info.lastDenialTime);
  return timeSinceDenial >= config.askAgainAfter;
}
```

### 7. Add Built-in Dialog Helpers (Presentation Layer)

**File:** `lib/presentation/helpers/notification_permission_dialogs.dart` (NEW)

Uses `adaptive_dialog` package (already in pubspec.yaml) for platform-native dialogs:

```dart
import 'package:adaptive_dialog/adaptive_dialog.dart';

/// Built-in dialogs for the notification permission flow.
/// Uses adaptive_dialog for platform-native look (Material on Android, Cupertino on iOS).

Future<bool> showNotificationValuePropositionDialog(
  BuildContext context,
  NotificationFlowStrings strings,
) async {
  final result = await showOkCancelAlertDialog(
    context: context,
    title: strings.valuePropositionTitle,
    message: strings.valuePropositionMessage,
    okLabel: strings.valuePropositionAcceptButton,
    cancelLabel: strings.valuePropositionDeclineButton,
  );
  return result == OkCancelResult.ok;
}

Future<bool> showNotificationGoToSettingsDialog(
  BuildContext context,
  NotificationFlowStrings strings,
) async {
  final result = await showOkCancelAlertDialog(
    context: context,
    title: strings.goToSettingsTitle,
    message: strings.goToSettingsMessage,
    okLabel: strings.goToSettingsButton,
    cancelLabel: strings.goToSettingsCancelButton,
  );
  return result == OkCancelResult.ok;
}

Future<bool> showNotificationAskAgainDialog(
  BuildContext context,
  NotificationFlowStrings strings,
  NotificationDenialInfo info,
) async {
  final result = await showOkCancelAlertDialog(
    context: context,
    title: strings.askAgainTitle,
    message: strings.askAgainMessage,
    okLabel: strings.askAgainAcceptButton,
    cancelLabel: strings.askAgainDeclineButton,
  );
  return result == OkCancelResult.ok;
}
```

## Usage Examples

### Consuming App - Disable Auto-Init
```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Disable automatic FCM initialization
  AppConfigBase.fcmAutoInitializeDefault = false;

  // ... rest of initialization
}
```

### Level 1: Use Defaults (Simplest)
```dart
// After onboarding or at the right moment in your app
final notificationService = GetIt.I.get<NotificationService>();
final result = await notificationService.runNotificationPermissionFlow(context);

// Optionally handle the result
if (result == NotificationFlowResult.granted ||
    result == NotificationFlowResult.alreadyGranted) {
  // Notifications are enabled!
}
```

### Level 2: Localized Strings
```dart
final result = await notificationService.runNotificationPermissionFlow(
  context,
  config: NotificationFlowConfig(
    strings: NotificationFlowStrings(
      valuePropositionTitle: l10n.notificationTitle,
      valuePropositionMessage: l10n.notificationMessage,
      valuePropositionAcceptButton: l10n.enable,
      valuePropositionDeclineButton: l10n.notNow,
      goToSettingsTitle: l10n.notificationsDisabled,
      goToSettingsMessage: l10n.pleaseEnableInSettings,
      goToSettingsButton: l10n.openSettings,
      goToSettingsCancelButton: l10n.cancel,
      askAgainTitle: l10n.enableNotifications,
      askAgainMessage: l10n.youPreviouslyDeclined,
      askAgainAcceptButton: l10n.yesEnable,
      askAgainDeclineButton: l10n.noThanks,
    ),
    askAgainAfter: const Duration(days: 3),
    maxAskCount: 2,
  ),
);
```

### Level 3: Custom Dialog Builders (Full Control)
```dart
final result = await notificationService.runNotificationPermissionFlow(
  context,
  config: NotificationFlowConfig(
    valuePropositionBuilder: (context) async {
      // Show your own beautiful custom dialog
      return await showModalBottomSheet<bool>(
        context: context,
        builder: (context) => MyCustomNotificationPrompt(),
      ) ?? false;
    },
    goToSettingsBuilder: (context) async {
      // Show your custom "go to settings" UI
      return await showMySettingsPrompt(context);
    },
    askAgainBuilder: (context, denialInfo) async {
      // Custom logic based on denial info
      // Maybe show different UI based on how many times denied
      return await showMyAskAgainDialog(
        context,
        denialCount: denialInfo.denialCount,
      );
    },
  ),
);
```

### Go-to-Settings Prompt Configuration Examples

**Never prompt to go to settings** (respect user's decision):
```dart
NotificationFlowConfig(
  showGoToSettingsPrompt: false,
)
```

**Prompt only once** (ask once, then never again):
```dart
NotificationFlowConfig(
  goToSettingsMaxAskCount: 1,
)
```

**Prompt periodically** (once per month, up to 3 times total):
```dart
NotificationFlowConfig(
  goToSettingsAskAgainAfter: const Duration(days: 30),
  goToSettingsMaxAskCount: 3,
)
```

**Prompt indefinitely but infrequently** (every 60 days, no limit):
```dart
NotificationFlowConfig(
  goToSettingsAskAgainAfter: const Duration(days: 60),
  goToSettingsMaxAskCount: null, // unlimited
)
```

**Handle the result**:
```dart
final result = await notificationService.runNotificationPermissionFlow(context);

switch (result) {
  case NotificationFlowResult.skippedGoToSettings:
    // Settings prompt was skipped due to config limits
    // (showGoToSettingsPrompt=false, or timing/count limits reached)
    // Don't show any UI - respect the config
    break;
  case NotificationFlowResult.declinedGoToSettings:
    // User was shown the prompt but declined
    // Maybe show a subtle hint in settings later
    break;
  case NotificationFlowResult.openedSettings:
    // User went to settings - handled automatically on app resume
    // (see "Automatic Resume Handling" below)
    break;
  // ... other cases
}
```

### Automatic Resume Handling After Settings

The package handles app resume automatically using `AppLifecycleService`. When the user returns from settings:

1. `NotificationService` subscribes to `AppLifecycleService.lifecycleStream`
2. On app resume after `openNotificationSettings()` was called, it auto-checks permission
3. If permission is now granted, it initializes FCM silently and clears denial tracking data

**Implementation in `NotificationService`:**
```dart
bool _waitingForSettingsReturn = false;
StreamSubscription<AppLifecycleState>? _lifecycleSubscription;

void _setupLifecycleListener() {
  _lifecycleSubscription ??= AppLifecycleService().lifecycleStream.listen((state) {
    if (state == AppLifecycleState.resumed && _waitingForSettingsReturn) {
      _waitingForSettingsReturn = false;
      _handleResumeAfterSettings();
    }
  });
}

Future<void> _handleResumeAfterSettings() async {
  // getPermissionStatus() auto-clears denial info if granted
  final status = await getPermissionStatus();
  if (status == NotificationPermissionStatus.authorized ||
      status == NotificationPermissionStatus.provisional) {
    logd('Permission granted via settings - initializing FCM');
    await initializeFcmToken(onTokenChanged: _onTokenChanged!);
  }
}

Future<bool> openNotificationSettings() async {
  _setupLifecycleListener();
  _waitingForSettingsReturn = true;
  // ... open settings
}

**Note on OEM / blocked-request detection:** In flow logic, treat “blocked request” only when the app *should* be able to prompt (e.g., Android runtime permission available) but a permission request attempt results in no dialog and the status remains unchanged. Do not label iOS denied-as-permanent as “blocked”.

**Note on APNS waiting:** `_waitForApnsToken()` should be best-effort and time-bounded; avoid delaying login-critical UX paths. If APNS token is not yet available, proceed with best-effort FCM initialization and retry later.
```

**For UI that needs to react to permission changes**, use the existing `NotificationPermissionBuilder` widget which already handles lifecycle events:
```dart
NotificationPermissionBuilder(
  onStatusChanged: (status) {
    if (status == NotificationPermissionStatus.authorized) {
      showSuccessMessage('Notifications enabled!');
    }
  },
  builder: (context, status, requestPermissions) {
    // Your UI here
  },
)
```

**Note:** `getPermissionStatus()` automatically clears denial and settings-prompt tracking data when it detects permission has been granted. This ensures the flow logic stays correct after the user enables notifications via settings.

### Consuming App - Trigger at Right Moment (Low-Level API)
```dart
// After user completes onboarding, or when they tap "Enable Notifications"
final notificationService = GetIt.I.get<NotificationService>();

// First, check current status to decide how to proceed
final status = await notificationService.getPermissionStatus();

switch (status) {
  case NotificationPermissionStatus.authorized:
  case NotificationPermissionStatus.provisional:
    // Already have permission - just initialize
    await notificationService.initializeFcmToken(onTokenChanged: _syncTokenToServer);
    break;

  case NotificationPermissionStatus.notDetermined:
    // Can request - show pre-prompt explaining value, then request
    final shouldRequest = await showNotificationValueDialog();
    if (shouldRequest) {
      final result = await notificationService.requestPermissions();
      // Handle result...
    }
    break;

  case NotificationPermissionStatus.denied:
    // Previously denied but can request again (Android)
    final denialInfo = await notificationService.getNotificationDenialInfo();
    if (_shouldAskAgain(denialInfo)) {
      final result = await notificationService.requestPermissions();
      // Handle result...
    }
    break;

  case NotificationPermissionStatus.permanentlyDenied:
    // Must direct to settings (iOS, or Android "Don't ask again")
    final wantsToEnable = await showGoToSettingsDialog();
    if (wantsToEnable) {
      await notificationService.openNotificationSettings();
    }
    break;
}
```

### Consuming App - "Ask Again Later" Logic
```dart
bool _shouldAskAgain(NotificationDenialInfo? info) {
  if (info == null) return true;
  if (info.isPermanent) return false;

  // Example: Ask again after 7 days and max 3 times
  final daysSinceDenial = DateTime.now().difference(info.lastDenialTime).inDays;
  return daysSinceDenial >= 7 && info.denialCount < 3;
}
```

### Consuming App - Handle Result After Requesting
```dart
final result = await notificationService.requestPermissions();

switch (result) {
  case NotificationPermissionStatus.authorized:
    // Clear any stored denial info
    await notificationService.clearNotificationDenialInfo();
    showSnackbar('Notifications enabled!');
    break;

  case NotificationPermissionStatus.denied:
    // Denied but can try again later (Android)
    showSnackbar('You can enable notifications later in settings');
    break;

  case NotificationPermissionStatus.permanentlyDenied:
    // Show dialog directing to settings
    showGoToSettingsDialog();
    break;

  default:
    // Handle other cases
    break;
}
```

### Build-time Override
```bash
flutter run --dart-define FCM_AUTO_INITIALIZE=false
```

## Defensive Error Handling

Platform behavior can vary due to:
- **OEM modifications** (Samsung, Xiaomi, OnePlus, etc. often customize permission flows)
- **Future Android versions** changing the permission model
- **Regional variations** (some countries have stricter privacy regulations)
- **Custom ROMs** with non-standard behavior

### Core Principle: Trust the System, Not Our Assumptions

**Never assume we can request permission again.** Always verify with the system before showing any UI.

### Implementation Safeguards

#### 1. Verify Before Requesting

Before calling `requestPermission()`, always check the current status:

```dart
Future<NotificationInitResult> initializeNotifications() async {
  // Always get fresh status from system - don't rely on cached state
  final currentStatus = await _getSystemPermissionStatus();

  // If already permanently denied, don't even try to request
  if (currentStatus == NotificationPermissionStatus.permanentlyDenied) {
    logd('Permission permanently denied - skipping request');
    return NotificationInitResult.permissionPermanentlyDenied;
  }

  // If already granted, just initialize
  if (currentStatus == NotificationPermissionStatus.authorized) {
    return await _initializeFCMToken();
  }

  // Now safe to request
  final result = await _requestPermission();

  // IMPORTANT: Check status AFTER request - it may have changed unexpectedly
  final statusAfterRequest = await _getSystemPermissionStatus();

  // Handle case where request silently failed (OEM blocking, etc.)
  if (statusAfterRequest == NotificationPermissionStatus.notDetermined) {
    // System didn't show dialog - maybe blocked by OEM
    loge('Permission request may have been blocked by system');
    return NotificationInitResult.error;
  }

  return _mapStatusToResult(statusAfterRequest);
}
```

#### 2. Handle "Silent Denial"

Some OEMs or situations may cause the permission request to silently fail:

```dart
// After requesting, verify the status actually changed
final statusBefore = await _getSystemPermissionStatus();
await _requestPermission();
final statusAfter = await _getSystemPermissionStatus();

if (statusBefore == NotificationPermissionStatus.notDetermined &&
    statusAfter == NotificationPermissionStatus.notDetermined) {
  // Request was blocked or ignored - treat as error, not denial
  // Don't increment denial count (user didn't actually see/deny it)
  return NotificationInitResult.error;
}
```

#### 3. Graceful Fallback for "denied" Status

When status is `denied` (not `permanentlyDenied`), don't assume we can re-request:

```dart
case NotificationPermissionStatus.denied:
  // TRY to request again, but be prepared for it to fail silently
  final result = await initializeNotifications();

  // If the system didn't show a dialog (returned error or still denied),
  // fall back to settings flow
  if (result == NotificationInitResult.error ||
      result == NotificationInitResult.permissionPermanentlyDenied) {
    // System wouldn't let us ask - fall back to settings
    return _handlePermanentlyDeniedFlow(context, config);
  }

  return _mapInitResultToFlowResult(result);
```

#### 4. Don't Trust Our Denial Count

Our internal count of "times denied" may not match reality:

```dart
// Instead of: if (denialCount < maxAskCount) { request() }
// Do this:
final canRequest = await _systemWillShowPermissionDialog();
if (!canRequest) {
  // System says no - go to settings flow regardless of our count
  return _handlePermanentlyDeniedFlow(context, config);
}
```

#### 5. Add Request Attempt Tracking

Track when we *attempted* to request, not just when user denied:

```dart
class NotificationDenialInfo {
  final DateTime lastDenialTime;
  final int denialCount;
  final bool isPermanent;

  // NEW: Track request attempts vs actual denials
  final int requestAttemptCount;  // Times we called requestPermission()
  final DateTime? lastRequestAttemptTime;
  final bool lastRequestWasBlocked;  // System didn't show dialog

  // ...
}
```

#### 6. Handle Unknown/Unexpected States

```dart
// In NotificationService.getPermissionStatus()
Future<NotificationPermissionStatus> getPermissionStatus() async {
  try {
    final status = await _getSystemPermissionStatus();

    // Auto-clear denial/settings info if permission was granted via settings
    if (status == NotificationPermissionStatus.authorized ||
        status == NotificationPermissionStatus.provisional) {
      final denialInfo = await _getStoredDenialInfo();
      if (denialInfo != null) {
        logd('Permission now granted - clearing stored denial info');
        await clearNotificationDenialInfo();
        await clearGoToSettingsPromptInfo();
      }
    }

    return status;
  } catch (e) {
    // Unknown error - assume we can't get notifications
    loge('Error getting permission status: $e');
    // Return a safe default - don't assume we have permission
    return NotificationPermissionStatus.denied;
  }
}
```

### Summary of Safeguards

| Risk | Mitigation |
|------|------------|
| OEM blocks second request | Check status after request; fall back to settings if unchanged |
| Future Android removes re-request | Always verify with system before showing "try again" UI |
| Silent permission denial | Detect when status doesn't change after request |
| Cached status is stale | Always get fresh status from system before decisions |
| Unknown permission state | Default to `permanentlyDenied` (safest assumption) |

## Platform-Specific Behavior

### iOS
- **First request:** System shows permission dialog
- **After denial:** `AuthorizationStatus.denied` - system will NOT show dialog again
- **Must use settings:** Always after first denial - `permanentlyDenied`
- **Detection:** If status is `.denied`, it's always permanent on iOS
- **Open settings:** `permission_handler.openAppSettings()` opens iOS Settings

### Android

**Android 13+ (API 33+):** `POST_NOTIFICATIONS` is a runtime permission (notifications off by default)
**Android 12 and below:** Notifications enabled by default, no runtime permission needed

**Permission flow (Android 13+):**
- **First request:** System shows permission dialog
- **After first denial:** Can request again - `shouldShowRequestPermissionRationale()` returns `true`
- **After second denial:** Automatically permanently denied (Android 11+ behavior - no checkbox needed)
- **Must use settings:** After second denial (or first if targeting API 32 or lower on Android 13+ device)

**Detection challenges:**
- `shouldShowRequestPermissionRationale()` returns `false` in TWO cases:
  1. Permission not yet requested (not determined)
  2. Permanently denied
- Must track whether permission was previously requested to distinguish these states
- `permission_handler` may report `denied` when actually `permanentlyDenied` in some cases

**Recommended approach:**
- Track "has requested before" in SharedPreferences
- If `shouldShowRequestPermissionRationale()` is `false` AND we've requested before → permanently denied
- **Open settings:** `permission_handler.openAppSettings()` opens Android Settings

### Web
- **First request:** Browser shows permission dialog (varies by browser)
- **After denial:** Most browsers block further requests (similar to iOS)
- **Must use settings:** User must click the lock/info icon in the address bar
- **Detection:** `Notification.permission` returns 'default', 'granted', or 'denied'
- **Open settings:** **Cannot programmatically open browser settings** - must show instructions instead

**Web-specific considerations:**
1. `permission_handler` does NOT support web - use `FirebaseMessaging` directly
2. `openNotificationSettings()` returns `false` on web (can't open settings)
3. The "go to settings" dialog should show browser-specific instructions
4. VAPID key must be configured in Firebase for web push to work

### Web Implementation

```dart
@override
Future<bool> openNotificationSettings() async {
  if (kIsWeb) {
    // Cannot open browser settings programmatically
    // Return false to indicate the app should show instructions instead
    return false;
  }
  // Mobile platforms
  return await openAppSettings();
}
```

**Web-specific strings for the config:**
```dart
class NotificationFlowStrings {
  // ... existing fields ...

  // Web-specific: Instructions when can't open settings
  final String webSettingsInstructionsTitle;
  final String webSettingsInstructionsMessage;
  final String webSettingsInstructionsButton;

  const NotificationFlowStrings({
    // ... existing defaults ...
    this.webSettingsInstructionsTitle = 'Enable Notifications',
    this.webSettingsInstructionsMessage =
        'To enable notifications:\n\n'
        '1. Click the lock/info icon in your browser\'s address bar\n'
        '2. Find "Notifications" in the permissions list\n'
        '3. Change it from "Block" to "Allow"\n'
        '4. Refresh this page',
    this.webSettingsInstructionsButton = 'Got It',
  });
}
```

**Updated flow for web permanently denied:**
```dart
case NotificationPermissionStatus.permanentlyDenied:
  if (kIsWeb) {
    // Show instructions dialog instead of opening settings
    final acknowledged = config.goToSettingsBuilder != null
        ? await config.goToSettingsBuilder!(context)
        : await _showWebSettingsInstructionsDialog(context, config.strings);
    return acknowledged
        ? NotificationFlowResult.openedSettings  // User saw instructions
        : NotificationFlowResult.declinedGoToSettings;
  } else {
    // Mobile: Can open settings
    final shouldOpenSettings = config.goToSettingsBuilder != null
        ? await config.goToSettingsBuilder!(context)
        : await _showGoToSettingsDialog(context, config.strings);
    if (!shouldOpenSettings) {
      return NotificationFlowResult.declinedGoToSettings;
    }
    await openNotificationSettings();
    return NotificationFlowResult.openedSettings;
  }
```

### Implementation Note
The `permission_handler` package provides `openAppSettings()` for mobile platforms.

**Note:** `permission_handler` is already included in `pubspec.yaml` - no additional dependency needed.

**Note:** `permission_handler` does not support web. The implementation must check `kIsWeb` and use `FirebaseMessaging` APIs directly for web permission status.

## Backward Compatibility
- Default is `true` (auto-initialize), preserving existing behavior
- Apps that don't configure this will work exactly as before

## Verification

### Basic Flow
1. Run the app with default settings - verify permission prompt appears on login
2. Set `fcmAutoInitializeDefault = false` - verify no prompt on login
3. Call `initializeNotifications()` manually - verify prompt appears and FCM works

### Permission Already Granted (Subsequent Launch)
4. Grant permission, close app, relaunch with `fcmAutoInitialize = false`
5. Verify FCM initializes silently (no dialog, but tokens updated)

### Denial Flow - iOS
6. Deny permission on iOS
7. Verify `getNotificationPermissionStatus()` returns `permanentlyDenied`
8. Verify `initializeNotifications()` returns `permissionPermanentlyDenied`
9. Verify `openNotificationSettings()` opens iOS Settings app

### Denial Flow - Android (API 33+)
10. Deny permission on Android (first denial)
11. Verify `getNotificationPermissionStatus()` returns `denied`
12. Verify `shouldShowRequestPermissionRationale` returns `true`
13. Verify calling `initializeNotifications()` again shows the dialog
14. Deny permission again (second denial)
15. Verify status changes to `permanentlyDenied` (automatic on Android 11+, no checkbox needed)
16. Verify calling `initializeNotifications()` does NOT show system dialog

### Denial Tracking
17. Deny permission, verify `getNotificationDenialInfo()` returns correct data
18. Grant permission via settings, call `getNotificationPermissionStatus()`
19. Verify denial info is **auto-cleared** (no manual `clearNotificationDenialInfo()` needed)
20. Verify go-to-settings prompt info is also auto-cleared

### Go-to-Settings Configuration
21. With `showGoToSettingsPrompt: false`:
    - Permanently deny permission
    - Run flow, verify returns `skippedGoToSettings` (no dialog shown)
22. With `goToSettingsMaxAskCount: 1`:
    - Permanently deny permission
    - Run flow, verify settings dialog appears
    - Decline to go to settings
    - Run flow again, verify returns `skippedGoToSettings` (count limit reached)
23. With `goToSettingsAskAgainAfter: Duration(days: 7)`:
    - Permanently deny permission, decline settings prompt
    - Run flow immediately, verify returns `skippedGoToSettings` (timing limit)
    - (Manual/mock test) Simulate 7 days passing, run flow, verify dialog appears again
24. Verify `getGoToSettingsPromptInfo()` returns correct data:
    - `promptCount` increments each time dialog is shown
    - `lastPromptTime` updates correctly
    - `lastActionWasOpenSettings` reflects user's choice

### Web-Specific Flow
25. Run on web with default settings (`useFCMWeb = false`)
26. Verify FCM is NOT initialized (no permission prompt, `useFCM` returns `false`)
27. Set `useFCMWebDefault = true` to enable web FCM
28. Verify FCM IS initialized and permission prompt appears (Chrome)
29. Deny permission on web
30. Verify `getNotificationPermissionStatus()` returns `permanentlyDenied`
31. Verify `openNotificationSettings()` returns `false` (can't open browser settings)
32. Verify the instructions dialog is shown with browser-specific guidance
33. Enable via browser lock icon, refresh, verify FCM works

### Edge Cases & Defensive Handling
34. **Blocked permission request** (simulate OEM blocking):
    - Mock `_requestPermission()` to not change status
    - Call `initializeNotifications()`
    - Verify returns `permissionRequestBlocked` (not `permissionDenied`)
    - Verify `denialCount` is NOT incremented
    - Verify `requestAttemptCount` IS incremented
    - Verify `lastRequestWasBlocked` is `true`
35. **System returns unexpected status**:
    - Mock system to throw an exception
    - Verify `getNotificationPermissionStatus()` returns `permanentlyDenied` (safe default)
36. **Status changes between check and request**:
    - Mock permission to become permanently denied during request
    - Verify graceful fallback to settings flow
37. **Re-request blocked after single denial** (stricter OEM):
    - Deny once on Android
    - Mock system to not show dialog on second request
    - Verify flow gracefully falls back to settings
38. **Fresh status on each call + auto-clear**:
    - Grant permission via settings while app is backgrounded
    - Resume app, call `getNotificationPermissionStatus()`
    - Verify returns `granted` (not stale cached `denied`)
    - Verify denial info and settings-prompt info were auto-cleared
39. **Denial info vs request attempts mismatch**:
    - Have 2 blocked requests + 1 actual denial
    - Verify `denialCount` is 1
    - Verify `requestAttemptCount` is 3

## Unit Tests

### Test Structure

```
test/
└── notification_permission/
    ├── notification_denial_info_test.dart
    ├── go_to_settings_prompt_info_test.dart
    ├── notification_flow_config_test.dart
    ├── notification_permission_helper_test.dart  # Tests for enhanced helper
    ├── should_ask_again_test.dart
    ├── should_show_go_to_settings_test.dart
    ├── notification_permission_flow_test.dart
    ├── mocks/
    │   ├── mock_permission_handler.dart
    │   └── mock_shared_preferences.dart
    └── integration/
        └── notification_permission_integration_test.dart
```

### Unit Test Cases

#### 1. NotificationDenialInfo Tests (`notification_denial_info_test.dart`)

```dart
group('NotificationDenialInfo', () {
  test('creates with required fields', () {
    final info = NotificationDenialInfo(
      lastDenialTime: DateTime.now(),
      denialCount: 2,
      isPermanent: false,
    );
    expect(info.requestAttemptCount, 0); // default
    expect(info.lastRequestWasBlocked, false); // default
  });

  test('serializes to JSON correctly', () {
    final info = NotificationDenialInfo(...);
    final json = info.toJson();
    expect(json['denialCount'], 2);
  });

  test('deserializes from JSON correctly', () {
    final json = {'lastDenialTime': ..., 'denialCount': 2, ...};
    final info = NotificationDenialInfo.fromJson(json);
    expect(info.denialCount, 2);
  });

  test('handles missing optional fields in JSON', () {
    final json = {'lastDenialTime': ..., 'denialCount': 1, 'isPermanent': true};
    final info = NotificationDenialInfo.fromJson(json);
    expect(info.requestAttemptCount, 0);
    expect(info.lastRequestWasBlocked, false);
  });
});
```

#### 2. _shouldAskAgain() Tests (`should_ask_again_test.dart`)

```dart
group('_shouldAskAgain', () {
  test('returns true when info is null (never asked)', () {
    expect(_shouldAskAgain(null, defaultConfig), true);
  });

  test('returns false when isPermanent is true', () {
    final info = NotificationDenialInfo(isPermanent: true, ...);
    expect(_shouldAskAgain(info, defaultConfig), false);
  });

  test('returns false when denialCount >= maxAskCount', () {
    final config = NotificationFlowConfig(maxAskCount: 3);
    final info = NotificationDenialInfo(denialCount: 3, ...);
    expect(_shouldAskAgain(info, config), false);
  });

  test('returns false when not enough time has passed', () {
    final config = NotificationFlowConfig(askAgainAfter: Duration(days: 7));
    final info = NotificationDenialInfo(
      lastDenialTime: DateTime.now().subtract(Duration(days: 3)),
      ...
    );
    expect(_shouldAskAgain(info, config), false);
  });

  test('returns true when enough time has passed and under count limit', () {
    final config = NotificationFlowConfig(
      askAgainAfter: Duration(days: 7),
      maxAskCount: 3,
    );
    final info = NotificationDenialInfo(
      lastDenialTime: DateTime.now().subtract(Duration(days: 10)),
      denialCount: 2,
      isPermanent: false,
    );
    expect(_shouldAskAgain(info, config), true);
  });
});
```

#### 3. _shouldShowGoToSettingsPrompt() Tests (`should_show_go_to_settings_test.dart`)

```dart
group('_shouldShowGoToSettingsPrompt', () {
  test('returns true when info is null (never shown)', () {
    final config = NotificationFlowConfig();
    expect(_shouldShowGoToSettingsPrompt(null, config), true);
  });

  test('returns false when promptCount >= goToSettingsMaxAskCount', () {
    final config = NotificationFlowConfig(goToSettingsMaxAskCount: 2);
    final info = GoToSettingsPromptInfo(promptCount: 2, ...);
    expect(_shouldShowGoToSettingsPrompt(info, config), false);
  });

  test('returns true when goToSettingsMaxAskCount is null (unlimited)', () {
    final config = NotificationFlowConfig(goToSettingsMaxAskCount: null);
    final info = GoToSettingsPromptInfo(promptCount: 100, ...);
    // Still need to check timing
    expect(_shouldShowGoToSettingsPrompt(info, config), ...);
  });

  test('returns false when not enough time since last prompt', () {
    final config = NotificationFlowConfig(
      goToSettingsAskAgainAfter: Duration(days: 30),
    );
    final info = GoToSettingsPromptInfo(
      lastPromptTime: DateTime.now().subtract(Duration(days: 15)),
      promptCount: 1,
    );
    expect(_shouldShowGoToSettingsPrompt(info, config), false);
  });

  test('returns true when enough time has passed', () {
    final config = NotificationFlowConfig(
      goToSettingsAskAgainAfter: Duration(days: 30),
      goToSettingsMaxAskCount: 5,
    );
    final info = GoToSettingsPromptInfo(
      lastPromptTime: DateTime.now().subtract(Duration(days: 45)),
      promptCount: 2,
    );
    expect(_shouldShowGoToSettingsPrompt(info, config), true);
  });
});
```

#### 4. Permission Flow Tests (`notification_permission_flow_test.dart`)

```dart
group('runNotificationPermissionFlow', () {
  late MockNotificationService notificationService;
  late MockBuildContext context;

  setUp(() {
    notificationService = MockNotificationService();
    context = MockBuildContext();
  });

  test('returns fcmDisabled when FCM is disabled', () async {
    AppConfigBase.useFCMDefault = false;

    final result = await notificationService.runNotificationPermissionFlow(context);
    expect(result, NotificationFlowResult.fcmDisabled);
  });

  test('returns alreadyGranted when permission already granted', () async {
    when(notificationService.getPermissionStatus())
        .thenAnswer((_) async => NotificationPermissionStatus.authorized);

    final result = await notificationService.runNotificationPermissionFlow(context);
    expect(result, NotificationFlowResult.alreadyGranted);
  });

  test('shows value proposition for notDetermined status', () async {
    when(notificationService.getPermissionStatus())
        .thenAnswer((_) async => NotificationPermissionStatus.notDetermined);

    await notificationService.runNotificationPermissionFlow(context);

    verify(notificationService._showValuePropositionDialog(context, any)).called(1);
  });

  test('returns skippedGoToSettings when config disables it', () async {
    when(notificationService.getPermissionStatus())
        .thenAnswer((_) async => NotificationPermissionStatus.permanentlyDenied);

    final config = NotificationFlowConfig(showGoToSettingsPrompt: false);
    final result = await notificationService.runNotificationPermissionFlow(
      context,
      config: config,
    );

    expect(result, NotificationFlowResult.skippedGoToSettings);
  });

  test('detects blocked permission request', () async {
    // Status doesn't change after request
    when(notificationService.getPermissionStatus())
        .thenAnswer((_) async => NotificationPermissionStatus.notDetermined);
    when(notificationService._requestPermission())
        .thenAnswer((_) async => {}); // Does nothing

    final result = await notificationService.requestPermissions();

    expect(result, NotificationPermissionStatus.notDetermined); // Unchanged
    // Verify denial count NOT incremented
    final info = await notificationService.getNotificationDenialInfo();
    expect(info?.denialCount, 0);
    expect(info?.requestAttemptCount, 1);
    expect(info?.lastRequestWasBlocked, true);
  });

  test('falls back to settings flow when re-request blocked', () async {
    // First call: denied (can retry)
    // Second call: still denied (blocked)
    var callCount = 0;
    when(notificationService.getPermissionStatus()).thenAnswer((_) async {
      callCount++;
      return NotificationPermissionStatus.denied;
    });

    final result = await notificationService.runNotificationPermissionFlow(context);

    // Should fall back to settings flow
    verify(notificationService._showGoToSettingsDialog(context, any)).called(1);
  });
});
```

#### 5. Integration Tests (`notification_permission/integration/notification_permission_integration_test.dart`)

```dart
group('Notification Permission Integration', () {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  test('persists denial info to SharedPreferences', () async {
    final notificationService = NotificationService();
    await notificationService.initialize(...);

    // Simulate denial
    await notificationService.permissionHelper.recordDenial(isPermanent: false);

    // Verify persisted with dreamic_ prefix
    final storedJson = prefs.getString('dreamic_notification_denial_info');
    expect(storedJson, isNotNull);

    final info = await notificationService.getNotificationDenialInfo();
    expect(info?.denialCount, 1);
  });

  test('clears denial info after permission granted', () async {
    // Set up existing denial info (note: dreamic_ prefix)
    prefs.setString('dreamic_notification_denial_info', '{"denialCount": 2, ...}');

    final notificationService = NotificationService();
    await notificationService.initialize(...);
    await notificationService.clearNotificationDenialInfo();

    final info = await notificationService.getNotificationDenialInfo();
    expect(info, isNull);
  });

  test('persists go-to-settings prompt info', () async {
    final notificationService = NotificationService();
    await notificationService.initialize(...);

    await notificationService.permissionHelper.recordGoToSettingsPrompt(openedSettings: true);

    final info = await notificationService.getGoToSettingsPromptInfo();
    expect(info?.promptCount, 1);
    expect(info?.lastActionWasOpenSettings, true);
  });

  test('tracks has-requested-before flag for Android detection', () async {
    final notificationService = NotificationService();
    await notificationService.initialize(...);

    // Before first request (note: dreamic_ prefix)
    expect(prefs.getBool('dreamic_notification_has_requested'), isNull);

    // After request
    await notificationService.requestPermissions();

    expect(prefs.getBool('dreamic_notification_has_requested'), true);
  });

  test('auto-clears denial info when permission detected as granted', () async {
    // Set up: user previously denied, then enabled via settings
    prefs.setString('dreamic_notification_denial_info', '{"denialCount": 2, ...}');
    prefs.setString('dreamic_notification_settings_prompt_info', '{"promptCount": 1, ...}');

    final notificationService = NotificationService();
    await notificationService.initialize(...);
    // Mock the system to return granted
    mockPermissionHandler.setStatus(NotificationPermissionStatus.authorized);

    // Act: check status (simulating app resume after settings)
    final status = await notificationService.getPermissionStatus();

    // Assert: status is granted and tracking data was auto-cleared
    expect(status, NotificationPermissionStatus.authorized);
    expect(prefs.getString('dreamic_notification_denial_info'), isNull);
    expect(prefs.getString('dreamic_notification_settings_prompt_info'), isNull);
  });

  test('does not clear denial info when permission still denied', () async {
    // Set up: user previously denied
    prefs.setString('dreamic_notification_denial_info', '{"denialCount": 2, ...}');

    final notificationService = NotificationService();
    await notificationService.initialize(...);
    // Mock the system to still return denied
    mockPermissionHandler.setStatus(NotificationPermissionStatus.denied);

    // Act: check status
    final status = await notificationService.getPermissionStatus();

    // Assert: denial info preserved
    expect(status, NotificationPermissionStatus.denied);
    expect(prefs.getString('dreamic_notification_denial_info'), isNotNull);
  });
});
```

### Mocking Strategy

```dart
// mock_permission_handler.dart
class MockPermissionHandler {
  NotificationPermissionStatus _status = NotificationPermissionStatus.notDetermined;
  bool _shouldShowRationale = false;
  bool _blockNextRequest = false;

  void setStatus(NotificationPermissionStatus status) {
    _status = status;
  }

  void setShouldShowRationale(bool value) {
    _shouldShowRationale = value;
  }

  void blockNextRequest() {
    _blockNextRequest = true;
  }

  Future<NotificationPermissionStatus> getStatus() async {
    return _status;
  }

  Future<NotificationPermissionStatus> request() async {
    if (_blockNextRequest) {
      _blockNextRequest = false;
      return _status; // Status unchanged - request blocked
    }
    // Simulate actual request behavior
    return _status;
  }

  bool shouldShowRequestRationale() {
    return _shouldShowRationale;
  }
}
```

### Test Coverage Goals

| Component | Coverage Target |
|-----------|-----------------|
| `NotificationDenialInfo` | 100% |
| `GoToSettingsPromptInfo` | 100% |
| `NotificationFlowConfig` | 100% |
| `_shouldAskAgain()` | 100% |
| `_shouldShowGoToSettingsPrompt()` | 100% |
| `initializeNotifications()` | 90%+ |
| `runNotificationPermissionFlow()` | 90%+ |
| Defensive error handling paths | 80%+ |
| SharedPreferences persistence | 90%+ |
