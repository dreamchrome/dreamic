import 'dart:isolate';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
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

/// Resets the early-error buffer state for tests. The buffer and the
/// installed-flag are module-level statics that persist across test cases in
/// one VM, so without a reset the buffer/flush assertions become order-
/// dependent (Issue 63).
@visibleForTesting
void resetEarlyErrorHandlersForTest() {
  _earlyErrorBuffer.clear();
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

  // Firebase Crashlytics requires Firebase to be initialized and doesn't support web
  final canUseFirebaseCrashlytics = config.useFirebaseCrashlytics &&
      AppConfigBase.isFirebaseInitialized &&
      !kIsWeb;

  debugPrint('Error Reporting Configuration: '
      'useFirebaseCrashlytics=${config.useFirebaseCrashlytics}, '
      'customReporter=${config.customReporter != null}, '
      'customReporterManagesErrorHandlers=${config.customReporterManagesErrorHandlers}, '
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
  } else {
    // Setup error handlers for production
    // Note: If using Firebase Crashlytics, Firebase must be initialized first
    // via appInitFirebase() before calling appInitErrorHandling()

    // Only set up error handlers if the custom reporter doesn't manage them
    // (e.g., Sentry with SentryFlutter.init sets up its own handlers)
    if (!config.customReporterManagesErrorHandlers) {
      // Setup Flutter error handler for non-async exceptions
      FlutterError.onError = (FlutterErrorDetails details) {
        if (canUseFirebaseCrashlytics) {
          FirebaseCrashlytics.instance.recordFlutterError(details);
        }
        if (shouldUseCustomReporter) {
          config.customReporter!.recordFlutterError(details);
        }
      };

      // Setup async error handler
      PlatformDispatcher.instance.onError = (error, stack) {
        if (canUseFirebaseCrashlytics) {
          FirebaseCrashlytics.instance.recordError(error, stack);
        }
        if (shouldUseCustomReporter) {
          config.customReporter!.recordError(error, stack);
        }
        return true;
      };
    } else {
      // Custom reporter manages error handlers, but we still need to
      // chain Firebase Crashlytics if enabled
      if (canUseFirebaseCrashlytics) {
        // Save the custom reporter's error handler
        final originalFlutterErrorHandler = FlutterError.onError;
        final originalPlatformErrorHandler = PlatformDispatcher.instance.onError;

        // Set up handlers that report to both Firebase and the custom reporter
        FlutterError.onError = (FlutterErrorDetails details) {
          FirebaseCrashlytics.instance.recordFlutterError(details);
          // Call the custom reporter's handler if it was set
          originalFlutterErrorHandler?.call(details);
        };

        PlatformDispatcher.instance.onError = (error, stack) {
          FirebaseCrashlytics.instance.recordError(error, stack);
          // Call the custom reporter's handler if it exists
          return originalPlatformErrorHandler?.call(error, stack) ?? true;
        };
      }
    }

    // Catch errors outside of the Flutter framework (isolates)
    // Only for non-web platforms
    // Note: When customReporter manages error handlers (e.g., Sentry's init),
    // they typically set up their own isolate error listeners
    //
    // Apply-once across gate-retry re-runs: `addErrorListener` allows multiple
    // listeners, so an unguarded re-run would accumulate them (Issue 31).
    if (!kIsWeb && !_isolateErrorListenerAdded) {
      _isolateErrorListenerAdded = true;
      if (!config.customReporterManagesErrorHandlers) {
        // Standard approach: we set up the isolate listener
        Isolate.current.addErrorListener(
          RawReceivePort((pair) async {
            final List<dynamic> errorAndStacktrace = pair;
            final error = errorAndStacktrace.first;
            final stackTrace = errorAndStacktrace.last as StackTrace;

            if (canUseFirebaseCrashlytics) {
              await FirebaseCrashlytics.instance.recordError(error, stackTrace);
            }
            if (shouldUseCustomReporter) {
              config.customReporter!.recordError(error, stackTrace);
            }
          }).sendPort,
        );
      } else if (canUseFirebaseCrashlytics) {
        // Custom reporter manages handlers, but we need Firebase to catch isolate errors
        // Chain with any existing listener that the custom reporter may have set
        Isolate.current.addErrorListener(
          RawReceivePort((pair) async {
            final List<dynamic> errorAndStacktrace = pair;
            final error = errorAndStacktrace.first;
            final stackTrace = errorAndStacktrace.last as StackTrace;

            // Report to Firebase
            await FirebaseCrashlytics.instance.recordError(error, stackTrace);

            // Note: Custom reporter's isolate listener (if any) will also catch this
            // since multiple listeners can be added to the same isolate
          }).sendPort,
        );
      }
    }

    // (a) Production branch — the reporter is now attached. Flush every error
    // buffered by the early handlers before this point to it, then clear the
    // buffer (a no-op when the installer was never called — the buffer is empty).
    _flushAndClearEarlyErrorBuffer();
  }
}
