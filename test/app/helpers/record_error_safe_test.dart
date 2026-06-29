import 'package:dreamic/app/app_config_base.dart';
import 'package:dreamic/app/helpers/app_errorhandling_init.dart';
import 'package:dreamic/error_reporting/error_reporter_interface.dart';
import 'package:dreamic/utils/logger.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reporter that records every error routed through `_recordErrorSafe` (forwarded
/// via [recordError]) and every breadcrumb. `extends ErrorReporter` to inherit
/// the default no-op members.
class _RecordingReporter extends ErrorReporter {
  final List<Object> recordedErrors = [];
  final List<String> breadcrumbs = [];

  @override
  void recordError(Object error, StackTrace? stackTrace) {
    recordedErrors.add(error);
  }

  @override
  void addBreadcrumb(String message, {String? category, Map<String, dynamic>? data}) {
    breadcrumbs.add(message);
  }
}

/// Reporter whose [recordError] throws — used to prove the re-entrancy guard
/// catches a failing report without re-entering / crashing.
class _ThrowingReporter extends ErrorReporter {
  int recordCalls = 0;

  @override
  void recordError(Object error, StackTrace? stackTrace) {
    recordCalls++;
    throw StateError('reporter blew up while recording');
  }
}

/// An error whose [toString] throws, used to prove the chokepoint never throws
/// into the caller even when the dedup-key / redaction `toString()` blows up.
class _ToStringThrows implements Exception {
  @override
  String toString() => throw StateError('toString blew up');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingReporter reporter;

  setUp(() {
    reporter = _RecordingReporter();
    resetEarlyErrorHandlersForTest();
    Logger.setCustomErrorReporter(null);
    Logger.resetEarlyBreadcrumbBufferForTest();
    AppConfigBase.resetBreadcrumbLevelWarnedForTest();
  });

  tearDown(() {
    resetEarlyErrorHandlersForTest();
    Logger.setErrorReportingConfig(null);
    Logger.setCustomErrorReporter(null);
    Logger.resetEarlyBreadcrumbBufferForTest();
    AppConfigBase.resetBreadcrumbLevelWarnedForTest();
  });

  group('_recordErrorSafe — re-entrancy guard (ERH-011 / BEH-11)', () {
    test('an error raised inside a report is console-only, never re-entered', () {
      final throwing = _ThrowingReporter();
      setActiveReporterForTest(throwing);

      // Must not throw into the caller even though the reporter throws.
      expect(
        () => recordErrorSafeForTest(StateError('boom'), StackTrace.current),
        returnsNormally,
      );
      // The reporter was invoked exactly once — the failure was not re-reported
      // (no recursion through the guard).
      expect(throwing.recordCalls, 1);
    });

    test('a toString-throwing error is suppressed (chokepoint never throws)', () {
      setActiveReporterForTest(reporter);

      expect(
        () => recordErrorSafeForTest(_ToStringThrows(), StackTrace.current),
        returnsNormally,
      );
      // The dedup-key / forward path threw and was caught → nothing recorded.
      expect(reporter.recordedErrors, isEmpty);
    });
  });

