import 'dart:async';

import 'package:flutter/foundation.dart';

import 'error_reporter_interface.dart';

/// An [ErrorReporter] that fans every call out to multiple backends so several
/// crash-reporting SDKs (e.g. Sentry + Firebase Crashlytics) can run
/// concurrently (BEH-2 / ERH-023).
///
/// Single-backend stays the common, frictionless case — wrap children in a
/// [CompositeErrorReporter] only when you genuinely run more than one backend.
/// dreamic stays **backend-agnostic**: this primitive depends on no specific
/// SDK; the children do.
///
/// **Per-child isolation (BEH-11):** every fan-out call wraps each child in its
/// **own** try/catch, so one child throwing in `recordError` / `addBreadcrumb` /
/// `setUser` / `clearUser` (or failing to initialize) never blocks the others
/// and never crashes the app. A child that fails to [initialize] is logged
/// (console only) and **skipped** on every subsequent call.
///
/// **Flag reconciliation (ERH-007):** the composite carries no
/// `reporterRequiresFirebase` / `customReporterManagesErrorHandlers` flags — they
/// live on `ErrorReportingConfig`. The consumer computes the OR'd values across
/// the children it composes and passes them in the config alongside this
/// composite.
class CompositeErrorReporter extends ErrorReporter {
  CompositeErrorReporter(this.reporters);

  /// The child reporters this composite fans out to.
  final List<ErrorReporter> reporters;

  /// Children whose [initialize] threw — excluded from every subsequent fan-out
  /// so a broken backend stays out of the way (BEH-11). Identity-based so a
  /// re-registered instance is treated independently.
  final Set<ErrorReporter> _failedReporters = Set<ErrorReporter>.identity();

  /// The currently-usable children (every child that did not fail to
  /// initialize). Used by all fan-out methods.
  Iterable<ErrorReporter> get _activeReporters =>
      reporters.where((r) => !_failedReporters.contains(r));

  /// Initializes every child concurrently.
  ///
  /// Each child is invoked via `Future.sync(() => child.initialize())` **before**
  /// the per-child `.catchError` guard, so a child whose `initialize()` throws
  /// **synchronously** (before returning a Future) is caught too — a bare
  /// `child.initialize().catchError(...)` would let a synchronous throw escape
  /// `Future.wait` and abort the whole group, crashing boot (ERH-043 / BEH-11).
  ///
  /// `Future.wait(..., eagerError: false)` waits for ALL children regardless of
  /// individual failures: one child's init failure never aborts the group. A
  /// failed child is logged (console only) and recorded in [_failedReporters] so
  /// it is skipped on every subsequent fan-out call.
  @override
  Future<void> initialize() async {
    await Future.wait(
      reporters.map(
        (reporter) => Future.sync(() => reporter.initialize()).catchError(
          (Object e, StackTrace _) {
            _failedReporters.add(reporter);
            debugPrint(
              'CompositeErrorReporter: child ${reporter.runtimeType} failed to '
              'initialize (suppressed; skipped on subsequent calls): $e',
            );
          },
        ),
      ),
      eagerError: false,
    );
  }

  @override
  void recordError(Object error, StackTrace? stackTrace) {
    for (final reporter in _activeReporters) {
      try {
        reporter.recordError(error, stackTrace);
      } catch (e) {
        debugPrint(
          'CompositeErrorReporter: child ${reporter.runtimeType}.recordError '
          'threw (suppressed; other backends unaffected): $e',
        );
      }
    }
  }

  @override
  void recordFlutterError(FlutterErrorDetails details) {
    for (final reporter in _activeReporters) {
      try {
        reporter.recordFlutterError(details);
      } catch (e) {
        debugPrint(
          'CompositeErrorReporter: child ${reporter.runtimeType}.'
          'recordFlutterError threw (suppressed; other backends unaffected): $e',
        );
      }
    }
  }

  @override
  void addBreadcrumb(String message, {String? category, Map<String, dynamic>? data}) {
    for (final reporter in _activeReporters) {
      try {
        reporter.addBreadcrumb(message, category: category, data: data);
      } catch (e) {
        debugPrint(
          'CompositeErrorReporter: child ${reporter.runtimeType}.addBreadcrumb '
          'threw (suppressed; other backends unaffected): $e',
        );
      }
    }
  }

  @override
  void setUser(String userId, {String? email, String? username}) {
    for (final reporter in _activeReporters) {
      try {
        reporter.setUser(userId, email: email, username: username);
      } catch (e) {
        debugPrint(
          'CompositeErrorReporter: child ${reporter.runtimeType}.setUser threw '
          '(suppressed; other backends unaffected): $e',
        );
      }
    }
  }

  @override
  void clearUser() {
    for (final reporter in _activeReporters) {
      try {
        reporter.clearUser();
      } catch (e) {
        debugPrint(
          'CompositeErrorReporter: child ${reporter.runtimeType}.clearUser threw '
          '(suppressed; other backends unaffected): $e',
        );
      }
    }
  }
}
