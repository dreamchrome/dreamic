import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';

import '../../utils/logger.dart';
import '../child_forwarder/singleton_child_forwarder.dart';

/// Mixin for singleton route page widgets that enables deep link child
/// forwarding. When the guard or extension prevents a duplicate singleton
/// and forwards child routes, this mixin receives them and navigates
/// using the widget's own inner router.
///
/// ## Setup (2 steps in the consuming app):
///
/// 1. Add the mixin to your page's State class and override
///    [singletonRouteName]
/// 2. Set [innerRouter] from your AutoTabsRouter/AutoRouter builder callback
///
/// ```dart
/// class _HomeWrapperPageState extends State<HomeWrapperPage>
///     with SingletonRouteMixin {
///   @override
///   String get singletonRouteName => HomeWrapperRoute.name;
///
///   @override
///   Widget build(BuildContext context) {
///     return AutoTabsRouter(
///       routes: const [...],
///       builder: (context, child) {
///         innerRouter = context.tabsRouter; // captures inner router
///         return Scaffold(body: child, ...);
///       },
///     );
///   }
/// }
/// ```
///
/// ## How it works:
///
/// - In [initState], registers a listener with [SingletonChildForwarder]
/// - When children are forwarded (from guard or extension), the listener fires
///   synchronously and calls `innerRouter.navigate()` for each child
/// - In [dispose], removes the listener to prevent leaks
///
/// ## Important: Setting [innerRouter]
///
/// The [innerRouter] property MUST be set from the AutoTabsRouter/AutoRouter
/// builder callback. This is because `context.router` from the page widget
/// itself returns the PARENT router (root StackRouter), not the inner
/// TabsRouter/StackRouter created by the page's AutoTabsRouter widget.
/// The builder callback's context is inside the AutoTabsRouter subtree,
/// so `context.tabsRouter` or `context.router` there returns the correct
/// inner router.
///
/// If [innerRouter] is not set when children arrive, an error is logged
/// pointing to this requirement.
mixin SingletonRouteMixin<T extends StatefulWidget> on State<T> {
  /// The route name this singleton is registered under.
  /// Must match the name used in `SingletonRouteGuard.forRoute()`.
  String get singletonRouteName;

  /// The inner router for this singleton's child navigation.
  /// Set this from the AutoTabsRouter/AutoRouter builder callback.
  ///
  /// Example:
  /// ```dart
  /// builder: (context, child) {
  ///   innerRouter = context.tabsRouter;
  ///   return Scaffold(body: child);
  /// }
  /// ```
  @protected
  RoutingController? innerRouter;

  @override
  void initState() {
    super.initState();
    SingletonChildForwarder.forRoute(singletonRouteName)
        .setListener(_onChildrenForwarded);
  }

  void _onChildrenForwarded(List<PageRouteInfo> children) {
    if (innerRouter != null) {
      logd(
        'SingletonRouteMixin: Forwarding ${children.length} '
        'child route(s) to $singletonRouteName',
      );
      for (final child in children) {
        innerRouter!.navigate(child);
      }
    } else {
      // innerRouter not set — this is a setup error in the consuming app.
      // Log with loge() to report to Crashlytics so it gets fixed.
      loge(
        'SingletonRouteMixin: innerRouter is null for $singletonRouteName — '
        'cannot forward ${children.length} child route(s). '
        'FIX: Set innerRouter = context.tabsRouter (or context.router) in '
        'your AutoTabsRouter/AutoRouter builder callback. See '
        'SingletonRouteMixin documentation for setup instructions.',
      );
    }
  }

  @override
  void dispose() {
    SingletonChildForwarder.forRoute(singletonRouteName).setListener(null);
    super.dispose();
  }
}
