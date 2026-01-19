import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:adaptive_dialog/adaptive_dialog.dart';
import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:shared_preferences/shared_preferences.dart';
import '../app/app_config_base.dart';
import '../app/helpers/app_lifecycle_service.dart';
import '../data/models/notification_payload.dart';
import '../data/models/notification_permission_status.dart';
import '../data/repos/auth_service_int.dart';
import 'package:get_it/get_it.dart';
import '../utils/logger.dart';
import 'notification_channel_manager.dart';
import 'notification_image_loader.dart';
import 'notification_permission_helper.dart';
import 'notification_types.dart';

/// Callback type for handling notification taps.
///
/// Called when user taps a notification from any app state (foreground, background, terminated).
///
/// - [route]: The route to navigate to (extracted from notification data)
/// - [data]: Additional data from the notification
typedef NotificationActionCallback = Future<void> Function(
  String? route,
  Map<String, dynamic>? data,
);

/// Callback type for handling notification action button taps.
///
/// Called when user taps an action button on a notification.
///
/// - [actionId]: The ID of the action that was tapped
/// - [route]: The route associated with the notification
/// - [data]: Additional data from the notification
typedef NotificationButtonActionCallback = Future<void> Function(
  String actionId,
  String? route,
  Map<String, dynamic>? data,
);

/// Callback type for handling foreground messages.
///
/// Called when a notification arrives while app is in foreground.
typedef ForegroundMessageCallback = Future<void> Function(
  NotificationPayload payload,
);

/// Callback type for error handling.
typedef NotificationErrorCallback = void Function(
  String error,
  StackTrace? stackTrace,
);

/// Central service for managing notifications in Dreamic-based apps.
///
/// This service handles:
/// - FCM (Firebase Cloud Messaging) message receiving and parsing
/// - Local notification display
/// - Notification permission management
/// - Notification routing and deep linking
/// - Badge count management
/// - Rich notifications (images, actions)
///
/// ## Usage
///
/// Initialize the service early in your app startup:
///
/// ```dart
/// await NotificationService().initialize(
///   onNotificationTapped: (route, data) {
///     if (route != null) {
///       appRouter.navigateNamed(route, arguments: data);
///     }
///   },
/// );
/// ```
///
/// Request permissions when appropriate:
///
/// ```dart
/// final status = await NotificationService().requestPermissions();
/// ```
///
/// ## Optional Feature
///
/// This service is completely optional. Apps that don't use notifications:
/// - Don't need to import or initialize this service
/// - Don't need notification entitlements
/// - Won't have notification code in their build (tree-shaking)
class NotificationService {
  static NotificationService? _instance;

  bool _initialized = false;
  FlutterLocalNotificationsPlugin? _localNotifications;
  NotificationChannelManager? _channelManager;

  // Configuration
  bool _showNotificationsInForeground = true;
  int _reminderIntervalDays = 30;

  // Callbacks
  NotificationActionCallback? _onNotificationTapped;
  NotificationButtonActionCallback? _onNotificationAction;
  ForegroundMessageCallback? _onForegroundMessage;
  NotificationErrorCallback? _onError;

  // Streams
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedAppSubscription;
  final StreamController<int> _badgeCountController = StreamController<int>.broadcast();
  int _currentBadgeCount = 0;

  // Permission helper (owns all permission-related SharedPreferences keys)
  late final NotificationPermissionHelper _permissionHelper;

  //
  // FCM Token Management
  //

  /// Legacy key from AuthServiceImpl - migrate on first read
  static const String _legacyFcmTokenKey = 'commonSharedKeyFcmToken';

  /// New prefixed key for FCM token storage
  static const String _fcmTokenKey = 'dreamic_fcm_token';

  /// Cached FCM token (in-memory)
  String? _cachedFcmToken;

  /// Subscription to FCM token refresh events
  StreamSubscription<String>? _tokenRefreshSubscription;

  /// Whether FCM token management has been initialized
  bool _hasFcmTokenInitialized = false;

  /// Key for storing app-level notifications enabled preference
  static const String _keyNotificationsEnabled = 'dreamic_notifications_enabled';

  /// Subscription to auth service login stream
  StreamSubscription<bool>? _authSubscription;

  /// Subscription to app lifecycle events for detecting return from settings
  StreamSubscription<AppLifecycleState>? _lifecycleSubscription;

  /// Flag indicating we're waiting for user to return from settings
  bool _waitingForSettingsReturn = false;

  /// Callback invoked when a token should be registered/updated, or unregistered.
  ///
  /// - If [newToken] is non-null: register/update mapping on backend.
  /// - If [oldToken] is non-null and [newToken] is null: unregister [oldToken] on backend (best-effort).
  Future<void> Function(String? newToken, String? oldToken)? _onTokenChanged;

  /// Private constructor for singleton pattern.
  NotificationService._internal() {
    _permissionHelper = NotificationPermissionHelper(notificationService: this);
  }

  /// Stream of badge count changes.
  ///
  /// Emits the current badge count whenever it changes via [updateBadgeCount].
  /// Use this stream to reactively update UI based on badge count.
  ///
  /// Example:
  /// ```dart
  /// NotificationService().badgeCountStream.listen((count) {
  ///   print('Badge count changed to: $count');
  /// });
  /// ```
  Stream<int> get badgeCountStream => _badgeCountController.stream;

  /// Gets the singleton instance of NotificationService.
  ///
  /// The service remains dormant until [initialize] is called.
  factory NotificationService() {
    _instance ??= NotificationService._internal();
    return _instance!;
  }

  /// Whether the service has been initialized.
  bool get isInitialized => _initialized;

  /// Whether to show notifications when app is in foreground.
  bool get showNotificationsInForeground => _showNotificationsInForeground;

  /// Access the permission helper for advanced permission flow control.
  ///
  /// The helper provides detailed methods for tracking denials, checking
  /// permission state, and determining when to show various prompts.
  NotificationPermissionHelper get permissionHelper => _permissionHelper;

