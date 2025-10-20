import 'package:dreamic/app/helpers/error_reporter_interface.dart';
import 'package:dreamic/utils/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mock error reporter for testing logger behavior
class MockLoggerErrorReporter implements ErrorReporter {
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

void main() {
  group('Logger Error Reporting', () {
    late MockLoggerErrorReporter mockReporter;

    setUp(() {
      mockReporter = MockLoggerErrorReporter();
      // Reset logger state
      Logger.setErrorReportingConfig(null);
      Logger.setCustomErrorReporter(null);
    });

    test('Scenario 1: Firebase only - custom reporter is null', () {
      // Firebase only config (customReporter is null)
      Logger.setErrorReportingConfig(
        const ErrorReportingConfig.firebaseOnly(enableInDebug: true),
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

    test('Scenario 4: Both (manual) - logs to custom reporter', () {
      Logger.setErrorReportingConfig(
        ErrorReportingConfig.both(
          reporter: mockReporter,
          customReporterManagesErrorHandlers: false,
          enableInDebug: true,
        ),
      );
      Logger.setCustomErrorReporter(mockReporter);

      final error = Exception('Test error');
      loge(error, 'Test message');

      expect(mockReporter.recordedErrors, hasLength(1));
      expect(mockReporter.recordedErrors.first, equals(error));
    });

    test('Scenario 5: Both (wrapper) - logs to custom reporter', () {
      Logger.setErrorReportingConfig(
        ErrorReportingConfig.both(
          reporter: mockReporter,
          customReporterManagesErrorHandlers: true,
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
  });
}
