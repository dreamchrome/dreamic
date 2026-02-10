import 'package:auto_route/auto_route.dart';
import 'package:dreamic/app/app_config_base.dart';
import 'package:dreamic/navigation/child_forwarder/singleton_child_forwarder.dart';
import 'package:dreamic/navigation/guards/singleton_route_guard.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockRootStackRouter extends Mock implements RootStackRouter {}

class MockAutoRoutePage extends Mock implements AutoRoutePage {}

class MockRouteData extends Mock implements RouteData {}

class MockNavigationResolver extends Mock implements NavigationResolver {}

class MockRouteMatch extends Mock implements RouteMatch {}

// ---------------------------------------------------------------------------
// Test route stub for PageRouteInfo instances used in child forwarding.
// ---------------------------------------------------------------------------

class _TestChildRoute extends PageRouteInfo<void> {
  const _TestChildRoute() : super('TestChildRoute');
  static const String name = 'TestChildRoute';
}

// ---------------------------------------------------------------------------

void main() {
  const testRouteName = 'TestRoute';

  late SingletonRouteGuard guard;
  late MockRootStackRouter mockRouter;
  late MockNavigationResolver mockResolver;
  late MockRouteMatch mockRouteMatch;

  setUpAll(() {
    // Register fallback values for types used with any() matchers.
    registerFallbackValue((Route<dynamic> route) => false);
  });

  setUp(() {
    guard = const SingletonRouteGuard.forRoute(testRouteName);
    mockRouter = MockRootStackRouter();
    mockResolver = MockNavigationResolver();
    mockRouteMatch = MockRouteMatch();

    // Common stubs shared by all tests.
    when(() => mockRouter.root).thenReturn(mockRouter);
    when(() => mockResolver.route).thenReturn(mockRouteMatch);

    // Suppress error reporting during tests (avoids Firebase access).
    AppConfigBase.doDisableErrorReportingOverride = true;
  });

  tearDown(() {
    AppConfigBase.doDisableErrorReportingOverride = null;
    // Clean forwarder state to prevent cross-test contamination.
    final forwarder = SingletonChildForwarder.forRoute(testRouteName);
    forwarder.setListener((_) {}); // Drain any pending children.
    forwarder.setListener(null); // Clear listener.
  });

  // Helper: creates a mock page whose routeData.name returns [name].
  MockAutoRoutePage createMockPage(String name) {
    final mockPage = MockAutoRoutePage();
    final mockData = MockRouteData();
    when(() => mockData.name).thenReturn(name);
    when(() => mockPage.routeData).thenReturn(mockData);
    return mockPage;
  }

  group('SingletonRouteGuard', () {
    // ---------------------------------------------------------------
    // Cold start — stack is empty
    // ---------------------------------------------------------------

    group('cold start (empty stack)', () {
      test('allows navigation when stack is empty', () {
        when(() => mockRouter.stack).thenReturn(<AutoRoutePage>[]);

        guard.onNavigation(mockResolver, mockRouter);

        verify(() => mockResolver.next(true)).called(1);
        verifyNever(() => mockRouter.popUntil(any()));
      });
    });

    // ---------------------------------------------------------------
    // Warm start — singleton already in stack
    // ---------------------------------------------------------------

    group('warm start (route exists in stack)', () {
      late MockAutoRoutePage existingPage;

      setUp(() {
        existingPage = createMockPage(testRouteName);
        when(() => mockRouter.stack)
            .thenReturn(<AutoRoutePage>[existingPage]);
      });

      test('blocks navigation and pops to existing instance', () {
        when(() => mockRouteMatch.children).thenReturn(null);

        guard.onNavigation(mockResolver, mockRouter);

        verify(() => mockRouter.popUntil(any())).called(1);
        verify(() => mockResolver.next(false)).called(1);
        verifyNever(() => mockResolver.next(true));
      });

      test('forwards child routes via forwarder when blocking duplicate', () {
        // Set up child routes on the pending navigation.
        final mockChildMatch = MockRouteMatch();
        when(() => mockChildMatch.toPageRouteInfo())
            .thenReturn(const _TestChildRoute());
        when(() => mockRouteMatch.children)
            .thenReturn(<RouteMatch>[mockChildMatch]);

        // Register listener to capture forwarded children.
        List<PageRouteInfo>? receivedChildren;
        SingletonChildForwarder.forRoute(testRouteName)
            .setListener((children) => receivedChildren = children);

        guard.onNavigation(mockResolver, mockRouter);

        // Duplicate blocked.
        verify(() => mockResolver.next(false)).called(1);
        // Popped to existing.
        verify(() => mockRouter.popUntil(any())).called(1);
        // Children forwarded through forwarder.
        expect(receivedChildren, isNotNull);
        expect(receivedChildren!.length, 1);
        expect(receivedChildren!.first.routeName, _TestChildRoute.name);
      });

      test('forwards multiple child routes preserving order', () {
        final childA = MockRouteMatch();
        when(() => childA.toPageRouteInfo())
            .thenReturn(const _TestChildRoute());
        final childB = MockRouteMatch();
        when(() => childB.toPageRouteInfo())
            .thenReturn(const PageRouteInfo('SettingsRoute'));
        when(() => mockRouteMatch.children)
            .thenReturn(<RouteMatch>[childA, childB]);

        List<PageRouteInfo>? receivedChildren;
        SingletonChildForwarder.forRoute(testRouteName)
            .setListener((children) => receivedChildren = children);

        guard.onNavigation(mockResolver, mockRouter);

        expect(receivedChildren, isNotNull);
        expect(receivedChildren!.length, 2);
        expect(receivedChildren![0].routeName, _TestChildRoute.name);
        expect(receivedChildren![1].routeName, 'SettingsRoute');
      });

      test('does NOT forward when children is null', () {
        when(() => mockRouteMatch.children).thenReturn(null);

        List<PageRouteInfo>? receivedChildren;
        SingletonChildForwarder.forRoute(testRouteName)
            .setListener((children) => receivedChildren = children);

        guard.onNavigation(mockResolver, mockRouter);

        expect(receivedChildren, isNull);
        verify(() => mockResolver.next(false)).called(1);
      });

      test('does NOT forward when children list is empty', () {
        when(() => mockRouteMatch.children).thenReturn(<RouteMatch>[]);

        List<PageRouteInfo>? receivedChildren;
        SingletonChildForwarder.forRoute(testRouteName)
            .setListener((children) => receivedChildren = children);

        guard.onNavigation(mockResolver, mockRouter);

        expect(receivedChildren, isNull);
        verify(() => mockResolver.next(false)).called(1);
      });
    });

    // ---------------------------------------------------------------
    // Multiple instances in stack (bug detection)
    // ---------------------------------------------------------------

    group('multiple instances detection', () {
      test('still pops and blocks when two instances exist', () {
        final page1 = createMockPage(testRouteName);
        final page2 = createMockPage(testRouteName);
        when(() => mockRouter.stack)
            .thenReturn(<AutoRoutePage>[page1, page2]);
        when(() => mockRouteMatch.children).thenReturn(null);

        // Should not throw — logs error internally and continues.
        guard.onNavigation(mockResolver, mockRouter);

        verify(() => mockRouter.popUntil(any())).called(1);
        verify(() => mockResolver.next(false)).called(1);
      });
    });

    // ---------------------------------------------------------------
    // popUntil failure — graceful fallback
    // ---------------------------------------------------------------

    group('popUntil failure', () {
      test('falls back to resolver.next(true) when popUntil throws', () {
        final existingPage = createMockPage(testRouteName);
        when(() => mockRouter.stack)
            .thenReturn(<AutoRoutePage>[existingPage]);
        when(() => mockRouteMatch.children).thenReturn(null);
        when(() => mockRouter.popUntil(any()))
            .thenThrow(Exception('popUntil failed'));

        guard.onNavigation(mockResolver, mockRouter);

        // Fallback: allow navigation rather than leaving user stuck.
        verify(() => mockResolver.next(true)).called(1);
        verifyNever(() => mockResolver.next(false));
      });

      test('does not attempt child forwarding when popUntil throws', () {
        final existingPage = createMockPage(testRouteName);
        when(() => mockRouter.stack)
            .thenReturn(<AutoRoutePage>[existingPage]);
        // Even with children present, popUntil failure skips forwarding.
        final mockChildMatch = MockRouteMatch();
        when(() => mockChildMatch.toPageRouteInfo())
            .thenReturn(const _TestChildRoute());
        when(() => mockRouteMatch.children)
            .thenReturn(<RouteMatch>[mockChildMatch]);
        when(() => mockRouter.popUntil(any()))
            .thenThrow(Exception('popUntil failed'));

        List<PageRouteInfo>? receivedChildren;
        SingletonChildForwarder.forRoute(testRouteName)
            .setListener((children) => receivedChildren = children);

        guard.onNavigation(mockResolver, mockRouter);

        // Children were NOT forwarded because popUntil threw before
        // the forwarding code executed.
        expect(receivedChildren, isNull);
        verify(() => mockResolver.next(true)).called(1);
      });
    });

    // ---------------------------------------------------------------
    // Custom log message
    // ---------------------------------------------------------------

    group('custom log message', () {
      test('accepts and uses custom log message without error', () {
        const customGuard = SingletonRouteGuard.forRoute(
          testRouteName,
          customLogMessage: 'Custom: singleton protected',
        );
        final existingPage = createMockPage(testRouteName);
        when(() => mockRouter.stack)
            .thenReturn(<AutoRoutePage>[existingPage]);
        when(() => mockRouteMatch.children).thenReturn(null);

        // Should not throw — custom message is used internally for logging.
        customGuard.onNavigation(mockResolver, mockRouter);

        verify(() => mockResolver.next(false)).called(1);
      });
    });

    // ---------------------------------------------------------------
    // Non-matching routes — stack has routes but not the singleton
    // ---------------------------------------------------------------

    group('non-matching routes in stack', () {
      test('allows navigation when stack has only different routes', () {
        final otherPage = createMockPage('OtherRoute');
        when(() => mockRouter.stack)
            .thenReturn(<AutoRoutePage>[otherPage]);

        guard.onNavigation(mockResolver, mockRouter);

        verify(() => mockResolver.next(true)).called(1);
        verifyNever(() => mockRouter.popUntil(any()));
      });

      test('detects singleton among other routes in mixed stack', () {
        final otherPage = createMockPage('OtherRoute');
        final singletonPage = createMockPage(testRouteName);
        final anotherPage = createMockPage('AnotherRoute');
        when(() => mockRouter.stack)
            .thenReturn(<AutoRoutePage>[otherPage, singletonPage, anotherPage]);
        when(() => mockRouteMatch.children).thenReturn(null);

        guard.onNavigation(mockResolver, mockRouter);

        // Singleton found in mixed stack — should block and pop.
        verify(() => mockRouter.popUntil(any())).called(1);
        verify(() => mockResolver.next(false)).called(1);
      });
    });
  });
}
