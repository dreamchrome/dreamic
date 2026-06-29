import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:dreamic/app/app_config_base.dart';
import 'package:dreamic/error_reporting/error_reporter_interface.dart';
import 'package:dreamic/utils/logger.dart';

/// Global error reporting configuration
ErrorReportingConfig? _errorReportingConfig;

/// One buffered error captured by the early handlers before the reporter is
/// attached.
class _BufferedError {
  _BufferedError(this.error, this.stackTrace);
  final Object error;
  final StackTrace? stackTrace;
}

/// Maximum number of errors held in the early buffer. A pre-attach crash loop
/// must not grow the buffer without bound, so the buffer drops the OLDEST
/// entry once it exceeds this cap (Issue 16/82).
const int _earlyErrorBufferCap = 50;

/// Module-level, always-initialized (never lazy/nullable) buffer of errors the
/// early handlers caught BEFORE the reporter attached (Issue 36).
///
/// Always-present so the flush at [appInitErrorHandling] is a safe no-op for
/// apps that call `appInitErrorHandling` WITHOUT [installEarlyErrorHandlers]
/// (e.g. `mypurposeplan_admin`): the buffer is simply empty and the flush
/// returns immediately. A lazy/nullable buffer would NPE on their startup.
/// Capped at [_earlyErrorBufferCap] with drop-oldest semantics.
final List<_BufferedError> _earlyErrorBuffer = <_BufferedError>[];

/// Whether [appInitErrorHandling] has run (reporter attached, or reporting
/// determined disabled). Gates [reportBootstrapDiagnostic]: before this, a
/// bootstrap diagnostic is DEFERRED; after, it reports immediately.
bool _errorHandlingAttached = false;

/// One bootstrap diagnostic (error + message + stack) captured BEFORE the
/// reporter attached.
class _DeferredBootstrapReport {
  _DeferredBootstrapReport(this.error, this.message, this.stackTrace);
  final Object error;
  final String message;
  final StackTrace? stackTrace;
}

/// Bootstrap diagnostics reported before the reporter attached — flushed when
/// [appInitErrorHandling] attaches. Capped like the early buffer (drop-oldest).
final List<_DeferredBootstrapReport> _deferredBootstrapReports =
    <_DeferredBootstrapReport>[];

/// Apply-once guard for the isolate error-listener registration (Issue 31).
///
/// `Isolate.current.addErrorListener` ALLOWS multiple listeners, so each retry
/// re-run of [appInitErrorHandling] would otherwise accumulate another listener
/// (a leak — uncaught isolate errors then reported N times). Setting
/// `FlutterError.onError` / `PlatformDispatcher.onError` is overwrite-idempotent
/// and needs no guard; only the listener ADD does. Module-level so it survives
/// across the gate-retry re-runs; reset for tests via
/// [resetDreamicBootstrapIdempotencyForTest].
bool _isolateErrorListenerAdded = false;

void _bufferEarlyError(Object error, StackTrace? stackTrace) {
  _earlyErrorBuffer.add(_BufferedError(error, stackTrace));
  // Drop-oldest beyond the cap so an unbounded pre-attach crash loop cannot
  // grow the buffer (Issue 16). removeAt(0) keeps the most-recent [cap] entries.
  while (_earlyErrorBuffer.length > _earlyErrorBufferCap) {
    _earlyErrorBuffer.removeAt(0);
  }
}

// ---------------------------------------------------------------------------
// Error chokepoint (`_recordErrorSafe`) — Phase 3 (ERH-011/003/028/021/032).
//
// Every capture surface (the isolate listener here; the guarded zone + web-JS
// handlers wired in Phase 4) routes through `_recordErrorSafe` so they share one
// re-entrancy guard, one cross-surface dedup, one redaction pass, and one
// pre-attach buffering fallback.
// ---------------------------------------------------------------------------

/// The reporter `_recordErrorSafe` forwards to once attached. Set ONLY on the
/// active production path in [appInitErrorHandling] (the same place
/// `Logger.setCustomErrorReporter` is set), and cleared on every disabled/
/// blocked path so `_recordErrorSafe` falls back to buffering. `null` ⇒ no
/// reporter attached yet (or reporting suppressed) ⇒ buffer into
/// [_earlyErrorBuffer] (ERH-011 / BEH-12).
ErrorReporter? _activeReporter;

