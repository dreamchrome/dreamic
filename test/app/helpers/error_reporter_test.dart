import 'package:dreamic/app/helpers/error_reporter_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mock error reporter for testing
class MockErrorReporter implements ErrorReporter {
  bool initializeCalled = false;
  final List<Object> recordedErrors = [];
  final List<FlutterErrorDetails> recordedFlutterErrors = [];

  @override
  Future<void> initialize() async {
    initializeCalled = true;
  }

  @override
  void recordError(Object error, StackTrace? stackTrace) {
    recordedErrors.add(error);
  }

  @override
  void recordFlutterError(FlutterErrorDetails details) {
    recordedFlutterErrors.add(details);
  }

  void reset() {
    initializeCalled = false;
    recordedErrors.clear();
    recordedFlutterErrors.clear();
  }
}

void main() {
  group('ErrorReportingConfig', () {
    test('firebaseOnly creates correct configuration', () {
      const config = ErrorReportingConfig.firebaseOnly(
        enableInDebug: true,
        enableOnWeb: false,
      );

      expect(config.customReporter, isNull);
      expect(config.useFirebaseCrashlytics, isTrue);
      expect(config.enableInDebug, isTrue);
      expect(config.enableOnWeb, isFalse);
    });

    test('customOnly creates correct configuration', () {
      final reporter = MockErrorReporter();
      final config = ErrorReportingConfig.customOnly(
        reporter: reporter,
        enableInDebug: false,
        enableOnWeb: true,
      );

      expect(config.customReporter, equals(reporter));
      expect(config.useFirebaseCrashlytics, isFalse);
      expect(config.enableInDebug, isFalse);
      expect(config.enableOnWeb, isTrue);
    });

    test('both creates correct configuration', () {
      final reporter = MockErrorReporter();
      final config = ErrorReportingConfig.both(
        reporter: reporter,
        enableInDebug: true,
        enableOnWeb: true,
      );

      expect(config.customReporter, equals(reporter));
      expect(config.useFirebaseCrashlytics, isTrue);
      expect(config.enableInDebug, isTrue);
      expect(config.enableOnWeb, isTrue);
    });

    test('default configuration uses Firebase only', () {
      const config = ErrorReportingConfig();

      expect(config.customReporter, isNull);
      expect(config.useFirebaseCrashlytics, isTrue);
      expect(config.enableInDebug, isFalse);
      expect(config.enableOnWeb, isFalse);
    });
  });

  group('MockErrorReporter', () {
    late MockErrorReporter reporter;

    setUp(() {
      reporter = MockErrorReporter();
    });

    test('initialize sets flag', () async {
      expect(reporter.initializeCalled, isFalse);
      await reporter.initialize();
      expect(reporter.initializeCalled, isTrue);
    });

    test('recordError adds to list', () {
      final error = Exception('Test error');
      final stackTrace = StackTrace.current;

      expect(reporter.recordedErrors, isEmpty);
      reporter.recordError(error, stackTrace);
      expect(reporter.recordedErrors, hasLength(1));
      expect(reporter.recordedErrors.first, equals(error));
    });

    test('recordFlutterError adds to list', () {
      final details = FlutterErrorDetails(
        exception: Exception('Flutter test error'),
      );

      expect(reporter.recordedFlutterErrors, isEmpty);
      reporter.recordFlutterError(details);
      expect(reporter.recordedFlutterErrors, hasLength(1));
      expect(reporter.recordedFlutterErrors.first, equals(details));
    });

    test('reset clears all data', () async {
      await reporter.initialize();
      reporter.recordError(Exception('Test'), null);
      reporter.recordFlutterError(
        FlutterErrorDetails(exception: Exception('Test')),
      );

      expect(reporter.initializeCalled, isTrue);
      expect(reporter.recordedErrors, hasLength(1));
      expect(reporter.recordedFlutterErrors, hasLength(1));

      reporter.reset();

      expect(reporter.initializeCalled, isFalse);
      expect(reporter.recordedErrors, isEmpty);
      expect(reporter.recordedFlutterErrors, isEmpty);
    });

    test('multiple errors are tracked', () {
      reporter.recordError(Exception('Error 1'), null);
      reporter.recordError(Exception('Error 2'), null);
      reporter.recordError(Exception('Error 3'), null);

      expect(reporter.recordedErrors, hasLength(3));
    });
  });
}
