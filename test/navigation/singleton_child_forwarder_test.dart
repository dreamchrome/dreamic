import 'package:auto_route/auto_route.dart';
import 'package:dreamic/navigation/child_forwarder/singleton_child_forwarder.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Test route stubs — minimal PageRouteInfo subclasses for forwarding tests.
// These mirror the pattern auto_route's codegen produces.
// ---------------------------------------------------------------------------

class _TestRoute extends PageRouteInfo<void> {
  const _TestRoute({List<PageRouteInfo>? children})
      : super('TestRoute', initialChildren: children);
  static const String name = 'TestRoute';
}

class _TestChildRoute extends PageRouteInfo<void> {
  const _TestChildRoute() : super('TestChildRoute');
  static const String name = 'TestChildRoute';
}

class _TestGrandchildRoute extends PageRouteInfo<void> {
  const _TestGrandchildRoute() : super('TestGrandchildRoute');
  static const String name = 'TestGrandchildRoute';
}

// ---------------------------------------------------------------------------

void main() {
  const routeName = 'TestRoute';
  const otherRouteName = 'OtherRoute';

  /// Drains pending children (if any) and clears the listener for the given
  /// route name, leaving the forwarder in a clean state for the next test.
  void cleanForwarder(String name) {
    final forwarder = SingletonChildForwarder.forRoute(name);
    // A non-null listener drains _pendingChildren on registration.
    forwarder.setListener((_) {});
    // Setting null clears _listener.
    forwarder.setListener(null);
  }

  tearDown(() {
    cleanForwarder(routeName);
    cleanForwarder(otherRouteName);
  });

  group('SingletonChildForwarder', () {
    // ----- forRoute() factory -----

    group('forRoute', () {
      test('returns the same instance for the same route name', () {
        final a = SingletonChildForwarder.forRoute(routeName);
        final b = SingletonChildForwarder.forRoute(routeName);
        expect(identical(a, b), isTrue);
      });

      test('returns different instances for different route names', () {
        final a = SingletonChildForwarder.forRoute(routeName);
        final b = SingletonChildForwarder.forRoute(otherRouteName);
        expect(identical(a, b), isFalse);
      });
    });

    // ----- Immediate delivery (listener already registered) -----

    group('forward with listener registered', () {
      test('delivers children immediately when listener is registered', () {
        List<PageRouteInfo>? received;
        SingletonChildForwarder.forRoute(routeName)
            .setListener((children) => received = children);

        SingletonChildForwarder.forRoute(routeName)
            .forward([const _TestChildRoute()]);

        expect(received, isNotNull);
        expect(received!.length, 1);
        expect(received!.first.routeName, _TestChildRoute.name);
      });

      test('delivers multiple children preserving order', () {
        List<PageRouteInfo>? received;
        SingletonChildForwarder.forRoute(routeName)
            .setListener((children) => received = children);

        SingletonChildForwarder.forRoute(routeName)
            .forward([const _TestChildRoute(), const _TestRoute()]);

        expect(received, isNotNull);
        expect(received!.length, 2);
        expect(received![0].routeName, _TestChildRoute.name);
        expect(received![1].routeName, _TestRoute.name);
      });

      test('delivers children with nested hierarchy intact', () {
        List<PageRouteInfo>? received;
        SingletonChildForwarder.forRoute(routeName)
            .setListener((children) => received = children);

        // Simulate a deep link: HomeWrapper → Settings → Profile
        final nestedRoute = _TestRoute(
          children: [const _TestGrandchildRoute()],
        );
        SingletonChildForwarder.forRoute(routeName).forward([nestedRoute]);

        expect(received, isNotNull);
        expect(received!.length, 1);
        expect(received!.first.routeName, _TestRoute.name);
        expect(
          received!.first.initialChildren?.first.routeName,
          _TestGrandchildRoute.name,
        );
      });

      test('each forward call delivers independently', () {
        final deliveries = <List<PageRouteInfo>>[];
        SingletonChildForwarder.forRoute(routeName)
            .setListener((children) => deliveries.add(children));

        SingletonChildForwarder.forRoute(routeName)
            .forward([const _TestChildRoute()]);
        SingletonChildForwarder.forRoute(routeName)
            .forward([const _TestRoute()]);

        expect(deliveries.length, 2);
        expect(deliveries[0].first.routeName, _TestChildRoute.name);
        expect(deliveries[1].first.routeName, _TestRoute.name);
      });
    });

    // ----- Queuing (no listener when forward() is called) -----

    group('forward without listener (queuing)', () {
      test('queues children and delivers when listener registers', () {
        // Forward without a listener — children are queued.
        SingletonChildForwarder.forRoute(routeName)
            .forward([const _TestChildRoute()]);

        // Register listener — queued children are delivered immediately.
        List<PageRouteInfo>? received;
        SingletonChildForwarder.forRoute(routeName)
            .setListener((children) => received = children);

        expect(received, isNotNull);
        expect(received!.length, 1);
        expect(received!.first.routeName, _TestChildRoute.name);
      });

      test('clears pending children after delivery — no re-delivery', () {
        // Queue children.
        SingletonChildForwarder.forRoute(routeName)
            .forward([const _TestChildRoute()]);

        // First listener drains the queue.
        int callCount = 0;
        SingletonChildForwarder.forRoute(routeName)
            .setListener((_) => callCount++);
        expect(callCount, 1);

        // Remove listener and re-register — should NOT re-deliver.
        SingletonChildForwarder.forRoute(routeName).setListener(null);
        SingletonChildForwarder.forRoute(routeName)
            .setListener((_) => callCount++);
        expect(callCount, 1); // Still 1 — no re-delivery.
      });

      test('last forward() replaces previously queued children', () {
        // Forward twice without a listener — second replaces first.
        SingletonChildForwarder.forRoute(routeName)
            .forward([const _TestChildRoute()]);
        SingletonChildForwarder.forRoute(routeName)
            .forward([const _TestRoute(), const _TestGrandchildRoute()]);

        // Register listener — only the second batch is delivered.
        List<PageRouteInfo>? received;
        SingletonChildForwarder.forRoute(routeName)
            .setListener((children) => received = children);

        expect(received, isNotNull);
        expect(received!.length, 2);
        expect(received![0].routeName, _TestRoute.name);
        expect(received![1].routeName, _TestGrandchildRoute.name);
      });
    });

    // ----- Listener management -----

    group('setListener', () {
      test('after removing listener, new forwards are queued', () {
        // Set and then remove listener.
        SingletonChildForwarder.forRoute(routeName)
            .setListener((_) {});
        SingletonChildForwarder.forRoute(routeName).setListener(null);

        // Forward — should queue because listener is now null.
        SingletonChildForwarder.forRoute(routeName)
            .forward([const _TestChildRoute()]);

        // Register new listener — queued children are delivered.
        List<PageRouteInfo>? received;
        SingletonChildForwarder.forRoute(routeName)
            .setListener((children) => received = children);

        expect(received, isNotNull);
        expect(received!.length, 1);
      });

      test('replacing listener routes deliveries to the new one', () {
        List<PageRouteInfo>? firstReceived;
        List<PageRouteInfo>? secondReceived;

        // Register first listener.
        SingletonChildForwarder.forRoute(routeName)
            .setListener((children) => firstReceived = children);

        // Replace with second listener.
        SingletonChildForwarder.forRoute(routeName)
            .setListener((children) => secondReceived = children);

        // Forward — should go to second listener only.
        SingletonChildForwarder.forRoute(routeName)
            .forward([const _TestChildRoute()]);

        expect(firstReceived, isNull);
        expect(secondReceived, isNotNull);
        expect(secondReceived!.length, 1);
      });

      test('setting listener to null with no pending children is safe', () {
        // Should not throw or misbehave.
        SingletonChildForwarder.forRoute(routeName).setListener(null);
      });
    });

    // ----- Instance isolation -----

    group('route name isolation', () {
      test('forwarding to one route does not affect another', () {
        List<PageRouteInfo>? routeAReceived;
        List<PageRouteInfo>? routeBReceived;

        SingletonChildForwarder.forRoute(routeName)
            .setListener((children) => routeAReceived = children);
        SingletonChildForwarder.forRoute(otherRouteName)
            .setListener((children) => routeBReceived = children);

        // Forward only to routeName.
        SingletonChildForwarder.forRoute(routeName)
            .forward([const _TestChildRoute()]);

        expect(routeAReceived, isNotNull);
        expect(routeBReceived, isNull);
      });

      test('queuing for one route does not affect another', () {
        // Queue children for routeName (no listener).
        SingletonChildForwarder.forRoute(routeName)
            .forward([const _TestChildRoute()]);

        // Register listener for otherRouteName — should NOT receive anything.
        List<PageRouteInfo>? received;
        SingletonChildForwarder.forRoute(otherRouteName)
            .setListener((children) => received = children);

        expect(received, isNull);
      });
    });
  });
}
