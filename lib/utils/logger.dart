import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import '../app/app_config_base.dart';

enum LogLevel {
  debugVerbose,
  debug,
  info,
  warn,
  error,
}

class Logger {
  static Function(String message)? _onLogFunction;

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
    if (!AppConfigBase.doUseBackendEmulator && !kIsWeb) {
      FirebaseCrashlytics.instance.recordError(error, trace ?? StackTrace.current);
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
