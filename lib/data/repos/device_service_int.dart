import 'package:dartz/dartz.dart';
import 'package:dreamic/data/helpers/repository_failure.dart';
import 'package:dreamic/data/models/device_info.dart';
import 'package:dreamic/data/repos/auth_service_int.dart';

/// Service interface for managing device registration and timezone tracking.
///
/// The DeviceService tracks device-level information with timezone as the
/// primary use case. It maintains a canonical Firestore document per
/// install/profile at `users/{uid}/devices/{deviceId}` containing:
/// - Device state for timezone-aware logic (timezone, offset, lastActiveAt)
/// - Current push token when available (for notification delivery)
///
/// ## Separation of Concerns
///
/// - **DeviceService** owns: device identity, timezone/offset tracking,
///   activity tracking (`lastActiveAt`), backend persistence (all Firestore
///   device doc writes), and deleting the device doc on logout.
/// - **NotificationService** owns: permission prompting, token acquisition,
///   and local token lifecycle. It forwards token changes to DeviceService
///   for persistence but does NOT persist tokens during logout (DeviceService
///   handles cleanup by deleting the device doc).
///
/// ## Integration (Recommended: Race-Free Initialization)
///
/// Use [DreamicServices.initialize] for the simplest, race-free setup:
///
/// ```dart
/// // Single call handles all wiring correctly
/// final services = await DreamicServices.initialize(
///   firebaseApp: Firebase.app(),
///   enableDeviceService: true,
///   enableNotifications: true,
/// );
/// ```
///
/// For manual wiring with race-free initialization, pass callbacks to
/// AuthService constructor and use [initialize]:
///
/// ```dart
/// // 1. Create services
/// final deviceService = DeviceServiceImpl();
/// final notificationService = NotificationService();
///
/// // 2. Register in GetIt early
/// GetIt.I.registerSingleton<DeviceServiceInt>(deviceService);
///
/// // 3. Create auth with callbacks pre-registered (race-free)
/// final auth = AuthServiceImpl(
///   firebaseApp: app,
///   onAuthenticatedCallbacks: [deviceService.handleAuthenticated],
///   onAboutToLogOutCallbacks: [deviceService.handleAboutToLogOut],
/// );
///
/// // 4. Initialize services in parallel (critical for race-free!)
/// await Future.wait([
///   deviceService.initialize(authService: auth),
///   notificationService.initialize(authService: auth),
/// ]);
/// ```
///
/// ## Legacy Integration
///
/// The [connectToAuthService] method is still available for apps that:
/// - Don't have warm-start race issues (e.g., always require fresh login)
/// - Want to connect services dynamically after auth is established
///
/// ```dart
/// // Legacy approach (may miss auth events on warm start)
/// await deviceService.connectToAuthService();
/// ```
///
/// See `docs/plans/auth-race/plan.auth-race.md` for migration details.
///
/// ## Best-Effort Operations
///
/// All device operations are best-effort and should never block the app.
/// Failures are logged but not surfaced to users. A pending payload system
/// ensures eventual consistency across flaky networks.
///
/// ## Key Constraints
///
/// - **DST-safe**: `timezoneOffsetMinutes` is refreshed even when the IANA
///   timezone string doesn't change (to handle DST transitions).
/// - **Efficient**: Throttling prevents unnecessary writes on frequent
///   app resume events.
/// - **Robust**: Offline failures don't block the app; sync retries on
///   later lifecycle events.
///
/// See also:
/// - [DeviceInfo] for the device document model
/// - [AuthServiceInt] for authentication lifecycle callbacks
abstract class DeviceServiceInt {
  /// Registers or updates the current device in Firestore.
  ///
  /// Called automatically on login/auth refresh when connected to AuthService.
  /// Creates or updates the device document with current timezone, offset,
  /// platform, app version, and marks the device as active.
  ///
  /// This is best-effort and should not block app startup. On success,
  /// updates internal cache for timezone/offset throttling.
  ///
  /// ## When Called
  ///
  /// - On initial login (via `addOnAuthenticatedCallback`)
  /// - Can be called manually if needed
  ///
  /// ## Returns
  ///
  /// - `Right(unit)` on success
  /// - `Left(RepositoryFailure)` on failure (logged, not surfaced to user)
  ///
  /// ## Example
  ///
  /// ```dart
  /// final result = await deviceService.registerDevice();
  /// result.fold(
  ///   (failure) => log('Device registration failed: $failure'),
  ///   (_) => log('Device registered successfully'),
  /// );
  /// ```
  Future<Either<RepositoryFailure, Unit>> registerDevice();

