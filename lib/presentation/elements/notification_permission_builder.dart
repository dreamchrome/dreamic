import 'package:flutter/material.dart';
import '../../notifications/notification_service.dart';
import '../../data/models/notification_permission_status.dart';

/// A builder widget that provides notification permission state and actions.
///
/// This is a headless component that provides permission status and request
/// functionality to your custom UI via a builder callback. The builder
/// automatically rebuilds when permission status changes.
///
/// Example:
/// ```dart
/// NotificationPermissionBuilder(
///   builder: (context, status, requestPermissions) {
///     if (status == NotificationPermissionStatus.authorized) {
///       return Text('Notifications enabled!');
///     }
///     return ElevatedButton(
///       onPressed: requestPermissions,
///       child: Text('Enable Notifications'),
///     );
///   },
/// )
/// ```
///
/// You can also use it to conditionally show content:
/// ```dart
/// NotificationPermissionBuilder(
///   builder: (context, status, requestPermissions) {
///     return Column(
///       children: [
///         Text('Status: ${status.name}'),
///         if (status != NotificationPermissionStatus.authorized)
///           OutlinedButton(
///             onPressed: requestPermissions,
///             child: Text('Enable'),
///           ),
///         if (status == NotificationPermissionStatus.authorized)
///           NotificationListWidget(),
///       ],
///     );
///   },
/// )
/// ```
class NotificationPermissionBuilder extends StatefulWidget {
  /// Builder callback that provides permission status and request method.
  ///
  /// - `context`: Build context
  /// - `status`: Current notification permission status
  /// - `requestPermissions`: Function to request permissions
  final Widget Function(
    BuildContext context,
    NotificationPermissionStatus status,
    Future<void> Function() requestPermissions,
  ) builder;

  /// Optional callback when permission status changes.
  final void Function(NotificationPermissionStatus status)? onStatusChanged;

  const NotificationPermissionBuilder({
    super.key,
    required this.builder,
    this.onStatusChanged,
  });

  @override
  State<NotificationPermissionBuilder> createState() => _NotificationPermissionBuilderState();
}

class _NotificationPermissionBuilderState extends State<NotificationPermissionBuilder>
    with WidgetsBindingObserver {
  NotificationPermissionStatus _status = NotificationPermissionStatus.notDetermined;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPermissionStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Reload permission status when app resumes
    // (user might have changed it in system settings)
    if (state == AppLifecycleState.resumed) {
      _loadPermissionStatus();
    }
  }

  Future<void> _loadPermissionStatus() async {
    try {
      final service = NotificationService();
      final status = await service.getPermissionStatus();

      if (mounted) {
        setState(() {
          final oldStatus = _status;
          _status = status;
          _isLoading = false;

          // Call status changed callback if status actually changed
          if (oldStatus != status && !_isLoading) {
            widget.onStatusChanged?.call(status);
          }
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

  Future<void> _requestPermissions() async {
    try {
      final service = NotificationService();
      final newStatus = await service.requestPermissions();

      if (mounted) {
        setState(() {
          final oldStatus = _status;
          _status = newStatus;

          // Call status changed callback if status changed
          if (oldStatus != newStatus) {
            widget.onStatusChanged?.call(newStatus);
          }
        });
      }
    } catch (e) {
      // Error is already logged by NotificationService
      // Just reload the current status
      await _loadPermissionStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    // During initial load, show the builder with current status
    // (it starts as notDetermined which is a reasonable default)
    return widget.builder(
      context,
      _status,
      _requestPermissions,
    );
  }
}
