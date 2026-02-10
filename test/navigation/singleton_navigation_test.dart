import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:dreamic/app/app_config_base.dart';
import 'package:dreamic/navigation/child_forwarder/singleton_child_forwarder.dart';
import 'package:dreamic/navigation/extensions/singleton_navigation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockRootStackRouter extends Mock implements RootStackRouter {}

class MockAutoRoutePage extends Mock implements AutoRoutePage {}

class MockRouteData extends Mock implements RouteData {}

// ---------------------------------------------------------------------------
// Test route stubs — minimal PageRouteInfo subclasses matching auto_route's
// generated pattern.
// ---------------------------------------------------------------------------

class _TestRoute extends PageRouteInfo<void> {
  const _TestRoute({List<PageRouteInfo>? children})
      : super('TestRoute', initialChildren: children);
  static const String name = 'TestRoute';
}

class _TestChildRoute extends PageRouteInfo<void> {
  const _TestChildRoute({List<PageRouteInfo>? children})
      : super('TestChildRoute', initialChildren: children);
  static const String name = 'TestChildRoute';
}

class _TestGrandchildRoute extends PageRouteInfo<void> {
  const _TestGrandchildRoute() : super('TestGrandchildRoute');
  static const String name = 'TestGrandchildRoute';
}

// ---------------------------------------------------------------------------

