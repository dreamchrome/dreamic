import 'package:auto_route/auto_route.dart';

import '../../utils/logger.dart';
import '../child_forwarder/singleton_child_forwarder.dart';

/// Generic guard that prevents duplicate instances of a singleton route.
///
/// Usage in route configuration:
/// ```dart
/// AutoRoute(
///   page: HomeWrapperRoute.page,
///   guards: [
///     SingletonRouteGuard.forRoute(HomeWrapperRoute.name),
///   ],
/// )
/// ```
///
/// This guard intercepts `navigate()`, `push()`, `replace()`, and path-based
/// navigation calls. It does NOT protect against `replaceAll()` because
/// `replaceAll` clears the stack before guards run — use the
/// [navigateToSingleton] extension method for `replaceAll` use cases.
///
/// Safe for initial routes: On cold start the stack is empty, so the guard
/// finds no matches and allows navigation through. No special handling needed.
class SingletonRouteGuard extends AutoRouteGuard {
  /// The route name to protect (use the static `.name` property from generated
  /// routes, e.g. `HomeWrapperRoute.name`).
  final String routeName;

  /// Optional: Custom message for debug logs when a duplicate is prevented.
  final String? customLogMessage;

  const SingletonRouteGuard.forRoute(
    this.routeName, {
    this.customLogMessage,
  });

  @override
  void onNavigation(NavigationResolver resolver, StackRouter router) {
    // Check if route already exists in stack
    final matches = router.root.stack.where(
      (page) => page.routeData.name == routeName,
    );
    final exists = matches.isNotEmpty;

    // Detect multiple instances — indicates a bug bypassed our protection
    if (matches.length > 1) {
      loge(
        'SingletonRouteGuard: ${matches.length} instances of $routeName '
        'found in stack. This should never happen — something bypassed '
        'singleton protection. Popping to topmost occurrence.',
      );
    }

    if (exists) {
      // Duplicate detected — pop to existing instance instead of creating a
      // new one. NOTE: If triggered via replace()/replacePath(), the last page
      // has already been removed before this guard runs. popUntil then removes
      // additional pages above the existing singleton. Net effect: more pages
      // removed than a replace() caller might expect, but the end state is
      // correct (user lands on the existing singleton). See coverage table in
      // the plan document.
      final message = customLogMessage ??
          'SingletonRouteGuard: Duplicate $routeName prevented — '
              'popping to existing instance';
      logd(message);

      try {
        // CRITICAL: Use .root to ensure we pop at root level
        router.root.popUntil((route) => route.data?.name == routeName);

        // DEEP LINK SUPPORT: Forward child routes to the existing singleton
        // via the SingletonChildForwarder. The forwarder delivers children to
        // the singleton widget's mixin listener, which navigates using its own
        // inner router reference (captured in the widget's build method).
        //
        // This fires synchronously: forward() → listener → innerRouter.navigate().
        // The singleton is already mounted (popUntil only removed routes above
        // it), so the listener and inner router are immediately available.
        //
        // If the singleton widget doesn't use SingletonRouteMixin (no listener
        // registered), children are queued and a warning is logged. They will
        // be delivered when/if the listener is registered, or dropped if never
        // registered. See SingletonChildForwarder and SingletonRouteMixin.
        final childMatches = resolver.route.children;
        if (childMatches != null && childMatches.isNotEmpty) {
          logd(
            'SingletonRouteGuard: Forwarding ${childMatches.length} '
            'child route(s) to existing $routeName',
          );
          final childRoutes =
              childMatches.map((m) => m.toPageRouteInfo()).toList();
          SingletonChildForwarder.forRoute(routeName).forward(childRoutes);
        }

        // popUntil succeeded — block the duplicate parent navigation
        resolver.next(false);
      } catch (e) {
        // popUntil failed — allow navigation as a safety valve rather than
        // leaving the user stuck. A duplicate singleton is less harmful than
        // a navigation dead-end. The error log ensures this gets fixed.
        loge(
          e,
          'SingletonRouteGuard: popUntil failed for $routeName, '
          'allowing navigation as fallback',
        );
        resolver.next(true);
      }
    } else {
      // No existing instance — allow navigation (cold start or first entry)
      logd('SingletonRouteGuard: No existing $routeName — allowing navigation');
      resolver.next(true);
    }
  }
}