  group('_recordErrorSafe — bounded-set dedup (ERH-003/028 / BEH-9)', () {
    test('the same (error, stack) re-arrival is reported once', () {
      setActiveReporterForTest(reporter);
      final err = StateError('same');
      final st = StackTrace.current;

      recordErrorSafeForTest(err, st);
      recordErrorSafeForTest(err, st); // identical (error, stack) → skipped
      recordErrorSafeForTest(err, st);

      expect(reporter.recordedErrors, hasLength(1));
    });

    test('distinct (error, stack) pairs are each reported', () {
      setActiveReporterForTest(reporter);
      final st = StackTrace.current;

      recordErrorSafeForTest(StateError('a'), st);
      recordErrorSafeForTest(StateError('b'), st);
      recordErrorSafeForTest(StateError('c'), st);

      expect(reporter.recordedErrors, hasLength(3));
    });

    test('the dedup set is bounded at capacity 20 (FIFO drop-oldest), so an '
        'evicted key re-reports', () {
      setActiveReporterForTest(reporter);
      final st = StackTrace.current;

      // Report 21 distinct errors; the very first key (e0) is evicted (cap 20).
      for (var i = 0; i < 21; i++) {
        recordErrorSafeForTest(StateError('e$i'), st);
      }
      expect(reporter.recordedErrors, hasLength(21));
      // The set holds at most 20 keys.
      expect(dedupSetLengthForTest, 20);

      // e0 was evicted → re-arrival is treated as new and re-reported.
      recordErrorSafeForTest(StateError('e0'), st);
      expect(reporter.recordedErrors, hasLength(22));

      // e20 (most-recent of the burst) is still in the set → its re-arrival is
      // deduped (not reported again).
      final before = reporter.recordedErrors.length;
      recordErrorSafeForTest(StateError('e20'), st);
      expect(reporter.recordedErrors, hasLength(before));
    });
  });

  group('_recordErrorSafe — redaction-fail dedup-preservation (ERH-028 / BEH-9)',
      () {
    test('two distinct errors that redact to the SAME string are NOT deduped '
        'into one (dedup keys pre-redaction)', () {
      setActiveReporterForTest(reporter);
      final st = StackTrace.current;

      // Two distinct secrets that redaction normalizes to the same form
      // (`oobCode=[redacted]`). If dedup keyed on the POST-redaction string they
      // would collapse to one; keying on the ORIGINAL identity keeps them two.
      recordErrorSafeForTest(StateError('oobCode=SECRET_ONE'), st);
      recordErrorSafeForTest(StateError('oobCode=SECRET_TWO'), st);

      expect(reporter.recordedErrors, hasLength(2));
      // Both were redacted before forwarding (no secret reaches the reporter).
      for (final e in reporter.recordedErrors) {
        expect(e.toString(), isNot(contains('SECRET_')));
        expect(e.toString(), contains('oobCode=[redacted]'));
      }
    });

    test('an error with no secret keeps its original (rich) error object', () {
      setActiveReporterForTest(reporter);
      final err = StateError('a plain error');

      recordErrorSafeForTest(err, StackTrace.current);

      // No redaction change → the original object is forwarded untouched.
      expect(reporter.recordedErrors.single, same(err));
    });
  });

  group('_recordErrorSafe — pre-attach buffering (ERH-011 / BEH-12)', () {
    test('buffers into the early-error buffer when no reporter is attached', () {
      // No reporter attached (active reporter null) → buffer, do not forward.
      setActiveReporterForTest(null);
      expect(earlyErrorBufferLengthForTest, 0);

      recordErrorSafeForTest(StateError('pre-attach'), StackTrace.current);

      expect(reporter.recordedErrors, isEmpty);
      expect(earlyErrorBufferLengthForTest, 1);
    });
  });