  /// Initializes the notification service.
  ///
  /// This method sets up all notification handling including:
  /// - Local notification plugin initialization
  /// - FCM message listeners (foreground, background, terminated)
  /// - Notification action handlers
  /// - Platform-specific configuration
  /// - Auto-wiring to auth service (if registered in GetIt)
  ///
  /// **This is the only method consuming apps need to call to set up notifications.**
  ///
  /// Parameters:
  /// - [onNotificationTapped]: Callback for when user taps a notification
  /// - [onNotificationAction]: Callback for when user taps an action button
  /// - [onForegroundMessage]: Callback for when notification arrives in foreground
  /// - [onError]: Callback for handling errors
  /// - [showNotificationsInForeground]: Whether to display notifications in foreground (default: true)
  /// - [reminderIntervalDays]: Days between permission reminders (default: 30)
  /// - [onTokenChanged]: Callback for FCM token changes. If not provided and auth service
  ///   is available, uses the default Firebase callable function implementation.
  /// - [autoConnectAuth]: Whether to automatically connect to auth service if available
  ///   in GetIt (default: true). Set to false if you want to call [connectToAuthService]
  ///   manually with custom configuration.
  ///
  /// Example:
  /// ```dart
  /// await NotificationService().initialize(
  ///   onNotificationTapped: (route, data) async {
  ///     if (route != null) {
  ///       Navigator.of(context).pushNamed(route, arguments: data);
  ///     }
  ///   },
  ///   showNotificationsInForeground: true,
  /// );
  /// ```
  Future<void> initialize({
    NotificationActionCallback? onNotificationTapped,
    NotificationButtonActionCallback? onNotificationAction,
    ForegroundMessageCallback? onForegroundMessage,
    NotificationErrorCallback? onError,
    bool showNotificationsInForeground = true,
    int reminderIntervalDays = 30,
    Future<void> Function(String? newToken, String? oldToken)? onTokenChanged,
    bool autoConnectAuth = true,
  }) async {
    if (_initialized) {
      logi('NotificationService already initialized');
      return;
    }

    try {
      _onNotificationTapped = onNotificationTapped;
      _onNotificationAction = onNotificationAction;
      _onForegroundMessage = onForegroundMessage;
      _onError = onError;
      _showNotificationsInForeground = showNotificationsInForeground;
      _reminderIntervalDays = reminderIntervalDays;

      // Initialize local notifications plugin
      await _initializeLocalNotifications();

      // Set up FCM message handlers
      await _setupFCMHandlers();

      // Check for initial message (app opened from terminated state via notification)
      await _checkInitialMessage();

      _initialized = true;
      logi('NotificationService initialized successfully');

      // Auto-wire to auth service if available and enabled
      if (autoConnectAuth) {
        // Check if auth service is available before attempting to connect
        bool authAvailable = false;
        try {
          authAvailable = GetIt.I.isRegistered<AuthServiceInt>();
        } catch (e) {
          // GetIt not initialized or other error
          logd('GetIt check failed: $e');
        }

        if (authAvailable) {
          await connectToAuthService(onTokenChanged: onTokenChanged);
        } else {
          // This is a configuration error - report it but don't crash
          const errorMsg = 'autoConnectAuth is enabled but AuthServiceInt is not '
              'registered in GetIt. FCM token management will not work automatically. '
              'Either register AuthServiceInt before initializing NotificationService, '
              'or set autoConnectAuth: false and call connectToAuthService() manually later.';
          loge(errorMsg);
          _onError?.call(errorMsg, null);
        }
      } else if (onTokenChanged != null) {
        // Even without auto-connect, store the callback for later use
        _onTokenChanged = onTokenChanged;
      }
    } catch (e, stackTrace) {
      loge(e, 'Failed to initialize NotificationService', stackTrace);
      _onError?.call('Failed to initialize NotificationService: $e', stackTrace);
      rethrow;
    }
  }

  /// Initializes the local notifications plugin with platform-specific configuration.
  Future<void> _initializeLocalNotifications() async {
    _localNotifications = FlutterLocalNotificationsPlugin();

    // Android initialization
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS initialization
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false, // We'll request permissions explicitly
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    // macOS initialization
    const macOSSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initializationSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
      macOS: macOSSettings,
    );

