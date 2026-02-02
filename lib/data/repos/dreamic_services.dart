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
    bool showNotificationsInForeground = true,
    int reminderIntervalDays = 30,
    // GetIt registration control
    bool registerInGetIt = true,
  }) async {
    logd('DreamicServices: Starting initialization');

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
      if (onAuthenticatedCallbacks != null) ...onAuthenticatedCallbacks,
    ];

    final onAboutToLogOutPrioritized =
        <PrioritizedCallback<Future<void> Function()>>[
      if (deviceService != null)
        PrioritizedCallback(deviceService.handleAboutToLogOut, priority: 0),
      if (notificationService != null)
        PrioritizedCallback(
            notificationService.handleAboutToLogOut,
            priority: 0),
      if (onAboutToLogOutCallbacks != null) ...onAboutToLogOutCallbacks,
    ];

    final onLoggedOutPrioritized =
        <PrioritizedCallback<Future<void> Function()>>[
      if (onLoggedOutCallbacks != null) ...onLoggedOutCallbacks,
    ];

    logd('DreamicServices: Collected ${onAuthenticatedPrioritized.length} '
        'onAuthenticated callbacks, ${onAboutToLogOutPrioritized.length} '
        'onAboutToLogOut callbacks, ${onLoggedOutPrioritized.length} '
        'onLoggedOut callbacks');

    // 4. Create AuthService with callbacks pre-registered
    //    CRITICAL: Callbacks are registered in AuthService constructor BEFORE
    //    Firebase listeners attach. This ensures no auth events are missed,
    //    even on warm start when user is already logged in.
    final auth = AuthServiceImpl(
      firebaseApp: firebaseApp,
      onAuthenticatedPrioritized: onAuthenticatedPrioritized,
      onAboutToLogOutPrioritized: onAboutToLogOutPrioritized,
      onLoggedOutPrioritized: onLoggedOutPrioritized,
    );

    logd('DreamicServices: Created AuthService with pre-registered callbacks');

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

    // 6. Register auth in GetIt (after services are initialized)
    //    Auth is registered last because services may need to be resolved
    //    during AuthService's initial auth state callbacks.
    if (registerInGetIt && !GetIt.I.isRegistered<AuthServiceInt>()) {
      GetIt.I.registerSingleton<AuthServiceInt>(auth);
      logd('DreamicServices: Registered AuthServiceInt in GetIt');
    }

    logd('DreamicServices: Initialization complete');

    return DreamicServicesResult(
      auth: auth,
      deviceService: deviceService,
      notificationService: notificationService,
    );
  }
}