/// Re-entrancy guard for the whole record path (redaction + dedup + forward).
/// While a report is in flight, any error raised inside it is logged to console
/// only and never re-reported, so a failing reporter/redaction cannot recurse
/// (ERH-011 / BEH-11). Cleared in a `finally` so a thrown report still resets it.
bool _reportingInFlight = false;

/// Capacity of the cross-surface dedup set. The same `(error, stack)` re-arriving
/// (e.g. via both the zone and `PlatformDispatcher.onError`) is reported once
/// (ERH-003, ERH-028 / BEH-9). Small + FIFO drop-oldest so a long-running app
/// never accumulates keys without bound.
const int _dedupSetCapacity = 20;

/// FIFO-ordered identity keys of the most-recent [_dedupSetCapacity] reported
/// errors. Keyed on the ORIGINAL `(error.toString(), stackTrace.toString())`
/// identity **before** redaction (ERH-028), so a fail-closed redaction
/// placeholder can never collapse two distinct errors into one (BEH-9). A List
/// (not a Set) preserves insertion order for the drop-oldest eviction; the set
/// is small so the linear `contains` is negligible.
final List<String> _recentErrorKeys = <String>[];

/// Returns the dedup identity for an `(error, stackTrace)` pair, computed on the
/// ORIGINAL (pre-redaction) values.
String _dedupKey(Object error, StackTrace? stackTrace) =>
    '${error.toString()} ${stackTrace?.toString() ?? ''}';

/// Records [key] in the bounded dedup set, evicting the oldest beyond the cap.
void _rememberErrorKey(String key) {
  _recentErrorKeys.add(key);
  while (_recentErrorKeys.length > _dedupSetCapacity) {
    _recentErrorKeys.removeAt(0);
  }
}

/// The single error chokepoint. Every capture surface routes here so they all
/// share: a re-entrancy guard, cross-surface dedup (keyed pre-redaction), a
/// central redaction pass, and a pre-attach buffering fallback. Non-throwing.
///
/// Order is load-bearing:
///  1. Re-entrancy short-circuit (an error raised WHILE reporting → console only).
///  2. Dedup check on the ORIGINAL `(error, stack)` identity, BEFORE redaction
///     (ERH-028 / BEH-9) — a redaction placeholder can never over-collapse.
///  3. If no reporter is attached → buffer the ORIGINAL into [_earlyErrorBuffer]
///     (reported via `loge()` on the attach flush) and return — pre-attach
///     zone/web-JS/isolate errors are retained (ERH-011 / BEH-12).
///  4. Redact (ERH-005, fail-closed) and forward to the attached reporter.
///
/// The whole path (including redaction + forward) runs inside the re-entrancy
/// guard so a redaction or reporter failure cannot re-enter (ERH-011 / BEH-11).
void _recordErrorSafe(Object error, StackTrace? stackTrace) {
  // (1) Re-entrancy: never report an error raised while reporting.
  if (_reportingInFlight) {
    debugPrint('Suppressed re-entrant error during reporting: $error');
    return;
  }
  _reportingInFlight = true;
  try {
    // (2) Dedup on the ORIGINAL identity, before redaction (ERH-028 / BEH-9).
    final key = _dedupKey(error, stackTrace);
    if (_recentErrorKeys.contains(key)) {
      return; // Already reported this exact (error, stack) — skip.
    }
    _rememberErrorKey(key);

    // (3) No reporter attached → buffer for the attach-time flush (BEH-12).
    //     Buffer the ORIGINAL (un-redacted): the flush re-reports via `loge()`,
    //     and the dedup key (recorded above on the original) already prevents a
    //     post-attach re-arrival of this same (error, stack) from double-
    //     reporting. The `loge()` flush IS redacted (fail-closed) centrally in
    //     `Logger._crashReport` before it reaches any backend, so a pre-attach
    //     error carrying a secret is scrubbed on flush just like a post-attach
    //     direct report (BEH-8) — buffering the original keeps the dedup key and
    //     rich type intact until that single central redaction runs.
    if (_activeReporter == null) {
      _bufferEarlyError(error, stackTrace);
      return;
    }

    // (4) Redact (fail-closed) + forward to the attached reporter.
    final redacted = Logger.redactErrorForReporting(error);
    _activeReporter!.recordError(redacted, stackTrace);
  } catch (e) {
    // The record path itself must never throw into the caller (BEH-11). The
    // re-entrancy guard above already prevents this from re-reporting.
    debugPrint('Error while recording an error (suppressed): $e');
  } finally {
    _reportingInFlight = false;
  }
}