    // Set up notification tap handler
    await _localNotifications!.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _handleNotificationTap,
    );

    // Create default notification channel on Android
    if (!kIsWeb && Platform.isAndroid) {
      _channelManager = NotificationChannelManager(_localNotifications!);
      await _channelManager!.createDefaultChannels();
    }

    logi('Local notifications initialized');
  }

  /// Sets up Firebase Cloud Messaging message handlers.
  Future<void> _setupFCMHandlers() async {
    // Handle foreground messages
    _foregroundSubscription = FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle notification taps when app is in background
    _openedAppSubscription = FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

    // Configure iOS foreground presentation options
    if (!kIsWeb && (Platform.isIOS || Platform.isMacOS)) {
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: _showNotificationsInForeground,
        badge: true,
        sound: true,
      );
    }

    logi('FCM message handlers set up');
  }

  /// Checks if app was opened from a notification while terminated.
  Future<void> _checkInitialMessage() async {
    try {
      final message = await FirebaseMessaging.instance.getInitialMessage();
      if (message != null) {
        logi('App opened from notification (terminated state)');
        await _handleMessageOpenedApp(message);
      }
    } catch (e, stackTrace) {
      loge(e, 'Error checking initial message', stackTrace);
      _onError?.call('Error checking initial message: $e', stackTrace);
    }
  }

  /// Handles incoming FCM messages when app is in foreground.
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    try {
      logi('Received foreground message: ${message.messageId}');

      final payload = NotificationPayload.fromRemoteMessage(message);

      // Call foreground message callback if provided
      if (_onForegroundMessage != null) {
        await _onForegroundMessage!(payload);
      }

      // Display local notification if enabled
      if (_showNotificationsInForeground) {
        await showNotification(payload);
      }
    } catch (e, stackTrace) {
      loge(e, 'Error handling foreground message', stackTrace);
      _onError?.call('Error handling foreground message: $e', stackTrace);
    }
  }

  /// Handles notification taps when app is in background or foreground.
  Future<void> _handleMessageOpenedApp(RemoteMessage message) async {
    try {
      logi('Notification tapped (background/foreground): ${message.messageId}');

      final payload = NotificationPayload.fromRemoteMessage(message);

      if (_onNotificationTapped != null) {
        await _onNotificationTapped!(payload.route, payload.data);
      }
    } catch (e, stackTrace) {
      loge(e, 'Error handling message opened app', stackTrace);
      _onError?.call('Error handling message opened app: $e', stackTrace);
    }
  }

  /// Handles notification taps via local notifications plugin.
  Future<void> _handleNotificationTap(NotificationResponse response) async {
    try {
      logi('Local notification tapped: ${response.id}');

      // Parse payload data
      final payloadStr = response.payload;
      if (payloadStr == null || payloadStr.isEmpty) {
        return;
      }

      final payload = _deserializePayload(payloadStr);
      if (payload == null) {
        logi('Failed to deserialize notification payload');
        return;
      }

      // For action button taps
      if (response.actionId != null && _onNotificationAction != null) {
        logi('Action button tapped: ${response.actionId}');
        await _onNotificationAction!(response.actionId!, payload.route, payload.data);
        return;
      }

      // For regular notification taps
      if (_onNotificationTapped != null) {
        await _onNotificationTapped!(payload.route, payload.data);
      }
    } catch (e, stackTrace) {
      loge(e, 'Error handling notification tap', stackTrace);
      _onError?.call('Error handling notification tap: $e', stackTrace);
    }
  }

  /// Displays a local notification.
  ///
  /// Supports rich notifications including:
  /// - Images (downloaded and cached automatically)
  /// - Action buttons (up to 3 per notification)
  /// - Custom sounds
  /// - Badge updates
  ///
  /// Parameters:
  /// - [payload]: The notification content and configuration
  ///
  /// Returns the notification ID that was used.
  Future<int> showNotification(NotificationPayload payload) async {
    if (!_initialized) {
      throw StateError('NotificationService not initialized. Call initialize() first.');
    }

    try {
      final id = payload.id ?? DateTime.now().millisecondsSinceEpoch.remainder(100000);

      // Download image if provided
      String? imagePath;
      if (payload.imageUrl != null && payload.imageUrl!.isNotEmpty) {
        imagePath = await NotificationImageLoader.downloadImage(payload.imageUrl!);
        if (imagePath != null) {
          logi('Notification image downloaded: $imagePath');
        } else {
          logi('Failed to download notification image, displaying without image');
        }
      }

      // Build action buttons for Android
      List<AndroidNotificationAction>? androidActions;
      if (payload.actions.isNotEmpty && !kIsWeb && Platform.isAndroid) {
        androidActions = payload.actions.map((action) {
          return AndroidNotificationAction(
            action.id,
            action.label,
            icon: action.icon != null ? DrawableResourceAndroidBitmap(action.icon!) : null,
            showsUserInterface: action.launchesApp,
            contextual: false,
          );
        }).toList();
      }

      // Android-specific settings
      // Use channel from payload, or default to standard channel
      final channelId = payload.channelId ?? NotificationChannelManager.channelDefault;

      final androidDetails = AndroidNotificationDetails(
        channelId,
        _getChannelName(channelId),
        channelDescription: _getChannelDescription(channelId),
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        enableLights: true,
        styleInformation: imagePath != null
            ? BigPictureStyleInformation(
                FilePathAndroidBitmap(imagePath),
                contentTitle: payload.title,
                summaryText: payload.body,
                hideExpandedLargeIcon: false,
              )
            : null,
        actions: androidActions,
        category: payload.category != null
            ? AndroidNotificationCategory.values.firstWhere(
                (c) => c.toString().split('.').last == payload.category,
                orElse: () => AndroidNotificationCategory.message,
              )
            : null,
      );

      // Build iOS/macOS attachment for image
      List<DarwinNotificationAttachment>? iosAttachments;
      if (imagePath != null && !kIsWeb && (Platform.isIOS || Platform.isMacOS)) {
        iosAttachments = [
          DarwinNotificationAttachment(imagePath),
        ];
      }

      // iOS-specific settings
      final iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        badgeNumber: payload.badge,
        categoryIdentifier: payload.category,
        attachments: iosAttachments,
      );

      final notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
        macOS: iosDetails,
      );

      // Serialize payload data for tap handling
      final payloadJson = _serializePayload(payload);

      await _localNotifications!.show(
        id,
        payload.title ?? 'Notification',
        payload.body,
        notificationDetails,
        payload: payloadJson,
      );

      logi('Displayed notification: $id with ${payload.actions.length} actions');
      return id;
    } catch (e, stackTrace) {
      loge(e, 'Error showing notification', stackTrace);
      _onError?.call('Error showing notification: $e', stackTrace);
      rethrow;
    }
  }

  /// Cancels a specific notification by ID.
  Future<void> cancelNotification(int id) async {
    if (!_initialized) {
      throw StateError('NotificationService not initialized. Call initialize() first.');
    }

    try {
      await _localNotifications!.cancel(id);
      logi('Cancelled notification: $id');
    } catch (e, stackTrace) {
      loge(e, 'Error cancelling notification', stackTrace);
      _onError?.call('Error cancelling notification: $e', stackTrace);
    }
  }

  /// Cancels all notifications.
  Future<void> cancelAllNotifications() async {
    if (!_initialized) {
      throw StateError('NotificationService not initialized. Call initialize() first.');
    }

    try {
      await _localNotifications!.cancelAll();
      logi('Cancelled all notifications');
    } catch (e, stackTrace) {
      loge(e, 'Error cancelling all notifications', stackTrace);
      _onError?.call('Error cancelling all notifications: $e', stackTrace);
    }
  }

  /// Gets a list of currently active (displayed) notifications.
  ///
  /// Returns a list of [ActiveNotification] objects representing notifications
  /// currently shown in the system tray/notification center.
  ///
  /// This is useful for:
  /// - Debugging notification display
  /// - Managing notification state
  /// - Checking if a specific notification is still displayed
  /// - Cleaning up old notifications
  ///
  /// On iOS, this requires iOS 10+ and returns notifications from the notification center.
  /// On Android, this returns notifications from the status bar.
  /// On web, this always returns an empty list.
  ///
  /// Example:
  /// ```dart
  /// final active = await NotificationService().getActiveNotifications();
  /// print('Currently showing ${active.length} notifications');
  ///
  /// // Check if specific notification is displayed
  /// final hasNotification = active.any((n) => n.id == 42);
  /// ```
  Future<List<ActiveNotification>> getActiveNotifications() async {
    if (!_initialized) {
      throw StateError('NotificationService not initialized. Call initialize() first.');
    }

    try {
      if (kIsWeb) {
        // Web doesn't support querying active notifications
        return [];
      }

      final activeNotifications = await _localNotifications!.getActiveNotifications();

      logi('Found ${activeNotifications.length} active notifications');
      return activeNotifications;
    } catch (e, stackTrace) {
      loge(e, 'Error getting active notifications', stackTrace);
      _onError?.call('Error getting active notifications: $e', stackTrace);
      return [];
    }
  }

  /// Gets the current notification permission status.
  ///
  /// Returns the permission status without showing a prompt.
  ///
  /// **Auto-clear behavior:** If permission is detected as `authorized` or
  /// `provisional` and there is stored denial/settings-prompt info, it will
  /// be automatically cleared. This handles the case where the user enabled
  /// notifications via system settings.
  Future<NotificationPermissionStatus> getPermissionStatus() async {
    try {
      final settings = await FirebaseMessaging.instance.getNotificationSettings();

      NotificationPermissionStatus status;
      switch (settings.authorizationStatus) {
        case AuthorizationStatus.authorized:
          status = NotificationPermissionStatus.authorized;
        case AuthorizationStatus.denied:
          status = NotificationPermissionStatus.denied;
        case AuthorizationStatus.notDetermined:
          status = NotificationPermissionStatus.notDetermined;
        case AuthorizationStatus.provisional:
          status = NotificationPermissionStatus.provisional;
      }

      // Auto-clear denial/settings info if permission was granted via settings
      if (status == NotificationPermissionStatus.authorized ||
          status == NotificationPermissionStatus.provisional) {
        await _permissionHelper.autoClearIfGranted();
      }

      return status;
    } catch (e, stackTrace) {
      loge(e, 'Error getting permission status', stackTrace);
      _onError?.call('Error getting permission status: $e', stackTrace);
      // Return denied as safe default - don't assume we have permission
      return NotificationPermissionStatus.denied;
    }
  }

  /// Requests notification permissions from the user.
  ///
  /// On iOS, this shows the system permission prompt if permissions haven't been
  /// determined yet. Once denied, users must enable permissions in Settings.
  ///
  /// On Android 13+, this shows the runtime permission prompt.
  ///
  /// Returns the resulting permission status.
  Future<NotificationPermissionStatus> requestPermissions({
    bool provisional = false,
  }) async {
    try {
      // Get status before request to detect blocked requests
      final statusBefore = await getPermissionStatus();

      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: provisional,
        criticalAlert: false,
        announcement: false,
        carPlay: false,
      );

      final status = _convertAuthorizationStatus(settings.authorizationStatus);

      // Track the result using the permission helper
      if (status == NotificationPermissionStatus.denied) {
        // Check if this is a permanent denial
        // iOS: Always permanent after first denial
        // Android: Permanent after second denial
        final isPermanent = !kIsWeb &&
            ((Platform.isIOS || Platform.isMacOS) ||
                (await _permissionHelper.getPermissionDenialCount()) >= 1);
        await _permissionHelper.recordDenial(isPermanent: isPermanent);
      } else if (status == NotificationPermissionStatus.authorized ||
          status == NotificationPermissionStatus.provisional) {
        // Permission granted - clear any stored denial info
        await _permissionHelper.autoClearIfGranted();
      } else if (statusBefore == NotificationPermissionStatus.notDetermined &&
          status == NotificationPermissionStatus.notDetermined) {
        // Status didn't change - request may have been blocked
        await _permissionHelper.recordBlockedRequest();
      }

      logi('Permission request result: $status');

      return status;
    } catch (e, stackTrace) {
      loge(e, 'Error requesting permissions', stackTrace);
      _onError?.call('Error requesting permissions: $e', stackTrace);
      return NotificationPermissionStatus.denied;
    }
  }

  /// Opens the system settings page for this app.
  ///
  /// Useful when permissions have been denied and user needs to manually
  /// enable them in Settings.
  @Deprecated('Use openNotificationSettings() instead for better web handling')
  Future<void> openSystemSettings() async {
    try {
      // Use Firebase Messaging's method to open settings
      await FirebaseMessaging.instance.requestPermission();
      logi('Opened system settings');
    } catch (e, stackTrace) {
      loge(e, 'Error opening system settings', stackTrace);
      _onError?.call('Error opening system settings: $e', stackTrace);
    }
  }

  /// Opens the system notification settings page for this app.
  ///
  /// On mobile platforms (iOS/Android), opens the app's notification settings.
  /// On web, returns false since browser settings cannot be opened programmatically.
  /// When this returns false, apps should show instructions to the user.
  ///
  /// Returns true if settings were opened successfully, false otherwise.
  ///
  /// Example:
  /// ```dart
  /// final opened = await notificationService.openNotificationSettings();
  /// if (!opened) {
  ///   // Show instructions dialog for web users
  ///   showDialog(context: context, builder: (_) => WebSettingsInstructionsDialog());
  /// }
  /// ```
  Future<bool> openNotificationSettings() async {
    try {
      if (kIsWeb) {
        // Cannot open browser settings programmatically
        // Return false to indicate the app should show instructions instead
        logd('Cannot open browser settings programmatically on web');
        return false;
      }

      // Use permission_handler to open app settings on mobile platforms
      final opened = await ph.openAppSettings();
      if (opened) {
        logi('Opened notification settings');
      } else {
        logw('Failed to open notification settings');
      }
      return opened;
    } catch (e, stackTrace) {
      loge(e, 'Error opening notification settings', stackTrace);
      _onError?.call('Error opening notification settings: $e', stackTrace);
      return false;
    }
  }

  /// Initialize notifications manually.
  ///
  /// Use this when [AppConfigBase.fcmAutoInitialize] is false and you want to
  /// trigger notification setup at a specific point in your app flow.
  ///
  /// This method:
  /// 1. Checks if FCM is enabled in configuration
  /// 2. Requests notification permissions from the user
  /// 3. Initializes FCM token management if permission is granted
  ///
  /// Returns a [NotificationInitResult] indicating the outcome:
  /// - [NotificationInitResult.success]: Permission granted and FCM initialized
  /// - [NotificationInitResult.permissionDenied]: User denied (may be able to retry on Android)
  /// - [NotificationInitResult.permissionPermanentlyDenied]: Must use system settings
  /// - [NotificationInitResult.permissionRequestBlocked]: System blocked the request
  /// - [NotificationInitResult.fcmDisabledConfig]: FCM disabled in AppConfigBase
  /// - [NotificationInitResult.alreadyInitialized]: Already initialized
  /// - [NotificationInitResult.error]: An error occurred
  ///
  /// Example:
  /// ```dart
  /// // After onboarding or at the right moment
  /// final result = await notificationService.initializeNotifications();
  /// if (result == NotificationInitResult.success) {
  ///   showSnackbar('Notifications enabled!');
  /// }
  /// ```
  Future<NotificationInitResult> initializeNotifications() async {
    if (!AppConfigBase.useFCM) {
      logd('initializeNotifications: FCM is disabled in AppConfigBase');
      return NotificationInitResult.fcmDisabledConfig;
    }

    if (_hasFcmTokenInitialized) {
      logd('initializeNotifications: Already initialized');
      return NotificationInitResult.alreadyInitialized;
    }

    try {
      // Get status before request to detect blocked requests
      final statusBefore = await getPermissionStatus();

      // Request permission
      final permissionResult = await requestPermissions();

      // Check for blocked request (status unchanged from notDetermined)
      if (statusBefore == NotificationPermissionStatus.notDetermined &&
          permissionResult == NotificationPermissionStatus.notDetermined) {
        logw('Permission request may have been blocked by system');
        return NotificationInitResult.permissionRequestBlocked;
      }

      if (permissionResult == NotificationPermissionStatus.authorized ||
          permissionResult == NotificationPermissionStatus.provisional) {
        // Permission granted - initialize FCM token if callback is set
        if (_onTokenChanged != null) {
          await initializeFcmToken(onTokenChanged: _onTokenChanged!);
        }
        logi('Notifications initialized successfully');
        return NotificationInitResult.success;
      } else if (permissionResult == NotificationPermissionStatus.denied) {
        // Check if this is a permanent denial
        final canPrompt = await _permissionHelper.canPromptForPermission();
        if (!canPrompt) {
          return NotificationInitResult.permissionPermanentlyDenied;
        }
        return NotificationInitResult.permissionDenied;
      } else {
        return NotificationInitResult.permissionPermanentlyDenied;
      }
    } catch (e, stackTrace) {
      loge(e, 'initializeNotifications failed', stackTrace);
      _onError?.call('initializeNotifications failed: $e', stackTrace);
      return NotificationInitResult.error;
    }
  }

  //
  // Auth Integration Methods
  //

  /// Connects to an auth service to automatically manage FCM tokens on login/logout.
  ///
  /// When the user logs in:
  /// - If [AppConfigBase.fcmAutoInitialize] is true: requests permission and initializes FCM
  /// - If [AppConfigBase.fcmAutoInitialize] is false: only initializes if permission is already granted
  ///
  /// When the user logs out:
  /// - Performs local token cleanup (stops listener, deletes Firebase token, clears cache)
  /// - Does NOT call backend to unregister token (user is already logged out)
  /// - Server should prune stale tokens when push sends fail
  /// - For backend unregister, call [preLogoutCleanup] manually before sign out
  ///
  /// [authService] is the auth service to connect to. If null, attempts to
  /// resolve from GetIt (guarded - logs and skips if not registered).
  ///
  /// [onTokenChanged] callback for syncing tokens to your backend.
  /// If not provided, uses the default Firebase callable function configured
  /// in [AppConfigBase.notificationsUpdateFcmTokenFunction].
  ///
  /// Example:
  /// ```dart
  /// await notificationService.connectToAuthService(
  ///   onTokenChanged: (newToken, oldToken) async {
  ///     await myBackendService.updateFcmToken(newToken, oldToken);
  ///   },
  /// );
  /// ```
  Future<void> connectToAuthService({
    AuthServiceInt? authService,
    Future<void> Function(String? newToken, String? oldToken)? onTokenChanged,
  }) async {
    // Cancel any existing subscription
    await _authSubscription?.cancel();

    // Store the token callback
    _onTokenChanged = onTokenChanged ?? _defaultTokenChangedCallback;

    // Try to get auth service
    AuthServiceInt? auth = authService;
    if (auth == null) {
      try {
        if (GetIt.I.isRegistered<AuthServiceInt>()) {
          auth = GetIt.I.get<AuthServiceInt>();
          logd('Resolved AuthServiceInt from GetIt');
        } else {
          logd('AuthServiceInt not registered in GetIt, skipping auth connection');
          return;
        }
      } catch (e) {
        logd('Could not resolve AuthServiceInt from GetIt: $e');
        return;
      }
    }

    // Subscribe to auth changes
    _authSubscription = auth.isLoggedInStream.listen((isLoggedIn) async {
      if (isLoggedIn) {
        await _handleLogin();
      } else {
        // Local cleanup only - user is already logged out so backend calls
        // would fail. Server will prune stale tokens on send failures.
        // For backend unregister, call preLogoutCleanup() before signOut().
        logd('Auth logout detected, performing local token cleanup');
        try {
          // Stop token refresh listener
          await _tokenRefreshSubscription?.cancel();
          _tokenRefreshSubscription = null;

          // Delete FCM token from Firebase
          try {
            await FirebaseMessaging.instance.deleteToken();
            logd('Deleted FCM token from Firebase');
          } catch (e) {
            logw('Failed to delete FCM token from Firebase: $e');
          }

          // Clear cached tokens
          await clearFcmToken();
          logd('Local token cleanup completed');
        } catch (e) {
          // Swallow any unexpected errors - cleanup is best-effort
          logw('Unexpected error during auto logout cleanup: $e');
        }
      }
    });

    logi('Connected to auth service for FCM token management');
  }

  /// Handles login event - initializes FCM based on configuration.
  Future<void> _handleLogin() async {
    if (!AppConfigBase.useFCM) {
      logd('FCM is disabled in AppConfigBase, skipping initialization');
      return;
    }

    if (AppConfigBase.fcmAutoInitialize) {
      // Auto-initialize: request permission and initialize FCM
      logd('FCM auto-init enabled, initializing notifications');
      await initializeNotifications();
    } else {
      // Check if permission was already granted previously
      final status = await getPermissionStatus();
      if (status == NotificationPermissionStatus.authorized ||
          status == NotificationPermissionStatus.provisional) {
        // Permission already granted - safe to initialize silently (no dialog)
        logd('FCM auto-init disabled, but permission already granted - initializing silently');
        if (_onTokenChanged != null) {
          await initializeFcmToken(onTokenChanged: _onTokenChanged!);
        }
      } else {
        // No permission yet - wait for manual trigger
        logd('FCM auto-initialization disabled, call initializeNotifications() or '
            'runNotificationPermissionFlow() when ready');
      }
    }
  }

  /// Default token changed callback using Firebase callable functions.
  Future<void> _defaultTokenChangedCallback(String? newToken, String? oldToken) async {
    try {
      final functionName = AppConfigBase.notificationsUpdateFcmTokenUseGrouped
          ? AppConfigBase.notificationsUpdateFcmTokenGroupFunction!
          : AppConfigBase.notificationsUpdateFcmTokenFunction;

      final callable = AppConfigBase.firebaseFunctionCallable(functionName);

      final data = <String, dynamic>{
        if (newToken != null) 'fcmToken': newToken,
        if (oldToken != null) 'oldFcmToken': oldToken,
      };

      // Add action parameter if using grouped style
      if (AppConfigBase.notificationsUpdateFcmTokenUseGrouped) {
        data['action'] = AppConfigBase.notificationsUpdateFcmTokenAction;
      }

      await callable.call(data);
      logd(
          'FCM token synced via default callable: ${newToken != null ? 'registered' : 'unregistered'}');
    } catch (e) {
      loge(e, 'Failed to sync FCM token via default callable');
      // Don't rethrow - token sync failure shouldn't block other operations
    }
  }

  /// Performs pre-logout cleanup for notifications.
  ///
  /// **IMPORTANT:** Call this BEFORE signing out the user, while they are still
  /// authenticated. This allows the token unregistration to succeed on the backend.
  ///
  /// This method:
  /// 1. Attempts to unregister the current FCM token on the backend (best-effort)
  /// 2. Stops the token refresh listener
  /// 3. Deletes the FCM token from Firebase
  /// 4. Clears cached tokens (both new and legacy keys)
  ///
  /// If backend unregister fails (offline/server error), the method still proceeds
  /// with local cleanup. The server should handle stale tokens on send failures.
  ///
  /// **Note on automatic cleanup:** If you use [connectToAuthService], local cleanup
  /// (steps 2-4) happens automatically when logout is detected. However, the backend
  /// unregister (step 1) cannot run automatically because the user is already logged
  /// out when the auth stream fires. If you need backend unregister, call this method
  /// manually before [AuthServiceInt.signOut]. The server should prune stale tokens
  /// when push sends fail, so manual pre-logout cleanup is optional but recommended.
  ///
  /// [timeout] is the maximum time to wait for backend unregister (default: 5 seconds).
  ///
  /// Example:
  /// ```dart
  /// // In your logout flow (recommended for backend token cleanup):
  /// await notificationService.preLogoutCleanup();
  /// await authService.signOut();
  ///
  /// // Or rely on automatic local cleanup (server prunes stale tokens):
  /// await authService.signOut(); // Local cleanup happens via connectToAuthService
  /// ```
  Future<void> preLogoutCleanup({Duration timeout = const Duration(seconds: 5)}) async {
    logd('Starting pre-logout cleanup');

    // Step 1: Best-effort backend unregister while still authenticated
    if (_onTokenChanged != null && _cachedFcmToken != null) {
      try {
        await _onTokenChanged!(null, _cachedFcmToken).timeout(
          timeout,
          onTimeout: () {
            logw('Pre-logout token unregister timed out after $timeout');
          },
        );
        logd('Successfully unregistered FCM token on backend');
      } catch (e) {
        logw('Failed to unregister FCM token on backend (continuing with local cleanup): $e');
        // Continue with cleanup even if backend fails
      }
    }

    // Step 2: Stop token refresh subscription
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;

    // Step 3: Delete FCM token from Firebase
    try {
      await FirebaseMessaging.instance.deleteToken();
      logd('Deleted FCM token from Firebase');
    } catch (e) {
      logw('Failed to delete FCM token from Firebase: $e');
    }

    // Step 4: Clear cached tokens
    await clearFcmToken();

    logi('Pre-logout cleanup completed');
  }

  //
  // App-Level Notification Toggle
  //

  /// Disables notifications at the app level.
  ///
  /// This is a preference-level toggle (not OS permission). It:
  /// 1. Attempts to unregister the FCM token on the backend (best-effort)
  /// 2. Stops the token refresh listener
  /// 3. Deletes the FCM token from Firebase
  /// 4. Clears cached tokens
  /// 5. Sets the app-level notifications enabled flag to false
  ///
  /// If the user re-enables via [enableNotifications], there is no extra
  /// system prompt unless they revoked permission in device settings.
  ///
  /// Example:
  /// ```dart
  /// // In your settings screen
  /// await notificationService.disableNotifications();
  /// setState(() => notificationsEnabled = false);
  /// ```
  Future<void> disableNotifications() async {
    logd('Disabling notifications at app level');

    // Best-effort backend unregister
    if (_onTokenChanged != null && _cachedFcmToken != null) {
      try {
        await _onTokenChanged!(null, _cachedFcmToken);
        logd('Unregistered FCM token on backend');
      } catch (e) {
        logw('Failed to unregister FCM token (continuing with disable): $e');
      }
    }

    // Stop token refresh listener
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;

    // Delete FCM token from Firebase
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (e) {
      logw('Failed to delete FCM token: $e');
    }

    // Clear cached tokens
    await clearFcmToken();

    // Set app-level flag
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyNotificationsEnabled, false);

    logi('Notifications disabled at app level');
  }

  /// Enables notifications at the app level.
  ///
  /// This is a thin wrapper that:
  /// 1. Sets the app-level notifications enabled flag to true
  /// 2. Re-checks permission status
  /// 3. Requests permission if needed (may show system prompt)
  /// 4. Fetches a fresh FCM token and syncs to backend
  /// 5. Restarts the token refresh listener
  ///
  /// Returns a [NotificationInitResult] indicating the outcome.
  ///
  /// Example:
  /// ```dart
  /// // In your settings screen
  /// final result = await notificationService.enableNotifications();
  /// if (result == NotificationInitResult.success) {
  ///   setState(() => notificationsEnabled = true);
  /// }
  /// ```
  Future<NotificationInitResult> enableNotifications() async {
    logd('Enabling notifications at app level');

    // Set app-level flag first
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyNotificationsEnabled, true);

    // Reset initialization state so initializeNotifications can run
    _hasFcmTokenInitialized = false;

    // Use the existing init flow
    final result = await initializeNotifications();

    if (result == NotificationInitResult.success ||
        result == NotificationInitResult.alreadyInitialized) {
      logi('Notifications enabled at app level');
    } else {
      logw('Failed to enable notifications: $result');
      // Revert the flag if we couldn't enable
      await prefs.setBool(_keyNotificationsEnabled, false);
    }

    return result;
  }

  /// Returns whether notifications are enabled at the app level.
  ///
  /// This is the app-level preference flag (default: true). Use this to
  /// gate notification surfaces in your UI.
  ///
  /// Note: This is separate from OS permission status. A user could have
  /// notifications enabled at the app level but denied at the OS level.
  ///
  /// Example:
  /// ```dart
  /// final enabled = await notificationService.isNotificationsEnabled();
  /// if (enabled) {
  ///   showNotificationBadge();
  /// }
  /// ```
  Future<bool> isNotificationsEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_keyNotificationsEnabled) ?? true; // Default to true
    } catch (e) {
      loge(e, 'Error checking notifications enabled status');
      return true; // Default to true on error
    }
  }

  /// Converts Firebase authorization status to our enum.
  NotificationPermissionStatus _convertAuthorizationStatus(AuthorizationStatus status) {
    switch (status) {
      case AuthorizationStatus.authorized:
        return NotificationPermissionStatus.authorized;
      case AuthorizationStatus.denied:
        return NotificationPermissionStatus.denied;
      case AuthorizationStatus.notDetermined:
        return NotificationPermissionStatus.notDetermined;
      case AuthorizationStatus.provisional:
        return NotificationPermissionStatus.provisional;
    }
  }

  //
  // Convenience wrappers that delegate to NotificationPermissionHelper
  // These maintain backward compatibility while centralizing logic in the helper.
  //

  /// Gets the number of times permissions have been requested.
  ///
  /// Delegates to [NotificationPermissionHelper.getPermissionRequestCount].
  Future<int> getPermissionRequestCount() => _permissionHelper.getPermissionRequestCount();

  /// Gets the number of times permissions have been denied.
  ///
  /// Delegates to [NotificationPermissionHelper.getPermissionDenialCount].
  Future<int> getPermissionDenialCount() => _permissionHelper.getPermissionDenialCount();

  /// Checks if enough time has passed to show a permission reminder.
  ///
  /// Delegates to [NotificationPermissionHelper.shouldShowPeriodicReminder].
  Future<bool> shouldShowPeriodicReminder() =>
      _permissionHelper.shouldShowPeriodicReminder(intervalDays: _reminderIntervalDays);

  /// Updates the last reminder date to now.
  ///
  /// Delegates to [NotificationPermissionHelper.updateLastReminderDate].
  Future<void> updateLastReminderDate() => _permissionHelper.updateLastReminderDate();

  /// Gets metadata about previous notification permission denials.
  ///
  /// Useful for implementing "ask again after X days" or "ask again after Y launches" logic.
  /// Delegates to [NotificationPermissionHelper.getNotificationDenialInfo].
  Future<NotificationDenialInfo?> getNotificationDenialInfo() =>
      _permissionHelper.getNotificationDenialInfo();

  /// Clears stored denial info (e.g., after user grants permission via settings).
  ///
  /// Delegates to [NotificationPermissionHelper.clearNotificationDenialInfo].
  Future<void> clearNotificationDenialInfo() => _permissionHelper.clearNotificationDenialInfo();

  /// Gets metadata about previous "go to settings" prompts.
  ///
  /// Useful for apps that want custom logic for when to show the settings prompt.
  /// Delegates to [NotificationPermissionHelper.getGoToSettingsPromptInfo].
  Future<GoToSettingsPromptInfo?> getGoToSettingsPromptInfo() =>
      _permissionHelper.getGoToSettingsPromptInfo();

  /// Clears stored "go to settings" prompt info.
  ///
  /// Delegates to [NotificationPermissionHelper.clearGoToSettingsPromptInfo].
  Future<void> clearGoToSettingsPromptInfo() => _permissionHelper.clearGoToSettingsPromptInfo();

  //
  // High-Level Permission Flow
  //

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
  ///
  /// Returns a [NotificationFlowResult] indicating how the flow completed.
  ///
  /// Example:
  /// ```dart
  /// final result = await notificationService.runNotificationPermissionFlow(context);
  /// if (result == NotificationFlowResult.granted ||
  ///     result == NotificationFlowResult.alreadyGranted) {
  ///   showSnackbar('Notifications enabled!');
  /// }
  /// ```
  Future<NotificationFlowResult> runNotificationPermissionFlow(
    BuildContext context, {
    NotificationFlowConfig config = const NotificationFlowConfig(),
  }) async {
    // Check FCM enabled
    if (!AppConfigBase.useFCM) {
      logd('runNotificationPermissionFlow: FCM is disabled');
      return NotificationFlowResult.fcmDisabled;
    }

    try {
      final status = await getPermissionStatus();
      final canPromptAgain = await _permissionHelper.canPromptForPermission();
      // Treat denial as permanent if we can't prompt again.
      // On web, most browsers treat first denial as permanent, so we route to
      // the go-to-settings flow which returns shownWebInstructions.
      final isPermanentDenied =
          status == NotificationPermissionStatus.denied && !canPromptAgain;

      switch (status) {
        case NotificationPermissionStatus.authorized:
        case NotificationPermissionStatus.provisional:
          // Already have permission - just initialize
          await initializeNotifications();
          logd('runNotificationPermissionFlow: Already granted');
          return NotificationFlowResult.alreadyGranted;

        case NotificationPermissionStatus.notDetermined:
          // Show value proposition first
          final shouldProceed = config.valuePropositionBuilder != null
              ? await config.valuePropositionBuilder!(context)
              : await _showValuePropositionDialog(context, config.strings);

          if (!shouldProceed) {
            logd('runNotificationPermissionFlow: User declined value proposition');
            return NotificationFlowResult.declinedValueProposition;
          }

          // Request permission
          final result = await initializeNotifications();
          return _mapInitResultToFlowResult(result);

        case NotificationPermissionStatus.denied:
          // If effectively permanent, route to go-to-settings path
          if (isPermanentDenied) {
            return await _handlePermanentlyDeniedFlow(context, config);
          }

          // Check if we should ask again
          final denialInfo = await getNotificationDenialInfo();
          if (!_shouldAskAgain(denialInfo, config)) {
            logd('runNotificationPermissionFlow: Skipping ask-again (config limits)');
            return NotificationFlowResult.skippedAskAgain;
          }

          // Show ask-again dialog
          final shouldAsk = config.askAgainBuilder != null
              ? await config.askAgainBuilder!(context, denialInfo!)
              : await _showAskAgainDialog(context, config.strings, denialInfo);

          if (!shouldAsk) {
            logd('runNotificationPermissionFlow: User declined ask-again');
            return NotificationFlowResult.skippedAskAgain;
          }

          final result = await initializeNotifications();
          return _mapInitResultToFlowResult(result);
      }
    } catch (e, stackTrace) {
      loge(e, 'Error in runNotificationPermissionFlow', stackTrace);
      _onError?.call('Error in runNotificationPermissionFlow: $e', stackTrace);
      return NotificationFlowResult.error;
    }
  }

  /// Handles the permanently denied flow (go-to-settings).
  Future<NotificationFlowResult> _handlePermanentlyDeniedFlow(
    BuildContext context,
    NotificationFlowConfig config,
  ) async {
    if (!config.showGoToSettingsPrompt) {
      logd('runNotificationPermissionFlow: Skipping go-to-settings (disabled in config)');
      return NotificationFlowResult.skippedGoToSettings;
    }

    // Check timing/count limits for go-to-settings prompt
    final settingsPromptInfo = await getGoToSettingsPromptInfo();
    if (!_shouldShowGoToSettingsPrompt(settingsPromptInfo, config)) {
      logd('runNotificationPermissionFlow: Skipping go-to-settings (timing/count limits)');
      return NotificationFlowResult.skippedGoToSettings;
    }

    // Show the prompt (with web-specific handling)
    final shouldOpenSettings = await _showGoToSettingsPromptWithTracking(
      context,
      config,
      settingsPromptInfo,
    );

    if (!shouldOpenSettings) {
      logd('runNotificationPermissionFlow: User declined go-to-settings');
      return NotificationFlowResult.declinedGoToSettings;
    }

    // On web, we can't open browser settings programmatically
    if (kIsWeb) {
      logd('runNotificationPermissionFlow: Web platform, showing instructions');
      return NotificationFlowResult.shownWebInstructions;
    }

    // On mobile, attempt to open system settings
    final opened = await openNotificationSettings();
    if (opened) {
      _setupLifecycleListener();
      _waitingForSettingsReturn = true;
    }
    logd('runNotificationPermissionFlow: Opened settings (success=$opened)');
    return NotificationFlowResult.openedSettings;
  }

  /// Determines if we should ask the user again after a previous denial.
  bool _shouldAskAgain(NotificationDenialInfo? info, NotificationFlowConfig config) {
    if (info == null) return true;
    if (info.isPermanent) return false;
    if (info.denialCount >= config.maxAskCount) return false;

    final timeSinceDenial = DateTime.now().difference(info.lastDenialTime);
    return timeSinceDenial >= config.askAgainAfter;
  }

  /// Determines if we should show the go-to-settings prompt.
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

  /// Maps [NotificationInitResult] to [NotificationFlowResult].
  NotificationFlowResult _mapInitResultToFlowResult(NotificationInitResult result) {
    switch (result) {
      case NotificationInitResult.success:
        return NotificationFlowResult.granted;
      case NotificationInitResult.alreadyInitialized:
        return NotificationFlowResult.alreadyGranted;
      case NotificationInitResult.permissionDenied:
        return NotificationFlowResult.deniedPermission;
      case NotificationInitResult.permissionPermanentlyDenied:
        return NotificationFlowResult.deniedPermanently;
      case NotificationInitResult.permissionRequestBlocked:
        return NotificationFlowResult.deniedPermission;
      case NotificationInitResult.fcmDisabledConfig:
      case NotificationInitResult.fcmDisabledInstance:
        return NotificationFlowResult.fcmDisabled;
      case NotificationInitResult.error:
        return NotificationFlowResult.error;
    }
  }

  //
  // Built-in Dialog Helpers
  //

  /// Shows the value proposition dialog.
  /// Returns true if user wants to proceed with permission request.
  Future<bool> _showValuePropositionDialog(
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

  /// Shows the go-to-settings dialog.
  /// Returns true if user wants to open settings.
  Future<bool> _showGoToSettingsDialog(
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

  /// Shows the ask-again dialog.
  /// Returns true if user wants to try again.
  Future<bool> _showAskAgainDialog(
    BuildContext context,
    NotificationFlowStrings strings,
    NotificationDenialInfo? info,
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

  /// Shows web-specific instructions for enabling notifications.
  /// Returns true when user acknowledges the instructions.
  Future<bool> _showWebSettingsInstructionsDialog(
    BuildContext context,
    NotificationFlowStrings strings,
  ) async {
    final result = await showOkAlertDialog(
      context: context,
      title: strings.webSettingsInstructionsTitle,
      message: strings.webSettingsInstructionsMessage,
      okLabel: strings.webSettingsInstructionsButton,
    );
    return result == OkCancelResult.ok;
  }

  /// Shows go-to-settings prompt with tracking and web-specific handling.
  Future<bool> _showGoToSettingsPromptWithTracking(
    BuildContext context,
    NotificationFlowConfig config,
    GoToSettingsPromptInfo? existingInfo,
  ) async {
    bool shouldOpenSettings;

    if (kIsWeb) {
      // On web, show instructions dialog instead
      shouldOpenSettings = config.goToSettingsBuilder != null
          ? await config.goToSettingsBuilder!(context)
          : await _showWebSettingsInstructionsDialog(context, config.strings);
    } else {
      // On mobile, show go-to-settings dialog
      shouldOpenSettings = config.goToSettingsBuilder != null
          ? await config.goToSettingsBuilder!(context)
          : await _showGoToSettingsDialog(context, config.strings);
    }

    // Record the prompt
    await _permissionHelper.recordGoToSettingsPrompt(openedSettings: shouldOpenSettings);

    return shouldOpenSettings;
  }

  //
  // Lifecycle Handling for Settings Return
  //

  /// Sets up a lifecycle listener to detect when user returns from settings.
  void _setupLifecycleListener() {
    if (_lifecycleSubscription != null) {
      // Already set up
      return;
    }

    // Ensure AppLifecycleService is initialized
    final lifecycleService = AppLifecycleService();
    if (!lifecycleService.isInitialized) {
      lifecycleService.initialize();
    }

    _lifecycleSubscription = lifecycleService.lifecycleStream.listen((state) {
      if (state == AppLifecycleState.resumed && _waitingForSettingsReturn) {
        _waitingForSettingsReturn = false;
        _handleResumeAfterSettings();
      }
    });

    logd('Lifecycle listener set up for settings return detection');
  }

  /// Handles app resume after user returns from settings.
  Future<void> _handleResumeAfterSettings() async {
    // getPermissionStatus() auto-clears denial info if granted
    final status = await getPermissionStatus();
    if (status == NotificationPermissionStatus.authorized ||
        status == NotificationPermissionStatus.provisional) {
      logd('Permission granted via settings - initializing FCM');
      if (_onTokenChanged != null) {
        await initializeFcmToken(onTokenChanged: _onTokenChanged!);
      }
    } else {
      logd('Returned from settings - permission still not granted');
    }
  }

  //
  // FCM Token Management Methods
  //

  /// Gets the stored FCM token, migrating from legacy key if necessary.
  ///
  /// Handles migration from the old `commonSharedKeyFcmToken` key used by
  /// AuthServiceImpl to the new `dreamic_fcm_token` prefixed key.
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

  /// Stores the FCM token using the new prefixed key.
  ///
  /// Also removes any legacy key if it exists to ensure clean migration.
  Future<void> _storeToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_fcmTokenKey, token);
    // Also remove legacy key if it exists (in case of upgrade during active session)
    if (prefs.containsKey(_legacyFcmTokenKey)) {
      await prefs.remove(_legacyFcmTokenKey);
    }
  }

  /// Clears the stored FCM token. Call this on sign out.
  ///
  /// Clears both new and legacy keys to ensure clean state.
  Future<void> clearFcmToken() async {
    _cachedFcmToken = null;
    _hasFcmTokenInitialized = false;
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_fcmTokenKey);
    await prefs.remove(_legacyFcmTokenKey); // Clear legacy key too
    logd('FCM token cleared');
  }

  /// Waits for APNS token to be available on iOS/macOS.
  ///
  /// APNS token is required before FCM token can be retrieved on Apple platforms.
  /// This method waits up to ~7.5 seconds for the token to become available.
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

  /// Initializes FCM token management and syncs with server.
  ///
  /// Call this after user is authenticated. The service will:
  /// 1. Get the current FCM token
  /// 2. Sync it to the server via [onTokenChanged]
  /// 3. Listen for token refreshes and sync automatically
  ///
  /// [onTokenChanged] is called when the token changes. Use this to sync
  /// the token to your backend server. The callback receives:
  /// - [newToken]: The new FCM token (null if unregistering)
  /// - [oldToken]: The previous FCM token (null if first registration)
  ///
  /// Example:
  /// ```dart
  /// await notificationService.initializeFcmToken(
  ///   onTokenChanged: (newToken, oldToken) async {
  ///     await myBackendService.updateFcmToken(newToken, oldToken);
  ///   },
  /// );
  /// ```
  Future<void> initializeFcmToken({
    required Future<void> Function(String? newToken, String? oldToken) onTokenChanged,
  }) async {
    if (_hasFcmTokenInitialized) {
      logd('FCM token already initialized');
      return;
    }

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
        // Prefer the persisted token as the source of truth for "old token"
        // (cached in-memory values may be null on cold start).
        if (token != oldToken) {
          await _onTokenChanged!(token, oldToken);
          await _storeToken(token);
        }
        _cachedFcmToken = token;
        logd('FCM token initialized: ${token.substring(0, 20)}...');
      }
    } catch (e) {
      loge(e, 'Failed to get FCM token');
      return; // Non-critical, don't propagate
    }

    // Listen for token refreshes
    _tokenRefreshSubscription = FirebaseMessaging.instance.onTokenRefresh.listen(
      (newToken) async {
        final oldToken = await _getStoredToken();
        try {
          await _onTokenChanged!(newToken, oldToken);
          await _storeToken(newToken);
          _cachedFcmToken = newToken;
          logd('FCM token refreshed: ${newToken.substring(0, 20)}...');
        } catch (e) {
          loge(e, 'Error syncing refreshed token');
        }
      },
    );

    _hasFcmTokenInitialized = true;
    logi('FCM token management initialized');
  }

  /// Gets the current cached FCM token.
  ///
  /// Returns the in-memory cached token. This may be null if:
  /// - [initializeFcmToken] hasn't been called yet
  /// - Token retrieval failed
  /// - [clearFcmToken] was called
  String? get cachedFcmToken => _cachedFcmToken;

  /// Whether FCM token management has been initialized.
  bool get isFcmTokenInitialized => _hasFcmTokenInitialized;

  /// Updates the app icon badge count.
  ///
  /// On iOS and Android, this updates the badge number shown on the app icon.
  /// On web, badge support varies by browser.
  ///
  /// Set [count] to 0 to clear the badge.
  ///
  /// Emits the new count to [badgeCountStream] for reactive UI updates.
  Future<void> updateBadgeCount(int count) async {
    try {
      // Update internal state
      _currentBadgeCount = count;

      // Emit to stream for reactive UI updates
      if (!_badgeCountController.isClosed) {
        _badgeCountController.add(count);
      }

      // Update platform badge via app_badge_plus
      // Note: Requires platform permissions (see NOTIFICATION_GUIDE.md)
      try {
        await AppBadgePlus.updateBadge(count);
      } catch (e) {
        // Badge update failed - this is non-critical
        logi('Badge update failed (platform may not support badges): $e');
      }

      logi('Badge count updated to: $count');
    } catch (e, stackTrace) {
      loge(e, 'Failed to update badge count', stackTrace);
      _onError?.call('Failed to update badge count: $e', stackTrace);
    }
  }

  /// Clears the app icon badge.
  ///
  /// Equivalent to calling `updateBadgeCount(0)`.
  Future<void> clearBadge() async {
    await updateBadgeCount(0);
  }

  /// Gets the current badge count synchronously.
  ///
  /// Returns the last known badge count. For reactive updates,
  /// use [badgeCountStream] instead.
  int getBadgeCount() {
    return _currentBadgeCount;
  }

  /// Disposes of the service and cleans up resources.
  Future<void> dispose() async {
    await _foregroundSubscription?.cancel();
    await _openedAppSubscription?.cancel();
    await _tokenRefreshSubscription?.cancel();
    await _authSubscription?.cancel();
    await _lifecycleSubscription?.cancel();
    await _badgeCountController.close();
    _foregroundSubscription = null;
    _openedAppSubscription = null;
    _tokenRefreshSubscription = null;
    _authSubscription = null;
    _lifecycleSubscription = null;
    _waitingForSettingsReturn = false;
    _initialized = false;
    _hasFcmTokenInitialized = false;
    logi('NotificationService disposed');
  }

  /// Serializes notification payload to JSON string for tap handling.
  String _serializePayload(NotificationPayload payload) {
    try {
      final json = payload.toJson();
      return jsonEncode(json);
    } catch (e) {
      loge(e, 'Error serializing notification payload');
      return '{}';
    }
  }

  /// Deserializes notification payload from JSON string.
  NotificationPayload? _deserializePayload(String payloadStr) {
    try {
      if (payloadStr.isEmpty) return null;
      final json = jsonDecode(payloadStr) as Map<String, dynamic>;
      return NotificationPayload.fromJson(json);
    } catch (e) {
      loge(e, 'Error deserializing notification payload');
      return null;
    }
  }

  /// Gets the channel manager for advanced channel operations.
  ///
  /// Returns null on non-Android platforms.
  ///
  /// Example:
  /// ```dart
  /// final manager = NotificationService().channelManager;
  /// await manager?.createChannel(customChannel);
  /// ```
  NotificationChannelManager? get channelManager => _channelManager;

  /// Gets the display name for a channel ID.
  String _getChannelName(String channelId) {
    switch (channelId) {
      case NotificationChannelManager.channelHighPriority:
        return 'Urgent Notifications';
      case NotificationChannelManager.channelDefault:
        return 'Default Notifications';
      case NotificationChannelManager.channelLowPriority:
        return 'Low Priority Notifications';
      case NotificationChannelManager.channelSilent:
        return 'Silent Notifications';
      default:
        return 'Notifications';
    }
  }

  /// Gets the description for a channel ID.
  String _getChannelDescription(String channelId) {
    switch (channelId) {
      case NotificationChannelManager.channelHighPriority:
        return 'Important, time-sensitive notifications';
      case NotificationChannelManager.channelDefault:
        return 'Standard app notifications';
      case NotificationChannelManager.channelLowPriority:
        return 'Non-urgent notifications';
      case NotificationChannelManager.channelSilent:
        return 'Background updates';
      default:
        return 'App notifications';
    }
  }
}
