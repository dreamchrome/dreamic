import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/helpers/notification_service.dart';

/// A badge widget that automatically displays the current notification count.
///
/// This widget syncs with [NotificationService] to display the app's badge count
/// (typically unread notifications). It automatically updates when the badge
/// count changes and uses Material Design 3 Badge for proper theming.
///
/// **Automatic Mode (no count parameter):**
/// ```dart
/// NotificationBadgeWidget(
///   child: Icon(Icons.notifications),
/// )
/// // Automatically shows NotificationService().getBadgeCount()
/// ```
///
/// **Manual Mode (with count parameter):**
/// ```dart
/// NotificationBadgeWidget(
///   count: 5,
///   child: Icon(Icons.shopping_cart),
/// )
/// // Shows the specific count you provide
/// ```
///
/// **Custom styling:**
/// ```dart
/// NotificationBadgeWidget(
///   maxCount: 99,              // Shows "99+" for counts > 99
///   hideWhenZero: true,        // Hides badge when count is 0
///   backgroundColor: Colors.red,
///   textColor: Colors.white,
///   child: IconButton(
///     icon: Icon(Icons.mail),
///     onPressed: () {},
///   ),
/// )
/// ```
///
/// **Custom alignment:**
/// ```dart
/// NotificationBadgeWidget(
///   alignment: AlignmentDirectional(-12, -4),  // Top-left
///   offset: Offset(4, -4),     // Fine-tune position
///   child: YourWidget(),
/// )
/// ```
class NotificationBadgeWidget extends StatefulWidget {
  /// The count to display in the badge.
  ///
  /// If null (default), automatically fetches count from NotificationService
  /// and rebuilds when it changes. If provided, displays the specific count
  /// without automatic updates.
  final int? count;

  /// The widget to display the badge on top of.
  final Widget child;

  /// Whether to hide the badge when count is zero.
  /// Defaults to true.
  final bool hideWhenZero;

  /// Maximum count to display before showing overflow indicator.
  /// For example, if maxCount is 99, counts above 99 will show as "99+".
  /// Defaults to 99.
  final int maxCount;

  /// Background color of the badge.
  /// Defaults to theme's error color (typically red).
  final Color? backgroundColor;

  /// Text color of the count.
  /// Defaults to theme's onError color (typically white).
  final Color? textColor;

  /// Alignment of the badge relative to the child.
  /// Defaults to top-right corner: `AlignmentDirectional(12, -4)`.
  /// Common values:
  /// - Top-right: `AlignmentDirectional(12, -4)` (default)
  /// - Top-left: `AlignmentDirectional(-12, -4)`
  /// - Bottom-right: `AlignmentDirectional(12, 20)`
  final AlignmentGeometry? alignment;

  /// Additional offset from the aligned position.
  /// Useful for fine-tuning placement.
  final Offset? offset;

  /// Text style for the count.
  /// If not provided, uses Flutter's default badge text style.
  final TextStyle? textStyle;

  /// Whether the badge is enabled.
  /// When false, only the child is displayed without the badge.
  /// Defaults to true.
  final bool isLabelVisible;

  const NotificationBadgeWidget({
    super.key,
    this.count,
    required this.child,
    this.hideWhenZero = true,
    this.maxCount = 99,
    this.backgroundColor,
    this.textColor,
    this.alignment,
    this.offset,
    this.textStyle,
    this.isLabelVisible = true,
  });

  @override
  State<NotificationBadgeWidget> createState() => _NotificationBadgeWidgetState();
}

class _NotificationBadgeWidgetState extends State<NotificationBadgeWidget> {
  int _currentCount = 0;
  bool _isAutomaticMode = false;
  StreamSubscription<int>? _badgeCountSubscription;

  @override
  void initState() {
    super.initState();
    _isAutomaticMode = widget.count == null;
    if (_isAutomaticMode) {
      _subscribeToBadgeStream();
    } else {
      _currentCount = widget.count!;
    }
  }

  @override
  void didUpdateWidget(NotificationBadgeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Switch between automatic and manual mode if count parameter changes
    final wasAutomatic = oldWidget.count == null;
    _isAutomaticMode = widget.count == null;

    if (_isAutomaticMode != wasAutomatic) {
      if (_isAutomaticMode) {
        _subscribeToBadgeStream();
      } else {
        _unsubscribeFromBadgeStream();
      }
    }

    // Update count if in manual mode
    if (!_isAutomaticMode && widget.count != oldWidget.count) {
      setState(() {
        _currentCount = widget.count!;
      });
    }
  }

  void _subscribeToBadgeStream() {
    try {
      final service = NotificationService();

      // Get initial count synchronously
      _currentCount = service.getBadgeCount();

      // Subscribe to stream for updates
      _badgeCountSubscription = service.badgeCountStream.listen(
        (count) {
          if (mounted) {
            setState(() {
              _currentCount = count;
            });
          }
        },
        onError: (error) {
          // Ignore stream errors - badge count is non-critical
        },
      );
    } catch (e) {
      // Ignore errors - badge count is non-critical
    }
  }

  void _unsubscribeFromBadgeStream() {
    _badgeCountSubscription?.cancel();
    _badgeCountSubscription = null;
  }

  @override
  void dispose() {
    _unsubscribeFromBadgeStream();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Use manual count if provided, otherwise use automatic count
    final displayCount = widget.count ?? _currentCount;

    // Hide badge if count is zero and hideWhenZero is true
    if (widget.hideWhenZero && displayCount == 0) {
      return widget.child;
    }

    // Hide badge if explicitly disabled
    if (!widget.isLabelVisible) {
      return widget.child;
    }

    // Format count with overflow indicator
    final displayText =
        displayCount > widget.maxCount ? '${widget.maxCount}+' : displayCount.toString();

    final theme = Theme.of(context);
    final badgeColor = widget.backgroundColor ?? theme.colorScheme.error;
    final countColor = widget.textColor ?? theme.colorScheme.onError;

    return Badge(
      label: Text(displayText),
      backgroundColor: badgeColor,
      textColor: countColor,
      alignment: widget.alignment,
      offset: widget.offset,
      textStyle: widget.textStyle,
      child: widget.child,
    );
  }
}
