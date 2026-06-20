import 'dart:async';

import 'package:dreamic/app/startup/dreamic_app_init_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A plain (non-routing) splash that depends only on an inherited
/// `Directionality` (via `Text`).
class _PlainSplash extends StatelessWidget {
  const _PlainSplash();

  @override
  Widget build(BuildContext context) => const Text('splash');
}

void main() {
  group('DreamicAppInitHost — factory invocation', () {
    testWidgets('initFutureFactory is invoked exactly once on mount',
        (tester) async {
      var factoryCalls = 0;
      await tester.pumpWidget(
        DreamicAppInitHost(
          initFutureFactory: () {
            factoryCalls++;
            return Completer<void>().future;
          },
          minimumSplashDuration: Duration.zero,
          splash: const _PlainSplash(),
          child: const Text('child', textDirection: TextDirection.ltr),
        ),
      );

      expect(factoryCalls, 1);
    });

    testWidgets('initFutureFactory is NOT re-invoked on a plain rebuild',
        (tester) async {
      var factoryCalls = 0;
      Future<void> Function() factory() => () {
            factoryCalls++;
            return Completer<void>().future;
          };

      Widget build() => DreamicAppInitHost(
            initFutureFactory: factory(),
            minimumSplashDuration: Duration.zero,
            splash: const _PlainSplash(),
            child: const Text('child', textDirection: TextDirection.ltr),
          );

      await tester.pumpWidget(build());
      expect(factoryCalls, 1);

      // A plain rebuild (same widget position, new widget instance) must NOT
      // re-run the factory — the captured Future persists across rebuilds.
      await tester.pumpWidget(build());
      expect(factoryCalls, 1);
    });
  });

  group('DreamicAppInitHost — retry', () {
    testWidgets('retry re-invokes the factory with a fresh Key + Future, re-mounting the gate',
        (tester) async {
      var factoryCalls = 0;
      late VoidCallback capturedRetry;
      final completers = <Completer<void>>[];

      await tester.pumpWidget(
        DreamicAppInitHost(
          initFutureFactory: () {
            factoryCalls++;
            final c = Completer<void>();
            completers.add(c);
            return c.future;
          },
          minimumSplashDuration: Duration.zero,
          splash: const _PlainSplash(),
          errorBuilder: (context, retry) {
            capturedRetry = retry;
            return const Text('error', textDirection: TextDirection.ltr);
          },
          child: const Text('child', textDirection: TextDirection.ltr),
        ),
      );

      expect(factoryCalls, 1);

      // First generation fails → error shown.
      completers[0].completeError(Exception('boom-1'));
      await tester.pumpAndSettle();
      expect(find.text('error'), findsOneWidget);

      // Retry → factory re-invoked (generation 2), splash shown again.
      capturedRetry();
      await tester.pump();
      expect(factoryCalls, 2);
      expect(find.text('splash'), findsOneWidget);
      expect(find.text('error'), findsNothing);
    });

    testWidgets('recovery: first Future errors, retry Future succeeds → child mounts',
        (tester) async {
      var factoryCalls = 0;
      late VoidCallback capturedRetry;
      final completers = <Completer<void>>[];

      await tester.pumpWidget(
        DreamicAppInitHost(
          initFutureFactory: () {
            factoryCalls++;
            final c = Completer<void>();
            completers.add(c);
            return c.future;
          },
          minimumSplashDuration: Duration.zero,
          splash: const _PlainSplash(),
          errorBuilder: (context, retry) {
            capturedRetry = retry;
            return const Text('error', textDirection: TextDirection.ltr);
          },
          child: const Text('child', textDirection: TextDirection.ltr),
        ),
      );

      completers[0].completeError(Exception('boom'));
      await tester.pumpAndSettle();
      expect(find.text('error'), findsOneWidget);

      capturedRetry();
      await tester.pump();
      expect(factoryCalls, 2);

      // Second generation succeeds → child mounts.
      completers[1].complete();
      await tester.pumpAndSettle();
      expect(find.text('child'), findsOneWidget);
      expect(find.text('error'), findsNothing);
    });

    testWidgets(
        'persistent failure: first errors, retry ALSO errors → errorWidget shown again (Issue 102)',
        (tester) async {
      // This catches an eager/shared-Future wiring bug: if the factory were not
      // re-invoked per generation, the retry would reuse the already-completed
      // (errored) Future and might not re-show the error — or would reuse a
      // single Future that can't error twice.
      var factoryCalls = 0;
      late VoidCallback capturedRetry;
      final completers = <Completer<void>>[];

      await tester.pumpWidget(
        DreamicAppInitHost(
          initFutureFactory: () {
            factoryCalls++;
            final c = Completer<void>();
            completers.add(c);
            return c.future;
          },
          minimumSplashDuration: Duration.zero,
          splash: const _PlainSplash(),
          errorBuilder: (context, retry) {
            capturedRetry = retry;
            return const Text('error', textDirection: TextDirection.ltr);
          },
          child: const Text('child', textDirection: TextDirection.ltr),
        ),
      );

      completers[0].completeError(Exception('boom-1'));
      await tester.pumpAndSettle();
      expect(find.text('error'), findsOneWidget);

      capturedRetry();
      await tester.pump();
      expect(factoryCalls, 2);
      // A fresh Future for generation 2 — error it independently.
      completers[1].completeError(Exception('boom-2'));
      await tester.pumpAndSettle();

      expect(find.text('error'), findsOneWidget);
      expect(find.text('child'), findsNothing);
      expect(find.text('splash'), findsNothing);
    });
  });

  group('DreamicAppInitHost — optional errorBuilder (Issue 112)', () {
    testWidgets('no errorBuilder → gate falls back to its default error widget',
        (tester) async {
      final completer = Completer<void>();
      await tester.pumpWidget(
        DreamicAppInitHost(
          initFutureFactory: () => completer.future,
          minimumSplashDuration: Duration.zero,
          splash: const _PlainSplash(),
          // No errorBuilder supplied → host forwards null → gate default.
          child: const Text('child', textDirection: TextDirection.ltr),
        ),
      );

      completer.completeError(Exception('boom'));
      await tester.pump();
      await tester.pump();
      // In debug the default is `ErrorWidget`; no throw, no child.
      expect(find.byType(ErrorWidget), findsOneWidget);
      expect(find.text('child'), findsNothing);
    });
  });
}
