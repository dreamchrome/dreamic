import 'package:dreamic/error_reporting/composite_error_reporter.dart';
import 'package:dreamic/error_reporting/error_reporter_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records every fan-out call so the test can assert each child received it.
class _RecordingReporter extends ErrorReporter {
  final List<Object> errors = [];
  final List<FlutterErrorDetails> flutterErrors = [];
  final List<String> breadcrumbs = [];
  final List<String> usersSet = [];
  int clearUserCalls = 0;
  bool initialized = false;

  @override
  Future<void> initialize() async {
    initialized = true;
  }

  @override
  void recordError(Object error, StackTrace? stackTrace) => errors.add(error);

  @override
  void recordFlutterError(FlutterErrorDetails details) => flutterErrors.add(details);

  @override
  void addBreadcrumb(String message, {String? category, Map<String, dynamic>? data}) =>
      breadcrumbs.add(message);

  @override
  void setUser(String userId, {String? email, String? username}) => usersSet.add(userId);

  @override
  void clearUser() => clearUserCalls++;
}

/// A child that throws in EVERY fan-out member — proves per-child isolation: a
/// sibling still receives the call (BEH-11).
class _ThrowingReporter extends ErrorReporter {
  @override
  void recordError(Object error, StackTrace? stackTrace) =>
      throw StateError('recordError blew up');

  @override
  void recordFlutterError(FlutterErrorDetails details) =>
      throw StateError('recordFlutterError blew up');

  @override
  void addBreadcrumb(String message, {String? category, Map<String, dynamic>? data}) =>
      throw StateError('addBreadcrumb blew up');

  @override
  void setUser(String userId, {String? email, String? username}) =>
      throw StateError('setUser blew up');

  @override
  void clearUser() => throw StateError('clearUser blew up');
}

/// A child whose `initialize()` throws **synchronously** (before returning a
/// Future) — the ERH-043 case that a bare `child.initialize().catchError(...)`
/// would let escape `Future.wait`.
class _SyncInitThrowsReporter extends ErrorReporter {
  bool recordCalled = false;

  @override
  Future<void> initialize() {
    throw StateError('synchronous init failure');
  }

  @override
  void recordError(Object error, StackTrace? stackTrace) => recordCalled = true;
}

/// A child whose `initialize()` rejects **asynchronously**.
class _AsyncInitThrowsReporter extends ErrorReporter {
  bool recordCalled = false;

  @override
  Future<void> initialize() async {
    throw StateError('async init failure');
  }

  @override
  void recordError(Object error, StackTrace? stackTrace) => recordCalled = true;
}

void main() {
  group('CompositeErrorReporter — fan-out (BEH-2)', () {
    test('every call reaches every child', () {
      final a = _RecordingReporter();
      final b = _RecordingReporter();
      final composite = CompositeErrorReporter([a, b]);

      final st = StackTrace.current;
      final err = StateError('boom');
      composite.recordError(err, st);
      composite.addBreadcrumb('crumb', category: 'cat', data: {'k': 'v'});
      composite.setUser('u1', email: 'e@x.com', username: 'name');
      composite.clearUser();
      composite.recordFlutterError(
        FlutterErrorDetails(exception: err, stack: st),
      );

      for (final r in [a, b]) {
        expect(r.errors, [err]);
        expect(r.breadcrumbs, ['crumb']);
        expect(r.usersSet, ['u1']);
        expect(r.clearUserCalls, 1);
        expect(r.flutterErrors, hasLength(1));
      }
    });
  });

  group('CompositeErrorReporter — per-child isolation (BEH-11)', () {
    test('a child throwing in recordError never blocks siblings', () {
      final throwing = _ThrowingReporter();
      final healthy = _RecordingReporter();
      // Throwing child FIRST so it would short-circuit a naive loop.
      final composite = CompositeErrorReporter([throwing, healthy]);

      final err = StateError('boom');
      expect(() => composite.recordError(err, null), returnsNormally);
      expect(healthy.errors, [err]);
    });

    test('a child throwing in addBreadcrumb/setUser/clearUser/recordFlutterError '
        'never blocks siblings', () {
      final throwing = _ThrowingReporter();
      final healthy = _RecordingReporter();
      final composite = CompositeErrorReporter([throwing, healthy]);
      final st = StackTrace.current;

      expect(() => composite.addBreadcrumb('c'), returnsNormally);
      expect(() => composite.setUser('u'), returnsNormally);
      expect(() => composite.clearUser(), returnsNormally);
      expect(
        () => composite.recordFlutterError(
          FlutterErrorDetails(exception: StateError('e'), stack: st),
        ),
        returnsNormally,
      );

      expect(healthy.breadcrumbs, ['c']);
      expect(healthy.usersSet, ['u']);
      expect(healthy.clearUserCalls, 1);
      expect(healthy.flutterErrors, hasLength(1));
    });
  });

  group('CompositeErrorReporter — initialize (ERH-043 / BEH-11)', () {
    test('all healthy children initialize even when one rejects ASYNCHRONOUSLY',
        () async {
      final healthy = _RecordingReporter();
      final failing = _AsyncInitThrowsReporter();
      final composite = CompositeErrorReporter([failing, healthy]);

      await expectLater(composite.initialize(), completes);
      expect(healthy.initialized, isTrue);
    });

    test('a child that throws SYNCHRONOUSLY in initialize is caught (does not '
        'abort the group)', () async {
      final healthy = _RecordingReporter();
      final failing = _SyncInitThrowsReporter();
      // Failing child FIRST: a bare `.initialize().catchError(...)` would let the
      // synchronous throw escape Future.wait before `healthy` is invoked.
      final composite = CompositeErrorReporter([failing, healthy]);

      await expectLater(composite.initialize(), completes);
      expect(healthy.initialized, isTrue);
    });

    test('a child that failed to initialize is SKIPPED on subsequent fan-out',
        () async {
      final healthy = _RecordingReporter();
      final failing = _SyncInitThrowsReporter();
      final composite = CompositeErrorReporter([failing, healthy]);

      await composite.initialize();

      final err = StateError('boom');
      composite.recordError(err, null);

      // The failed child is skipped entirely (its recordError is never invoked).
      expect(failing.recordCalled, isFalse);
      // The healthy child still receives the fan-out.
      expect(healthy.errors, [err]);
    });
  });
}
