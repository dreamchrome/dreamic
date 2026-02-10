import 'package:auto_route/auto_route.dart';
import 'package:dreamic/app/app_config_base.dart';
import 'package:dreamic/navigation/child_forwarder/singleton_child_forwarder.dart';
import 'package:dreamic/navigation/mixins/singleton_route_mixin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockRoutingController extends Mock implements RoutingController {}

// ---------------------------------------------------------------------------
// Test route stubs
// ---------------------------------------------------------------------------

class _TestChildRoute extends PageRouteInfo<void> {
  const _TestChildRoute() : super('TestChildRoute');
  static const String name = 'TestChildRoute';
}

class _TestOtherRoute extends PageRouteInfo<void> {
  const _TestOtherRoute() : super('TestOtherRoute');
  static const String name = 'TestOtherRoute';
}

// ---------------------------------------------------------------------------
// Test widget using SingletonRouteMixin
// ---------------------------------------------------------------------------

const _testRouteName = 'TestSingletonRoute';

class _TestWidget extends StatefulWidget {
  /// When provided, [innerRouter] is set in initState so child forwarding
  /// can navigate via the mock router.
  final RoutingController? router;

  const _TestWidget({this.router});

  @override
  State<_TestWidget> createState() => _TestWidgetState();
}

class _TestWidgetState extends State<_TestWidget> with SingletonRouteMixin {
  @override
  String get singletonRouteName => _testRouteName;

  @override
  void initState() {
    super.initState();
    if (widget.router != null) {
      innerRouter = widget.router;
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    registerFallbackValue(const _TestChildRoute());
  });

  setUp(() {
    // Suppress Crashlytics / error reporting in tests.
    AppConfigBase.doDisableErrorReportingOverride = true;
  });

  tearDown(() {
    AppConfigBase.doDisableErrorReportingOverride = null;
    // Clean forwarder state to prevent cross-test contamination.
    final forwarder = SingletonChildForwarder.forRoute(_testRouteName);
    forwarder.setListener((_) {}); // Drain any pending children.
    forwarder.setListener(null); // Clear listener.
  });

  group('SingletonRouteMixin', () {
    // -----------------------------------------------------------------
    // Listener registration in initState
    // -----------------------------------------------------------------

    testWidgets('registers listener on initState', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: _TestWidget()));

      // Verify the listener is registered by forwarding children and then
      // checking that nothing is queued (the listener consumed them).
      SingletonChildForwarder.forRoute(_testRouteName)
          .forward([const _TestChildRoute()]);

      // If the mixin had NOT registered a listener, children would still be
      // queued. Replace the listener with a probe to check for queued items.
      List<PageRouteInfo>? queuedChildren;
      SingletonChildForwarder.forRoute(_testRouteName)
          .setListener((children) => queuedChildren = children);

      // Nothing queued — the mixin's listener already consumed them.
      expect(queuedChildren, isNull);
    });

    // -----------------------------------------------------------------
    // Listener removal in dispose
    // -----------------------------------------------------------------

    testWidgets('removes listener on dispose', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: _TestWidget()));

      // Dispose the widget by replacing it.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));

      // Forward children after dispose — should be queued (no listener).
      SingletonChildForwarder.forRoute(_testRouteName)
          .forward([const _TestChildRoute()]);

      // Register a probe listener — queued children should be delivered.
      List<PageRouteInfo>? received;
      SingletonChildForwarder.forRoute(_testRouteName)
          .setListener((children) => received = children);

      expect(received, isNotNull);
      expect(received!.length, 1);
      expect(received!.first.routeName, _TestChildRoute.name);
    });

    // -----------------------------------------------------------------
    // Child forwarding with innerRouter set
    // -----------------------------------------------------------------

    testWidgets('forwards children to innerRouter when set', (tester) async {
      final mockRouter = MockRoutingController();
      when(() => mockRouter.navigate(any())).thenAnswer((_) async => null);

      await tester.pumpWidget(
        MaterialApp(home: _TestWidget(router: mockRouter)),
      );

      // Forward one child via the forwarder.
      SingletonChildForwarder.forRoute(_testRouteName)
          .forward([const _TestChildRoute()]);

      // Mixin should have called innerRouter.navigate() for the child.
      verify(() => mockRouter.navigate(any())).called(1);
    });

    testWidgets('forwards multiple children to innerRouter', (tester) async {
      final mockRouter = MockRoutingController();
      when(() => mockRouter.navigate(any())).thenAnswer((_) async => null);

      await tester.pumpWidget(
        MaterialApp(home: _TestWidget(router: mockRouter)),
      );

      // Forward two children at once.
      SingletonChildForwarder.forRoute(_testRouteName)
          .forward([const _TestChildRoute(), const _TestOtherRoute()]);

      // navigate() should be called once per child.
      verify(() => mockRouter.navigate(any())).called(2);
    });

    // -----------------------------------------------------------------
    // innerRouter is null — error logging, no crash
    // -----------------------------------------------------------------

    testWidgets('does not throw when innerRouter is null', (tester) async {
      // No router passed — innerRouter remains null.
      await tester.pumpWidget(const MaterialApp(home: _TestWidget()));

      // Forward children — should log error but NOT throw.
      SingletonChildForwarder.forRoute(_testRouteName)
          .forward([const _TestChildRoute()]);

      // If we reach here without crashing, the test passes.
      // The mixin logged an error via loge() pointing to the setup issue.
    });

    testWidgets('does not call navigate when innerRouter is null',
        (tester) async {
      // No router passed — innerRouter remains null.
      await tester.pumpWidget(const MaterialApp(home: _TestWidget()));

      // Forward children — mixin should NOT attempt to call navigate.
      SingletonChildForwarder.forRoute(_testRouteName)
          .forward([const _TestChildRoute()]);

      // No way to verify navigate() wasn't called on a null router, but
      // the absence of a NullPointerException confirms the null check works.
    });
  });
}
