import 'package:flutter/foundation.dart';

/// Interface for external error reporting services
/// Implement this interface to integrate custom error reporting solutions
/// like Sentry, Bugsnag, or other crash reporting services.
///
/// Example implementation for Sentry:
/// ```dart
/// class SentryErrorReporter implements ErrorReporter {
///   @override
///   Future<void> initialize() async {
///     await SentryFlutter.init(
///       (options) {
///         options.dsn = 'your-dsn-here';
///       },
///     );
///   }
///
///   @override
///   void recordError(Object error, StackTrace? stackTrace) {
///     Sentry.captureException(error, stackTrace: stackTrace);
///   }
///
///   @override
///   void recordFlutterError(FlutterErrorDetails details) {
///     Sentry.captureException(
///       details.exception,
///       stackTrace: details.stack,
///     );
///   }
/// }
/// ```
abstract class ErrorReporter {
  /// Initialize the error reporting service
  /// This is called during app initialization
  Future<void> initialize();

  /// Record a generic error with optional stack trace
  void recordError(Object error, StackTrace? stackTrace);

  /// Record a Flutter-specific error
  void recordFlutterError(FlutterErrorDetails details);
}

/// Optional interface for error reporters that support user context.
///
/// This allows Dreamic to automatically set/clear the current user in an error
/// reporting service (e.g., Sentry) without Dreamic depending on that SDK.
///
/// If your reporter supports this, implement this interface in your consuming
/// app and Dreamic services (like `AuthServiceImpl`) can wire it up.
abstract interface class ErrorReporterUserContext {
  /// Set the current user for error reports.
  void setUser(String userId, {String? email, String? username});

  /// Clear the current user (e.g., on logout).
  void clearUser();
}

/// Configuration for error reporting
class ErrorReportingConfig {
  /// Custom error reporter implementation (e.g., Sentry)
  final ErrorReporter? customReporter;

  /// Whether to use Firebase Crashlytics
  /// Set to false when using a custom reporter exclusively
  final bool useFirebaseCrashlytics;

  /// Whether to enable error reporting in debug mode
  final bool enableInDebug;

  /// Whether to enable error reporting on web
  final bool enableOnWeb;

  /// Whether the custom reporter manages its own error handlers
  /// Set to true for services like Sentry that use SentryFlutter.init()
  /// with appRunner, which sets up error handlers automatically.
  /// When true, Dreamic won't set up duplicate error handlers.
  final bool customReporterManagesErrorHandlers;

  const ErrorReportingConfig({
    this.customReporter,
    this.useFirebaseCrashlytics = true,
    this.enableInDebug = false,
    this.enableOnWeb = false,
    this.customReporterManagesErrorHandlers = false,
  });

  /// Creates a configuration that uses only Firebase Crashlytics
  const ErrorReportingConfig.firebaseOnly({
    bool enableInDebug = false,
    bool enableOnWeb = false,
  }) : this(
          useFirebaseCrashlytics: true,
          customReporter: null,
          enableInDebug: enableInDebug,
          enableOnWeb: enableOnWeb,
          customReporterManagesErrorHandlers: false,
        );

  /// Creates a configuration that uses only a custom reporter
  ///
  /// Set [managesOwnErrorHandlers] to true if the reporter sets up its own
  /// error handlers (like SentryFlutter.init with appRunner).
  const ErrorReportingConfig.customOnly({
    required ErrorReporter reporter,
    bool enableInDebug = false,
    bool enableOnWeb = true,
    bool managesOwnErrorHandlers = false,
  }) : this(
          customReporter: reporter,
          useFirebaseCrashlytics: false,
          enableInDebug: enableInDebug,
          enableOnWeb: enableOnWeb,
          customReporterManagesErrorHandlers: managesOwnErrorHandlers,
        );

  /// Creates a configuration that uses both Firebase and a custom reporter
  ///
  /// Set [customReporterManagesErrorHandlers] to true if the reporter sets up
  /// its own error handlers (like SentryFlutter.init with appRunner).
  /// When true, only Firebase error handlers will be set up by Dreamic.
  const ErrorReportingConfig.both({
    required ErrorReporter reporter,
    bool enableInDebug = false,
    bool enableOnWeb = false,
    bool customReporterManagesErrorHandlers = false,
  }) : this(
          customReporter: reporter,
          useFirebaseCrashlytics: true,
          enableInDebug: enableInDebug,
          enableOnWeb: enableOnWeb,
          customReporterManagesErrorHandlers: customReporterManagesErrorHandlers,
        );
}