/// Public production entry point into the single error chokepoint.
///
/// Routes [error] / [stackTrace] through the private `_recordErrorSafe` (the
/// re-entrancy guard + cross-surface dedup + redaction + pre-attach buffering),
/// keeping `_recordErrorSafe` itself private. Used by the guarded zone's
/// `onError` ([DreamicErrorHandling.runGuarded] / [DreamicErrorHandling.recordZoneError])
/// and by the conditional-import web-JS handler module, so every Dart-side
/// capture surface funnels through the one chokepoint (ERH-001 / BEH-1, BEH-9).
///
/// Non-throwing (the chokepoint swallows its own failures).
void recordCapturedError(Object error, StackTrace? stackTrace) {
  _recordErrorSafe(error, stackTrace);
}

/// Test-only access to the current dedup-set size (ERH-003/028).
@visibleForTesting
int get dedupSetLengthForTest => _recentErrorKeys.length;

/// Test-only seam: route an `(error, stackTrace)` through the real chokepoint so
/// the re-entrancy / dedup / buffering behavior can be unit-tested without
/// driving a real isolate/zone/web-JS surface (mirrors `bufferEarlyErrorForTest`
/// but exercises the full `_recordErrorSafe` path).
@visibleForTesting
void recordErrorSafeForTest(Object error, [StackTrace? stackTrace]) {
  _recordErrorSafe(error, stackTrace);
}

/// Test-only seam: install a reporter as the active chokepoint target without
/// running the whole [appInitErrorHandling] branch, so `_recordErrorSafe`'s
/// attached-vs-buffering split can be exercised in isolation. Pass `null` to
/// simulate the pre-attach (unattached) state.
@visibleForTesting
void setActiveReporterForTest(ErrorReporter? reporter) {
  _activeReporter = reporter;
}

/// Test-only reset of the chokepoint module state (re-entrancy guard, dedup set,
/// active reporter) so module-level statics do not leak across test cases.
@visibleForTesting
void resetRecordErrorSafeStateForTest() {
  _reportingInFlight = false;
  _recentErrorKeys.clear();
  _activeReporter = null;
}

/// In debug builds, forwards [details] to Flutter's default error presenter
/// ([FlutterError.presentError]) so the error still reaches DevTools / the IDE
/// runtime-error inspector and the console still gets the standard, fully
/// formatted block (including the "relevant error-causing widget" attribution).
///
/// Every error handler below REPLACES [FlutterError.onError]. Without this call
/// the framework's default presentation is lost and debug tooling goes blind to
/// framework errors — they surface only through our own `loge()` / `debugPrint`
/// dump, with no structured DevTools event and no widget attribution. No-op in
/// release so production consoles / crash reporters are unaffected.
void _presentErrorInDebugConsole(FlutterErrorDetails details) {
  if (kDebugMode) {
    FlutterError.presentError(details);
  }
}

