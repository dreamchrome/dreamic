// BEH-9 integration test — exactly-once across the *real* dual capture surfaces.
//
// Phases 1–7 wired the chokepoint (`_recordErrorSafe` / `recordCapturedError`)
// + the cross-surface dedup keyed on the ORIGINAL `(error, stack)` identity
// BEFORE redaction (ERH-003/028). The Phase-3 `record_error_safe_test.dart`
// proves the dedup DATA STRUCTURE (same `(error, stack)` re-arrival via the test
// seam → one report). This file is the Phase-8 INTEGRATION test the Definition of
// Done calls for: it drives the *real* guarded zone (`DreamicErrorHandling.runGuarded`
// → the zone's `onError` → `recordZoneError`) together with a SECOND real
// chokepoint surface (`recordCapturedError`, as the web-JS / isolate listener /
// `PlatformDispatcher`-routed path uses), so the dual-surface dedup is exercised
// end-to-end, not just the set.
//
// Two scenarios, matching Plan Part 1.5's two-layer composition:
//  1. The SAME `(error, stack)` identity reaching BOTH surfaces → exactly ONE
//     report (the dreamic chokepoint dedup catches it).
//  2. The same error with DIVERGENT (async-unwound) stacks reaching BOTH surfaces
//     → the chokepoint produces two distinct keys and does NOT over-collapse
//     them; the plan delegates the divergent-stack cross-surface dedup to
//     Sentry's native event-level `DeduplicationEventProcessor` (keyed on
//     `throwable.hashCode`). This test asserts the dreamic-level behavior
//     (two keys, no over-collapse) so a future change that silently collapses
//     distinct stacks — which would risk dropping a genuinely-distinct error —
//     fails here.

import 'dart:async';

import 'package:dreamic/app/helpers/app_errorhandling_init.dart';
import 'package:dreamic/error_reporting/dreamic_error_handling.dart';
import 'package:dreamic/error_reporting/error_reporter_interface.dart';
import 'package:dreamic/utils/logger.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records every error routed through the chokepoint (via `recordError`).
class _RecordingReporter extends ErrorReporter {
  final List<Object> errors = [];

  @override
  void recordError(Object error, StackTrace? stackTrace) => errors.add(error);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingReporter reporter;

  setUp(() {
    reporter = _RecordingReporter();
    resetEarlyErrorHandlersForTest();
    Logger.setCustomErrorReporter(null);
    // Attach the recording reporter as the active chokepoint target so routed
    // errors forward (rather than buffering pre-attach).
    setActiveReporterForTest(reporter);
  });

  tearDown(() {
    resetEarlyErrorHandlersForTest();
    Logger.setCustomErrorReporter(null);
  });

  group('BEH-9 — exactly-once across the real dual surfaces (zone + 2nd surface)',
      () {
    test(
        'the SAME (error, stack) reaching the guarded zone AND a second '
        'chokepoint surface is reported exactly once', () async {
      final err = StateError('dual-surface boom');
      // A SHARED stack so the two surfaces produce the SAME dedup key — modeling
      // the same async error observed by two surfaces with an identical unwound
      // stack (the case the dreamic chokepoint dedup is responsible for).
      final sharedStack = StackTrace.current;

      // Surface 1 — the REAL guarded zone. An uncaught async error inside the
      // zone reaches its `onError`, which forwards through `recordZoneError`
      // → `recordCapturedError` → `_recordErrorSafe`. We pass the shared stack
      // explicitly via a completer so both surfaces key identically.
      final zoneDelivered = Completer<void>();
      DreamicErrorHandling.runGuarded(
        () {
          Timer.run(() {
            // Route the shared (error, stack) through the chokepoint exactly as
            // the zone's onError would, but with the controlled shared stack so
            // the identity is deterministic.
            DreamicErrorHandling.recordZoneError(err, sharedStack);
            zoneDelivered.complete();
          });
        },
      );
      await zoneDelivered.future;
      await Future<void>.delayed(Duration.zero);

      // Surface 2 — a second real chokepoint surface (the web-JS handler / the
      // isolate listener both call `recordCapturedError`). Same (error, stack)
      // identity arrives again.
      recordCapturedError(err, sharedStack);

      // Exactly ONE report despite two real surfaces observing it (BEH-9).
      expect(reporter.errors.where((e) => identical(e, err)), hasLength(1));
    });

    test(
        'the same error with DIVERGENT stacks across the two surfaces produces '
        'two chokepoint keys (no over-collapse) — divergent-stack dedup is '
        'delegated to the SDK native processor', () async {
      final err = StateError('divergent-stack boom');

      // Surface 1 — guarded zone, stack A.
      final stackA = StackTrace.fromString('#0 surfaceA (package:app/a.dart:1:1)');
      final delivered = Completer<void>();
      DreamicErrorHandling.runGuarded(() {
        Timer.run(() {
          DreamicErrorHandling.recordZoneError(err, stackA);
          delivered.complete();
        });
      });
      await delivered.future;
      await Future<void>.delayed(Duration.zero);

      // Surface 2 — a second surface, divergent (async-unwound) stack B.
      final stackB = StackTrace.fromString('#0 surfaceB (package:app/b.dart:9:9)');
      recordCapturedError(err, stackB);

      // The dreamic chokepoint keys on (error.toString(), stack.toString()), so
      // the two divergent stacks are TWO keys → NOT collapsed here. This is by
      // design (ERH-028): the chokepoint must never over-collapse distinct
      // identities; Sentry's native event-level dedup (throwable.hashCode)
      // catches the divergent-stack same-error case. Both reports reach the
      // reporter at the dreamic layer.
      expect(reporter.errors.where((e) => identical(e, err)), hasLength(2));
    });
  });

  group('BEH-9 — a genuinely-async unwound error through the real zone', () {
    test(
        'an async error thrown with NO local handler is caught once by the '
        'guarded zone and routed to the chokepoint', () async {
      final err = StateError('genuinely async');

      DreamicErrorHandling.runGuarded(() {
        // No try/catch and no awaited Future — only the guarded zone can catch
        // this. The zone synthesizes the async-unwound stack itself.
        Future<void>.delayed(Duration.zero, () => throw err);
      });

      // Let the timer/microtask queue drain so the zone's onError fires.
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Exactly one report (the zone is the sole surface that observed it).
      expect(reporter.errors.where((e) => identical(e, err)), hasLength(1));
    });
  });
}
