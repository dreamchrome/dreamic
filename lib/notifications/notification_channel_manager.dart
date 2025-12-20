import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../utils/logger.dart';

/// Manages Android notification channels.
///
/// Notification channels (Android 8.0+) allow users to control notification behavior
/// per category. This manager creates and manages predefined channels for common
/// notification types.
///
/// ## Usage
///
/// ```dart
/// final manager = NotificationChannelManager(flutterLocalNotificationsPlugin);
/// await manager.createDefaultChannels();
///
/// // Use a specific channel
/// await notificationService.showNotification(
///   payload,
///   channelId: NotificationChannelManager.channelHighPriority,
/// );
/// ```
///
/// ## Default Channels
///
/// - **High Priority**: Urgent notifications (alerts, time-sensitive updates)
/// - **Default**: Standard notifications (messages, updates)
/// - **Low Priority**: Non-urgent notifications (promotions, tips)
/// - **Silent**: No sound or vibration (background updates)
class NotificationChannelManager {
  final FlutterLocalNotificationsPlugin _plugin;

  /// High priority channel ID for urgent, time-sensitive notifications.
  static const String channelHighPriority = 'high_priority_channel';

  /// Default channel ID for standard notifications.
  static const String channelDefault = 'default_channel';

  /// Low priority channel ID for non-urgent notifications.
  static const String channelLowPriority = 'low_priority_channel';

  /// Silent channel ID for notifications with no sound or vibration.
  static const String channelSilent = 'silent_channel';

  NotificationChannelManager(this._plugin);

  /// Creates all default notification channels.
  ///
  /// Should be called during app initialization on Android devices.
  /// On iOS and web, this is a no-op.
  Future<void> createDefaultChannels() async {
    if (kIsWeb || !Platform.isAndroid) {
      logd('Skipping notification channel creation (not Android)');
      return;
    }

    try {
      await Future.wait([
        createChannel(_highPriorityChannel),
        createChannel(_defaultChannel),
        createChannel(_lowPriorityChannel),
        createChannel(_silentChannel),
      ]);
      logi('Created ${_defaultChannels.length} notification channels');
    } catch (e, stack) {
      loge(stack, 'Failed to create notification channels: $e');
    }
  }

  /// Creates a single notification channel.
  ///
  /// Example:
  /// ```dart
  /// await manager.createChannel(AndroidNotificationChannel(
  ///   'custom_channel',
  ///   'Custom Notifications',
  ///   description: 'Custom notification category',
  ///   importance: Importance.max,
  /// ));
  /// ```
  Future<void> createChannel(AndroidNotificationChannel channel) async {
    if (kIsWeb || !Platform.isAndroid) {
      return;
    }

    try {
      final androidPlugin =
          _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin == null) {
        loge(StackTrace.current, 'AndroidFlutterLocalNotificationsPlugin not available');
        return;
      }

      await androidPlugin.createNotificationChannel(channel);
      logd('Created notification channel: ${channel.id}');
    } catch (e, stack) {
      loge(stack, 'Failed to create channel ${channel.id}: $e');
    }
  }

  /// Deletes a notification channel.
  ///
  /// Note: On Android 8.0+, users must manually delete channels from system settings
  /// if they were previously created. This method only prevents future creation.
  Future<void> deleteChannel(String channelId) async {
    if (kIsWeb || !Platform.isAndroid) {
      return;
    }

    try {
      final androidPlugin =
          _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

      await androidPlugin?.deleteNotificationChannel(channelId);
      logd('Deleted notification channel: $channelId');
    } catch (e, stack) {
      loge(stack, 'Failed to delete channel $channelId: $e');
    }
  }

  /// Gets all created notification channels.
  ///
  /// Returns a list of channels that have been created on the device.
  /// Returns empty list on iOS and web.
  Future<List<AndroidNotificationChannel>> getChannels() async {
    if (kIsWeb || !Platform.isAndroid) {
      return [];
    }

    try {
      final androidPlugin =
          _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin == null) {
        return [];
      }

      final channels = await androidPlugin.getNotificationChannels();
      return channels ?? [];
    } catch (e, stack) {
      loge(stack, 'Failed to get notification channels: $e');
      return [];
    }
  }

  // Default channel definitions

  static final AndroidNotificationChannel _highPriorityChannel = AndroidNotificationChannel(
    channelHighPriority,
    'Urgent Notifications',
    description: 'Important, time-sensitive notifications that require immediate attention',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
    enableLights: true,
    showBadge: true,
  );

  static final AndroidNotificationChannel _defaultChannel = AndroidNotificationChannel(
    channelDefault,
    'Default Notifications',
    description: 'Standard app notifications',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
    enableLights: true,
    showBadge: true,
  );

  static final AndroidNotificationChannel _lowPriorityChannel = AndroidNotificationChannel(
    channelLowPriority,
    'Low Priority Notifications',
    description: 'Non-urgent notifications like promotions or tips',
    importance: Importance.low,
    playSound: false,
    enableVibration: false,
    enableLights: false,
    showBadge: true,
  );

  static final AndroidNotificationChannel _silentChannel = AndroidNotificationChannel(
    channelSilent,
    'Silent Notifications',
    description: 'Background updates with no sound or vibration',
    importance: Importance.low,
    playSound: false,
    enableVibration: false,
    enableLights: false,
    showBadge: false,
  );

  static final List<AndroidNotificationChannel> _defaultChannels = [
    _highPriorityChannel,
    _defaultChannel,
    _lowPriorityChannel,
    _silentChannel,
  ];

  /// Gets the default channels list.
  ///
  /// Useful for documentation or displaying available channels to users.
  static List<AndroidNotificationChannel> get defaultChannels => _defaultChannels;
}
