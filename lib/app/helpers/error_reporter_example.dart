// ignore_for_file: unused_import, unused_catch_stack

/// Example: Integrating Sentry with Dreamic
/// This file shows how to implement and configure Sentry as an error reporter
/// in a Flutter app using the Dreamic package.
///
/// Sentry has TWO integration approaches:
library;

import 'package:dreamic/app/helpers/error_reporter_interface.dart';
import 'package:dreamic/app/helpers/app_errorhandling_init.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
// import 'package:sentry_flutter/sentry_flutter.dart'; // Add this to your pubspec.yaml

/// APPROACH 1: Using Sentry's recommended SentryFlutter.init() wrapper
/// This is the RECOMMENDED approach as it lets Sentry manage error handlers
/// 
/// When using this approach, Sentry automatically sets up error handlers,
/// so set customReporterManagesErrorHandlers: true
/// 
/// Example main.dart:
void exampleMainSentryWrapper() async {
  /*
  WidgetsFlutterBinding.ensureInitialized();
  
  // Configure Dreamic to know Sentry manages its own error handlers
  configureErrorReporting(
    ErrorReportingConfig.customOnly(
      reporter: SentryErrorReporter(dsn: 'your-dsn'),
      managesOwnErrorHandlers: true,  // Important: tells Dreamic not to set handlers
      enableOnWeb: true,
    ),
  );
  
  // Initialize error handling (won't set up error handlers since Sentry manages them)
  await appInitErrorHandling();
  
  // Sentry's recommended initialization - wraps runApp()
  await SentryFlutter.init(
    (options) {
      options.dsn = 'https://your-dsn@sentry.io/project-id';
      options.tracesSampleRate = 1.0;
    },
    appRunner: () => runApp(MyApp()),
  );
  */
}

/// APPROACH 2: Manual Sentry integration (for more control)
/// Use this if you need more control over initialization order
/// or want to use the ErrorReporter interface pattern
///
/// Example Sentry implementation
/// 
/// To use this:
/// 1. Add sentry_flutter to your pubspec.yaml
/// 2. Uncomment the Sentry import above and the implementation below
/// 3. Configure in your main() function before calling appInitErrorHandling()
///
/// ```dart
/// // pubspec.yaml
/// dependencies:
///   sentry_flutter: ^9.7.0
/// ```
/*
class SentryErrorReporter implements ErrorReporter {
  final String dsn;
  final String? environment;
  final String? release;

  SentryErrorReporter({
    required this.dsn,
    this.environment,
    this.release,
  });

  @override
  Future<void> initialize() async {
    await SentryFlutter.init(
      (options) {
        options.dsn = dsn;
        options.environment = environment ?? (kDebugMode ? 'development' : 'production');
        options.release = release;
        options.tracesSampleRate = 1.0;
        
        // Optional: Add custom configuration
        options.beforeSend = (event, hint) {
          // You can modify or filter events here
          return event;
        };
      },
    );
  }

  @override
  void recordError(Object error, StackTrace? stackTrace) {
    Sentry.captureException(
      error,
      stackTrace: stackTrace,
    );
  }

  @override
  void recordFlutterError(FlutterErrorDetails details) {
    Sentry.captureException(
      details.exception,
      stackTrace: details.stack,
    );
  }
  
  // Additional helper methods for Sentry-specific features
  void setUserContext(String userId, String email, String username) {
    Sentry.configureScope((scope) {
      scope.user = SentryUser(
        id: userId,
        email: email,
        username: username,
      );
    });
  }
  
  void addBreadcrumb(String message, String category) {
    Sentry.addBreadcrumb(
      Breadcrumb(
        message: message,
        category: category,
        timestamp: DateTime.now(),
      ),
    );
  }
  
  void setTag(String key, String value) {
    Sentry.configureScope((scope) {
      scope.setTag(key, value);
    });
  }
}
*/

/// Example main.dart setup
void exampleMain() async {
  WidgetsFlutterBinding.ensureInitialized();

  // APPROACH 1 (RECOMMENDED): Use Sentry's wrapper (see exampleMainSentryWrapper above)
  
  // APPROACH 2: Manual integration
  // OPTION 1: Use Sentry only (recommended for web apps)
  /*
  configureErrorReporting(
    ErrorReportingConfig.customOnly(
      reporter: SentryErrorReporter(
        dsn: 'https://your-dsn@sentry.io/project-id',
        environment: kDebugMode ? 'development' : 'production',
        release: 'your-app@1.0.0+1',
      ),
      enableOnWeb: true,  // Sentry works on web
      enableInDebug: false,  // Disable in debug mode
      managesOwnErrorHandlers: false,  // We're using manual integration
    ),
  );
  */

  // OPTION 2: Use both Firebase Crashlytics and Sentry
  /*
  configureErrorReporting(
    ErrorReportingConfig.both(
      reporter: SentryErrorReporter(
        dsn: 'https://your-dsn@sentry.io/project-id',
      ),
      enableOnWeb: false,
      enableInDebug: false,
      customReporterManagesErrorHandlers: false,
    ),
  );
  */

  // OPTION 3: Use Firebase Crashlytics only (default)
  /*
  configureErrorReporting(
    ErrorReportingConfig.firebaseOnly(
      enableInDebug: false,
      enableOnWeb: false,
    ),
  );
  */
  // Or simply don't call configureErrorReporting() at all

  // Initialize error handling with configured reporter
  await appInitErrorHandling();

  // Continue with your app initialization...
  // runApp(MyApp());
}

/// Example: Custom error reporter for a different service
/// This shows the pattern for implementing any error reporting service
/*
class CustomErrorReporter implements ErrorReporter {
  final String apiKey;
  
  CustomErrorReporter({required this.apiKey});

  @override
  Future<void> initialize() async {
    // Initialize your error reporting service
    // await YourService.init(apiKey: apiKey);
  }

  @override
  void recordError(Object error, StackTrace? stackTrace) {
    // Send error to your service
    // YourService.reportError(error, stackTrace);
  }

  @override
  void recordFlutterError(FlutterErrorDetails details) {
    // Send Flutter error to your service
    // YourService.reportFlutterError(details);
  }
}
*/

/// Example: Using the error reporter in your app
void exampleUsage() {
  // Errors are automatically caught and reported
  
  // Manual error logging (automatically reports to configured service)
  try {
    // Your code that might throw
    throw Exception('Something went wrong');
  } catch (error, stackTrace) {
    // This will report to all configured error reporters
    // loge(error, 'Error in exampleUsage', stackTrace);
  }
}
