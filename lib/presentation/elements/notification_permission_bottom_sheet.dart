import 'package:adaptive_dialog/adaptive_dialog.dart';
import 'package:flutter/material.dart';
import '../../notifications/notification_service.dart';
import '../../data/models/notification_permission_status.dart';
import '../../utils/logger.dart';

/// A bottom sheet for requesting notification permissions with customizable content.
///
/// This widget provides a user-friendly interface for requesting notification
/// permissions, with appropriate messaging and actions based on the current
/// permission state.
///
/// **All text is fully customizable for localization.**
///
/// ## Usage
///
/// Simple usage with defaults:
/// ```dart
/// await NotificationPermissionBottomSheet.show(context);
/// ```
///
/// Customized usage with localization:
/// ```dart
/// await NotificationPermissionBottomSheet.show(
///   context,
///   title: AppLocalizations.of(context).notificationPermissionTitle,
///   description: AppLocalizations.of(context).notificationPermissionDescription,
///   allowButtonText: AppLocalizations.of(context).allow,
///   declineButtonText: AppLocalizations.of(context).notNow,
///   deniedDialogTitle: AppLocalizations.of(context).notificationsDeniedTitle,
///   deniedDialogMessage: AppLocalizations.of(context).notificationsDeniedMessage,
///   openSettingsButtonText: AppLocalizations.of(context).openSettings,
///   maybeLaterButtonText: AppLocalizations.of(context).maybeLater,
///   onResult: (status) {
///     if (status == NotificationPermissionStatus.authorized) {
///       // Handle success
///     }
///   },
/// );
/// ```
class NotificationPermissionBottomSheet extends StatelessWidget {
  final String title;
  final String description;
  final String allowButtonText;
  final String declineButtonText;

  // Denied dialog customization
  final String deniedDialogTitle;
  final String deniedDialogMessage;
  final String openSettingsButtonText;
  final String maybeLaterButtonText;

  final Color? primaryColor;
  final Color? backgroundColor;
  final Widget? icon;
  final Function(NotificationPermissionStatus)? onResult;

  const NotificationPermissionBottomSheet({
    super.key,
    this.title = 'Enable Notifications',
    this.description = 'Stay informed with notifications about important updates and activity.',
    this.allowButtonText = 'Allow Notifications',
    this.declineButtonText = 'Not Now',
    this.deniedDialogTitle = 'Notifications Disabled',
    this.deniedDialogMessage =
        'To enable notifications, please go to Settings and allow notifications for this app.',
    this.openSettingsButtonText = 'Open Settings',
    this.maybeLaterButtonText = 'Maybe Later',
    this.primaryColor,
    this.backgroundColor,
    this.icon,
    this.onResult,
  });

  /// Shows the notification permission bottom sheet.
  ///
  /// Automatically detects the current permission state and shows appropriate UI:
  /// - If not determined: Shows request prompt
  /// - If denied: Shows settings prompt (iOS) or retry prompt (Android)
  /// - If already authorized: Dismisses immediately with authorized status
  ///
  /// All text parameters are customizable for localization.
  static Future<NotificationPermissionStatus?> show(
    BuildContext context, {
    String title = 'Enable Notifications',
    String description = 'Stay informed with notifications about important updates and activity.',
    String allowButtonText = 'Allow Notifications',
    String declineButtonText = 'Not Now',
    String deniedDialogTitle = 'Notifications Disabled',
    String deniedDialogMessage =
        'To enable notifications, please go to Settings and allow notifications for this app.',
    String openSettingsButtonText = 'Open Settings',
    String maybeLaterButtonText = 'Maybe Later',
    Color? primaryColor,
    Color? backgroundColor,
    Widget? icon,
    Function(NotificationPermissionStatus)? onResult,
  }) async {
    // Check current status first
    final service = NotificationService();
    final currentStatus = await service.getPermissionStatus();

    // If already authorized, no need to show sheet
    if (currentStatus == NotificationPermissionStatus.authorized) {
      onResult?.call(currentStatus);
      return currentStatus;
    }

    if (!context.mounted) return null;

    final result = await showModalBottomSheet<NotificationPermissionStatus>(
      context: context,
      backgroundColor: backgroundColor ?? Theme.of(context).bottomSheetTheme.backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => NotificationPermissionBottomSheet(
        title: title,
        description: description,
        allowButtonText: allowButtonText,
        declineButtonText: declineButtonText,
        deniedDialogTitle: deniedDialogTitle,
        deniedDialogMessage: deniedDialogMessage,
        openSettingsButtonText: openSettingsButtonText,
        maybeLaterButtonText: maybeLaterButtonText,
        primaryColor: primaryColor,
        backgroundColor: backgroundColor,
        icon: icon,
        onResult: onResult,
      ),
    );

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final buttonColor = primaryColor ?? theme.primaryColor;

    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: theme.dividerColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Icon
          if (icon != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: icon!,
            )
          else
            Icon(
              Icons.notifications_active,
              size: 48,
              color: buttonColor,
            ),

          const SizedBox(height: 16),

          // Title
          Text(
            title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 12),

          // Description
          Text(
            description,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.textTheme.bodySmall?.color,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 24),

          // Allow button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: () => _handleAllowTap(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: buttonColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                allowButtonText,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Decline button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: TextButton(
              onPressed: () => _handleDeclineTap(context),
              style: TextButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                declineButtonText,
                style: TextStyle(
                  fontSize: 16,
                  color: theme.textTheme.bodyMedium?.color,
                ),
              ),
            ),
          ),

          // Safe area padding for bottom
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }

  Future<void> _handleAllowTap(BuildContext context) async {
    try {
      final service = NotificationService();
      final status = await service.requestPermissions();

      onResult?.call(status);

      if (context.mounted) {
        Navigator.of(context).pop(status);

        // If denied, show settings prompt
        if (status == NotificationPermissionStatus.denied) {
          await _showDeniedDialog(context);
        }
      }
    } catch (e) {
      loge(e, 'Error requesting permissions from bottom sheet');
      if (context.mounted) {
        Navigator.of(context).pop(NotificationPermissionStatus.denied);
      }
    }
  }

  void _handleDeclineTap(BuildContext context) {
    onResult?.call(NotificationPermissionStatus.denied);
    Navigator.of(context).pop(NotificationPermissionStatus.denied);
  }

  Future<void> _showDeniedDialog(BuildContext context) async {
    if (!context.mounted) return;

    final result = await showOkCancelAlertDialog(
      context: context,
      title: deniedDialogTitle,
      message: deniedDialogMessage,
      okLabel: openSettingsButtonText,
      cancelLabel: maybeLaterButtonText,
      isDestructiveAction: false,
    );

    if (result == OkCancelResult.ok && context.mounted) {
      final service = NotificationService();
      await service.openSystemSettings();
    }
  }
}
