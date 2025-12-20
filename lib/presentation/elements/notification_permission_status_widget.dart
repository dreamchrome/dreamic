import 'package:flutter/material.dart';
import '../../notifications/notification_service.dart';
import '../../data/models/notification_permission_status.dart';

/// A widget that displays the current notification permission status.
///
/// Automatically updates when permission status changes and provides
/// action buttons based on the current state.
///
/// ## Usage
///
/// Basic usage:
/// ```dart
/// NotificationPermissionStatusWidget()
/// ```
///
/// With custom actions:
/// ```dart
/// NotificationPermissionStatusWidget(
///   onEnablePressed: () async {
///     // Show custom permission flow
///   },
///   onSettingsPressed: () async {
///     // Custom settings navigation
///   },
/// )
/// ```
class NotificationPermissionStatusWidget extends StatefulWidget {
  final VoidCallback? onEnablePressed;
  final VoidCallback? onSettingsPressed;
  final EdgeInsets? padding;
  final bool showActionButton;

  const NotificationPermissionStatusWidget({
    super.key,
    this.onEnablePressed,
    this.onSettingsPressed,
    this.padding,
    this.showActionButton = true,
  });

  @override
  State<NotificationPermissionStatusWidget> createState() =>
      _NotificationPermissionStatusWidgetState();
}

class _NotificationPermissionStatusWidgetState extends State<NotificationPermissionStatusWidget> {
  NotificationPermissionStatus _status = NotificationPermissionStatus.notDetermined;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadPermissionStatus();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload status when widget is rebuilt or navigation returns
    _loadPermissionStatus();
  }

  Future<void> _loadPermissionStatus() async {
    if (!mounted) return;

    final service = NotificationService();
    final status = await service.getPermissionStatus();

    if (mounted) {
      setState(() {
        _status = status;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: widget.padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _getStatusColor().withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _getStatusColor().withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            _getStatusIcon(),
            color: _getStatusColor(),
            size: 32,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _getStatusTitle(),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: _getStatusColor(),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _getStatusDescription(),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (widget.showActionButton && _shouldShowActionButton()) const SizedBox(width: 12),
          if (widget.showActionButton && _shouldShowActionButton()) _buildActionButton(context),
        ],
      ),
    );
  }

  IconData _getStatusIcon() {
    switch (_status) {
      case NotificationPermissionStatus.authorized:
        return Icons.check_circle;
      case NotificationPermissionStatus.denied:
        return Icons.notifications_off;
      case NotificationPermissionStatus.notDetermined:
        return Icons.notifications_none;
      case NotificationPermissionStatus.provisional:
        return Icons.notifications;
    }
  }

  Color _getStatusColor() {
    switch (_status) {
      case NotificationPermissionStatus.authorized:
        return Colors.green;
      case NotificationPermissionStatus.denied:
        return Colors.orange;
      case NotificationPermissionStatus.notDetermined:
        return Colors.blue;
      case NotificationPermissionStatus.provisional:
        return Colors.blue;
    }
  }

  String _getStatusTitle() {
    switch (_status) {
      case NotificationPermissionStatus.authorized:
        return 'Notifications Enabled';
      case NotificationPermissionStatus.denied:
        return 'Notifications Disabled';
      case NotificationPermissionStatus.notDetermined:
        return 'Enable Notifications';
      case NotificationPermissionStatus.provisional:
        return 'Quiet Notifications';
    }
  }

  String _getStatusDescription() {
    switch (_status) {
      case NotificationPermissionStatus.authorized:
        return 'You\'ll receive notifications about important updates';
      case NotificationPermissionStatus.denied:
        return 'Enable in Settings to receive notifications';
      case NotificationPermissionStatus.notDetermined:
        return 'Stay informed with timely notifications';
      case NotificationPermissionStatus.provisional:
        return 'Notifications delivered quietly';
    }
  }

  bool _shouldShowActionButton() {
    return _status != NotificationPermissionStatus.authorized;
  }

  Widget _buildActionButton(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    final buttonText = _status == NotificationPermissionStatus.denied ? 'Settings' : 'Enable';
    final onPressed = _status == NotificationPermissionStatus.denied
        ? _handleSettingsPressed
        : _handleEnablePressed;

    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: _getStatusColor(),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: Text(buttonText),
    );
  }

  Future<void> _handleEnablePressed() async {
    if (widget.onEnablePressed != null) {
      widget.onEnablePressed!();
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final service = NotificationService();
      final status = await service.requestPermissions();

      if (mounted) {
        setState(() {
          _status = status;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleSettingsPressed() async {
    if (widget.onSettingsPressed != null) {
      widget.onSettingsPressed!();
      return;
    }

    final service = NotificationService();
    await service.openSystemSettings();

    // Reload status when user returns from settings
    await Future.delayed(const Duration(seconds: 1));
    await _loadPermissionStatus();
  }
}
