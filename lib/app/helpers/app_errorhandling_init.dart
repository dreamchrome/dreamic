import 'dart:isolate';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:dreamic/app/app_config_base.dart';
import 'package:dreamic/error_reporting/error_reporter_interface.dart';
import 'package:dreamic/utils/logger.dart';

/// Global error reporting configuration
ErrorReportingConfig? _errorReportingConfig;

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
    if (!kIsWeb) {
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
  }
}
