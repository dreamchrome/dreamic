import 'package:dreamic/app/app_config_base.dart';
import 'package:dreamic/app/helpers/app_errorhandling_init.dart';
import 'package:dreamic/error_reporting/error_reporter_interface.dart';
import 'package:dreamic/utils/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mock error reporter for testing logger behavior. `extends ErrorReporter` so it
/// inherits the default no-op breadcrumb/user-context members.
class MockLoggerErrorReporter extends ErrorReporter {
  final List<Object> recordedErrors = [];
  final List<FlutterErrorDetails> recordedFlutterErrors = [];

  @override
  Future<void> initialize() async {}

  @override
  void recordError(Object error, StackTrace? stackTrace) {
    recordedErrors.add(error);
  }

  @override
  void recordFlutterError(FlutterErrorDetails details) {
    recordedFlutterErrors.add(details);
  }

  void reset() {
    recordedErrors.clear();
    recordedFlutterErrors.clear();
  }
}

/// A reporter that overrides the (now first-class) [ErrorReporter.addBreadcrumb].
class MockBreadcrumbReporter extends MockLoggerErrorReporter {
  final List<String> breadcrumbs = [];

  @override
  void addBreadcrumb(String message, {String? category, Map<String, dynamic>? data}) {
    breadcrumbs.add(message);
  }
}

