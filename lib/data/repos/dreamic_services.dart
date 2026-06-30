import 'package:firebase_core/firebase_core.dart';
import 'package:get_it/get_it.dart';

import '../../notifications/notification_service.dart';
import '../../utils/logger.dart';
import 'auth_service_impl.dart';
import 'auth_service_int.dart';
import 'device_service_impl.dart';
import 'device_service_int.dart';

// Re-export PrioritizedCallback for consumers
export 'auth_service_int.dart' show PrioritizedCallback;

/// Result of [DreamicServices.initialize], containing references to all
/// initialized services.
///
/// This allows consuming apps to access the services directly if needed,
/// though they can also be resolved via GetIt after initialization.
class DreamicServicesResult {
  /// The initialized AuthService instance.
  final AuthServiceInt auth;

  /// The initialized DeviceService instance, or null if disabled.
  final DeviceServiceInt? deviceService;

  /// The initialized NotificationService instance, or null if disabled.
  final NotificationService? notificationService;

  /// Creates a result containing the initialized services.
  DreamicServicesResult({
    required this.auth,
    this.deviceService,
    this.notificationService,
  });
}

/// Initializes Dreamic services with correct callback ordering.
///
/// This class eliminates auth race conditions by registering callbacks
/// before Firebase listeners attach. See plan.auth-race.md for details.
///
/// ## Quick Start
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
/// ## What This Handles
///
/// 1. **Race-free callback registration**: Callbacks are passed to AuthService
///    constructor before Firebase listeners attach, ensuring no events are missed.
///
/// 2. **Correct initialization order**: Services are registered in GetIt before
///    AuthService is created, allowing code to resolve them during initialization.
///
/// 3. **Parallel service initialization**: Uses `Future.wait` to start all
///    `initialize()` calls synchronously, ensuring `_authService` is set in all
///    services before any microtasks (like auth callbacks) can run.
///
/// ## Architecture
///
/// The initialization flow is:
///
/// 1. Create services (DeviceService, NotificationService)
/// 2. Register services in GetIt early
/// 3. Collect callbacks from services
/// 4. Create AuthService with callbacks pre-registered
/// 5. Initialize services in parallel with auth reference
/// 6. Register AuthService in GetIt
///
/// ## Custom Callbacks
///
/// You can provide additional callbacks with individual priorities that run
/// alongside service callbacks:
///
/// ```dart
/// final services = await DreamicServices.initialize(
///   firebaseApp: app,
///   onAuthenticatedCallbacks: [
///     PrioritizedCallback((uid) async {
///       await analytics.trackLogin(uid);
///     }, priority: -10), // Run after core services
///   ],
///   onAboutToLogOutCallbacks: [
///     PrioritizedCallback(() async {
///       await analytics.trackLogout();
///     }, priority: 10), // Run before core services
///   ],
///   onLoggedOutCallbacks: [
///     PrioritizedCallback(() async {
///       await cache.clear();
///     }),
///   ],
/// );
/// ```
///
/// ## Manual Wiring Alternative
///
/// If you need more control, see the "After (race-free, manual wiring)"
/// example in plan.auth-race.md.
class DreamicServices {
  /// Initializes Dreamic services with correct callback ordering.
  ///
  /// This eliminates auth race conditions by registering callbacks
  /// before Firebase listeners attach.
  ///
  /// ## Parameters
  ///
  /// - [firebaseApp]: The Firebase app instance to use.
  /// - [enableDeviceService]: Whether to initialize DeviceService (default: true).
  /// - [enableNotifications]: Whether to initialize NotificationService (default: true).
  /// - [onAuthenticatedCallbacks]: Optional list of prioritized callbacks to run on authentication.
  /// - [onAboutToLogOutCallbacks]: Optional list of prioritized callbacks to run before logout.
  /// - [onLoggedOutCallbacks]: Optional list of prioritized callbacks to run after logout completes.
  /// - [onNotificationTapped]: Callback for when user taps a notification.
  /// - [onTokenChanged]: Optional callback for FCM token changes. When omitted
  ///   and both [enableDeviceService] and [enableNotifications] are true, the
  ///   token is persisted to the device document via
  ///   [DeviceServiceInt.persistFcmToken] automatically.
  /// - [showNotificationsInForeground]: Whether to show notifications in foreground.
  /// - [registerInGetIt]: Whether to register services in GetIt (default: true).
  ///   Set to false if you want to handle GetIt registration yourself.
  ///
  /// ## Callback Priorities
  ///
  /// Each callback can specify its own priority via [PrioritizedCallback]:
  /// - Higher priority values execute first (e.g., 100 runs before 0)
  /// - Default core services (DeviceService, NotificationService) use priority 0
  /// - Use positive values to run before core services
  /// - Use negative values to run after core services
  ///
  /// ## Returns
  ///
  /// A [DreamicServicesResult] containing references to all initialized services.
  ///
  /// ## Example
  ///
  /// ```dart
  /// final services = await DreamicServices.initialize(
  ///   firebaseApp: Firebase.app(),
  ///   enableDeviceService: true,
  ///   enableNotifications: true,
  ///   onAuthenticatedCallbacks: [
  ///     PrioritizedCallback((uid) async {
  ///       await analytics.trackLogin(uid);
  ///     }, priority: -10),
  ///   ],
  ///   onNotificationTapped: (route, data) async {
  ///     if (route != null) {
  ///       Navigator.of(context).pushNamed(route, arguments: data);
  ///     }
  ///   },
  /// );
  /// ```
  static Future<DreamicServicesResult> initialize({
    required FirebaseApp firebaseApp,
    bool enableDeviceService = true,
    bool enableNotifications = true,
    // Optional custom callbacks with individual priorities
    List<PrioritizedCallback<Future<void> Function(String? uid)>>?
        onAuthenticatedCallbacks,
    List<PrioritizedCallback<Future<void> Function()>>? onAboutToLogOutCallbacks,
    List<PrioritizedCallback<Future<void> Function()>>? onLoggedOutCallbacks,
    // NotificationService configuration
    NotificationActionCallback? onNotificationTapped,
    NotificationButtonActionCallback? onNotificationAction,
    ForegroundMessageCallback? onForegroundMessage,
    NotificationErrorCallback? onError,
    Future<void> Function(String? newToken, String? oldToken)? onTokenChanged,
    bool showNotificationsInForeground = true,
    int reminderIntervalDays = 30,
    // GetIt registration control
    bool registerInGetIt = true,
  }) async {
    logd('DreamicServices: Starting initialization');

    // Re-entrancy — early-return the cached result when already fully
    // initialized (Issue 47 part 2). The app-init gate retry re-runs the whole
    // bootstrap chain; a fatal failure in a LATER bootstrap step (after
    // DreamicServices itself succeeded) must not re-construct/re-subscribe these
    // services. Backed by a static cache (reset via
    // [resetDreamicServicesInitializedForTest] / the dreamic bootstrap reset,
    // Issue 75) so it survives `GetIt.reset()`-independent re-runs in one VM.
    if (_cachedResult != null) {
      logd('DreamicServices: Already initialized — returning cached result');
      return _cachedResult!;
    }

    // 1. Create services first (no auth connection yet)
    final DeviceServiceImpl? deviceService =
        enableDeviceService ? DeviceServiceImpl() : null;
    final NotificationService? notificationService =
        enableNotifications ? NotificationService() : null;

    // 2. Register services in GetIt EARLY
    //    This allows other code to resolve services during initialization if needed.
    //    Services are usable (with graceful degradation) even before initialize() completes.
    if (registerInGetIt) {
      if (deviceService != null && !GetIt.I.isRegistered<DeviceServiceInt>()) {
        GetIt.I.registerSingleton<DeviceServiceInt>(deviceService);
        logd('DreamicServices: Registered DeviceServiceInt in GetIt');
      }
      if (notificationService != null &&
          !GetIt.I.isRegistered<NotificationService>()) {
        GetIt.I.registerSingleton<NotificationService>(notificationService);
        logd('DreamicServices: Registered NotificationService in GetIt');
      }
    }

    // Re-entrancy — on ANY failure from here on, dispose AND unregister the
    // just-constructed/early-registered services before rethrowing (Issue
    // 47/52/56), so a gate retry re-registers fresh, live instances rather than
    // accumulating orphaned auth/FCM/lifecycle subscriptions or serving disposed
    // ones. The unregister is load-bearing: device/notif AND auth all register
    // EARLY (auth right after construction, step 4.5 below — it must be resolvable
    // before its own initial auth-state callbacks fire on the first `Future.wait`
    // yield), so the canonical `Future.wait` failure leaves all three registered —
    // dispose-only would make the retry's `isRegistered` guard serve disposed
    // instances. (Auth previously registered LAST, after the failure point, so it
    // needed no unregister; registering it early to fix the initial-callback
    // resolution race means the cleanup must now unregister it too.)
    // Holds the AuthService once constructed, so the catch handler can dispose
    // and unregister it on a post-construction failure.
    AuthServiceImpl? auth;
    try {
      // 3. Collect callbacks with priorities
      //    Device and Notification services provide public handlers that can be
      //    passed directly to AuthService constructor.
      //
      //    Default priority is 0 for core services. Custom callbacks can specify
      //    their own priority via PrioritizedCallback.
      final onAuthenticatedPrioritized =
          <PrioritizedCallback<Future<void> Function(String? uid)>>[
        if (deviceService != null)
          PrioritizedCallback(deviceService.handleAuthenticated, priority: 0),
        if (notificationService != null)
          PrioritizedCallback(
              notificationService.handleAuthenticated,
              priority: 0),
        ...?onAuthenticatedCallbacks,
      ];

      final onAboutToLogOutPrioritized =
          <PrioritizedCallback<Future<void> Function()>>[
        if (deviceService != null)
          PrioritizedCallback(deviceService.handleAboutToLogOut, priority: 0),
        if (notificationService != null)
          PrioritizedCallback(
              notificationService.handleAboutToLogOut,
              priority: 0),
        ...?onAboutToLogOutCallbacks,
      ];

      final onLoggedOutPrioritized =
          <PrioritizedCallback<Future<void> Function()>>[
        ...?onLoggedOutCallbacks,
      ];

      logd('DreamicServices: Collected ${onAuthenticatedPrioritized.length} '
          'onAuthenticated callbacks, ${onAboutToLogOutPrioritized.length} '
          'onAboutToLogOut callbacks, ${onLoggedOutPrioritized.length} '
          'onLoggedOut callbacks');

      // 4. Create AuthService with callbacks pre-registered
      //    CRITICAL: Callbacks are registered in AuthService constructor BEFORE
      //    Firebase listeners attach. This ensures no auth events are missed,
      //    even on warm start when user is already logged in.
      auth = AuthServiceImpl(
        firebaseApp: firebaseApp,
        onAuthenticatedPrioritized: onAuthenticatedPrioritized,
        onAboutToLogOutPrioritized: onAboutToLogOutPrioritized,
        onLoggedOutPrioritized: onLoggedOutPrioritized,
      );

      logd('DreamicServices: Created AuthService with pre-registered callbacks');

      // 4.5. Register auth in GetIt NOW — synchronously, BEFORE the parallel
      //      service init below performs its first `await` (Future.wait).
      //      CRITICAL: the AuthService's initial auth-state callbacks are fired
      //      ASYNCHRONOUSLY by Firebase right after the listener attaches in the
      //      constructor above — i.e. on the first event-loop turn, which is the
      //      `await Future.wait` yield below. Those callbacks (e.g. an app
      //      onAuthenticated/onLoggedOut) can resolve `g<AuthServiceInt>()`
      //      transitively (through a repo factory that depends on it), so
      //      AuthServiceInt MUST already be registered before that yield.
      //      Registering at step 6 (after Future.wait) was too late: on a cold
      //      start with no user, the initial "logged out" callback ran first and
      //      threw "AuthServiceInt not registered". Mirrors the EARLY device/notif
      //      registration above; the failure path unregisters it the same way.
      if (registerInGetIt && !GetIt.I.isRegistered<AuthServiceInt>()) {
        GetIt.I.registerSingleton<AuthServiceInt>(auth);
        logd('DreamicServices: Registered AuthServiceInt in GetIt (before service init)');
      }

      // 5. Initialize services with auth reference IN PARALLEL
      //    CRITICAL: All initialize() calls must START synchronously before any awaits.
      //    This ensures all services have _authService set before microtasks can run.
      //
      //    See: "Constraint 2: Parallel service initialization" in plan.auth-race.md
      //
      //    WRONG (race condition):
      //      await deviceService.initialize(authService: auth);     // Yields here!
      //      await notificationService.initialize(authService: auth); // Too late
      //
      //    RIGHT (race-free):
      //      await Future.wait([
      //        deviceService.initialize(authService: auth),
      //        notificationService.initialize(authService: auth),
      //      ]);
      // Resolve the effective FCM token-changed callback.
      //
      // When the consuming app didn't provide one explicitly AND both
      // DeviceService and NotificationService are enabled, default to delegating
      // to DeviceService.persistFcmToken. Without this, the silent FCM-token
      // capture path in NotificationService._handleLogin (when the user has
      // already granted permission and fcmAutoInitialize is false) would never
      // persist the token to the device document.
      final effectiveOnTokenChanged = onTokenChanged ??
          (deviceService != null && notificationService != null
              ? defaultTokenChangedCallback(deviceService)
              : null);

      final futures = <Future<void>>[];
      if (deviceService != null) {
        futures.add(deviceService.initialize(authService: auth));
      }
      if (notificationService != null) {
        futures.add(notificationService.initialize(
          authService: auth,
          onNotificationTapped: onNotificationTapped,
          onNotificationAction: onNotificationAction,
          onForegroundMessage: onForegroundMessage,
          onError: onError,
          onTokenChanged: effectiveOnTokenChanged,
          showNotificationsInForeground: showNotificationsInForeground,
          reminderIntervalDays: reminderIntervalDays,
          // We're handling auth connection directly, disable legacy auto-connect
          // ignore: deprecated_member_use_from_same_package
          autoConnectAuth: false,
        ));
      }

      if (futures.isNotEmpty) {
        await Future.wait(futures);
        logd('DreamicServices: Completed parallel service initialization');
      }

      // 6. (AuthServiceInt was registered in GetIt at step 4.5 above — BEFORE
      //    service init — so its own initial auth-state callbacks can resolve it.
      //    See the note there for why registering it here, after Future.wait, was
      //    too late.)

      logd('DreamicServices: Initialization complete');

      final result = DreamicServicesResult(
        auth: auth,
        deviceService: deviceService,
        notificationService: notificationService,
      );
      // Cache for the already-initialized early-return on a later-step retry.
      _cachedResult = result;
      return result;
    } catch (e, stackTrace) {
      loge(e, 'DreamicServices: initialization failed — disposing and '
          'unregistering partially-initialized services before rethrow',
          stackTrace);

      // Dispose the just-constructed services to cancel their auth/FCM/lifecycle
      // subscriptions, so a retry does not accumulate orphaned listeners.
      try {
        await notificationService?.dispose();
      } catch (disposeErr) {
        loge(disposeErr, 'DreamicServices: NotificationService.dispose failed '
            'during init-failure cleanup');
      }
      try {
        await deviceService?.dispose();
      } catch (disposeErr) {
        loge(disposeErr, 'DreamicServices: DeviceServiceImpl.dispose failed '
            'during init-failure cleanup');
      }
      // Auth now registers EARLY (step 4.5), so on the canonical Future.wait
      // failure it IS registered; dispose it (cancels its auth/idToken
      // subscriptions) and unregister it below so the retry re-registers a fresh,
      // live instance instead of serving this disposed one.
      try {
        auth?.dispose();
      } catch (disposeErr) {
        loge(disposeErr, 'DreamicServices: AuthServiceImpl.dispose failed '
            'during init-failure cleanup');
      }

      // Unregister the EARLY-registered device/notif so the retry's
      // `isRegistered` guard re-registers fresh, live instances rather than
      // serving the disposed ones (Issue 52). Only unregister if the registered
      // instance is the one we just constructed (guards against unregistering an
      // already-good instance from a prior successful run).
      if (registerInGetIt) {
        if (deviceService != null &&
            GetIt.I.isRegistered<DeviceServiceInt>() &&
            identical(GetIt.I<DeviceServiceInt>(), deviceService)) {
          GetIt.I.unregister<DeviceServiceInt>();
          logd('DreamicServices: Unregistered DeviceServiceInt after failure');
        }
        if (notificationService != null &&
            GetIt.I.isRegistered<NotificationService>() &&
            identical(GetIt.I<NotificationService>(), notificationService)) {
          GetIt.I.unregister<NotificationService>();
          logd('DreamicServices: Unregistered NotificationService after failure');
        }
        // Auth registers EARLY now (step 4.5), so unregister it too — same
        // identical() guard so a good instance from a prior successful run is left
        // intact.
        if (auth != null &&
            GetIt.I.isRegistered<AuthServiceInt>() &&
            identical(GetIt.I<AuthServiceInt>(), auth)) {
          GetIt.I.unregister<AuthServiceInt>();
          logd('DreamicServices: Unregistered AuthServiceInt after failure');
        }
      }

      rethrow;
    }
  }

