import 'package:auto_route/auto_route.dart';

import '../../utils/logger.dart';

/// Lightweight single-listener channel that forwards child routes from the
/// [SingletonRouteGuard] or [navigateToSingleton] extension to the singleton
/// widget that owns the inner router.
///
/// Flow:
/// 1. Guard/extension calls [forward] after popUntil
/// 2. If a listener is registered (widget is mounted): delivers immediately
/// 3. If no listener yet (edge case): queues children for later delivery
///
/// Each singleton route gets its own forwarder instance, keyed by route name.
/// Instances are created lazily and cached for the app's lifetime.
///
/// This class is framework-independent — it doesn't depend on auto_route
/// internals for inner router access. The singleton widget handles navigation
/// using its own `context.tabsRouter` / `context.router` from the builder.
class SingletonChildForwarder {
  static final Map<String, SingletonChildForwarder> _instances = {};

  /// Returns the forwarder for the given route name.
  /// Creates one on first access; returns the cached instance thereafter.
  static SingletonChildForwarder forRoute(String routeName) {
    return _instances.putIfAbsent(
      routeName,
      () => SingletonChildForwarder._(),
    );
  }

  SingletonChildForwarder._();

  void Function(List<PageRouteInfo> children)? _listener;
  List<PageRouteInfo>? _pendingChildren;

  /// Called by the singleton widget (via `SingletonRouteMixin`) to register
  /// its child-navigation handler.
  ///
  /// If children were forwarded before the listener was set (queued), they
  /// are delivered immediately upon registration.
  void setListener(void Function(List<PageRouteInfo> children)? listener) {
    _listener = listener;
    // Deliver any children that arrived before the listener was set
    if (listener != null && _pendingChildren != null) {
      logd(
        'SingletonChildForwarder: Delivering ${_pendingChildren!.length} '
        'queued child route(s)',
      );
      listener(_pendingChildren!);
      _pendingChildren = null;
    }
  }

  /// Called by the guard or extension after popUntil to forward child routes.
  ///
  /// If a listener is registered: delivers synchronously (within the same
  /// microtask as the guard's onNavigation). If no listener: queues children
  /// and logs a warning.
  void forward(List<PageRouteInfo> children) {
    if (_listener != null) {
      _listener!(children);
    } else {
      // Queue for delivery when listener registers.
      // This should not happen on warm start (widget is already mounted),
      // but handles edge cases gracefully.
      _pendingChildren = children;
      logw(
        'SingletonChildForwarder: No listener registered — queuing '
        '${children.length} child route(s). If this persists, ensure the '
        'singleton widget uses SingletonRouteMixin.',
      );
    }
  }
}
