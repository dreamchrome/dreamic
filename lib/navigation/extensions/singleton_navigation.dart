import 'package:auto_route/auto_route.dart';

import '../../utils/logger.dart';
import '../child_forwarder/singleton_child_forwarder.dart';

/// Tracks in-flight singleton navigations for race detection (diagnostic only).
///
/// This does NOT block navigation — it only reports concurrent calls as errors
/// so developers can fix the architectural issue in the consuming app.
/// Dart's single-threaded model makes true races nearly impossible, but if
/// two code paths do fire for the same route, the deduplication logic in
/// [SingletonNavigation.navigateToSingleton] handles correctness regardless.
///
/// Hot reload note: Static state survives hot reload. If a hot reload occurs
/// during the microsecond window of an in-flight navigation, the `finally`
/// block may not execute, leaving a stale entry in [_inFlight]. This causes
/// exactly one false-positive race warning on the next navigation to that
/// route, which self-clears after that invocation. This is dev-only and
/// harmless — no fix is warranted.
class _SingletonNavigationTracker {
  static final Set<String> _inFlight = {};

  /// Returns true if this route is already being navigated to (race detected).
  static bool markInFlight(String routeName) {
    if (_inFlight.contains(routeName)) return true; // Race detected
    _inFlight.add(routeName);
    return false;
  }

  static void markComplete(String routeName) {
    _inFlight.remove(routeName);
  }
}

/// Extension on [StackRouter] providing smart navigation to singleton routes
/// that prevents duplicate route instances.
extension SingletonNavigation on StackRouter {
  /// Navigates to a singleton route intelligently without creating duplicates:
  /// - If the route already exists in stack: pops to it
  /// - If the route does not exist: creates new stack with `replaceAll`
  ///
  /// IMPORTANT: Always uses `.root` to operate at root navigation level,
  /// ensuring correct behavior when called from nested routers (tabs) or
  /// fullscreen dialogs.
  ///
  /// Race detection: If two calls to this method for the same route overlap,
  /// an error is logged to surface the architectural issue. Navigation is never
  /// blocked — the stack-check deduplication ensures correctness regardless.
  ///
  /// Use this instead of direct `replaceAll([SomeRoute()])` calls for singleton
  /// routes.
  ///
  /// Example usage:
  /// ```dart
  /// await router.navigateToSingleton(const HomeWrapperRoute());
  /// await router.navigateToSingleton(DashboardRoute());
  /// await router.navigateToSingleton(AuthWrapperRoute(mode: AuthMode.login));
  /// ```
  ///
  /// Type-safe: Accepts any [PageRouteInfo], uses generated route name for
  /// matching.
  Future<void> navigateToSingleton(PageRouteInfo route) async {
    // Race detection — log error but never block navigation
    final isRace = _SingletonNavigationTracker.markInFlight(route.routeName);
    if (isRace) {
      loge(
        'navigateToSingleton: Concurrent call to ${route.routeName} detected. '
        'This indicates two code paths are racing to navigate to the same '
        'singleton route. Fix the calling code to prevent this.',
      );
    }

    try {
      // CRITICAL: Use root.stack because singleton routes are typically at
      // root level but this extension might be called from nested router
      // contexts
      final matches = root.stack.where(
        (r) => r.routeData.name == route.routeName,
      );
      final exists = matches.isNotEmpty;

      // Detect multiple instances — indicates a bug bypassed our protection
      if (matches.length > 1) {
        loge(
          'navigateToSingleton: ${matches.length} instances of '
          '${route.routeName} found in stack. This should never happen — '
          'something bypassed singleton protection. Popping to topmost '
          'occurrence.',
        );
      }

      if (exists) {
        // Route already exists — pop back to it (prevent duplicate)
        logd(
          'navigateToSingleton: ${route.routeName} exists, popping to it',
        );

        try {
          // Use root.popUntil to ensure we pop at root level
          root.popUntil((r) => r.data?.name == route.routeName);

          // DEEP LINK SUPPORT: Forward child routes to the existing singleton
          // via the SingletonChildForwarder. See guard comments and
          // SingletonChildForwarder/SingletonRouteMixin for full details.
          final children = route.initialChildren;
          if (children != null && children.isNotEmpty) {
            logd(
              'navigateToSingleton: Forwarding ${children.length} '
              'child route(s) to existing ${route.routeName}',
            );
            SingletonChildForwarder.forRoute(route.routeName)
                .forward(children);
          }
        } catch (e) {
          loge(
            e,
            'navigateToSingleton: Error during popUntil, '
            'falling back to replaceAll',
          );
          await root.replaceAll([route]);
        }
      } else {
        // Cold start or no existing instance — create fresh stack
        logd(
          'navigateToSingleton: ${route.routeName} does not exist, '
          'creating new stack',
        );
        // Use root.replaceAll to ensure we replace at root level
        await root.replaceAll([route]);
      }
    } catch (e) {
      // Reaches here if:
      // - root.stack.where() threw (router in bad state)
      // - replaceAll threw (in either the inner catch fallback or the else
      //   branch)
      // Don't retry replaceAll — if it already failed, the router is unusable.
      // Log the error for diagnostics and rethrow so the caller knows
      // navigation failed.
      loge(
        e,
        'navigateToSingleton: Navigation failed for ${route.routeName} — '
        'router may be in unstable state',
      );
      rethrow;
    } finally {
      _SingletonNavigationTracker.markComplete(route.routeName);
    }
  }

  /// Checks if a singleton route already exists in the stack.
  /// Useful for conditional logic before navigation.
  ///
  /// Example:
  /// ```dart
  /// if (!router.singletonExists(HomeWrapperRoute.name)) {
  ///   // Perform one-time setup
  /// }
  /// ```
  bool singletonExists(String routeName) {
    return root.stack.any((r) => r.routeData.name == routeName);
  }

  /// Alternative version that accepts [PageRouteInfo] for type safety.
  bool singletonExistsFor(PageRouteInfo route) {
    return singletonExists(route.routeName);
  }
}