/// Installs synchronous, dependency-free error handlers that BUFFER caught
/// errors into a bounded module-level list until the reporter attaches.
///
/// **Call this as an explicit `main()` line, pre-`runApp`, right after
/// `WidgetsFlutterBinding.ensureInitialized()`** — never fold it into the
/// gate/host/bootstrap. A widget's `initState` and the async bootstrap both run
/// AFTER `runApp`, so folding would install these handlers too late to capture
/// pre-mount / pre-attach errors (e.g. a `FlutterError` thrown while painting
/// the splash frame, or an error before Crashlytics attaches inside
/// `dreamicBootstrap()`).
///
/// When [appInitErrorHandling] later runs it FLUSHES (and clears) this buffer
/// to the attached reporter on every one of its code paths, so nothing caught
/// in the pre-attach window is lost.
///
/// Idempotent: a second call (e.g. a gate-retry re-run of any `main()`-shaped
/// code) re-installs the same overwrite-idempotent `FlutterError.onError` /
/// `PlatformDispatcher.onError` handlers and does not duplicate state.
void installEarlyErrorHandlers() {
  FlutterError.onError = (FlutterErrorDetails details) {
    _presentErrorInDebugConsole(details);
    debugPrint('Early Flutter Error: ${details.exceptionAsString()}');
    debugPrint('Stack trace:\n${details.stack}');
    _bufferEarlyError(details.exception, details.stack);
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stackTrace) {
    debugPrint('Early Platform Error: $error');
    debugPrint('Stack trace:\n$stackTrace');
    _bufferEarlyError(error, stackTrace);
    return true;
  };
}

/// Flushes every buffered early error to the now-attached reporter, then clears
/// the buffer.
///
/// Routes each buffered error through `loge()` so a single reporting path
/// (`Logger.error` → `_crashReport` → Crashlytics / custom reporter) covers the
/// flush — matching how the app-init gate reports its own `onError` (Issue 51).
///
/// Safe no-op when [installEarlyErrorHandlers] was never called: the buffer is
/// always-present and empty in that case (Issue 36).
void _flushAndClearEarlyErrorBuffer() {
  if (_earlyErrorBuffer.isEmpty) {
    return;
  }
  // Snapshot then clear FIRST, so a reporter that re-enters (or a concurrent
  // early handler) cannot re-flush the same entries.
  final buffered = List<_BufferedError>.of(_earlyErrorBuffer);
  _earlyErrorBuffer.clear();
  for (final entry in buffered) {
    loge(entry.error, 'Buffered early error (pre-reporter-attach)', entry.stackTrace);
  }
}

/// Flushes every breadcrumb buffered (already gated + redacted at emit time)
/// before the reporter attached to the now-attached [reporter], then clears the
/// early-breadcrumb buffer.
///
/// **Ordering (ERH-032 / BEH-12):** this runs BEFORE [_flushAndClearEarlyErrorBuffer]
/// so each buffered early error is reported with its preceding breadcrumb context
/// already in place (rather than orphaning the breadcrumbs onto a later event).
///
/// The drained crumbs were redacted once at emit time — forward them **without**
/// re-redacting (`Logger.drainEarlyBreadcrumbs()` returns the already-redacted
/// snapshot and clears the buffer). Wrapped per-crumb so one failed `addBreadcrumb`
/// can't abort the flush (breadcrumbs are diagnostic — BEH-11).
void _flushAndClearEarlyBreadcrumbs(ErrorReporter reporter) {
  final crumbs = Logger.drainEarlyBreadcrumbs();
  for (final crumb in crumbs) {
    try {
      reporter.addBreadcrumb(
        crumb.message,
        category: crumb.category,
        data: crumb.data,
      );
    } catch (e) {
      debugPrint('Failed to flush an early breadcrumb (suppressed): $e');
    }
  }
}

/// Drops every buffered early error WITHOUT reporting (error reporting is
/// disabled on this path) and clears the buffer.
///
/// Safe no-op when [installEarlyErrorHandlers] was never called (Issue 36).
void _logAndClearEarlyErrorBuffer(String reason) {
  if (_earlyErrorBuffer.isEmpty) {
    return;
  }
  debugPrint(
    'Discarding ${_earlyErrorBuffer.length} buffered early error(s) — $reason',
  );
  _earlyErrorBuffer.clear();
}