void main() {
  group('Logger Error Reporting', () {
    late MockLoggerErrorReporter mockReporter;

    setUp(() {
      mockReporter = MockLoggerErrorReporter();
      // Reset logger state
      Logger.setErrorReportingConfig(null);
      Logger.setCustomErrorReporter(null);
      // Override emulator check to allow error reporting in tests
      AppConfigBase.doUseBackendEmulatorOverride = false;
      AppConfigBase.doDisableErrorReportingOverride = false;
      AppConfigBase.doForceErrorReportingOverride = null;
    });

    tearDown(() {
      // Reset overrides
      AppConfigBase.doUseBackendEmulatorOverride = null;
      AppConfigBase.doDisableErrorReportingOverride = null;
      AppConfigBase.doForceErrorReportingOverride = null;
    });

    test('Scenario 1: No custom reporter - logs to console only', () {
      // Config with no custom reporter — dreamic has no built-in reporter, so
      // nothing is recorded (console only).
      Logger.setErrorReportingConfig(
        const ErrorReportingConfig(
          enableInDebug: true,
        ),
      );
      Logger.setCustomErrorReporter(null);

      final error = Exception('Test error');
      loge(error, 'Test message');

      // Should not throw even though custom reporter is null
      expect(mockReporter.recordedErrors, isEmpty);
    });

    test('Scenario 2: Sentry only (manual) - logs to custom reporter', () {
      Logger.setErrorReportingConfig(
        ErrorReportingConfig.customOnly(
          reporter: mockReporter,
          managesOwnErrorHandlers: false,
          enableInDebug: true,
        ),
      );
      Logger.setCustomErrorReporter(mockReporter);

      final error = Exception('Test error');
      loge(error, 'Test message');

      expect(mockReporter.recordedErrors, hasLength(1));
      expect(mockReporter.recordedErrors.first, equals(error));
    });

    test('Scenario 3: Sentry only (wrapper) - logs to custom reporter', () {
      // Even with managesOwnErrorHandlers: true, manual logging should work
      Logger.setErrorReportingConfig(
        ErrorReportingConfig.customOnly(
          reporter: mockReporter,
          managesOwnErrorHandlers: true, // Key: manages own handlers
          enableInDebug: true,
        ),
      );
      Logger.setCustomErrorReporter(mockReporter);

      final error = Exception('Test error');
      loge(error, 'Test message');

      // Should still log via custom reporter for manual logging
      expect(mockReporter.recordedErrors, hasLength(1));
      expect(mockReporter.recordedErrors.first, equals(error));
    });

    test('Scenario 4: Custom reporter (manual handlers) - logs to custom reporter', () {
      Logger.setErrorReportingConfig(
        ErrorReportingConfig.customOnly(
          reporter: mockReporter,
          managesOwnErrorHandlers: false,
          enableInDebug: true,
        ),
      );
      Logger.setCustomErrorReporter(mockReporter);

      final error = Exception('Test error');
      loge(error, 'Test message');

      expect(mockReporter.recordedErrors, hasLength(1));
      expect(mockReporter.recordedErrors.first, equals(error));
    });

    test('Scenario 5: Custom reporter (wrapper mode) - logs to custom reporter', () {
      Logger.setErrorReportingConfig(
        ErrorReportingConfig.customOnly(
          reporter: mockReporter,
          managesOwnErrorHandlers: true,
          enableInDebug: true,
        ),
      );
      Logger.setCustomErrorReporter(mockReporter);

      final error = Exception('Test error');
      loge(error, 'Test message');

      // Manual logging should work even when Sentry manages automatic handlers
      expect(mockReporter.recordedErrors, hasLength(1));
      expect(mockReporter.recordedErrors.first, equals(error));
    });

    test('Multiple manual errors are all logged', () {
      Logger.setErrorReportingConfig(
        ErrorReportingConfig.customOnly(
          reporter: mockReporter,
          managesOwnErrorHandlers: false,
          enableInDebug: true,
        ),
      );
      Logger.setCustomErrorReporter(mockReporter);

      loge(Exception('Error 1'));
      loge(Exception('Error 2'));
      loge(Exception('Error 3'));

      expect(mockReporter.recordedErrors, hasLength(3));
    });

    test('loge() redacts a secret in the error payload before forwarding (BEH-8)', () {
      // The loge() path funnels through Logger._crashReport, which now redacts
      // (fail-closed) before forwarding — so an oobCode/token in an error string
      // never reaches the backend (BEH-8), matching the _recordErrorSafe path.
      Logger.setErrorReportingConfig(
        ErrorReportingConfig.customOnly(
          reporter: mockReporter,
          managesOwnErrorHandlers: false,
          enableInDebug: true,
        ),
      );
      Logger.setCustomErrorReporter(mockReporter);

      loge(Exception(
        'reset failed for https://app.example/finish?oobCode=SUPERSECRET123&x=1',
      ));

      expect(mockReporter.recordedErrors, hasLength(1));
      final forwarded = mockReporter.recordedErrors.first.toString();
      expect(forwarded, contains('oobCode=[redacted]'));
      expect(forwarded, isNot(contains('SUPERSECRET123')));
    });

    test('loge() forwards the original error object untouched when no secret is present', () {
      // No secret → the rich error object is preserved (no stringification), so
      // the loge regression path is unchanged for the common case.
      Logger.setErrorReportingConfig(
        ErrorReportingConfig.customOnly(
          reporter: mockReporter,
          managesOwnErrorHandlers: false,
          enableInDebug: true,
        ),
      );
      Logger.setCustomErrorReporter(mockReporter);

      final error = Exception('plain failure, no secrets');
      loge(error);

      expect(mockReporter.recordedErrors, hasLength(1));
      expect(mockReporter.recordedErrors.first, same(error));
    });
  });

  group('Logger.breadcrumb — routes to the reporter', () {
    test('routes to a reporter that overrides addBreadcrumb', () {
      final reporter = MockBreadcrumbReporter();
      Logger.setCustomErrorReporter(reporter);

      logBreadcrumb('step: appInitFirebase', category: 'bootstrap');

      expect(reporter.breadcrumbs, ['step: appInitFirebase']);
    });

    test('is a silent no-op for a reporter that does NOT override it', () {
      // The plain mock inherits ErrorReporter's default no-op addBreadcrumb —
      // this must not throw.
      Logger.setCustomErrorReporter(MockLoggerErrorReporter());
      expect(() => logBreadcrumb('ignored'), returnsNormally);
    });

    test('is a silent no-op when there is no custom reporter', () {
      Logger.setCustomErrorReporter(null);
      expect(() => logBreadcrumb('ignored'), returnsNormally);
    });
  });

  group('reportBootstrapDiagnostic — defer before attach, flush on attach', () {
    late MockLoggerErrorReporter reporter;
    FlutterExceptionHandler? savedFlutterOnError;
    late final savedPlatformOnError = PlatformDispatcher.instance.onError;

    setUp(() {
      resetEarlyErrorHandlersForTest();
      reporter = MockLoggerErrorReporter();
      Logger.setErrorReportingConfig(null);
      Logger.setCustomErrorReporter(null);
      configureErrorReporting(const ErrorReportingConfig());
      // Force reporting on under the debug test runner.
      AppConfigBase.doUseBackendEmulatorOverride = false;
      AppConfigBase.doDisableErrorReportingOverride = false;
      AppConfigBase.doForceErrorReportingOverride = true;
      // appInitErrorHandling installs global handlers — save to restore.
      savedFlutterOnError = FlutterError.onError;
    });

    tearDown(() {
      FlutterError.onError = savedFlutterOnError;
      PlatformDispatcher.instance.onError = savedPlatformOnError;
      AppConfigBase.doUseBackendEmulatorOverride = null;
      AppConfigBase.doDisableErrorReportingOverride = null;
      AppConfigBase.doForceErrorReportingOverride = null;
      Logger.setErrorReportingConfig(null);
      Logger.setCustomErrorReporter(null);
      configureErrorReporting(const ErrorReportingConfig());
      resetEarlyErrorHandlersForTest();
    });

    test('a diagnostic reported BEFORE attach is delivered when the reporter attaches',
        () async {
      configureErrorReporting(
        ErrorReportingConfig.customOnly(
          reporter: reporter,
          enableInDebug: true,
          enableOnWeb: true,
        ),
      );

      final err = Exception('firebase-init-recovered');
      // Pre-attach (mirrors appInitFirebase recovery at step 1 on a Crashlytics
      // consumer, before the reporter attaches at step 2): must be deferred.
      reportBootstrapDiagnostic(err, 'recovery');
      expect(reporter.recordedErrors, isEmpty);

      // Attaching the reporter flushes the deferred diagnostic to it.
      await appInitErrorHandling();
      expect(reporter.recordedErrors, contains(err));
    });

    test('a diagnostic reported AFTER attach reports immediately', () async {
      configureErrorReporting(
        ErrorReportingConfig.customOnly(
          reporter: reporter,
          enableInDebug: true,
          enableOnWeb: true,
        ),
      );
      await appInitErrorHandling();

      final err = Exception('later');
      reportBootstrapDiagnostic(err, 'after');
      expect(reporter.recordedErrors, contains(err));
    });
  });
}