  /// Cached result of a successful [initialize], backing the re-entrancy
  /// early-return (Issue 47). `null` until the first successful init.
  static DreamicServicesResult? _cachedResult;

  /// Resets the "already-initialized" early-return cache so idempotency /
  /// re-entrancy unit tests are order-independent (Issue 75). The documented
  /// `@visibleForTesting` entry point is `resetDreamicBootstrapIdempotencyForTest()`
  /// (which calls this) — not `@visibleForTesting` itself so the combined reset
  /// can call it without a cross-file visibility-lint warning.
  static void resetDreamicServicesInitializedForTest() {
    _cachedResult = null;
  }

  /// Builds the default FCM token-changed callback used by [initialize] when
  /// both DeviceService and NotificationService are enabled and the consuming
  /// app didn't supply its own `onTokenChanged`.
  ///
  /// The returned callback delegates to [DeviceServiceInt.persistFcmToken] so
  /// the FCM token captured by [NotificationService] is written to the canonical
  /// device document. Failures are logged and swallowed — token sync failures
  /// must not block other operations.
  ///
  /// Apps can use this to compose their own logic with the default behavior:
  ///
  /// ```dart
  /// final services = await DreamicServices.initialize(
  ///   firebaseApp: app,
  ///   onTokenChanged: (newToken, oldToken) async {
  ///     await myAnalytics.trackTokenChange(newToken);
  ///     await DreamicServices
  ///         .defaultTokenChangedCallback(deviceService)(newToken, oldToken);
  ///   },
  /// );
  /// ```
  static Future<void> Function(String? newToken, String? oldToken)
      defaultTokenChangedCallback(DeviceServiceInt deviceService) {
    return (String? newToken, String? oldToken) async {
      try {
        final result = await deviceService.persistFcmToken(fcmToken: newToken);
        result.fold(
          (failure) => logw(
              'FCM token persistence via DeviceService failed: $failure'),
          (_) => logd('FCM token persisted via DeviceService: '
              '${newToken != null ? 'registered' : 'cleared'}'),
        );
      } catch (e, stackTrace) {
        loge(e, 'Unexpected error during FCM token persistence', stackTrace);
        // Don't rethrow - token sync failure shouldn't block other operations
      }
    };
  }
}