  /// Updates timezone and/or offset in Firestore if changed.
  ///
  /// Performs a fast local check first (no network if unchanged and within
  /// throttle window). Only syncs to server when:
  /// - Timezone IANA string changed (user traveled)
  /// - Timezone offset changed (DST transition)
  /// - Forced refresh interval exceeded (safety net for missed DST)
  ///
  /// ## Throttling
  ///
  /// - **Change debounce**: 10 minutes (prevents rapid flapping near borders)
  /// - **Unchanged throttle**: 48 hours (avoids resume spam)
  /// - **Forced refresh**: 48 hours (catches missed DST transitions)
  ///
  /// ## When Called
  ///
  /// - On app resume from background (via AppLifecycleService)
  /// - Throttled automatically
  ///
  /// ## Returns
  ///
  /// - `Right(true)` if server was updated
  /// - `Right(false)` if unchanged or throttled (no update needed)
  /// - `Left(RepositoryFailure)` on failure
  ///
  /// ## DST Safety
  ///
  /// The system computes offset using `DateTime.now().timeZoneOffset.inMinutes`,
  /// which correctly handles half-hour and 45-minute offsets (India, Nepal, etc).
  /// DST transitions are detected because offset changes even when the IANA
  /// timezone string doesn't.
  Future<Either<RepositoryFailure, bool>> updateTimezoneOrOffsetIfChanged();

  /// Gets the current device's unique identifier.
  ///
  /// Returns a stable UUIDv4 that uniquely identifies this app install/profile.
  /// The ID is generated once and persisted locally:
  /// - Mobile/Desktop: SharedPreferences
  /// - Web: IndexedDB → localStorage → in-memory fallback
  ///
  /// ## Stability
  ///
  /// - Stable across app restarts
  /// - May reset on uninstall/reinstall (mobile/desktop)
  /// - May reset on "Clear site data" (web)
  /// - Web is best-effort (storage can be cleared/blocked)
  ///
  /// ## Returns
  ///
  /// The device ID string (UUIDv4 format).
  ///
  /// ## Example
  ///
  /// ```dart
  /// final deviceId = await deviceService.getDeviceId();
  /// print('Device ID: $deviceId');
  /// // Output: Device ID: 550e8400-e29b-41d4-a716-446655440000
  /// ```
  Future<String> getDeviceId();

  /// Gets the current device's IANA timezone string.
  ///
  /// Returns the timezone identifier from the device's system settings
  /// (e.g., "America/New_York", "Europe/London", "Asia/Tokyo").
  ///
  /// This value includes DST rules and is the authoritative source for
  /// local time calculations on the backend.
  ///
  /// ## Returns
  ///
  /// The IANA timezone identifier string.
  ///
  /// ## Example
  ///
  /// ```dart
  /// final timezone = await deviceService.getCurrentTimezone();
  /// print('Timezone: $timezone');
  /// // Output: Timezone: America/New_York
  /// ```
  Future<String> getCurrentTimezone();

  /// Marks this device as active by updating `lastActiveAt`.
  ///
  /// Updates the device document's `lastActiveAt` timestamp to indicate
  /// recent activity. Used by backend to determine:
  /// - Which devices are "active" for notification delivery
  /// - Which devices to clean up as stale
  ///
  /// ## Throttling
  ///
  /// Default throttle is 60 minutes to avoid excessive writes. Configurable
  /// via Remote Config (`dreamic_device_touch_throttle_minutes`).
  ///
  /// ## When Called
  ///
  /// - On app resume from background (throttled)
  /// - After [registerDevice] (implicitly updates lastActiveAt)
  ///
  /// ## Server Behavior
  ///
  /// Uses upsert semantics: if the device doc doesn't exist, it will be
  /// created with minimal fields (deviceId, lastActiveAt, updatedAt).
  ///
  /// ## Returns
  ///
  /// - `Right(unit)` on success
  /// - `Left(RepositoryFailure)` on failure
  Future<Either<RepositoryFailure, Unit>> touchDevice();