/// Reports a bootstrap-time diagnostic that may fire BEFORE the error reporter
/// is attached, ensuring every consumer's backend captures it.
///
/// The `appInitFirebase` hang-recovery fires at the Firebase step. A custom
/// reporter that attaches before Firebase (e.g. Sentry via
/// `attachErrorReportingFirst`) is already live then, so this reports
/// immediately. A Firebase Crashlytics consumer does not attach until the
/// post-Firebase step, so this DEFERS the report and [appInitErrorHandling]
/// flushes it on attach — closing the "Crashlytics recovers silently" gap.
///
/// Non-throwing; safe to call any number of times. Deferred reports are capped
/// (drop-oldest) like the early buffer so a pre-attach loop can't grow it
/// unbounded.
void reportBootstrapDiagnostic(Object error, String message, [StackTrace? stackTrace]) {
  if (_errorHandlingAttached) {
    loge(error, message, stackTrace);
    return;
  }
  _deferredBootstrapReports.add(_DeferredBootstrapReport(error, message, stackTrace));
  while (_deferredBootstrapReports.length > _earlyErrorBufferCap) {
    _deferredBootstrapReports.removeAt(0);
  }
}

/// Flushes every deferred bootstrap diagnostic to the now-attached reporter via
/// `loge`, then clears them. No-op when none were deferred.
void _flushDeferredBootstrapReports() {
  if (_deferredBootstrapReports.isEmpty) {
    return;
  }
  final reports = List<_DeferredBootstrapReport>.of(_deferredBootstrapReports);
  _deferredBootstrapReports.clear();
  for (final r in reports) {
    loge(r.error, r.message, r.stackTrace);
  }
}

/// Drops deferred bootstrap diagnostics WITHOUT reporting (reporting disabled on
/// this path).
void _dropDeferredBootstrapReports() {
  _deferredBootstrapReports.clear();
}

/// Resets the early-error buffer state for tests. The buffer and the
/// installed-flag are module-level statics that persist across test cases in
/// one VM, so without a reset the buffer/flush assertions become order-
/// dependent (Issue 63).
@visibleForTesting
void resetEarlyErrorHandlersForTest() {
  _earlyErrorBuffer.clear();
  _deferredBootstrapReports.clear();
  _errorHandlingAttached = false;
  // Phase 3 chokepoint state is module-level too — reset it alongside so the
  // dedup/re-entrancy/active-reporter assertions stay order-independent.
  _reportingInFlight = false;
  _recentErrorKeys.clear();
  _activeReporter = null;
}

/// Resets the isolate error-listener apply-once flag (Issue 31/63) so the
/// "added at most once across retries" assertion is order-independent. Internal
/// test-support seam invoked only by the combined
/// `resetDreamicBootstrapIdempotencyForTest()` (the documented
/// `@visibleForTesting` entry point) — not `@visibleForTesting` itself so the
/// combined reset can call it without a cross-file visibility-lint warning.
void resetIsolateErrorListenerFlag() {
  _isolateErrorListenerAdded = false;
}

/// Test-only access to the current buffered-error count (Issue 16/82).
@visibleForTesting
int get earlyErrorBufferLengthForTest => _earlyErrorBuffer.length;

/// Test-only seam to push an error into the buffer as the early handlers would,
/// so the bounded-buffer / flush tests do not need to drive real
/// `FlutterError.onError` (Issue 16/82).
@visibleForTesting
void bufferEarlyErrorForTest(Object error, [StackTrace? stackTrace]) {
  _bufferEarlyError(error, stackTrace);
}

/// Configure error reporting before calling appInitErrorHandling()
///
/// Example with Sentry:
/// ```dart
/// configureErrorReporting(ErrorReportingConfig.customOnly(
///   reporter: SentryErrorReporter(),
/// ));
/// await appInitErrorHandling();
/// ```
void configureErrorReporting(ErrorReportingConfig config) {
  _errorReportingConfig = config;
}

/// Get the current error reporting configuration
ErrorReportingConfig get errorReportingConfig =>
    _errorReportingConfig ?? const ErrorReportingConfig();

/// Sets up minimal error handlers that only log to console.
/// Used when error reporting is completely disabled.
/// Note: Uses debugPrint directly to avoid any potential for error reporting
/// loops through loge -> _crashReport.
void _setupMinimalErrorHandlers() {
  FlutterError.onError = (details) {
    _presentErrorInDebugConsole(details);
    debugPrint('Flutter Error: ${details.exceptionAsString()}');
    debugPrint('Stack trace:\n${details.stack}');
  };

  PlatformDispatcher.instance.onError = (exception, stackTrace) {
    debugPrint('Platform Error: $exception');
    debugPrint('Stack trace:\n$stackTrace');
    return true;
  };
}

