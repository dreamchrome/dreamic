import 'dart:isolate';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:dreamic/app/app_config_base.dart';
import 'package:dreamic/app/helpers/error_reporter_interface.dart';
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

Future<void> appInitErrorHandling() async {
  final config = errorReportingConfig;

  // Set the error reporting configuration in Logger
  Logger.setErrorReportingConfig(config);

  // Initialize custom reporter if provided
  if (config.customReporter != null) {
    await config.customReporter!.initialize();
    // Set the custom error reporter in Logger for crash reporting
    Logger.setCustomErrorReporter(config.customReporter);
  }

  // Determine if we should use error reporting
  final shouldUseErrorReporting = !AppConfigBase.doUseBackendEmulator &&
      (config.enableInDebug || !kDebugMode) &&
      (config.enableOnWeb || !kIsWeb);

  // Disable analytics and crashlytics for web or emulator (unless configured otherwise)
  if (!shouldUseErrorReporting) {
    FlutterError.onError = (details) {
      loge(details.stack ?? StackTrace.current, details.exceptionAsString());

      // Still report to custom reporter if enabled on web/debug
      if (config.customReporter != null &&
          ((kIsWeb && config.enableOnWeb) || (kDebugMode && config.enableInDebug))) {
        config.customReporter!.recordFlutterError(details);
      }
    };

    PlatformDispatcher.instance.onError = (exception, stackTrace) {
      loge(stackTrace, exception.toString());

      // Still report to custom reporter if enabled on web/debug
      if (config.customReporter != null &&
          ((kIsWeb && config.enableOnWeb) || (kDebugMode && config.enableInDebug))) {
        config.customReporter!.recordError(exception, stackTrace);
      }
      return true;
    };
  } else {
    // Setup error handlers for production
    // Initialize Firebase if using Crashlytics
    if (config.useFirebaseCrashlytics) {
      await Firebase.initializeApp();
    }

    // Only set up error handlers if the custom reporter doesn't manage them
    // (e.g., Sentry with SentryFlutter.init sets up its own handlers)
    if (!config.customReporterManagesErrorHandlers) {
      // Setup Flutter error handler for non-async exceptions
      FlutterError.onError = (FlutterErrorDetails details) {
        if (config.useFirebaseCrashlytics) {
          FirebaseCrashlytics.instance.recordFlutterError(details);
        }
        if (config.customReporter != null) {
          config.customReporter!.recordFlutterError(details);
        }
      };

      // Setup async error handler
      PlatformDispatcher.instance.onError = (error, stack) {
        if (config.useFirebaseCrashlytics) {
          FirebaseCrashlytics.instance.recordError(error, stack);
        }
        if (config.customReporter != null) {
          config.customReporter!.recordError(error, stack);
        }
        return true;
      };
    } else {
      // Custom reporter manages error handlers, but we still need to
      // chain Firebase Crashlytics if enabled
      if (config.useFirebaseCrashlytics) {
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

            if (config.useFirebaseCrashlytics) {
              await FirebaseCrashlytics.instance.recordError(error, stackTrace);
            }
            if (config.customReporter != null) {
              config.customReporter!.recordError(error, stackTrace);
            }
          }).sendPort,
        );
      } else if (config.useFirebaseCrashlytics) {
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