  /// Persists the FCM token to the backend device record.
  ///
  /// Called by NotificationService when it obtains/refreshes the token or
  /// clears it due to notifications being disabled. This method only handles
  /// backend persistence—NotificationService owns the token lifecycle
  /// (fetch/refresh/cache/local state).
  ///
  /// ## When Called
  ///
  /// - Initial token acquisition (first successful read after enabling)
  /// - Token rotation/refresh (Firebase Messaging token refresh event)
  /// - Token cleared due to local disablement (user disables notifications
  ///   in-app while staying logged in)
  ///
  /// ## Important: Logout Path
  ///
  /// Do NOT call this method during logout. DeviceService deletes the device
  /// doc on logout via [unregisterDevice]; NotificationService should perform
  /// only local cleanup (clear cached token, detach listeners) without
  /// triggering a backend write that would race with device doc deletion.
  ///
  /// ## Token Uniqueness
  ///
  /// The backend enforces that a token appears on at most one device doc.
  /// On token update, it clears the same token from any other device docs
  /// (handles edge cases from offline failures or account switching).
  ///
  /// ## Parameters
  ///
  /// - [fcmToken]: The new FCM token, or `null` to clear the token.
  ///
  /// ## Returns
  ///
  /// - `Right(unit)` on success
  /// - `Left(RepositoryFailure)` on failure
  ///
  /// ## Example
  ///
  /// ```dart
  /// // Token obtained
  /// await deviceService.persistFcmToken(fcmToken: newToken);
  ///
  /// // Token cleared (e.g., user revoked permission while logged in)
  /// await deviceService.persistFcmToken(fcmToken: null);
  /// ```
  Future<Either<RepositoryFailure, Unit>> persistFcmToken({
    required String? fcmToken,
  });

  /// Removes the current device registration from Firestore.
  ///
  /// Called BEFORE logout while still authenticated, via the
  /// `addOnAboutToLogOutCallback` hook. Deletes the device document
  /// at `users/{uid}/devices/{deviceId}`.
  ///
  /// ## Important
  ///
  /// - Must be called while still authenticated (before sign out)
  /// - Best-effort and timeboxed; must never block logout
  /// - If offline, staleness cleanup will handle orphaned docs
  ///
  /// ## When Called
  ///
  /// - Automatically via `AuthServiceInt.addOnAboutToLogOutCallback`
  /// - Should not be called manually in most cases
  ///
  /// ## Returns
  ///
  /// - `Right(unit)` on success
  /// - `Left(RepositoryFailure)` on failure (logged, doesn't block logout)
  Future<Either<RepositoryFailure, Unit>> unregisterDevice();

  /// Gets all devices registered for the current user.
  ///
  /// Returns a list of all device documents under `users/{uid}/devices/`,
  /// ordered by `lastActiveAt` descending (most recent first).
  ///
  /// ## Requirements
  ///
  /// - User must be authenticated
  /// - Implemented via backend callable (no direct client Firestore reads)
  ///
  /// ## Use Cases
  ///
  /// - Displaying a "My Devices" settings screen
  /// - Admin/debugging tools
  /// - Showing which device will receive notifications
  ///
  /// ## Returns
  ///
  /// - `Right(List<DeviceInfo>)` with all user's devices
  /// - `Left(RepositoryFailure)` on failure or if not authenticated
  ///
  /// ## Example
  ///
  /// ```dart
  /// final result = await deviceService.getMyDevices();
  /// result.fold(
  ///   (failure) => showError('Could not load devices'),
  ///   (devices) {
  ///     for (final device in devices) {
  ///       print('${device.platform}: ${device.timezone}');
  ///     }
  ///   },
  /// );
  /// ```
  Future<Either<RepositoryFailure, List<DeviceInfo>>> getMyDevices();

  /// Connects this DeviceService to AuthService for automatic lifecycle wiring.
  ///
  /// **Note:** This is the legacy initialization approach. For new code, prefer
  /// [DreamicServices.initialize] or the race-free [initialize] + constructor
  /// callback pattern described in the class documentation.
  ///
  /// This method may miss auth events on warm start (when user is already
  /// logged in) because callbacks are registered after Firebase listeners
  /// have already attached. See `docs/plans/auth-race/plan.auth-race.md`.
  ///
  /// Registers callbacks with AuthService to automatically:
  /// - Call [registerDevice] on authentication (login)
  /// - Call [unregisterDevice] before logout (while still authenticated)
  ///
  /// ## When to Use This Method
  ///
  /// Use this method only if:
  /// - Your app always requires fresh login (no warm start race condition)
  /// - You need to connect services dynamically after auth is established
  /// - You're migrating legacy code incrementally
  ///
  /// ## Parameters
  ///
  /// - [authService]: Optional explicit AuthService instance. If null,
  ///   attempts to resolve from GetIt. If not registered, logs and no-ops.
  /// - [onAuthenticated]: Optional override for the authenticated callback.
  ///   Default: calls `registerDevice()`.
  /// - [onAboutToLogOut]: Optional override for the pre-logout callback.
  ///   Default: calls `unregisterDevice()`.
  ///
  /// ## Idempotency
  ///
  /// Safe to call multiple times. Removes old callbacks before adding new ones.
  ///
  /// ## Example (Legacy Pattern)
  ///
  /// ```dart
  /// // Legacy setup (may miss auth events on warm start)
  /// await deviceService.connectToAuthService();
  ///
  /// // With explicit AuthService
  /// await deviceService.connectToAuthService(authService: myAuthService);
  ///
  /// // With custom callbacks
  /// await deviceService.connectToAuthService(
  ///   onAuthenticated: (uid) async {
  ///     await deviceService.registerDevice();
  ///     await analytics.trackLogin(uid);
  ///   },
  /// );
  /// ```
  Future<void> connectToAuthService({
    AuthServiceInt? authService,
    Future<void> Function(String? uid)? onAuthenticated,
    Future<void> Function()? onAboutToLogOut,
  });

