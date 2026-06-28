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
      if (!kIsWeb && !_isolateErrorListenerAdded) {
        _isolateErrorListenerAdded = true;
        Isolate.current.addErrorListener(
          RawReceivePort((pair) {
            final List<dynamic> errorAndStacktrace = pair;
            final error = errorAndStacktrace.first;
            final stackTrace = errorAndStacktrace.last as StackTrace;
            if (shouldUseCustomReporter) {
              config.customReporter!.recordError(error, stackTrace);
            }
          }).sendPort,
        );
      }
    }

    // (a) Production branch — the reporter is now attached. Flush every error
    // buffered by the early handlers before this point to it, then clear the
    // buffer (a no-op when the installer was never called — the buffer is empty).
    _flushAndClearEarlyErrorBuffer();
    // Reporter attached: deliver any deferred bootstrap diagnostics (e.g. the
    // appInitFirebase recovery, which fired at the Firebase step before this
    // attach), then route future ones immediately.
    _errorHandlingAttached = true;
    _flushDeferredBootstrapReports();
  }
}