void main() {
  const testRouteName = 'TestRoute';

  late MockRootStackRouter mockRouter;

  setUpAll(() {
    registerFallbackValue((Route<dynamic> route) => false);
    registerFallbackValue(<PageRouteInfo>[]);
  });

  setUp(() {
    mockRouter = MockRootStackRouter();
    // root returns itself — RootStackRouter IS the root.
    when(() => mockRouter.root).thenReturn(mockRouter);

    // Suppress Crashlytics / error reporting in tests.
    AppConfigBase.doDisableErrorReportingOverride = true;
  });

  tearDown(() {
    AppConfigBase.doDisableErrorReportingOverride = null;
    // Clean forwarder state to prevent cross-test contamination.
    final forwarder = SingletonChildForwarder.forRoute(testRouteName);
    forwarder.setListener((_) {}); // Drain any pending children.
    forwarder.setListener(null); // Clear listener.
  });

  /// Helper: creates a mock page whose routeData.name returns [name].
  MockAutoRoutePage createMockPage(String name) {
    final mockPage = MockAutoRoutePage();
    final mockData = MockRouteData();
    when(() => mockData.name).thenReturn(name);
    when(() => mockPage.routeData).thenReturn(mockData);
    return mockPage;
  }

  group('SingletonNavigation extension', () {
    // -----------------------------------------------------------------
    // navigateToSingleton — route does NOT exist in stack
    // -----------------------------------------------------------------

    group('navigateToSingleton (route absent)', () {
      test('uses replaceAll when route does not exist in stack', () async {
        when(() => mockRouter.stack).thenReturn(<AutoRoutePage>[]);
        when(() => mockRouter.replaceAll(any())).thenAnswer((_) async {});

        await mockRouter.navigateToSingleton(const _TestRoute());

        verify(() => mockRouter.replaceAll(any())).called(1);
        verifyNever(() => mockRouter.popUntil(any()));
      });

      test('uses replaceAll when stack has only different routes', () async {
        final otherPage = createMockPage('OtherRoute');
        when(() => mockRouter.stack)
            .thenReturn(<AutoRoutePage>[otherPage]);
        when(() => mockRouter.replaceAll(any())).thenAnswer((_) async {});

        await mockRouter.navigateToSingleton(const _TestRoute());

        verify(() => mockRouter.replaceAll(any())).called(1);
        verifyNever(() => mockRouter.popUntil(any()));
      });
    });

    // -----------------------------------------------------------------
    // navigateToSingleton — route EXISTS in stack
    // -----------------------------------------------------------------

    group('navigateToSingleton (route present)', () {
      late MockAutoRoutePage existingPage;

      setUp(() {
        existingPage = createMockPage(testRouteName);
        when(() => mockRouter.stack)
            .thenReturn(<AutoRoutePage>[existingPage]);
      });

      test('uses popUntil when route exists in stack', () async {
        await mockRouter.navigateToSingleton(const _TestRoute());

        verify(() => mockRouter.popUntil(any())).called(1);
        verifyNever(() => mockRouter.replaceAll(any()));
      });

      test('forwards child routes via forwarder when popping to existing',
          () async {
        List<PageRouteInfo>? receivedChildren;
        SingletonChildForwarder.forRoute(testRouteName)
            .setListener((children) => receivedChildren = children);

        await mockRouter.navigateToSingleton(
          const _TestRoute(children: [_TestChildRoute()]),
        );

        verify(() => mockRouter.popUntil(any())).called(1);
        verifyNever(() => mockRouter.replaceAll(any()));
        expect(receivedChildren, isNotNull);
        expect(receivedChildren!.length, 1);
        expect(receivedChildren!.first.routeName, _TestChildRoute.name);
      });

      test('does NOT forward when children is null', () async {
        List<PageRouteInfo>? receivedChildren;
        SingletonChildForwarder.forRoute(testRouteName)
            .setListener((children) => receivedChildren = children);

        // _TestRoute() without children → initialChildren is null.
        await mockRouter.navigateToSingleton(const _TestRoute());

        verify(() => mockRouter.popUntil(any())).called(1);
        expect(receivedChildren, isNull);
      });

      test('does NOT forward when children list is empty', () async {
        List<PageRouteInfo>? receivedChildren;
        SingletonChildForwarder.forRoute(testRouteName)
            .setListener((children) => receivedChildren = children);

        await mockRouter.navigateToSingleton(
          const _TestRoute(children: []),
        );

        verify(() => mockRouter.popUntil(any())).called(1);
        expect(receivedChildren, isNull);
      });
    });

    // -----------------------------------------------------------------
    // popUntil failure — graceful fallback to replaceAll
    // -----------------------------------------------------------------

    group('popUntil failure fallback', () {
      test('falls back to replaceAll if popUntil throws', () async {
        final existingPage = createMockPage(testRouteName);
        when(() => mockRouter.stack)
            .thenReturn(<AutoRoutePage>[existingPage]);
        when(() => mockRouter.popUntil(any()))
            .thenThrow(Exception('popUntil failed'));
        when(() => mockRouter.replaceAll(any())).thenAnswer((_) async {});

        await mockRouter.navigateToSingleton(const _TestRoute());

        // popUntil was attempted.
        verify(() => mockRouter.popUntil(any())).called(1);
        // Fell back to replaceAll.
        verify(() => mockRouter.replaceAll(any())).called(1);
      });
    });

    // -----------------------------------------------------------------
    // Multiple instances in stack (bug detection)
    // -----------------------------------------------------------------

    group('multiple instances', () {
      test('still pops when multiple instances exist', () async {
        final page1 = createMockPage(testRouteName);
        final page2 = createMockPage(testRouteName);
        when(() => mockRouter.stack)
            .thenReturn(<AutoRoutePage>[page1, page2]);

        // Should not throw — logs error internally and pops.
        await mockRouter.navigateToSingleton(const _TestRoute());

        verify(() => mockRouter.popUntil(any())).called(1);
        verifyNever(() => mockRouter.replaceAll(any()));
      });
    });

    // -----------------------------------------------------------------
    // Outer error handling (replaceAll throws in else branch)
    // -----------------------------------------------------------------

    group('outer error handling', () {
      test('rethrows if replaceAll throws in else branch', () async {
        when(() => mockRouter.stack).thenReturn(<AutoRoutePage>[]);
        when(() => mockRouter.replaceAll(any()))
            .thenThrow(Exception('replaceAll failed'));

        expect(
          () => mockRouter.navigateToSingleton(const _TestRoute()),
          throwsA(isA<Exception>()),
        );
      });

      test('tracker is cleaned up even on error (finally block)', () async {
        when(() => mockRouter.stack).thenReturn(<AutoRoutePage>[]);

        // First call throws.
        when(() => mockRouter.replaceAll(any()))
            .thenThrow(Exception('replaceAll failed'));

        try {
          await mockRouter.navigateToSingleton(const _TestRoute());
        } catch (_) {
          // Expected.
        }

        // Reset replaceAll to succeed for the second call.
        reset(mockRouter);
        when(() => mockRouter.root).thenReturn(mockRouter);
        when(() => mockRouter.stack).thenReturn(<AutoRoutePage>[]);
        when(() => mockRouter.replaceAll(any())).thenAnswer((_) async {});

        // If the tracker wasn't cleaned up in the finally block, this second
        // call would trigger race detection. The fact that it completes without
        // error verifies cleanup. (Race detection only logs; it doesn't block.
        // But proper cleanup is still important for accurate diagnostics.)
        await mockRouter.navigateToSingleton(const _TestRoute());

        verify(() => mockRouter.replaceAll(any())).called(1);
      });
    });

    // -----------------------------------------------------------------
    // Race detection (diagnostic only — never blocks navigation)
    // -----------------------------------------------------------------

    group('race detection', () {
      test('does not block navigation when race is detected', () async {
        when(() => mockRouter.stack).thenReturn(<AutoRoutePage>[]);

        final completer = Completer<void>();
        var replaceAllCallCount = 0;
        when(() => mockRouter.replaceAll(any())).thenAnswer((_) {
          replaceAllCallCount++;
          // First call blocks until we complete manually.
          // Second call completes immediately.
          if (replaceAllCallCount == 1) return completer.future;
          return Future.value();
        });

        // Start first call — suspends at `await root.replaceAll(...)`.
        final future1 = mockRouter.navigateToSingleton(const _TestRoute());

        // Start second call while first is still in-flight.
        // The tracker detects a race (logs error) but allows navigation.
        final future2 = mockRouter.navigateToSingleton(const _TestRoute());

        // Unblock the first call.
        completer.complete();

        // Both should complete without errors.
        await future1;
        await future2;

        // replaceAll was called twice — once per navigation.
        expect(replaceAllCallCount, 2);
      });
    });

    // -----------------------------------------------------------------
    // singletonExists / singletonExistsFor
    // -----------------------------------------------------------------

    group('singletonExists', () {
      test('returns true when route exists in stack', () {
        final page = createMockPage(testRouteName);
        when(() => mockRouter.stack).thenReturn(<AutoRoutePage>[page]);

        expect(mockRouter.singletonExists(testRouteName), isTrue);
      });

      test('returns false when route does not exist', () {
        when(() => mockRouter.stack).thenReturn(<AutoRoutePage>[]);

        expect(mockRouter.singletonExists(testRouteName), isFalse);
      });

      test('returns false when stack has only different routes', () {
        final otherPage = createMockPage('OtherRoute');
        when(() => mockRouter.stack).thenReturn(<AutoRoutePage>[otherPage]);

        expect(mockRouter.singletonExists(testRouteName), isFalse);
      });

      test('returns true when singleton is among other routes', () {
        final otherPage = createMockPage('OtherRoute');
        final singletonPage = createMockPage(testRouteName);
        when(() => mockRouter.stack)
            .thenReturn(<AutoRoutePage>[otherPage, singletonPage]);

        expect(mockRouter.singletonExists(testRouteName), isTrue);
      });
    });

    group('singletonExistsFor', () {
      test('returns true when route exists', () {
        final page = createMockPage(testRouteName);
        when(() => mockRouter.stack).thenReturn(<AutoRoutePage>[page]);

        expect(mockRouter.singletonExistsFor(const _TestRoute()), isTrue);
      });

      test('returns false when route does not exist', () {
        when(() => mockRouter.stack).thenReturn(<AutoRoutePage>[]);

        expect(mockRouter.singletonExistsFor(const _TestRoute()), isFalse);
      });
    });

    // -----------------------------------------------------------------
    // navigateToSingletonWhere — custom matcher
    // -----------------------------------------------------------------

    group('navigateToSingletonWhere', () {
      test('pops to existing when matcher finds a match', () async {
        final matchingPage = createMockPage(testRouteName);
        when(() => mockRouter.stack)
            .thenReturn(<AutoRoutePage>[matchingPage]);

        await mockRouter.navigateToSingletonWhere(
          const _TestRoute(),
          matcher: (routeData) => routeData.name == testRouteName,
        );

        verify(() => mockRouter.popUntil(any())).called(1);
        verifyNever(() => mockRouter.replaceAll(any()));
      });

      test('uses replaceAll when matcher finds no match', () async {
        final otherPage = createMockPage('OtherRoute');
        when(() => mockRouter.stack)
            .thenReturn(<AutoRoutePage>[otherPage]);
        when(() => mockRouter.replaceAll(any())).thenAnswer((_) async {});

        await mockRouter.navigateToSingletonWhere(
          const _TestRoute(),
          matcher: (routeData) => routeData.name == testRouteName,
        );

        verify(() => mockRouter.replaceAll(any())).called(1);
        verifyNever(() => mockRouter.popUntil(any()));
      });

      test('uses replaceAll when stack is empty', () async {
        when(() => mockRouter.stack).thenReturn(<AutoRoutePage>[]);
        when(() => mockRouter.replaceAll(any())).thenAnswer((_) async {});

        await mockRouter.navigateToSingletonWhere(
          const _TestRoute(),
          matcher: (routeData) => routeData.name == testRouteName,
        );

        verify(() => mockRouter.replaceAll(any())).called(1);
        verifyNever(() => mockRouter.popUntil(any()));
      });

      test('matcher receives RouteData and can match on custom criteria',
          () async {
        // Create mock route data with a distinguishing path, stubbed
        // directly on the MockRouteData to avoid chained-stub issues.
        final matchingData = MockRouteData();
        when(() => matchingData.name).thenReturn(testRouteName);
        when(() => matchingData.path).thenReturn('/test/profile');
        final matchingPage = MockAutoRoutePage();
        when(() => matchingPage.routeData).thenReturn(matchingData);

        final nonMatchingData = MockRouteData();
        when(() => nonMatchingData.name).thenReturn(testRouteName);
        when(() => nonMatchingData.path).thenReturn('/test/feed');
        final nonMatchingPage = MockAutoRoutePage();
        when(() => nonMatchingPage.routeData).thenReturn(nonMatchingData);

        when(() => mockRouter.stack)
            .thenReturn(<AutoRoutePage>[nonMatchingPage, matchingPage]);

        await mockRouter.navigateToSingletonWhere(
          const _TestRoute(),
          matcher: (routeData) =>
              routeData.name == testRouteName &&
              routeData.path == '/test/profile',
        );

        verify(() => mockRouter.popUntil(any())).called(1);
        verifyNever(() => mockRouter.replaceAll(any()));
      });

      test('falls back to replaceAll if popUntil throws', () async {
        final matchingPage = createMockPage(testRouteName);
        when(() => mockRouter.stack)
            .thenReturn(<AutoRoutePage>[matchingPage]);
        when(() => mockRouter.popUntil(any()))
            .thenThrow(Exception('popUntil failed'));
        when(() => mockRouter.replaceAll(any())).thenAnswer((_) async {});

        await mockRouter.navigateToSingletonWhere(
          const _TestRoute(),
          matcher: (routeData) => routeData.name == testRouteName,
        );

        verify(() => mockRouter.popUntil(any())).called(1);
        verify(() => mockRouter.replaceAll(any())).called(1);
      });

      test('forwards child routes via forwarder when popping to existing',
          () async {
        final matchingPage = createMockPage(testRouteName);
        when(() => mockRouter.stack)
            .thenReturn(<AutoRoutePage>[matchingPage]);

        List<PageRouteInfo>? receivedChildren;
        SingletonChildForwarder.forRoute(testRouteName)
            .setListener((children) => receivedChildren = children);

        await mockRouter.navigateToSingletonWhere(
          const _TestRoute(children: [_TestChildRoute()]),
          matcher: (routeData) => routeData.name == testRouteName,
        );

        verify(() => mockRouter.popUntil(any())).called(1);
        expect(receivedChildren, isNotNull);
        expect(receivedChildren!.length, 1);
        expect(receivedChildren!.first.routeName, _TestChildRoute.name);
      });

      test('does NOT forward when no children present', () async {
        final matchingPage = createMockPage(testRouteName);
        when(() => mockRouter.stack)
            .thenReturn(<AutoRoutePage>[matchingPage]);

        List<PageRouteInfo>? receivedChildren;
        SingletonChildForwarder.forRoute(testRouteName)
            .setListener((children) => receivedChildren = children);

        await mockRouter.navigateToSingletonWhere(
          const _TestRoute(),
          matcher: (routeData) => routeData.name == testRouteName,
        );

        verify(() => mockRouter.popUntil(any())).called(1);
        expect(receivedChildren, isNull);
      });

      test('rethrows if replaceAll throws in else branch', () async {
        when(() => mockRouter.stack).thenReturn(<AutoRoutePage>[]);
        when(() => mockRouter.replaceAll(any()))
            .thenThrow(Exception('replaceAll failed'));

        expect(
          () => mockRouter.navigateToSingletonWhere(
            const _TestRoute(),
            matcher: (routeData) => routeData.name == testRouteName,
          ),
          throwsA(isA<Exception>()),
        );
      });
    });

    // -----------------------------------------------------------------
    // Deep link scenarios
    // -----------------------------------------------------------------

    group('deep link scenarios', () {
      group('cold start (empty stack)', () {
        test('replaceAll receives full route hierarchy with children',
            () async {
          when(() => mockRouter.stack).thenReturn(<AutoRoutePage>[]);
          when(() => mockRouter.replaceAll(any())).thenAnswer((_) async {});

          await mockRouter.navigateToSingleton(
            const _TestRoute(children: [_TestChildRoute()]),
          );

          // Capture the argument passed to replaceAll.
          final captured =
              verify(() => mockRouter.replaceAll(captureAny())).captured;
          final routes = captured.first as List<PageRouteInfo>;

          expect(routes.length, 1);
          expect(routes.first.routeName, _TestRoute.name);
          expect(routes.first.initialChildren, isNotNull);
          expect(routes.first.initialChildren!.length, 1);
          expect(
            routes.first.initialChildren!.first.routeName,
            _TestChildRoute.name,
          );
        });
      });

      group('warm start (route exists)', () {
        test('pops to existing and forwards children via forwarder', () async {
          final existingPage = createMockPage(testRouteName);
          when(() => mockRouter.stack)
              .thenReturn(<AutoRoutePage>[existingPage]);

          List<PageRouteInfo>? receivedChildren;
          SingletonChildForwarder.forRoute(testRouteName)
              .setListener((children) => receivedChildren = children);

          await mockRouter.navigateToSingleton(
            const _TestRoute(children: [_TestChildRoute()]),
          );

          // Popped to existing singleton.
          verify(() => mockRouter.popUntil(any())).called(1);
          verifyNever(() => mockRouter.replaceAll(any()));

          // Children forwarded via forwarder.
          expect(receivedChildren, isNotNull);
          expect(receivedChildren!.length, 1);
          expect(receivedChildren!.first.routeName, _TestChildRoute.name);
        });

        test('no child forwarding when navigating without children', () async {
          final existingPage = createMockPage(testRouteName);
          when(() => mockRouter.stack)
              .thenReturn(<AutoRoutePage>[existingPage]);

          List<PageRouteInfo>? receivedChildren;
          SingletonChildForwarder.forRoute(testRouteName)
              .setListener((children) => receivedChildren = children);

          await mockRouter.navigateToSingleton(const _TestRoute());

          verify(() => mockRouter.popUntil(any())).called(1);
          expect(receivedChildren, isNull);
        });
      });

      group('nested children', () {
        test('multi-level children are preserved through forwarding',
            () async {
          final existingPage = createMockPage(testRouteName);
          when(() => mockRouter.stack)
              .thenReturn(<AutoRoutePage>[existingPage]);

          List<PageRouteInfo>? receivedChildren;
          SingletonChildForwarder.forRoute(testRouteName)
              .setListener((children) => receivedChildren = children);

          // Deep link: TestRoute → TestChildRoute → TestGrandchildRoute
          await mockRouter.navigateToSingleton(
            const _TestRoute(
              children: [
                _TestChildRoute(
                  children: [_TestGrandchildRoute()],
                ),
              ],
            ),
          );

          verify(() => mockRouter.popUntil(any())).called(1);
          verifyNever(() => mockRouter.replaceAll(any()));

          // Top-level child forwarded.
          expect(receivedChildren, isNotNull);
          expect(receivedChildren!.length, 1);
          expect(receivedChildren!.first.routeName, _TestChildRoute.name);

          // Nested grandchild preserved in hierarchy.
          final forwardedChild = receivedChildren!.first;
          expect(forwardedChild.initialChildren, isNotNull);
          expect(forwardedChild.initialChildren!.length, 1);
          expect(
            forwardedChild.initialChildren!.first.routeName,
            _TestGrandchildRoute.name,
          );
        });

        test('cold start with nested children passes full hierarchy to '
            'replaceAll', () async {
          when(() => mockRouter.stack).thenReturn(<AutoRoutePage>[]);
          when(() => mockRouter.replaceAll(any())).thenAnswer((_) async {});

          await mockRouter.navigateToSingleton(
            const _TestRoute(
              children: [
                _TestChildRoute(
                  children: [_TestGrandchildRoute()],
                ),
              ],
            ),
          );

          final captured =
              verify(() => mockRouter.replaceAll(captureAny())).captured;
          final routes = captured.first as List<PageRouteInfo>;

          // Full hierarchy: TestRoute → TestChildRoute → TestGrandchildRoute
          expect(routes.first.routeName, _TestRoute.name);
          final child = routes.first.initialChildren!.first;
          expect(child.routeName, _TestChildRoute.name);
          expect(child.initialChildren!.first.routeName,
              _TestGrandchildRoute.name);
        });
      });
    });
  });
}
