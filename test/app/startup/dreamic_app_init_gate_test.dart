import 'dart:async';

import 'package:dreamic/app/app_config_base.dart';
import 'package:dreamic/app/startup/dreamic_app_init_gate.dart';
import 'package:dreamic/error_reporting/error_reporter_interface.dart';
import 'package:dreamic/utils/logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Spy that captures errors routed through `loge()` (both the logged message
/// and the reported error object). Wired via `Logger.setCustomErrorReporter`
/// + `Logger.setErrorReportingConfig`.
class _SpyErrorReporter implements ErrorReporter {
  final List<Object> recordedErrors = [];

  @override
  Future<void> initialize() async {}

  @override
  void recordError(Object error, StackTrace? stackTrace) {
    recordedErrors.add(error);
  }

  @override
  void recordFlutterError(FlutterErrorDetails details) {
    recordedErrors.add(details.exception);
  }
}

/// A plain (non-routing) splash that depends on an inherited `Directionality`
/// (via `Text`) but NOT on `MediaQuery` or any `BlocProvider`-scoped cubit —
/// mirroring `DreamicSplash` / `MppInitError`'s above-`MaterialApp`
/// constraints (Issue 73).
class _PlainSplash extends StatelessWidget {
  const _PlainSplash();

  @override
  Widget build(BuildContext context) {
    // `Text` requires a `Directionality` ancestor; the gate must provide one.
    return const Text('splash');
  }
}

/// A plain error widget under the same constraints (Issue 73).
class _PlainError extends StatelessWidget {
  const _PlainError();

  @override
  Widget build(BuildContext context) {
    return const Text('custom-error');
  }
}

/// A splash that mounts a routing app (`MaterialApp`) — must trip the
/// debug splash-is-plain guard.
class _RoutingSplash extends StatelessWidget {
  const _RoutingSplash();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: Scaffold(body: Text('bad splash')));
  }
}

