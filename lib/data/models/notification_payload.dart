import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:json_annotation/json_annotation.dart';
import 'notification_action.dart';

part 'notification_payload.g.dart';

/// Represents the complete payload of a notification.
///
/// This class encapsulates all information needed to display and handle
/// a notification, including content, routing, actions, and rich media.
@JsonSerializable(explicitToJson: true)
class NotificationPayload {
  /// Notification title.
  final String? title;

  /// Notification body text.
  final String? body;

  /// URL to an image to display in the notification.
  ///
  /// The image will be downloaded and cached before displaying the notification.
  /// If download fails, the notification will be displayed without the image.
  final String? imageUrl;

  /// Route or screen to navigate to when notification is tapped.
  ///
  /// This value is passed to the `onNotificationTapped` callback.
  /// The app is responsible for parsing and handling the route.
  final String? route;

  /// Additional data associated with the notification.
  ///
  /// This can contain any custom key-value pairs needed by the app,
  /// such as user IDs, content IDs, parameters, etc.
  final Map<String, dynamic> data;

  /// List of action buttons to display with the notification.
  final List<NotificationAction> actions;

  /// Unique identifier for this notification.
  ///
  /// If not provided, one will be generated automatically.
  /// Use a specific ID to replace/update existing notifications.
  final int? id;

  /// Notification channel ID (Android only).
  ///
  /// Determines the notification channel that should be used.
  /// If not specified, the default channel will be used.
  final String? channelId;

  /// Notification category (iOS only).
  ///
  /// Determines which notification actions are available.
  final String? category;

  /// Sound to play when notification is received.
  ///
  /// Use 'default' for the default notification sound.
  /// For custom sounds, provide the filename (without extension).
  final String? sound;

  /// Badge count to display on app icon (iOS/Android).
  ///
  /// If null, badge is not modified. Set to 0 to clear badge.
  final int? badge;

  /// Time-to-live for the notification in seconds.
  ///
  /// Determines how long the notification should be retained if
  /// the device is offline. After this period, the notification expires.
  final int? ttl;

  /// Priority of the notification.
  ///
  /// Affects how prominently the notification is displayed.
  /// Values: 'max', 'high', 'default', 'low', 'min'
  final String? priority;

  const NotificationPayload({
    this.title,
    this.body,
    this.imageUrl,
    this.route,
    this.data = const {},
    this.actions = const [],
    this.id,
    this.channelId,
    this.category,
    this.sound,
    this.badge,
    this.ttl,
    this.priority,
  });

  /// Creates a [NotificationPayload] from a Firebase Cloud Messaging [RemoteMessage].
  ///
  /// This factory extracts notification content from the FCM message and
  /// converts it to a standardized payload format.
  factory NotificationPayload.fromRemoteMessage(RemoteMessage message) {
    final notification = message.notification;
    final data = Map<String, dynamic>.from(message.data);

    // Extract route from multiple possible fields
    final route = data['route'] as String? ??
        data['screen'] as String? ??
        data['deepLink'] as String? ??
        data['url'] as String?;

    // Extract image URL
    final imageUrl = notification?.android?.imageUrl ??
        notification?.apple?.imageUrl ??
        data['imageUrl'] as String?;

    // Extract actions if present
    final actionsList = data['actions'] as List<dynamic>?;
    final actions =
        actionsList?.map((e) => NotificationAction.fromJson(e as Map<String, dynamic>)).toList() ??
            [];

    return NotificationPayload(
      title: notification?.title ?? data['title'] as String?,
      body: notification?.body ?? data['body'] as String?,
      imageUrl: imageUrl,
      route: route,
      data: data,
      actions: actions,
      channelId: notification?.android?.channelId ?? data['channelId'] as String?,
      category: message.category ?? data['category'] as String?,
      sound: notification?.android?.sound ?? data['sound'] as String?,
      badge: notification?.apple?.badge != null
          ? int.tryParse(notification!.apple!.badge.toString())
          : null,
      ttl: message.ttl,
      priority: data['priority'] as String?,
    );
  }

  /// Creates a [NotificationPayload] from JSON data.
  factory NotificationPayload.fromJson(Map<String, dynamic> json) =>
      _$NotificationPayloadFromJson(json);

  /// Converts this [NotificationPayload] to JSON data.
  Map<String, dynamic> toJson() => _$NotificationPayloadToJson(this);

  /// Creates a copy of this payload with the given fields replaced.
  NotificationPayload copyWith({
    String? title,
    String? body,
    String? imageUrl,
    String? route,
    Map<String, dynamic>? data,
    List<NotificationAction>? actions,
    int? id,
    String? channelId,
    String? category,
    String? sound,
    int? badge,
    int? ttl,
    String? priority,
  }) {
    return NotificationPayload(
      title: title ?? this.title,
      body: body ?? this.body,
      imageUrl: imageUrl ?? this.imageUrl,
      route: route ?? this.route,
      data: data ?? this.data,
      actions: actions ?? this.actions,
      id: id ?? this.id,
      channelId: channelId ?? this.channelId,
      category: category ?? this.category,
      sound: sound ?? this.sound,
      badge: badge ?? this.badge,
      ttl: ttl ?? this.ttl,
      priority: priority ?? this.priority,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NotificationPayload &&
          runtimeType == other.runtimeType &&
          title == other.title &&
          body == other.body &&
          imageUrl == other.imageUrl &&
          route == other.route &&
          id == other.id &&
          channelId == other.channelId &&
          category == other.category &&
          sound == other.sound &&
          badge == other.badge &&
          ttl == other.ttl &&
          priority == other.priority;

  @override
  int get hashCode =>
      title.hashCode ^
      body.hashCode ^
      imageUrl.hashCode ^
      route.hashCode ^
      id.hashCode ^
      channelId.hashCode ^
      category.hashCode ^
      sound.hashCode ^
      badge.hashCode ^
      ttl.hashCode ^
      priority.hashCode;

  @override
  String toString() {
    return 'NotificationPayload{title: $title, body: $body, '
        'imageUrl: $imageUrl, route: $route, id: $id, channelId: $channelId, '
        'category: $category, sound: $sound, badge: $badge, ttl: $ttl, '
        'priority: $priority, actions: ${actions.length}, data: ${data.keys}}';
  }
}
