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
///   activity tracking (`lastActiveAt`), and persisting the FCM token.
/// - **NotificationService** owns: permission prompting, token acquisition,
///   and local token lifecycle. It forwards token changes to DeviceService.
///
/// ## Integration
///
/// Call [connectToAuthService] during app startup to automatically wire
/// device registration/unregistration to authentication lifecycle events.
///
/// ```dart
/// // In your app initialization
/// await deviceService.connectToAuthService();
///
/// // NotificationService forwards token changes to DeviceService
/// await notificationService.connectToAuthService(
///   onTokenChanged: (newToken, oldToken) async {
///     await deviceService.updateFcmToken(fcmToken: newToken);
///   },
/// );
/// ```
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
  /// - On auth token refresh (via `addOnRefreshedCallback`)
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

  /// Updates the current device doc with the latest push token.
  ///
  /// Called by NotificationService when:
  /// - A token is first obtained (user grants permission)
  /// - A token rotates/refreshes (FCM rotation)
  /// - A token is deleted/unavailable (pass `null`)
  ///
  /// ## Important
  ///
  /// This does NOT prompt for permission; it only persists state.
  /// NotificationService owns permission prompting and token acquisition.
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
  /// await deviceService.updateFcmToken(fcmToken: newToken);
  ///
  /// // Token cleared (e.g., user revoked permission)
  /// await deviceService.updateFcmToken(fcmToken: null);
  /// ```
  Future<Either<RepositoryFailure, Unit>> updateFcmToken({
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
  /// Registers callbacks with AuthService to automatically:
  /// - Call [registerDevice] on authentication (login)
  /// - Call [registerDevice] on auth token refresh
  /// - Call [unregisterDevice] before logout (while still authenticated)
  ///
  /// This mirrors the pattern used by NotificationService and allows
  /// consuming apps to set up DeviceService with minimal configuration.
  ///
  /// ## Parameters
  ///
  /// - [authService]: Optional explicit AuthService instance. If null,
  ///   attempts to resolve from GetIt. If not registered, logs and no-ops.
  /// - [onAuthenticated]: Optional override for the authenticated callback.
  ///   Default: calls `registerDevice()`.
  /// - [onRefreshed]: Optional override for the refresh callback.
  ///   Default: calls `registerDevice()`.
  /// - [onAboutToLogOut]: Optional override for the pre-logout callback.
  ///   Default: calls `unregisterDevice()`.
  ///
  /// ## Idempotency
  ///
  /// Safe to call multiple times. Removes old callbacks before adding new ones.
  ///
  /// ## Example
  ///
  /// ```dart
  /// // Standard setup (uses defaults)
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
    Future<void> Function()? onRefreshed,
    Future<void> Function()? onAboutToLogOut,
  });
}
