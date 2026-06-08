import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dreamic/presentation/elements/tappable_action.dart';

/// Minimal fake Timer + factory so the tap path's internal timers (the
/// min-duration timer created on every tap, plus any primitive cooldown) do
/// not leak into teardown. These tests assert *provider/timer requirements*,
/// not debounce timing, so swallowing those timers keeps them focused.
class _FakeTimer implements Timer {
  @override
  void cancel() {}

  @override
  bool get isActive => false;

  @override
  int get tick => 0;
}

class _FakeTimerFactory extends TimerFactory {
  @override
  Timer createTimer(Duration duration, VoidCallback callback) => _FakeTimer();
}

void main() {
  // These tests mount the REAL TappableAction widget — something the existing
  // tappable_action_isolated_test.dart could not do, so it cloned a testable
  // copy (SimpleTappableAction / IsolatedGroupManager). They guard the two
  // fixes that made the real widget mountable in isolation.
  group('TappableAction (real widget)', () {
    testWidgets(
        'mounts and taps without an AppCubit provider when requireNetwork is false',
        (tester) async {
      var tapped = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            // Deliberately NO BlocProvider<AppCubit> anywhere in the tree.
            // Before Fix A, build() unconditionally wrapped in
            // BlocBuilder<AppCubit, AppState>, so this threw
            // ProviderNotFoundException during the first build.
            body: TappableAction(
              onTap: () => tapped++,
              timerFactory: _FakeTimerFactory(),
              config: const TappableActionConfig(
                requireNetwork: false,
                debounceTaps: false,
              ),
              builder: (context, onTap) => ElevatedButton(
                onPressed: onTap,
                child: const Text('tap me'),
              ),
            ),
          ),
        ),
      );

      expect(find.text('tap me'), findsOneWidget);

      await tester.tap(find.text('tap me'));
      await tester.pump();
      expect(tapped, 1);
    });

    testWidgets(
        'constructing the group manager with the production default config starts no pending timer',
        (tester) async {
      // forTesting() builds a *fresh* manager with the production default config
      // (10-minute maxGroupLifetime, real TimerFactory) — the exact construction
      // that, before Fix B, kicked off a perpetual self-rescheduling cleanup
      // Timer. Injecting it (instead of relying on the global singleton) makes
      // this guard order-independent: on the old code it leaked a real Timer and
      // failed at teardown with "A Timer is still pending..." regardless of which
      // test ran first. Reaching the end without that error is the assertion.
      final manager = TappableActionGroupManager.forTesting(
          const TappableActionGroupConfig());
      addTearDown(manager.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TappableAction(
              onTap: () {},
              groupManager: manager,
              config: const TappableActionConfig(requireNetwork: false),
              builder: (context, onTap) => ElevatedButton(
                onPressed: onTap,
                child: const Text('x'),
              ),
            ),
          ),
        ),
      );

      expect(find.text('x'), findsOneWidget);
    });
  });
}
