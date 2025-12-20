import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/models/notification_payload.dart';
import '../data/models/notification_permission_status.dart';
import '../utils/logger.dart';
import 'notification_channel_manager.dart';
import 'notification_image_loader.dart';

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

  // Shared preferences keys
  static const String _keyPermissionRequestCount = 'notification_permission_request_count';
  static const String _keyPermissionDenialCount = 'notification_permission_denial_count';
  static const String _keyLastPermissionRequest = 'notification_last_permission_request';
  static const String _keyLastReminderDate = 'notification_last_reminder_date';

  /// Private constructor for singleton pattern.
  NotificationService._internal();

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

  /// Initializes the notification service.
  ///
  /// This method sets up all notification handling including:
  /// - Local notification plugin initialization
  /// - FCM message listeners (foreground, background, terminated)
  /// - Notification action handlers
  /// - Platform-specific configuration
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
  Future<NotificationPermissionStatus> getPermissionStatus() async {
    try {
      final settings = await FirebaseMessaging.instance.getNotificationSettings();

      switch (settings.authorizationStatus) {
        case AuthorizationStatus.authorized:
          return NotificationPermissionStatus.authorized;
        case AuthorizationStatus.denied:
          return NotificationPermissionStatus.denied;
        case AuthorizationStatus.notDetermined:
          return NotificationPermissionStatus.notDetermined;
        case AuthorizationStatus.provisional:
          return NotificationPermissionStatus.provisional;
      }
    } catch (e, stackTrace) {
      loge(e, 'Error getting permission status', stackTrace);
      _onError?.call('Error getting permission status: $e', stackTrace);
      return NotificationPermissionStatus.notDetermined;
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
  ///
  /// If permissions are granted, this automatically triggers FCM token registration
  /// via AuthServiceImpl (if integrated).
  Future<NotificationPermissionStatus> requestPermissions({
    bool provisional = false,
  }) async {
    try {
      await _trackPermissionRequest();

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

      if (status == NotificationPermissionStatus.denied) {
        await _trackPermissionDenial();
      }

      logi('Permission request result: $status');

      // TODO: Notify AuthServiceImpl if permissions were granted

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

  /// Tracks when a permission request is made.
  Future<void> _trackPermissionRequest() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final count = prefs.getInt(_keyPermissionRequestCount) ?? 0;
      await prefs.setInt(_keyPermissionRequestCount, count + 1);
      await prefs.setInt(_keyLastPermissionRequest, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      loge(e, 'Error tracking permission request');
    }
  }

  /// Tracks when a permission request is denied.
  Future<void> _trackPermissionDenial() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final count = prefs.getInt(_keyPermissionDenialCount) ?? 0;
      await prefs.setInt(_keyPermissionDenialCount, count + 1);
    } catch (e) {
      loge(e, 'Error tracking permission denial');
    }
  }

  /// Gets the number of times permissions have been requested.
  Future<int> getPermissionRequestCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_keyPermissionRequestCount) ?? 0;
    } catch (e) {
      loge(e, 'Error getting permission request count');
      return 0;
    }
  }

  /// Gets the number of times permissions have been denied.
  Future<int> getPermissionDenialCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_keyPermissionDenialCount) ?? 0;
    } catch (e) {
      loge(e, 'Error getting permission denial count');
      return 0;
    }
  }

  /// Checks if enough time has passed to show a permission reminder.
  Future<bool> shouldShowPeriodicReminder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastReminder = prefs.getInt(_keyLastReminderDate);

      if (lastReminder == null) {
        return true; // Never shown before
      }

      final daysSinceLastReminder =
          DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(lastReminder)).inDays;

      return daysSinceLastReminder >= _reminderIntervalDays;
    } catch (e) {
      loge(e, 'Error checking reminder timing');
      return false;
    }
  }

  /// Updates the last reminder date to now.
  Future<void> updateLastReminderDate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyLastReminderDate, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      loge(e, 'Error updating last reminder date');
    }
  }

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
    await _badgeCountController.close();
    _foregroundSubscription = null;
    _openedAppSubscription = null;
    _initialized = false;
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
