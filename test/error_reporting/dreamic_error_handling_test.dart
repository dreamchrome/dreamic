import 'dart:async';

import 'package:dreamic/app/helpers/app_errorhandling_init.dart';
import 'package:dreamic/error_reporting/dreamic_error_handling.dart';
import 'package:dreamic/error_reporting/error_reporter_interface.dart';
import 'package:dreamic/error_reporting/web_js_error.dart';
import 'package:dreamic/utils/logger.dart';
import 'package:flutter_test/flutter_test.dart';

/// Captures every error routed through the chokepoint (via `recordError`).
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
    // errors forward (rather than buffering).
    setActiveReporterForTest(reporter);
  });

  tearDown(() {
    resetEarlyErrorHandlersForTest();
    Logger.setCustomErrorReporter(null);
  });

  group('DreamicErrorHandling.runGuarded (ERH-001 / BEH-1)', () {
    test('routes a thrown ASYNC error to the chokepoint', () async {
      final err = StateError('async boom');

      DreamicErrorHandling.runGuarded(() {
        // Schedule an async error with no local handler — only the guarded zone
        // can catch it.
        Timer.run(() => throw err);
      });

      // Let the microtask/timer queue drain so the zone's onError fires.
      await Future<void>.delayed(Duration.zero);

      expect(reporter.errors, contains(err));
    });

    test('default onError forwards to recordZoneError (chokepoint)', () async {
      final err = StateError('default-onError boom');
      DreamicErrorHandling.runGuarded(() {
        Future<void>.error(err);
      });
      await Future<void>.delayed(Duration.zero);
      expect(reporter.errors, contains(err));
    });

    test('recordZoneError routes directly through the chokepoint', () {
      final err = StateError('direct');
      DreamicErrorHandling.recordZoneError(err, StackTrace.current);
      expect(reporter.errors, contains(err));
    });
  });

  group('web-JS simulateWebError seam (ERH-009)', () {
    test('routes a synthesized web error through the chokepoint', () {
      final webError = WebJsError('boom', 'TypeError', StackTrace.current);
      DreamicErrorHandling.simulateWebError(webError, webError.stack);
      expect(reporter.errors, contains(webError));
    });

    test('routed web errors participate in cross-surface dedup', () {
      final webError = WebJsError('dup', 'Error', StackTrace.empty);
      DreamicErrorHandling.simulateWebError(webError, webError.stack);
      DreamicErrorHandling.simulateWebError(webError, webError.stack);
      // Same (error, stack) identity → reported exactly once (BEH-9).
      expect(reporter.errors.where((e) => identical(e, webError)), hasLength(1));
    });

    test('installEarlyWebErrorHandlers is a safe no-op on the VM (stub import '
        'resolves — ERH-015)', () {
      // On VM/mobile the conditional import resolves the no-op stub; this must
      // compile and run without a `window`.
      expect(DreamicErrorHandling.installEarlyWebErrorHandlers, returnsNormally);
    });
  });
}
