import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../app/app_cubit.dart';

/// A badge widget that automatically displays the current notification count.
///
/// This widget uses [AppCubit] state to display the app's unread notification count.
/// It automatically updates when the count changes and uses Material Design 3 Badge
/// for proper theming.
///
/// **Automatic Mode (no count parameter):**
/// ```dart
/// NotificationBadgeWidget(
///   child: Icon(Icons.notifications),
/// )
/// // Automatically shows AppState.unreadNotificationCount
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
class NotificationBadgeWidget extends StatelessWidget {
  /// The count to display in the badge.
  ///
  /// If null (default), automatically fetches count from AppState.unreadNotificationCount
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
  Widget build(BuildContext context) {
    // If count is provided manually, use it directly without BlocBuilder
    if (count != null) {
      return _buildBadge(context, count!);
    }

    // Otherwise, use BlocBuilder to get count from AppCubit
    return BlocSelector<AppCubit, AppState, int>(
      selector: (state) => state.unreadNotificationCount,
      builder: (context, unreadCount) {
        return _buildBadge(context, unreadCount);
      },
    );
  }

  Widget _buildBadge(BuildContext context, int displayCount) {
    // Hide badge if count is zero and hideWhenZero is true
    if (hideWhenZero && displayCount == 0) {
      return child;
    }

    // Hide badge if explicitly disabled
    if (!isLabelVisible) {
      return child;
    }

    // Format count with overflow indicator
    final displayText =
        displayCount > maxCount ? '$maxCount+' : displayCount.toString();

    final theme = Theme.of(context);
    final badgeColor = backgroundColor ?? theme.colorScheme.error;
    final countColor = textColor ?? theme.colorScheme.onError;

    return Badge(
      label: Text(displayText),
      backgroundColor: badgeColor,
      textColor: countColor,
      alignment: alignment,
      offset: offset,
      textStyle: textStyle,
      child: child,
    );
  }
}
