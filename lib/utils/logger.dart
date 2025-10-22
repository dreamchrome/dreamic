import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import '../app/app_config_base.dart';
import '../app/helpers/error_reporter_interface.dart';

enum LogLevel {
  debugVerbose,
  debug,
  info,
  warn,
  error,
}

class Logger {
  static Function(String message)? _onLogFunction;
  static ErrorReporter? _customErrorReporter;
  static ErrorReportingConfig? _errorReportingConfig;

  /// Set the error reporting configuration
  /// This is typically called automatically by the error handling initialization
  static void setErrorReportingConfig(ErrorReportingConfig? config) {
    _errorReportingConfig = config;
  }

  /// Set a custom error reporter for logging errors
  /// This is typically called automatically by the error handling initialization
  static void setCustomErrorReporter(ErrorReporter? reporter) {
    _customErrorReporter = reporter;
  }

  static void setLogFunction(Function(String message)? function) {
    _onLogFunction = function;
  }

  static void log(LogLevel level, String message) {
    if (_shouldLog(level)) {
      // Use print() in release mode for web to ensure logs appear in production
      // debugPrint is compiled away in Flutter release builds
      final logMessage = level == LogLevel.debugVerbose ? 'DEBUGVERBOSE: $message' : message;

      if (kReleaseMode && kIsWeb) {
        // ignore: avoid_print
        print(logMessage);
      } else {
        debugPrint(logMessage);
      }
      _onLogFunction?.call(message);
    }
  }

  static void error(Object error, [String? message, StackTrace? stackTrace]) {
    final timestamp = DateTime.now().toIso8601String();

    // Use print() in release mode for web to ensure logs appear in production
    void logOutput(String msg) {
      if (kReleaseMode && kIsWeb) {
        // ignore: avoid_print
        print(msg);
      } else {
        debugPrint(msg);
      }
    }

    if (message != null) {
      logOutput('[$timestamp] MESSAGE: $message');
      _onLogFunction?.call(message);
    }

    logOutput('[$timestamp] ERROR: ${error.toString()}');
    if (stackTrace != null) {
      logOutput('STACKTRACE: ${stackTrace.toString()}');
    }

    _crashReport(error, trace: stackTrace);
  }

  static bool _shouldLog(LogLevel messageLevel) {
    final configLevel = AppConfigBase.logLevel;
    return messageLevel.index >= configLevel.index;
  }

  static void _crashReport(Object error, {StackTrace? trace}) {
    final stackTrace = trace ?? StackTrace.current;
    final config = _errorReportingConfig ?? const ErrorReportingConfig();

    // Determine if we should use error reporting based on configuration
    final shouldUseErrorReporting = !AppConfigBase.doUseBackendEmulator &&
        (config.enableInDebug || !kDebugMode) &&
        (config.enableOnWeb || !kIsWeb);

    // Report to Firebase Crashlytics if enabled and conditions are met
    // Note: Firebase Crashlytics does not support web - only call on native platforms
    if (shouldUseErrorReporting && config.useFirebaseCrashlytics && !kIsWeb) {
      FirebaseCrashlytics.instance.recordError(error, stackTrace);
    }

    // Report to custom error reporter if configured
    if (_customErrorReporter != null) {
      // Custom reporter should respect the config's enableOnWeb and enableInDebug settings
      if (shouldUseErrorReporting ||
          (kIsWeb && config.enableOnWeb) ||
          (kDebugMode && config.enableInDebug)) {
        _customErrorReporter!.recordError(error, stackTrace);
      }
    }
  }
}

// Convenience methods
void logv(String message) => Logger.log(LogLevel.debugVerbose, message);
void logd(String message) => Logger.log(LogLevel.debug, message);
void logi(String message) => Logger.log(LogLevel.info, message);
void logw(String message) => Logger.log(LogLevel.warn, message);
void loge(Object error, [String? message, StackTrace? trace]) =>
    Logger.error(error, message, trace);
