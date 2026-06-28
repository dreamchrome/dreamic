import 'package:dreamic/error_reporting/error_reporter_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mock error reporter for testing. `extends ErrorReporter` so it inherits the
/// default no-op `addBreadcrumb` / `setUser` / `clearUser`, overriding only what
/// it cares about.
class MockErrorReporter extends ErrorReporter {
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

/// A minimal reporter that overrides ONLY [recordError] — proving the other
/// members have working defaults.
class MinimalErrorReporter extends ErrorReporter {
  final List<Object> recordedErrors = [];

  @override
  void recordError(Object error, StackTrace? stackTrace) => recordedErrors.add(error);
}

void main() {
  group('ErrorReportingConfig', () {
    test('customOnly creates correct configuration', () {
      final reporter = MockErrorReporter();
      final config = ErrorReportingConfig.customOnly(
        reporter: reporter,
        enableInDebug: false,
        enableOnWeb: true,
      );

      expect(config.customReporter, equals(reporter));
      expect(config.enableInDebug, isFalse);
      expect(config.enableOnWeb, isTrue);
      expect(config.reporterRequiresFirebase, isFalse);
      expect(config.customReporterManagesErrorHandlers, isFalse);
    });

    test('customOnly honors requiresFirebase + managesOwnErrorHandlers', () {
      final reporter = MockErrorReporter();
      final config = ErrorReportingConfig.customOnly(
        reporter: reporter,
        requiresFirebase: true,
        managesOwnErrorHandlers: true,
      );

      expect(config.reporterRequiresFirebase, isTrue);
      expect(config.customReporterManagesErrorHandlers, isTrue);
    });

    test('default configuration has no reporter (no reporting)', () {
      const config = ErrorReportingConfig();

      expect(config.customReporter, isNull);
      expect(config.enableInDebug, isFalse);
      expect(config.enableOnWeb, isFalse);
      expect(config.reporterRequiresFirebase, isFalse);
    });
  });

  group('ErrorReporter defaults (folded-in members)', () {
    test('minimal reporter: addBreadcrumb / setUser / clearUser are no-op', () {
      final reporter = MinimalErrorReporter();

      // None of the default members throw, and none route to recordError.
      reporter.addBreadcrumb('crumb', category: 'bootstrap', data: {'k': 'v'});
      reporter.setUser('uid-1', email: 'a@b.c', username: 'ab');
      reporter.clearUser();

      expect(reporter.recordedErrors, isEmpty);
    });

    test('minimal reporter: recordFlutterError defaults to recordError', () {
      final reporter = MinimalErrorReporter();
      final ex = Exception('flutter');

      reporter.recordFlutterError(FlutterErrorDetails(exception: ex));

      expect(reporter.recordedErrors, equals([ex]));
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