  // ============================================================
  // Race-Free Initialization API (plan.auth-race.md)
  // ============================================================

  /// Public handler for auth state changes. Called when user authenticates.
  ///
  /// This method can be passed to AuthService constructor for race-free
  /// initialization, ensuring callbacks are registered before Firebase
  /// listeners attach.
  ///
  /// ## Usage
  ///
  /// ```dart
  /// // Race-free initialization pattern:
  /// final deviceService = DeviceServiceImpl();
  /// final auth = AuthServiceImpl(
  ///   firebaseApp: app,
  ///   onAuthenticatedCallbacks: [deviceService.handleAuthenticated],
  /// );
  /// await deviceService.initialize(authService: auth);
  /// ```
  ///
  /// ## Defensive Behavior
  ///
  /// - Returns immediately if [uid] is null (shouldn't happen in practice)
  /// - Logs a warning if called before [initialize] (indicates ordering bug)
  /// - Uses pending payload fallback for graceful degradation
  ///
  /// ## Parameters
  ///
  /// - [uid]: The authenticated user's ID, or null on logout.
  Future<void> handleAuthenticated(String? uid);

  /// Public handler for pre-logout cleanup.
  ///
  /// This method can be passed to AuthService constructor for race-free
  /// initialization. It unregisters the device before logout completes.
  ///
  /// ## Usage
  ///
  /// ```dart
  /// // Race-free initialization pattern:
  /// final deviceService = DeviceServiceImpl();
  /// final auth = AuthServiceImpl(
  ///   firebaseApp: app,
  ///   onAboutToLogOutCallbacks: [deviceService.handleAboutToLogOut],
  /// );
  /// ```
  ///
  /// ## Behavior
  ///
  /// Calls [unregisterDevice] to delete the device document from Firestore.
  /// This is best-effort and should never block logout.
  Future<void> handleAboutToLogOut();

  /// Initializes DeviceService with auth reference for race-free setup.
  ///
  /// Call this AFTER creating AuthService with callbacks pre-registered.
  /// This sets up the auth reference and lifecycle service connection
  /// without registering callbacks (since they were passed to AuthService).
  ///
  /// ## Critical Constraint
  ///
  /// The implementation MUST set `_authService` synchronously at the start,
  /// before any await statements. This ensures the auth reference is available
  /// when callbacks fire (which may happen via microtask immediately after
  /// AuthService construction).
  ///
  /// ## Usage
  ///
  /// ```dart
  /// // Race-free initialization pattern:
  /// final deviceService = DeviceServiceImpl();
  /// final auth = AuthServiceImpl(
  ///   firebaseApp: app,
  ///   onAuthenticatedCallbacks: [deviceService.handleAuthenticated],
  ///   onAboutToLogOutCallbacks: [deviceService.handleAboutToLogOut],
  /// );
  ///
  /// // CRITICAL: Use Future.wait for parallel initialization
  /// await Future.wait([
  ///   deviceService.initialize(authService: auth),
  ///   notificationService.initialize(authService: auth),
  /// ]);
  /// ```
  ///
  /// ## Parameters
  ///
  /// - [authService]: The AuthService instance to connect to.
  Future<void> initialize({required AuthServiceInt authService});

  /// Whether this service is connected to auth.
  ///
  /// Returns true after [initialize] or [connectToAuthService] has been
  /// called successfully. Used by other services (e.g., NotificationService)
  /// to determine if DeviceService will handle cleanup responsibilities.
  ///
  /// ## Usage
  ///
  /// ```dart
  /// if (deviceService.isConnectedToAuth) {
  ///   // DeviceService will handle device doc cleanup on logout
  /// } else {
  ///   // Must handle cleanup ourselves
  /// }
  /// ```
  bool get isConnectedToAuth;
}
