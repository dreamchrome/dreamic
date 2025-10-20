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
      // final timestamp = DateTime.now().toIso8601String();
      // final prefix = level.name.toUpperCase();
      // debugPrint('[$timestamp] $prefix: $message');
      if (level == LogLevel.debugVerbose) {
        debugPrint('DEBUGVERBOSE: $message');

        //  else if (level == LogLevel.debug) {
        //   debugPrint('DEBUG: $message');
        // } else if (level == LogLevel.info) {
        //   debugPrint('INFO: $message');
        // } else if (level == LogLevel.warn) {
        //   debugPrint('WARN: $message');
        // } else if (level == LogLevel.error) {
        //   debugPrint('ERROR: $message');
        // }
      } else {
        // debugPrint('${level.name}: $message');
        debugPrint(message);
      }
      _onLogFunction?.call(message);
    }
  }

  static void error(Object error, [String? message, StackTrace? stackTrace]) {
    final timestamp = DateTime.now().toIso8601String();

    if (message != null) {
      debugPrint('[$timestamp] MESSAGE: $message');
      _onLogFunction?.call(message);
    }

    debugPrint('[$timestamp] ERROR: ${error.toString()}');
    if (stackTrace != null) {
      debugPrint('STACKTRACE: ${stackTrace.toString()}');
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
    if (shouldUseErrorReporting && config.useFirebaseCrashlytics) {
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