void main() {
  late _SpyErrorReporter spy;

  setUp(() {
    spy = _SpyErrorReporter();
    // enableInDebug so the custom reporter fires under the debug test runner;
    // the dreamic test env sets DO_USE_BACKEND_EMULATOR=true, which suppresses
    // reporting unless forced — force it so the spy actually receives errors.
    AppConfigBase.doForceErrorReportingOverride = true;
    Logger.setErrorReportingConfig(
      ErrorReportingConfig.customOnly(
        reporter: spy,
        enableInDebug: true,
        enableOnWeb: true,
      ),
    );
    Logger.setCustomErrorReporter(spy);
  });

  tearDown(() {
    Logger.setErrorReportingConfig(null);
    Logger.setCustomErrorReporter(null);
    AppConfigBase.doForceErrorReportingOverride = null;
  });

  group('DreamicAppInitGate — splash / child transitions', () {
    testWidgets('shows splash until the Future completes, then mounts child',
        (tester) async {
      final completer = Completer<void>();
      await tester.pumpWidget(
        DreamicAppInitGate(
          initFuture: completer.future,
          minimumSplashDuration: Duration.zero,
          splash: const _PlainSplash(),
          child: const Text('child', textDirection: TextDirection.ltr),
        ),
      );

      // Pending: splash shown, child not.
      expect(find.text('splash'), findsOneWidget);
      expect(find.text('child'), findsNothing);

      completer.complete();
      await tester.pumpAndSettle();

      // Resolved: child shown, splash gone.
      expect(find.text('child'), findsOneWidget);
      expect(find.text('splash'), findsNothing);
    });

    testWidgets('shows errorWidget on Future throw and does NOT mount child',
        (tester) async {
      final completer = Completer<void>();
      await tester.pumpWidget(
        DreamicAppInitGate(
          initFuture: completer.future,
          minimumSplashDuration: Duration.zero,
          splash: const _PlainSplash(),
          errorWidget: const _PlainError(),
          child: const Text('child', textDirection: TextDirection.ltr),
        ),
      );

      expect(find.text('splash'), findsOneWidget);

      completer.completeError(Exception('boom'));
      await tester.pumpAndSettle();

      expect(find.text('custom-error'), findsOneWidget);
      expect(find.text('child'), findsNothing);
      expect(find.text('splash'), findsNothing);
    });

    testWidgets('gate loges AND reports the error on Future throw (Issue 51)',
        (tester) async {
      final completer = Completer<void>();
      final error = Exception('fatal-init');
      await tester.pumpWidget(
        DreamicAppInitGate(
          initFuture: completer.future,
          minimumSplashDuration: Duration.zero,
          splash: const _PlainSplash(),
          errorWidget: const _PlainError(),
          child: const Text('child', textDirection: TextDirection.ltr),
        ),
      );

      completer.completeError(error);
      await tester.pumpAndSettle();

      // The handled `.then(onError:)` async error is reported via `loge()`,
      // which routes to the error backend (the spy reporter here).
      expect(spy.recordedErrors, contains(error));
    });
  });

  group('DreamicAppInitGate — single-shot identity', () {
    testWidgets('a different initFuture on rebuild is ignored', (tester) async {
      final first = Completer<void>();
      final second = Completer<void>();

      Widget build(Future<void> f) => DreamicAppInitGate(
            initFuture: f,
            minimumSplashDuration: Duration.zero,
            splash: const _PlainSplash(),
            child: const Text('child', textDirection: TextDirection.ltr),
          );

      await tester.pumpWidget(build(first.future));
      // Rebuild same widget type (same position, no Key change) with a second
      // Future — should be ignored; the gate still tracks `first`.
      await tester.pumpWidget(build(second.future));

      // Completing the SECOND (ignored) Future must NOT mount the child.
      second.complete();
      await tester.pumpAndSettle();
      expect(find.text('child'), findsNothing);
      expect(find.text('splash'), findsOneWidget);

      // Completing the FIRST (captured) Future mounts the child.
      first.complete();
      await tester.pumpAndSettle();
      expect(find.text('child'), findsOneWidget);
    });
  });

  group('DreamicAppInitGate — minimumSplashDuration min-hold (Issue 101)', () {
    testWidgets('fast bootstrap still holds the splash for the minimum',
        (tester) async {
      await tester.pumpWidget(
        DreamicAppInitGate(
          // Already-completed Future → bootstrap is instantaneous.
          initFuture: Future<void>.value(),
          minimumSplashDuration: const Duration(milliseconds: 800),
          splash: const _PlainSplash(),
          child: const Text('child', textDirection: TextDirection.ltr),
        ),
      );

      // Let the Future microtask resolve, but stay under the 800ms min-hold.
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('splash'), findsOneWidget);
      expect(find.text('child'), findsNothing);

      // After the min-hold elapses, the child mounts.
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('child'), findsOneWidget);
      expect(find.text('splash'), findsNothing);
    });

    testWidgets('slow bootstrap adds no extra delay past completion',
        (tester) async {
      final completer = Completer<void>();
      await tester.pumpWidget(
        DreamicAppInitGate(
          initFuture: completer.future,
          minimumSplashDuration: const Duration(milliseconds: 200),
          splash: const _PlainSplash(),
          child: const Text('child', textDirection: TextDirection.ltr),
        ),
      );

      // Let the min-hold elapse while the bootstrap is still pending.
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('splash'), findsOneWidget);

      // Bootstrap completes well after the min-hold → child mounts immediately
      // (no additional time advance — a zero-duration pump suffices to flush
      // the completion microtask and rebuild).
      completer.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('child'), findsOneWidget);
    });

    testWidgets('Duration.zero removes the splash as soon as bootstrap completes',
        (tester) async {
      final completer = Completer<void>();
      await tester.pumpWidget(
        DreamicAppInitGate(
          initFuture: completer.future,
          minimumSplashDuration: Duration.zero,
          splash: const _PlainSplash(),
          child: const Text('child', textDirection: TextDirection.ltr),
        ),
      );

      completer.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('child'), findsOneWidget);
      expect(find.text('splash'), findsNothing);
    });

    testWidgets(
        'errorWidget on a fatal error shows without waiting out a 5s minimum',
        (tester) async {
      final completer = Completer<void>();
      await tester.pumpWidget(
        DreamicAppInitGate(
          initFuture: completer.future,
          minimumSplashDuration: const Duration(seconds: 5),
          splash: const _PlainSplash(),
          errorWidget: const _PlainError(),
          child: const Text('child', textDirection: TextDirection.ltr),
        ),
      );

      // Fail the bootstrap, then drain the error microtask WITHOUT advancing
      // the 5s min-hold (each pump here advances zero wall time). The error
      // must already be showing — the min-hold gates only success→child.
      completer.completeError(Exception('boom'));
      await tester.pump();
      await tester.pump();
      expect(find.text('custom-error'), findsOneWidget);
      expect(find.text('splash'), findsNothing);
      expect(find.text('child'), findsNothing);
    });
  });

  group('DreamicAppInitGate — default error widget (Issue 112)', () {
    testWidgets('null errorWidget falls back to the built-in default without throwing',
        (tester) async {
      // In debug the default is `ErrorWidget`, which needs no Material ancestor.
      final completer = Completer<void>();
      await tester.pumpWidget(
        DreamicAppInitGate(
          initFuture: completer.future,
          minimumSplashDuration: Duration.zero,
          splash: const _PlainSplash(),
          // No errorWidget supplied.
          child: const Text('child', textDirection: TextDirection.ltr),
        ),
      );

      completer.completeError(Exception('boom'));
      await tester.pump();
      await tester.pump();
      // The default debug error widget renders (a red ErrorWidget); no throw.
      expect(find.byType(ErrorWidget), findsOneWidget);
      expect(find.text('child'), findsNothing);
    });
  });

  group('DreamicAppInitGate — deep-link preservation (child-wrap)', () {
    testWidgets('child is not built while the gate is pending (wrap, not builder)',
        (tester) async {
      var childBuilds = 0;
      final completer = Completer<void>();
      await tester.pumpWidget(
        DreamicAppInitGate(
          initFuture: completer.future,
          minimumSplashDuration: Duration.zero,
          splash: const _PlainSplash(),
          child: Builder(
            builder: (context) {
              childBuilds++;
              return const Text('child', textDirection: TextDirection.ltr);
            },
          ),
        ),
      );

      // The routing child must NOT be instantiated/built while pending — the
      // platform-buffered deep link survives until it mounts on success.
      expect(childBuilds, 0);

      completer.complete();
      await tester.pumpAndSettle();
      expect(childBuilds, 1);
    });
  });

  group('DreamicAppInitGate — no-MaterialApp-ancestor rendering (Issues 61/73)', () {
    testWidgets(
        'splash branch renders with no MaterialApp/MediaQuery/AppCubit ancestor',
        (tester) async {
      // Pump the gate directly (no MaterialApp wrapper) — the splash uses
      // `Text` (needs Directionality) but no MediaQuery/cubit.
      await tester.pumpWidget(
        DreamicAppInitGate(
          initFuture: Completer<void>().future,
          minimumSplashDuration: Duration.zero,
          splash: const _PlainSplash(),
          child: const Text('child', textDirection: TextDirection.ltr),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('splash'), findsOneWidget);
    });

    testWidgets('error branch renders a Text-using widget with no ancestor',
        (tester) async {
      final completer = Completer<void>();
      await tester.pumpWidget(
        DreamicAppInitGate(
          initFuture: completer.future,
          minimumSplashDuration: Duration.zero,
          splash: const _PlainSplash(),
          errorWidget: const _PlainError(),
          child: const Text('child', textDirection: TextDirection.ltr),
        ),
      );

      completer.completeError(Exception('boom'));
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('custom-error'), findsOneWidget);
    });
  });

  group('DreamicAppInitGate — debug splash-is-plain guard (Issue 66)', () {
    testWidgets('throws when the splash mounts a routing app', (tester) async {
      await tester.pumpWidget(
        DreamicAppInitGate(
          initFuture: Completer<void>().future,
          minimumSplashDuration: Duration.zero,
          splash: const _RoutingSplash(),
          child: const Text('child', textDirection: TextDirection.ltr),
        ),
      );

      // The post-frame guard throws a FlutterError naming the offender.
      final error = tester.takeException();
      expect(error, isA<FlutterError>());
      expect(
        error.toString(),
        contains('must be a plain widget, not a routing app'),
      );
    });

    testWidgets('does NOT throw for the default Directionality-wrapped splash',
        (tester) async {
      await tester.pumpWidget(
        DreamicAppInitGate(
          initFuture: Completer<void>().future,
          minimumSplashDuration: Duration.zero,
          splash: const _PlainSplash(),
          child: const Text('child', textDirection: TextDirection.ltr),
        ),
      );
      // A `Directionality` is not a `WidgetsApp`, so the default wrap doesn't
      // trip the guard.
      expect(tester.takeException(), isNull);
    });
  });
}