Future<void> appInitErrorHandling() async {
  final config = errorReportingConfig;

  // Set the error reporting configuration in Logger
  Logger.setErrorReportingConfig(config);

  // Check for master kill switch first - this disables ALL error reporting
  // regardless of other settings. Use for live Firebase dev projects.
  if (AppConfigBase.doDisableErrorReporting) {
    debugPrint('Error Reporting DISABLED via DO_DISABLE_ERROR_REPORTING');
    _setupMinimalErrorHandlers();
    // (b) Kill-switch path — reporting is disabled, so the early buffer cannot
    // be flushed anywhere; drop+clear it (a no-op when the installer was never
    // called). MUST run before the early `return`, or the buffer leaks (Issue 35).
    _logAndClearEarlyErrorBuffer('error reporting disabled (kill switch)');
    // Reporting is off — no chokepoint target, so `_recordErrorSafe` (e.g. a
    // re-routed isolate error) buffers (and that buffer is dropped next attach).
    _activeReporter = null;
    // Reporting is off — drop any deferred bootstrap diagnostics and mark
    // attached so later ones short-circuit (loge no-ops under the kill switch).
    _errorHandlingAttached = true;
    _dropDeferredBootstrapReports();
    return;
  }

  // Determine if error reporting is blocked by emulator mode
  // Can be overridden with DO_FORCE_ERROR_REPORTING for testing
  final isBlockedByEmulator =
      AppConfigBase.doUseBackendEmulator && !AppConfigBase.doForceErrorReporting;

  // Determine if we should use error reporting
  // This must be checked BEFORE initializing reporters to prevent
  // Sentry/Crashlytics from capturing errors when running in emulator
  final shouldUseErrorReporting = !isBlockedByEmulator &&
      (config.enableInDebug || !kDebugMode) &&
      (config.enableOnWeb || !kIsWeb);

  // Custom reporter follows the same rules as main error reporting
  // The enableOnWeb/enableInDebug flags allow reporting on those platforms,
  // but only when not blocked by emulator mode or master kill switch
  final shouldUseCustomReporter = config.customReporter != null &&
      !isBlockedByEmulator &&
      ((config.enableInDebug || !kDebugMode) && (config.enableOnWeb || !kIsWeb));

  debugPrint('Error Reporting Configuration: '
      'customReporter=${config.customReporter != null}, '
      'customReporterManagesErrorHandlers=${config.customReporterManagesErrorHandlers}, '
      'reporterRequiresFirebase=${config.reporterRequiresFirebase}, '
      'enableInDebug=${config.enableInDebug}, '
      'enableOnWeb=${config.enableOnWeb}, '
      'doUseBackendEmulator=${AppConfigBase.doUseBackendEmulator}, '
      'doForceErrorReporting=${AppConfigBase.doForceErrorReporting}, '
      'isBlockedByEmulator=$isBlockedByEmulator, '
      'shouldUseErrorReporting=$shouldUseErrorReporting, '
      'shouldUseCustomReporter=$shouldUseCustomReporter, '
      'environmentType=${AppConfigBase.environmentType.value}');

  // Initialize custom reporter ONLY if it should be used
  // This prevents Sentry/etc from setting up internal error handlers
  // when running in emulator mode
  if (shouldUseCustomReporter) {
    await config.customReporter!.initialize();
    // Set the custom error reporter in Logger for crash reporting
    Logger.setCustomErrorReporter(config.customReporter);
    // Attach the chokepoint target so `_recordErrorSafe` (the isolate listener,
    // plus the Phase-4 zone/web-JS surfaces) forwards instead of buffering
    // (ERH-011/021). Set here so it is live BEFORE the buffer flush below.
    _activeReporter = config.customReporter;
  } else {
    // No active reporter on this path — `_recordErrorSafe` falls back to
    // buffering (its buffer is dropped on the disabled/blocked branch below).
    _activeReporter = null;
  }

  // Disable analytics and crashlytics for web or emulator (unless configured otherwise)
  if (!shouldUseErrorReporting) {
    FlutterError.onError = (details) {
      _presentErrorInDebugConsole(details);
      loge(details.stack ?? StackTrace.current, details.exceptionAsString());

      // Still report to custom reporter if it was initialized (enabled on web/debug)
      if (shouldUseCustomReporter) {
        config.customReporter!.recordFlutterError(details);
      }
    };

    PlatformDispatcher.instance.onError = (exception, stackTrace) {
      loge(stackTrace, exception.toString());

      // Still report to custom reporter if it was initialized (enabled on web/debug)
      if (shouldUseCustomReporter) {
        config.customReporter!.recordError(exception, stackTrace);
      }
      return true;
    };

    // (c) Emulator-blocked / debug-no-reporting branch. The minimal handlers
    // above replaced the early buffering handlers; reporting is suppressed on
    // this path, so drop+clear the early buffer (a no-op when the installer was
    // never called). This branch does NOT early-return — the buffer would
    // otherwise leak (Issue 35).
    _logAndClearEarlyErrorBuffer('error reporting blocked (emulator/debug)');
    // Reporting suppressed on this path — drop deferred bootstrap diagnostics
    // and mark attached (later ones short-circuit; loge no-ops here).
    _errorHandlingAttached = true;
    _dropDeferredBootstrapReports();
  } else {
    // Production branch. dreamic ships no built-in reporter, so the handlers
    // route to the single registered reporter (if any).

    // Only install handlers if the reporter doesn't manage its own (e.g. Sentry
    // via SentryFlutter.init with appRunner). When it does, dreamic leaves
    // FlutterError.onError / PlatformDispatcher.onError / the isolate listener to
    // the reporter and just wires loge() + flushes the buffers below.
    if (!config.customReporterManagesErrorHandlers) {
      // Flutter-framework (non-async) errors.
      FlutterError.onError = (FlutterErrorDetails details) {
        _presentErrorInDebugConsole(details);
        if (shouldUseCustomReporter) {
          config.customReporter!.recordFlutterError(details);
        }
      };

      // Async / platform errors.
      PlatformDispatcher.instance.onError = (error, stack) {
        if (shouldUseCustomReporter) {
          config.customReporter!.recordError(error, stack);
        }
        return true;
      };

      // Errors outside the Flutter framework (isolates), non-web only.
      // Apply-once across gate-retry re-runs: `addErrorListener` allows multiple
      // listeners, so an unguarded re-run would accumulate them (Issue 31).
      //
      // Registered AT attach and routed through `_recordErrorSafe` (ERH-021), so
      // isolate errors get the same re-entrancy guard, cross-surface dedup, and
      // redaction as every other surface (BEH-1/9/11). Pre-attach uncaught main-
      // isolate errors are already covered by the early `FlutterError.onError` /
      // `PlatformDispatcher.onError` handlers (which buffer) — this listener does
      // NOT buffer pre-attach isolate errors (ERH-029).
      if (!kIsWeb && !_isolateErrorListenerAdded) {
        _isolateErrorListenerAdded = true;
        Isolate.current.addErrorListener(
          RawReceivePort((pair) {
            final List<dynamic> errorAndStacktrace = pair;
            final error = errorAndStacktrace.first as Object;
            final stackTrace = errorAndStacktrace.last as StackTrace;
            _recordErrorSafe(error, stackTrace);
          }).sendPort,
        );
      }
    }

    // (a) Production branch — the reporter is now attached. Flush the early
    // buffers in BREADCRUMBS-then-ERRORS order (ERH-032 / BEH-12) so each
    // buffered early error is reported with its preceding breadcrumb trail
    // already in place. Flushed breadcrumbs were redacted at emit time and are
    // NOT re-redacted. Both flushes are safe no-ops when their buffers are empty
    // (e.g. the installer was never called — Issue 36).
    if (_activeReporter != null) {
      _flushAndClearEarlyBreadcrumbs(_activeReporter!);
    }
    _flushAndClearEarlyErrorBuffer();
    // Reporter attached: deliver any deferred bootstrap diagnostics (e.g. the
    // appInitFirebase recovery, which fired at the Firebase step before this
    // attach), then route future ones immediately.
    _errorHandlingAttached = true;
    _flushDeferredBootstrapReports();
  }
}
