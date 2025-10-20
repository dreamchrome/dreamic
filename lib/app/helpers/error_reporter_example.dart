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

/// APPROACH 1: Using Sentry's recommended SentryFlutter.init() wrapper (RECOMMENDED)
/// This is the RECOMMENDED approach as it lets Sentry manage error handlers
///
/// This approach uses Sentry's appRunner pattern which automatically:
/// - Sets up error handlers (FlutterError.onError, PlatformDispatcher.onError)
/// - Runs your app in a proper error zone
/// - Captures all uncaught errors
///
/// IMPORTANT: When using this approach:
/// - Set managesOwnErrorHandlers: true in ErrorReportingConfig
/// - DO NOT call appInitErrorHandling() - Sentry handles initialization
/// - Pass your runApp() call to the appRunner parameter
///
/// Example main.dart:
void exampleMainSentryWrapper() async {
  /*
  import 'package:flutter/widgets.dart';
  import 'package:sentry_flutter/sentry_flutter.dart';
  import 'package:dreamic/dreamic.dart';

  Future<void> main() async {
    WidgetsFlutterBinding.ensureInitialized();
    
    // Sentry's recommended initialization - wraps runApp() in appRunner
    await SentryFlutter.init(
      (options) {
        options.dsn = 'https://your-dsn@sentry.io/project-id';
        // Use ENVIRONMENT_TYPE dart-define (set via --dart-define=ENVIRONMENT_TYPE=production)
        options.environment = AppConfigBase.environmentType.value;
        // Auto-generated release string (e.g., "my-app@1.0.0+42")
        options.release = await AppConfigBase.getAppRelease();
        options.tracesSampleRate = 1.0;
      },
      // CRITICAL: Use appRunner to wrap your app initialization
      // This ensures Sentry's error handlers are properly set up
      appRunner: () => runApp(MyApp()),
    );
  }
  
  // Alternative: If you want to use Dreamic's error reporting config system:
  Future<void> mainWithDreamicConfig() async {
    WidgetsFlutterBinding.ensureInitialized();
    
    // Configure Dreamic to know Sentry manages its own error handlers
    configureErrorReporting(
      ErrorReportingConfig.customOnly(
        reporter: null,  // No reporter needed - Sentry initialized directly
        managesOwnErrorHandlers: true,  // Important: tells Dreamic not to set handlers
        enableOnWeb: true,
      ),
    );
    
    // Initialize Sentry with appRunner
    await SentryFlutter.init(
      (options) {
        options.dsn = 'https://your-dsn@sentry.io/project-id';
        options.environment = AppConfigBase.environmentType.value;
        options.release = await AppConfigBase.getAppRelease();
        options.tracesSampleRate = 1.0;
      },
      appRunner: () => runApp(MyApp()),
    );
  }
  */
}

/// APPROACH 2: Manual Sentry integration (for more control)
/// Use this if you need more control over initialization order
/// or want to use the ErrorReporter interface pattern
///
/// IMPORTANT: This approach does NOT use appRunner, so you must:
/// - Call initialize() on the reporter before runApp()
/// - Set managesOwnErrorHandlers: false in ErrorReportingConfig
/// - Let Dreamic's appInitErrorHandling() set up error handlers
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
///
/// Build commands with environment configuration:
/// ```bash
/// # Development build
/// flutter build ios --dart-define=ENVIRONMENT_TYPE=development
///
/// # Staging build
/// flutter build ios --dart-define=ENVIRONMENT_TYPE=staging
///
/// # Production build
/// flutter build ios --dart-define=ENVIRONMENT_TYPE=production
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
    // Get the app version for release tracking
    final appRelease = release ?? await AppConfigBase.getAppRelease();
    
    // IMPORTANT: This does NOT use appRunner
    // Error handlers are managed by Dreamic's appInitErrorHandling()
    await SentryFlutter.init(
      (options) {
        options.dsn = dsn;
        // Use ENVIRONMENT_TYPE dart-define or fallback to parameter
        options.environment = environment ?? AppConfigBase.environmentType.value;
        // Use the app version for release tracking
        options.release = appRelease;
        options.tracesSampleRate = 1.0;
        
        // Optional: Add custom configuration
        options.beforeSend = (event, hint) {
          // You can modify or filter events here
          return event;
        };
      },
      // DO NOT use appRunner here - error handlers managed by Dreamic
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

  // ==================================================================================
  // APPROACH 1 (RECOMMENDED): Use Sentry's appRunner wrapper
  // ==================================================================================
  // This is Sentry's recommended approach - see exampleMainSentryWrapper() above
  //
  // Summary:
  // - Use SentryFlutter.init() with appRunner parameter
  // - Sentry manages all error handlers automatically
  // - DO NOT call appInitErrorHandling()
  // - Clean and simple setup
  //
  // Example:
  /*
  await SentryFlutter.init(
    (options) {
      options.dsn = 'https://your-dsn@sentry.io/project-id';
      options.environment = AppConfigBase.environmentType.value;
      options.release = await AppConfigBase.getAppRelease();
      options.tracesSampleRate = 1.0;
    },
    appRunner: () => runApp(MyApp()),
  );
  return; // Exit main - app is running
  */

  // ==================================================================================
  // APPROACH 2: Manual integration with Dreamic's error handling
  // ==================================================================================
  // Use this if you need more control or want to use the ErrorReporter interface

  // OPTION 1: Use Sentry only (recommended for web apps)
  /*
  // Environment and release are automatically configured
  // Environment uses ENVIRONMENT_TYPE dart-define (see AppConfigBase.environmentType)
  // Release is auto-generated from app version (see AppConfigBase.getAppRelease())
  configureErrorReporting(
    ErrorReportingConfig.customOnly(
      reporter: SentryErrorReporter(
        dsn: 'https://your-dsn@sentry.io/project-id',
        // environment and release auto-configured from AppConfigBase
      ),
      enableOnWeb: true,  // Sentry works on web
      enableInDebug: false,  // Disable in debug mode
      managesOwnErrorHandlers: false,  // We're using manual integration
    ),
  );
  
  // Initialize error handling with configured reporter
  await appInitErrorHandling();
  
  // Run your app
  runApp(MyApp());
  */

  // OPTION 2: Use both Firebase Crashlytics and Sentry
  /*
  configureErrorReporting(
    ErrorReportingConfig.both(
      reporter: SentryErrorReporter(
        dsn: 'https://your-dsn@sentry.io/project-id',
        // environment and release auto-configured from AppConfigBase
      ),
      enableOnWeb: false,  // Crashlytics doesn't work on web
      enableInDebug: false,
      customReporterManagesErrorHandlers: false,
    ),
  );
  
  // Initialize error handling with configured reporter
  await appInitErrorHandling();
  
  // Run your app
  runApp(MyApp());
  */

  // OPTION 3: Use Firebase Crashlytics only (default)
  /*
  configureErrorReporting(
    ErrorReportingConfig.firebaseOnly(
      enableInDebug: false,
      enableOnWeb: false,
    ),
  );
  // Or simply don't call configureErrorReporting() at all

  // Initialize error handling with configured reporter
  await appInitErrorHandling();

  // Continue with your app initialization...
  runApp(MyApp());
  */
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
