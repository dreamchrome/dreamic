import 'package:json_annotation/json_annotation.dart';

part 'notification_action.g.dart';

/// Represents an action button that can be displayed with a notification.
///
/// Actions allow users to interact with notifications without opening the app.
/// Common examples include "Reply", "Archive", "Delete", etc.
@JsonSerializable()
class NotificationAction {
  /// Unique identifier for this action.
  ///
  /// This ID is passed to the `onNotificationAction` callback when the
  /// action is triggered.
  final String id;

  /// User-facing label for the action button.
  final String label;

  /// Optional icon identifier for the action button.
  ///
  /// The format depends on the platform:
  /// - Android: Resource name (e.g., "ic_reply")
  /// - iOS: SF Symbol name (e.g., "arrow.turn.up.left")
  final String? icon;

  /// Whether this action requires the app to be unlocked/authenticated.
  ///
  /// If true, the action will only be available when the device is unlocked
  /// (iOS) or may prompt for authentication (Android).
  @JsonKey(defaultValue: false)
  final bool requiresAuth;

  /// Whether tapping this action should launch the app in foreground.
  ///
  /// If false, the action will be handled in the background without
  /// bringing the app to the foreground.
  @JsonKey(defaultValue: true)
  final bool launchesApp;

  const NotificationAction({
    required this.id,
    required this.label,
    this.icon,
    this.requiresAuth = false,
    this.launchesApp = true,
  });

  /// Creates a [NotificationAction] from JSON data.
  factory NotificationAction.fromJson(Map<String, dynamic> json) =>
      _$NotificationActionFromJson(json);

  /// Converts this [NotificationAction] to JSON data.
  Map<String, dynamic> toJson() => _$NotificationActionToJson(this);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NotificationAction &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          label == other.label &&
          icon == other.icon &&
          requiresAuth == other.requiresAuth &&
          launchesApp == other.launchesApp;

  @override
  int get hashCode =>
      id.hashCode ^ label.hashCode ^ icon.hashCode ^ requiresAuth.hashCode ^ launchesApp.hashCode;

  @override
  String toString() {
    return 'NotificationAction{id: $id, label: $label, icon: $icon, '
        'requiresAuth: $requiresAuth, launchesApp: $launchesApp}';
  }
}
