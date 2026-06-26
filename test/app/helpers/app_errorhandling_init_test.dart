import 'package:dreamic/app/app_config_base.dart';
import 'package:dreamic/app/helpers/app_errorhandling_init.dart';
import 'package:dreamic/error_reporting/error_reporter_interface.dart';
import 'package:dreamic/utils/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Spy reporter that captures errors routed through `loge()` (and therefore the
/// early-buffer flush, which flushes via `loge()`).
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _SpyErrorReporter spy;

  setUp(() {
    spy = _SpyErrorReporter();
    resetEarlyErrorHandlersForTest();
  });

  tearDown(() {
    Logger.setErrorReportingConfig(null);
    Logger.setCustomErrorReporter(null);
    // Reset the module-level config appInitErrorHandling reads for branching.
    configureErrorReporting(const ErrorReportingConfig());
    AppConfigBase.doForceErrorReportingOverride = null;
    AppConfigBase.doUseBackendEmulatorOverride = null;
    AppConfigBase.doDisableErrorReportingOverride = null;
    resetEarlyErrorHandlersForTest();
  });

  /// Configures a custom-reporter production path so `appInitErrorHandling`
  /// takes its production branch and FLUSHES the early buffer to [spy].
  ///
  /// Two configs must agree: `configureErrorReporting()` drives
  /// `appInitErrorHandling`'s branch selection (it reads its own module-level
  /// config), while `Logger.setErrorReportingConfig` + `setCustomErrorReporter`
  /// drive the `loge()` reporting path the flush routes through.
  void wireProductionReporting() {
    AppConfigBase.doForceErrorReportingOverride = true;
    AppConfigBase.doUseBackendEmulatorOverride = false;
    AppConfigBase.doDisableErrorReportingOverride = false;
    final config = ErrorReportingConfig.customOnly(
      reporter: spy,
      enableInDebug: true,
      enableOnWeb: true,
    );
    configureErrorReporting(config);
    Logger.setErrorReportingConfig(config);
    Logger.setCustomErrorReporter(spy);
  }

  group('early error buffer — capture + flush', () {
    test('production branch flushes buffered errors to the reporter and clears',
        () async {
      installEarlyErrorHandlers();
      final err1 = StateError('boom-1');
      final err2 = StateError('boom-2');
      bufferEarlyErrorForTest(err1);
      bufferEarlyErrorForTest(err2);
      expect(earlyErrorBufferLengthForTest, 2);

      wireProductionReporting();
      await appInitErrorHandling();

      // Both buffered errors were reported (via the loge() flush path)...
      expect(spy.recordedErrors, containsAll(<Object>[err1, err2]));
      // ...and the buffer is now empty (cleared on flush — no leak).
      expect(earlyErrorBufferLengthForTest, 0);
    });

    test('disabled (kill-switch) branch drops + clears the buffer (no leak)',
        () async {
      installEarlyErrorHandlers();
      bufferEarlyErrorForTest(StateError('boom'));
      expect(earlyErrorBufferLengthForTest, 1);

      AppConfigBase.doDisableErrorReportingOverride = true;
      await appInitErrorHandling();

      // Reporting disabled — nothing reported, buffer cleared.
      expect(spy.recordedErrors, isEmpty);
      expect(earlyErrorBufferLengthForTest, 0);
    });

    test('emulator-blocked branch drops + clears the buffer (no leak)',
        () async {
      installEarlyErrorHandlers();
      bufferEarlyErrorForTest(StateError('boom'));
      expect(earlyErrorBufferLengthForTest, 1);

      // Emulator blocks reporting and does NOT force it → !shouldUseErrorReporting.
      AppConfigBase.doUseBackendEmulatorOverride = true;
      AppConfigBase.doForceErrorReportingOverride = false;
      AppConfigBase.doDisableErrorReportingOverride = false;
      Logger.setErrorReportingConfig(const ErrorReportingConfig());
      await appInitErrorHandling();

      expect(spy.recordedErrors, isEmpty);
      expect(earlyErrorBufferLengthForTest, 0);
    });
  });

  group('early error buffer — bounds + safe no-op (Issues 16/36/82)', () {
    test('bounded buffer drops the OLDEST beyond the ~50 cap', () {
      installEarlyErrorHandlers();
      // Push well past the cap; the most-recent 50 must survive, oldest dropped.
      for (var i = 0; i < 75; i++) {
        bufferEarlyErrorForTest(StateError('e$i'));
      }
      expect(earlyErrorBufferLengthForTest, 50);

      // Flush and assert the survivors are the most-recent 50 (e25..e74), i.e.
      // the oldest 25 were dropped.
      wireProductionReporting();
      return appInitErrorHandling().then((_) {
        expect(spy.recordedErrors.length, 50);
        final messages =
            spy.recordedErrors.map((e) => (e as StateError).message).toSet();
        expect(messages.contains('e0'), isFalse); // oldest dropped
        expect(messages.contains('e24'), isFalse); // oldest dropped
        expect(messages.contains('e25'), isTrue); // first survivor
        expect(messages.contains('e74'), isTrue); // newest survivor
      });
    });

    test(
        'flush is a safe no-op when installEarlyErrorHandlers() was never called '
        '(admin path — no NPE)', () async {
      // Do NOT call installEarlyErrorHandlers(); the buffer is always-present
      // and empty (Issue 36) — admin calls appInitErrorHandling directly.
      wireProductionReporting();
      // Must not throw / NPE.
      await appInitErrorHandling();
      expect(spy.recordedErrors, isEmpty);
      expect(earlyErrorBufferLengthForTest, 0);
    });
  });

  group('isolate error-listener apply-once (Issue 31)', () {
    test(
        'reset clears the apply-once flag so the listener is re-addable across runs',
        () {
      // The production path adds the isolate listener at most once across
      // retries (guarded by the module flag). We can't directly count platform
      // listeners here, but we assert the dreamic-core reset seam exists and is
      // callable (so the idempotency tests can make the assertion
      // order-independent — Issue 63).
      resetIsolateErrorListenerFlag();
      // Calling it twice is harmless (idempotent reset).
      resetIsolateErrorListenerFlag();
    });
  });

  group('debug error presentation — DevTools / IDE visibility', () {
    test(
        'emulator/no-reporting branch forwards to FlutterError.presentError in debug',
        () async {
      // The branch used during normal local dev (emulator on, reporting off) —
      // !shouldUseErrorReporting. Before this guard it replaced onError with a
      // loge()-only handler, suppressing the structured error event so DevTools /
      // get_runtime_errors / the "relevant error-causing widget" block went blind.
      AppConfigBase.doUseBackendEmulatorOverride = true;
      AppConfigBase.doForceErrorReportingOverride = false;
      AppConfigBase.doDisableErrorReportingOverride = false;
      Logger.setErrorReportingConfig(const ErrorReportingConfig());

      await appInitErrorHandling();

      // Capture the framework's default presentation calls. `presentError` is
      // read dynamically inside the installed handler, so overriding it after
      // appInitErrorHandling still intercepts the call.
      final presented = <FlutterErrorDetails>[];
      final originalPresentError = FlutterError.presentError;
      FlutterError.presentError = presented.add;
      addTearDown(() => FlutterError.presentError = originalPresentError);

      // Fire the installed handler as the framework would on a build/layout error.
      final details = FlutterErrorDetails(exception: StateError('boom'));
      FlutterError.onError!(details);

      expect(presented, contains(details));
    });
  });
}
