import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dreamic/presentation/responsive/responsive.dart';

/// Sets the test view's logical width to [width] (and a fixed height), with a
/// device-pixel-ratio of 1.0 so logical px == physical px, then registers a
/// reset so the view change cannot leak into other tests.
void _setWidth(WidgetTester tester, double width, {double height = 800}) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.reset);
}

/// A leaf widget that increments [buildCount] every time it builds and reads
/// `context.deviceSize`, so a test can assert exactly how many times the
/// device-class read triggered a rebuild.
class _BuildCounter extends StatelessWidget {
  const _BuildCounter(this.onBuild);

  final void Function(DeviceSize size) onBuild;

  @override
  Widget build(BuildContext context) {
    onBuild(context.deviceSize);
    return const SizedBox.shrink();
  }
}

void main() {
  // Breakpoints are mutable process-global statics; capture and restore them so
  // BEH-02's mutation (and any default change) cannot bleed across tests (D5).
  late double savedTablet;
  late double savedDesktop;

  setUp(() {
    savedTablet = Breakpoints.tablet;
    savedDesktop = Breakpoints.desktop;
  });

  tearDown(() {
    Breakpoints.tablet = savedTablet;
    Breakpoints.desktop = savedDesktop;
  });

  group('BEH-01: classify boundaries (default breakpoints)', () {
    test('599 → mobile, 600 → tablet, 1023 → tablet, 1024 → desktop', () {
      // Defaults: tablet = 600, desktop = 1024.
      expect(classify(599), DeviceSize.mobile);
      expect(classify(600), DeviceSize.tablet);
      expect(classify(1023), DeviceSize.tablet);
      expect(classify(1024), DeviceSize.desktop);
    });

    test('extreme widths classify at the ends', () {
      expect(classify(0), DeviceSize.mobile);
      expect(classify(double.maxFinite), DeviceSize.desktop);
    });
  });

  group('BEH-02: breakpoints are globally configurable', () {
    test('mutating Breakpoints changes subsequent classify results', () {
      // 700 is tablet under defaults (600/1024).
      expect(classify(700), DeviceSize.tablet);

      Breakpoints.tablet = 800;
      Breakpoints.desktop = 1400;

      // Same width now reclassifies under the new thresholds.
      expect(classify(700), DeviceSize.mobile);
      expect(classify(800), DeviceSize.tablet);
      expect(classify(1399), DeviceSize.tablet);
      expect(classify(1400), DeviceSize.desktop);
      // tearDown restores 600/1024.
    });
  });

  group('BEH-03: class-based context accessors reflect the device class', () {
    testWidgets('tablet-width scope → isTablet, deviceSize == tablet',
        (tester) async {
      _setWidth(tester, 700); // tablet
      late BuildContext captured;
      await tester.pumpWidget(
        ResponsiveScope(
          child: Builder(builder: (context) {
            captured = context;
            return const SizedBox.shrink();
          }),
        ),
      );

      expect(captured.deviceSize, DeviceSize.tablet);
      expect(captured.isMobile, isFalse);
      expect(captured.isTablet, isTrue);
      expect(captured.isDesktop, isFalse);
    });

    testWidgets('mobile-width scope → isMobile', (tester) async {
      _setWidth(tester, 400); // mobile
      late BuildContext captured;
      await tester.pumpWidget(
        ResponsiveScope(
          child: Builder(builder: (context) {
            captured = context;
            return const SizedBox.shrink();
          }),
        ),
      );

      expect(captured.deviceSize, DeviceSize.mobile);
      expect(captured.isMobile, isTrue);
      expect(captured.isTablet, isFalse);
      expect(captured.isDesktop, isFalse);
    });

    testWidgets('desktop-width scope → isDesktop', (tester) async {
      _setWidth(tester, 1300); // desktop
      late BuildContext captured;
      await tester.pumpWidget(
        ResponsiveScope(
          child: Builder(builder: (context) {
            captured = context;
            return const SizedBox.shrink();
          }),
        ),
      );

      expect(captured.deviceSize, DeviceSize.desktop);
      expect(captured.isDesktop, isTrue);
    });
  });

  group('BEH-04: responsive<T>() fallback chaining (all four cases)', () {
    /// Pumps a scope at [width] and returns the resolved value of
    /// `context.responsive(...)` for the given args.
    Future<String> resolve(
      WidgetTester tester,
      double width, {
      required String mobile,
      String? tablet,
      String? desktop,
    }) async {
      _setWidth(tester, width);
      late String result;
      await tester.pumpWidget(
        ResponsiveScope(
          child: Builder(builder: (context) {
            result = context.responsive<String>(
              mobile: mobile,
              tablet: tablet,
              desktop: desktop,
            );
            return const SizedBox.shrink();
          }),
        ),
      );
      return result;
    }

    testWidgets('mobile-only → tablet and desktop both get mobile',
        (tester) async {
      expect(await resolve(tester, 400, mobile: 'M'), 'M'); // mobile device
      expect(await resolve(tester, 700, mobile: 'M'), 'M'); // tablet → mobile
      expect(await resolve(tester, 1300, mobile: 'M'), 'M'); // desktop → mobile
    });

    testWidgets('mobile+tablet → desktop gets the tablet value',
        (tester) async {
      expect(await resolve(tester, 400, mobile: 'M', tablet: 'T'), 'M');
      expect(await resolve(tester, 700, mobile: 'M', tablet: 'T'), 'T');
      // desktop falls back to tablet (desktop ?? tablet ?? mobile).
      expect(await resolve(tester, 1300, mobile: 'M', tablet: 'T'), 'T');
    });

    testWidgets(
        'mobile+desktop (tablet omitted) → tablet device gets MOBILE, '
        'desktop device gets desktop', (tester) async {
      // The chain treats a null tablet as "inherit from mobile" — it does NOT
      // skip ahead to desktop (RU-013).
      expect(await resolve(tester, 700, mobile: 'M', desktop: 'D'), 'M');
      expect(await resolve(tester, 1300, mobile: 'M', desktop: 'D'), 'D');
      // mobile device still gets mobile.
      expect(await resolve(tester, 400, mobile: 'M', desktop: 'D'), 'M');
    });

    testWidgets('all three distinct → each class returns its own value',
        (tester) async {
      expect(
          await resolve(tester, 400, mobile: 'M', tablet: 'T', desktop: 'D'),
          'M');
      expect(
          await resolve(tester, 700, mobile: 'M', tablet: 'T', desktop: 'D'),
          'T');
      expect(
          await resolve(tester, 1300, mobile: 'M', tablet: 'T', desktop: 'D'),
          'D');
    });
  });

  group('BEH-05: class-based reads trigger segment-only rebuilds', () {
    testWidgets(
        'within-class resize → no rebuild; across-boundary resize → +1',
        (tester) async {
      var buildCount = 0;
      DeviceSize? lastSize;
      // The scope's child is a stable const so the subtree is preserved across
      // resizes; the only thing that can rebuild the counter is a
      // _ResponsiveData class flip (RU-014).
      final counter = _BuildCounter((size) {
        buildCount++;
        lastSize = size;
      });

      _setWidth(tester, 700); // tablet
      await tester.pumpWidget(ResponsiveScope(child: counter));
      expect(buildCount, 1);
      expect(lastSize, DeviceSize.tablet);

      // Within-class resize (tablet → tablet): no rebuild. Drive via the view +
      // pump(), NOT a fresh pumpWidget, so the child instance stays identical.
      _setWidth(tester, 800); // still tablet
      await tester.pump();
      expect(buildCount, 1, reason: 'within-class resize must not rebuild');
      expect(lastSize, DeviceSize.tablet);

      // Across-boundary resize (tablet → desktop): exactly one rebuild.
      _setWidth(tester, 1100); // desktop
      await tester.pump();
      expect(buildCount, 2, reason: 'across-boundary resize rebuilds once');
      expect(lastSize, DeviceSize.desktop);
    });
  });

  group('BEH-09: missing ResponsiveScope → release-safe FlutterError', () {
    testWidgets('reading context.deviceSize without a scope throws FlutterError',
        (tester) async {
      // The throw happens during build, so the framework captures it rather
      // than pumpWidget rethrowing — retrieve via takeException, do NOT wrap
      // pumpWidget in throwsA (RU-008).
      await tester.pumpWidget(
        Builder(builder: (context) {
          context.deviceSize;
          return const SizedBox.shrink();
        }),
      );

      final exception = tester.takeException();
      expect(exception, isA<FlutterError>());
      expect(
        (exception as FlutterError).message,
        contains('No ResponsiveScope found. Wrap your app in a ResponsiveScope.'),
      );
    });
  });

  group('BEH-06: responsiveByViewportWidth picks the highest match', () {
    /// Resolves the helper at [width] using [breakpoints]/[fallback], under a
    /// bare MediaQuery (no scope needed — BEH-10).
    Future<int> pick(
      WidgetTester tester,
      double width, {
      required Map<double, int> breakpoints,
      required int fallback,
    }) async {
      late int result;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(size: Size(width, 800)),
          child: Builder(builder: (context) {
            result = context.responsiveByViewportWidth<int>(
              breakpoints: breakpoints,
              fallback: fallback,
            );
            return const SizedBox.shrink();
          }),
        ),
      );
      return result;
    }

    testWidgets('highest threshold <= width wins', (tester) async {
      final bp = {0.0: 1, 600.0: 2, 1024.0: 3};
      expect(await pick(tester, 500, breakpoints: bp, fallback: 0), 1);
      expect(await pick(tester, 600, breakpoints: bp, fallback: 0), 2);
      expect(await pick(tester, 700, breakpoints: bp, fallback: 0), 2);
      expect(await pick(tester, 1024, breakpoints: bp, fallback: 0), 3);
      expect(await pick(tester, 2000, breakpoints: bp, fallback: 0), 3);
    });

    testWidgets('width below all thresholds → fallback', (tester) async {
      final bp = {600.0: 2, 1024.0: 3};
      expect(await pick(tester, 400, breakpoints: bp, fallback: 99), 99);
    });

    testWidgets('unsorted input map still resolves correctly', (tester) async {
      // Insertion order is intentionally scrambled.
      final bp = {1024.0: 3, 0.0: 1, 600.0: 2};
      expect(await pick(tester, 700, breakpoints: bp, fallback: 0), 2);
      expect(await pick(tester, 1100, breakpoints: bp, fallback: 0), 3);
      expect(await pick(tester, 100, breakpoints: bp, fallback: 0), 1);
    });
  });

  group('BEH-07: clampByViewportWidth interpolates and clamps', () {
    /// Resolves clampByViewportWidth at [width] under a bare MediaQuery.
    Future<double> clamp(
      WidgetTester tester,
      double width, {
      required double minValue,
      required double maxValue,
      double minW = 360,
      double maxW = 1200,
    }) async {
      late double result;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(size: Size(width, 800)),
          child: Builder(builder: (context) {
            result = context.clampByViewportWidth(
              minValue: minValue,
              maxValue: maxValue,
              minW: minW,
              maxW: maxW,
            );
            return const SizedBox.shrink();
          }),
        ),
      );
      return result;
    }

    testWidgets('at/below minW → minValue', (tester) async {
      expect(await clamp(tester, 360, minValue: 10, maxValue: 20), 10);
      expect(await clamp(tester, 100, minValue: 10, maxValue: 20), 10);
    });

    testWidgets('at/above maxW → maxValue', (tester) async {
      expect(await clamp(tester, 1200, minValue: 10, maxValue: 20), 20);
      expect(await clamp(tester, 5000, minValue: 10, maxValue: 20), 20);
    });

    testWidgets('midpoint width → midpoint value', (tester) async {
      // minW=360, maxW=1200 → midpoint width 780 → t=0.5 → 15.
      expect(await clamp(tester, 780, minValue: 10, maxValue: 20), 15);
    });

    testWidgets('values past either end are clamped, never extrapolated',
        (tester) async {
      // Below minW would extrapolate to <10 without the clamp; above maxW to >20.
      expect(await clamp(tester, 0, minValue: 10, maxValue: 20), 10);
      expect(await clamp(tester, 10000, minValue: 10, maxValue: 20), 20);
    });
  });

  group('BEH-08: clampByViewportWidth degenerate range → minValue', () {
    Future<double> clamp(
      WidgetTester tester,
      double width, {
      required double minValue,
      required double maxValue,
      required double minW,
      required double maxW,
    }) async {
      late double result;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(size: Size(width, 800)),
          child: Builder(builder: (context) {
            result = context.clampByViewportWidth(
              minValue: minValue,
              maxValue: maxValue,
              minW: minW,
              maxW: maxW,
            );
            return const SizedBox.shrink();
          }),
        ),
      );
      return result;
    }

    testWidgets('minW == maxW → minValue (no NaN/Infinity)', (tester) async {
      final result = await clamp(tester, 500,
          minValue: 10, maxValue: 20, minW: 500, maxW: 500);
      expect(result, 10);
      expect(result.isNaN, isFalse);
      expect(result.isInfinite, isFalse);
    });

    testWidgets('minW > maxW (negative range) → minValue', (tester) async {
      final result = await clamp(tester, 500,
          minValue: 10, maxValue: 20, minW: 800, maxW: 400);
      expect(result, 10);
      expect(result.isNaN, isFalse);
      expect(result.isInfinite, isFalse);
    });
  });

  group('BEH-10: viewport-width helpers read the call-site MediaQuery', () {
    testWidgets(
        '(a) override under a scope → helpers track local width while '
        'deviceSize tracks the scope', (tester) async {
      // Scope sees a desktop-width window (1300); a nested MediaQuery overrides
      // the size to a mobile width (400) for a sub-subtree.
      _setWidth(tester, 1300);
      late DeviceSize scopeClass;
      late int byWidth;
      late double clamped;

      await tester.pumpWidget(
        ResponsiveScope(
          child: MediaQuery(
            data: const MediaQueryData(size: Size(400, 800)),
            child: Builder(builder: (context) {
              scopeClass = context.deviceSize; // still the scope's class
              byWidth = context.responsiveByViewportWidth<int>(
                breakpoints: {0.0: 1, 600.0: 2, 1024.0: 3},
                fallback: 0,
              );
              clamped = context.clampByViewportWidth(
                minValue: 10,
                maxValue: 20,
                minW: 360,
                maxW: 1200,
              );
              return const SizedBox.shrink();
            }),
          ),
        ),
      );

      // Class read reflects the SCOPE (1300 → desktop), not the 400 override.
      expect(scopeClass, DeviceSize.desktop);
      // Width helpers reflect the LOCAL 400px override.
      expect(byWidth, 1); // 400 < 600 → lowest bucket
      // 400 < minW(360)? no — 400 is just above minW, t = (400-360)/840 ≈ 0.0476.
      final expected = 10 + (20 - 10) * ((400 - 360) / (1200 - 360));
      expect(clamped, closeTo(expected, 1e-9));
    });

    testWidgets(
        '(b) no scope at all → helpers resolve width-correctly and do not throw',
        (tester) async {
      // Bare MediaQuery, NO ResponsiveScope ancestor — the deliberate contrast
      // with BEH-09's FlutterError (RU-015).
      late int byWidth;
      late double clamped;

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(700, 800)),
          child: Builder(builder: (context) {
            byWidth = context.responsiveByViewportWidth<int>(
              breakpoints: {0.0: 1, 600.0: 2, 1024.0: 3},
              fallback: 0,
            );
            clamped = context.clampByViewportWidth(
              minValue: 10,
              maxValue: 20,
              minW: 360,
              maxW: 1200,
            );
            return const SizedBox.shrink();
          }),
        ),
      );

      // (i) width-correct values for a 700px viewport.
      expect(byWidth, 2); // 700 ≥ 600, < 1024
      final expected = 10 + (20 - 10) * ((700 - 360) / (1200 - 360));
      expect(clamped, closeTo(expected, 1e-9));
      // (ii) nothing thrown — viewport helpers need only a MediaQuery (RU-005).
      expect(tester.takeException(), isNull);
    });
  });
}