  group('appInitErrorHandling — attach flush order (ERH-032 / BEH-12)', () {
    /// Drives the production branch of `appInitErrorHandling` with [reporter] as
    /// the attached reporter (force reporting on, no emulator, enabled in debug).
    Future<void> attachProductionReporter() async {
      AppConfigBase.doForceErrorReportingOverride = true;
      AppConfigBase.doUseBackendEmulatorOverride = false;
      AppConfigBase.doDisableErrorReportingOverride = false;
      final config = ErrorReportingConfig.customOnly(
        reporter: reporter,
        enableInDebug: true,
        enableOnWeb: true,
      );
      configureErrorReporting(config);
      Logger.setErrorReportingConfig(config);
      addTearDown(() {
        configureErrorReporting(const ErrorReportingConfig());
        AppConfigBase.doForceErrorReportingOverride = null;
        AppConfigBase.doUseBackendEmulatorOverride = null;
        AppConfigBase.doDisableErrorReportingOverride = null;
      });
      await appInitErrorHandling();
    }

    test('flushes early breadcrumbs BEFORE early errors on attach', () async {
      // Emit a pre-attach breadcrumb (buffered, since no reporter attached) and
      // buffer a pre-attach error.
      installEarlyErrorHandlers();
      logBreadcrumb('early crumb', level: LogLevel.info);
      bufferEarlyErrorForTest(StateError('early error'));
      expect(Logger.earlyBreadcrumbBufferLengthForTest, 1);
      expect(earlyErrorBufferLengthForTest, 1);

      await attachProductionReporter();

      // Both flushed.
      expect(reporter.breadcrumbs, ['early crumb']);
      expect(reporter.recordedErrors, hasLength(1));
      // Breadcrumb arrived before the error (interleave order is observable via
      // the per-reporter lists; the breadcrumb flush runs first so it is in place
      // when the error is reported).
      expect(reporter.breadcrumbs.single, 'early crumb');
      // Buffers cleared (no re-flush).
      expect(Logger.earlyBreadcrumbBufferLengthForTest, 0);
      expect(earlyErrorBufferLengthForTest, 0);
    });

    test('flushed early breadcrumbs are NOT re-redacted (redacted once at emit)',
        () async {
      installEarlyErrorHandlers();
      // A secret in a pre-attach breadcrumb is redacted at emit time; the flush
      // must not double-process (and must still carry the redacted form).
      logBreadcrumb('go to ?oobCode=SECRET');

      await attachProductionReporter();

      expect(reporter.breadcrumbs.single, isNot(contains('SECRET')));
      expect(reporter.breadcrumbs.single, contains('oobCode=[redacted]'));
    });

    test('an early breadcrumb-flush failure does not abort the error flush',
        () async {
      // A reporter whose addBreadcrumb throws must not prevent the error flush.
      final flaky = _FlakyBreadcrumbReporter();
      reporter = flaky; // attachProductionReporter closes over `reporter`.
      installEarlyErrorHandlers();
      logBreadcrumb('will throw on flush');
      bufferEarlyErrorForTest(StateError('still-reported'));

      await attachProductionReporter();

      // The breadcrumb threw but the error flush still delivered.
      expect(flaky.recordedErrors, hasLength(1));
    });
  });

  group('appInitErrorHandling — loge() regression (post-refactor)', () {
    test('loge() still delivers through the attached reporter', () async {
      AppConfigBase.doForceErrorReportingOverride = true;
      AppConfigBase.doUseBackendEmulatorOverride = false;
      AppConfigBase.doDisableErrorReportingOverride = false;
      final config = ErrorReportingConfig.customOnly(
        reporter: reporter,
        enableInDebug: true,
        enableOnWeb: true,
      );
      configureErrorReporting(config);
      Logger.setErrorReportingConfig(config);
      addTearDown(() {
        configureErrorReporting(const ErrorReportingConfig());
        AppConfigBase.doForceErrorReportingOverride = null;
        AppConfigBase.doUseBackendEmulatorOverride = null;
        AppConfigBase.doDisableErrorReportingOverride = null;
      });

      await appInitErrorHandling();

      final err = StateError('via loge');
      loge(err, 'a message');
      // The loge() → _crashReport() → reporter path still delivers after the
      // chokepoint refactor (it routes directly, not through _recordErrorSafe).
      expect(reporter.recordedErrors, contains(err));
    });
  });
}

/// A reporter whose [addBreadcrumb] throws (to prove the breadcrumb flush is
/// per-crumb guarded) while still recording errors.
class _FlakyBreadcrumbReporter extends _RecordingReporter {
  @override
  void addBreadcrumb(String message, {String? category, Map<String, dynamic>? data}) {
    throw StateError('breadcrumb flush blew up');
  }
}
