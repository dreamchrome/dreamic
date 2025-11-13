/// Represents the status of notification permissions across platforms.
///
/// This enum provides a unified way to represent notification permission
/// states across iOS, Android, and web platforms.
enum NotificationPermissionStatus {
  /// Notification permissions have been granted by the user.
  ///
  /// The app can display notifications and badges.
  authorized,

  /// Notification permissions have been denied by the user.
  ///
  /// On iOS, this is a permanent state and permissions cannot be re-requested.
  /// On Android, permissions can be requested again unless permanently denied.
  /// The app must direct users to system settings to enable notifications.
  denied,

  /// Notification permissions have not been requested yet.
  ///
  /// The app can show a permission rationale and request permissions.
  /// This is the initial state before any permission request.
  notDetermined,

  /// Notification permissions have been provisionally authorized (iOS only).
  ///
  /// Notifications are delivered quietly to the Notification Center without
  /// sound, badge, or banner. The user can promote to full authorization
  /// from the Notification Center.
  provisional,
}
