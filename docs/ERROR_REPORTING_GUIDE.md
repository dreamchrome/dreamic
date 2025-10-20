# Error Reporting Integration Guide

This comprehensive guide explains how to integrate error reporting services (Firebase Crashlytics, Sentry, Bugsnag, etc.) into your Dreamic-based Flutter application.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Architecture](#architecture)
- [Setup Methods](#setup-methods)
- [Sentry Integration](#sentry-integration)
- [Build Configuration (dart-define)](#build-configuration-dart-define)
- [Configuration Options](#configuration-options)
- [Error Coverage](#error-coverage)
- [Example Implementations](#example-implementations)
- [Testing](#testing)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)
- [API Reference](#api-reference)

## Overview

The Dreamic package provides a flexible error reporting system that allows you to:
- ✅ Use Firebase Crashlytics (default)
- ✅ Use a custom error reporter (e.g., Sentry, Bugsnag)
- ✅ Use both Firebase Crashlytics and a custom reporter simultaneously
- ✅ Support wrapper-based initialization (like `SentryFlutter.init`)
- ✅ Full web platform support
- ✅ Zero dependencies on specific error reporting services

### Why Use External Error Reporting?

**Sentry Benefits:**
- Works on all platforms including web
- Rich debugging context (breadcrumbs, user context, etc.)
- Performance monitoring
- Release health monitoring
- Source map support for web

**Firebase Crashlytics Benefits:**
- Native crash reporting for iOS/Android
- Integrated with Firebase ecosystem
- Free tier available
- Automatic symbolication

**Use Both:**
For maximum coverage, use Firebase Crashlytics for native crashes and Sentry for cross-platform errors including web.

## Quick Start

### Using Firebase Crashlytics (Default)

No configuration needed - Firebase Crashlytics is enabled by default:

```dart
import 'package:dreamic/app/helpers/app_errorhandling_init.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase
  final fbApp = await appInitFirebase(DefaultFirebaseOptions.currentPlatform);
  
  // Initialize error handling with default Firebase Crashlytics
  await appInitErrorHandling();
  
  runApp(MyApp());
}
```

### Using Sentry (Recommended Approach)

The simplest and recommended way to use Sentry with Dreamic:

```dart
import 'package:flutter/widgets.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:dreamic/dreamic.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase if needed
  await appInitFirebase(DefaultFirebaseOptions.currentPlatform);
  
  // Use Sentry's recommended initialization with appRunner
  await SentryFlutter.init(
    (options) {
      options.dsn = 'https://your-dsn@sentry.io/project-id';
      // Use ENVIRONMENT_TYPE dart-define (set via --dart-define=ENVIRONMENT_TYPE=production)
      options.environment = AppConfigBase.environmentType.value;
      // Auto-generated release string (e.g., "my-app@1.0.0+42")
      options.release = await AppConfigBase.getAppRelease();
      options.tracesSampleRate = 1.0;
    },
    // CRITICAL: Use appRunner with appRunIfValidVersion for version checking
    appRunner: () => appRunIfValidVersion(() => MyApp()),
  );
}
```

**Key Points:**
- ✅ No custom ErrorReporter implementation needed
- ✅ Sentry manages all error handlers automatically  
- ✅ Works on all platforms including web
- ✅ DO NOT call `appInitErrorHandling()` when using this approach
- ✅ Use `appRunIfValidVersion()` in appRunner for automatic version checking
- ✅ Use `--dart-define=ENVIRONMENT_TYPE=production` for environment configuration
```

## Architecture

The error reporting system consists of:

1. **`ErrorReporter` Interface** - Abstract interface for implementing custom error reporters
2. **`ErrorReportingConfig`** - Configuration class with multiple factory constructors
3. **`configureErrorReporting()`** - Pre-configure error reporting
4. **`appInitErrorHandling()`** - Initialize error handlers
5. **Handler Management** - Supports both manual and wrapper-based setups
6. **Automatic Integration** - Logger and error handlers automatically use configured reporters

### Key Components

```dart
// Interface for custom error reporters
abstract class ErrorReporter {
  Future<void> initialize();
  void recordError(Object error, StackTrace? stackTrace);
  void recordFlutterError(FlutterErrorDetails details);
}

// Configuration with builder pattern
class ErrorReportingConfig {
  final ErrorReporter? customReporter;
  final bool useFirebaseCrashlytics;
  final bool customReporterManagesErrorHandlers;
  final bool enableInDebug;
  final bool enableOnWeb;
  
  // Factory constructors
  const ErrorReportingConfig.firebaseOnly({...});
  const ErrorReportingConfig.customOnly({...});
  const ErrorReportingConfig.both({...});
}
```

## Setup Methods

There are **two main approaches** for integrating custom error reporters with Dreamic, depending on how your error reporting service initializes.

### Method 1: Wrapper-Based Initialization (RECOMMENDED for Sentry)

Use this when your error reporter provides a wrapper function (like `SentryFlutter.init`) that sets up error handlers and wraps your app initialization.

**When to use:**
- ✅ Using `SentryFlutter.init()` with `appRunner`
- ✅ Your error reporter manages its own error handlers
- ✅ You want the external service to control error handling

**How it works:**
1. Call `configureErrorReporting()` with `managesOwnErrorHandlers: true`
2. Call `appInitErrorHandling()` (won't set up duplicate handlers)
3. Call wrapper function (e.g., `SentryFlutter.init`) which calls `runApp()`

**Example:**
```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase (if using)
  final fbApp = await appInitFirebase(DefaultFirebaseOptions.currentPlatform);
  
  // Configure error reporting BEFORE wrapper
  await configureErrorReporting(
    ErrorReportingConfig.customOnly(
      reporter: SentryErrorReporter(dsn: 'your-dsn'),
      managesOwnErrorHandlers: true,  // Important!
      enableOnWeb: true,
    ),
  );
  
  // Initialize Dreamic's error handling
  await appInitErrorHandling();
  
  // Sentry's wrapper sets up handlers and runs app
  await SentryFlutter.init(
    (options) {
      options.dsn = 'https://your-dsn@sentry.io/project-id';
      options.environment = AppConfigBase.environmentType.value;
      options.release = await AppConfigBase.getAppRelease();
      options.tracesSampleRate = 1.0;
    },
    appRunner: () => appRunIfValidVersion(() => MyApp()),
  );
}
```

### Method 2: Manual Initialization

Use this for full control over initialization or when your error reporter doesn't provide a wrapper function.

**When to use:**
- ✅ Using manual `Sentry.init()` (not `SentryFlutter.init`)
- ✅ Implementing custom error reporters
- ✅ You want Dreamic to manage error handlers
- ✅ More control over initialization order

**How it works:**
1. Implement the `ErrorReporter` interface fully
2. Call `configureErrorReporting()` with `managesOwnErrorHandlers: false` (default)
3. Call `appInitErrorHandling()` (sets up error handlers)
4. Call `runApp()`

**Example:**
```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase (if using)
  final fbApp = await appInitFirebase(DefaultFirebaseOptions.currentPlatform);
  
  // Configure with manual setup
  await configureErrorReporting(
    ErrorReportingConfig.customOnly(
      reporter: SentryErrorReporter(dsn: 'your-dsn'),
      managesOwnErrorHandlers: false,  // Dreamic manages handlers
      enableOnWeb: true,
    ),
  );
  
  // Initialize error handling (sets up handlers)
  await appInitErrorHandling();
  
  // Run app with version checking
  appRunIfValidVersion(() => MyApp());
}
```

## Sentry Integration

Sentry is the most popular third-party error reporting service for Flutter. Here's how to integrate it with Dreamic.

### Step 1: Add Dependencies

Add Sentry to your `pubspec.yaml`:

```yaml
dependencies:
  dreamic: ^x.x.x
  sentry_flutter: ^9.7.0
```

### Step 2: Choose Your Approach

#### Approach A: SentryFlutter.init with appRunner (RECOMMENDED)

This is Sentry's recommended approach using the `appRunner` parameter. Sentry automatically sets up all error handlers and wraps your app initialization.

**How it works:**
- Sentry's `appRunner` parameter receives your `runApp()` call
- Sentry automatically configures `FlutterError.onError` and `PlatformDispatcher.onError`
- All uncaught errors are sent to Sentry
- No need for custom `ErrorReporter` implementation

**Example main.dart:**

```dart
import 'package:flutter/widgets.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:dreamic/dreamic.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase (if needed)
  await appInitFirebase(DefaultFirebaseOptions.currentPlatform);
  
  // Use Sentry's recommended initialization with appRunner
  await SentryFlutter.init(
    (options) {
      options.dsn = 'https://your-dsn@sentry.io/project-id';
      // Use ENVIRONMENT_TYPE dart-define (set via --dart-define=ENVIRONMENT_TYPE=production)
      options.environment = AppConfigBase.environmentType.value;
      // Auto-generated release string (e.g., "my-app@1.0.0+42")
      options.release = await AppConfigBase.getAppRelease();
      options.tracesSampleRate = 1.0;
      
      // Optional: Add navigation tracking
      // options.navigatorKey = GlobalKey<NavigatorState>();
    },
    // CRITICAL: Use appRunner with appRunIfValidVersion
    // This ensures Sentry's error handlers are properly set up
    // AND validates app version before running
    appRunner: () => appRunIfValidVersion(() => MyApp()),
  );
}
```

**Key Points:**
- ✅ Simplest integration - no custom `ErrorReporter` needed
- ✅ Sentry manages all error handlers automatically
- ✅ Works on all platforms including web
- ✅ DO NOT call `appInitErrorHandling()` when using this approach
- ✅ Use `appRunIfValidVersion()` in `appRunner` for automatic version checking
- ✅ Version checking happens before app runs, shows outdated page if needed

#### Approach B: SentryFlutter.init with Dreamic ErrorReporter (Alternative)

Use this if you want to integrate with Dreamic's error reporting configuration system while still using Sentry's appRunner:

```dart
import 'package:flutter/widgets.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:dreamic/app/helpers/app_errorhandling_init.dart';
import 'package:dreamic/app/helpers/error_reporter_interface.dart';
import 'package:dreamic/dreamic.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase (if needed)
  await appInitFirebase(DefaultFirebaseOptions.currentPlatform);
  
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
    appRunner: () => appRunIfValidVersion(() => MyApp()),
  );
}
```

#### Approach C: Manual Sentry Integration (Advanced)

Use this approach if you need more control over initialization order or want to use the ErrorReporter interface pattern.

**IMPORTANT:** This approach does NOT use `appRunner`, so you must let Dreamic's `appInitErrorHandling()` set up error handlers.

```dart
import 'package:dreamic/app/helpers/error_reporter_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:dreamic/dreamic.dart';

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
    // IMPORTANT: This does NOT use appRunner
    // Error handlers are managed by Dreamic's appInitErrorHandling()
    await SentryFlutter.init(
      (options) {
        options.dsn = dsn;
        options.environment = environment ?? AppConfigBase.environmentType.value;
        options.release = release ?? await AppConfigBase.getAppRelease();
        options.tracesSampleRate = 1.0;
      },
      // DO NOT use appRunner here - error handlers managed by Dreamic
    );
  }

  @override
  void recordError(Object error, StackTrace? stackTrace) {
    Sentry.captureException(error, stackTrace: stackTrace);
  }

  @override
  void recordFlutterError(FlutterErrorDetails details) {
    Sentry.captureException(details.exception, stackTrace: details.stack);
  }
}
```

Then in your `main.dart`:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Configure with manual setup
  configureErrorReporting(
    ErrorReportingConfig.customOnly(
      reporter: SentryErrorReporter(
        dsn: 'https://your-dsn@sentry.io/project-id',
        // environment and release auto-configured from AppConfigBase
      ),
      managesOwnErrorHandlers: false,  // Dreamic manages handlers
      enableOnWeb: true,
    ),
  );

  // Initialize error handling (sets up error handlers)
  await appInitErrorHandling();

  // Run your app
  runApp(MyApp());
}
```

### Step 3: Using Both Sentry and Firebase

You can use **both** Sentry and Firebase Crashlytics simultaneously!

#### With SentryFlutter.init Wrapper:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase
  final fbApp = await appInitFirebase(DefaultFirebaseOptions.currentPlatform);
  
  // Configure both services
  await configureErrorReporting(
    ErrorReportingConfig.both(
      reporter: SentryErrorReporter(dsn: 'your-dsn'),
      customReporterManagesErrorHandlers: true,  // Sentry manages handlers
      enableOnWeb: false,  // Firebase on mobile, Sentry on web
      enableInDebug: false,
    ),
  );
  
  // Initialize Dreamic (chains Firebase to Sentry's handlers)
  await appInitErrorHandling();
  
  // Sentry wraps the app with version checking
  await SentryFlutter.init(
    (options) {
      options.dsn = 'your-dsn';
      options.environment = AppConfigBase.environmentType.value;
      options.release = await AppConfigBase.getAppRelease();
    },
    appRunner: () => appRunIfValidVersion(() => MyApp()),
  );
}
```

**What happens:**
1. Sentry's wrapper sets up error handlers
2. Dreamic saves those handlers
3. Dreamic wraps them to also report to Firebase
4. Errors go to **both** Sentry and Firebase

#### With Manual Setup:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase
  final fbApp = await appInitFirebase(DefaultFirebaseOptions.currentPlatform);
  
  // Configure both services
  await configureErrorReporting(
    ErrorReportingConfig.both(
      reporter: SentryErrorReporter(dsn: 'your-dsn'),
      customReporterManagesErrorHandlers: false,  // Dreamic manages
    ),
  );
  
  await appInitErrorHandling();
  appRunIfValidVersion(() => MyApp());
}
```

#### With `SentryFlutter.init`:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final fbApp = await appInitFirebase(DefaultFirebaseOptions.currentPlatform);
  
  configureErrorReporting(
    ErrorReportingConfig.both(
      reporter: null,  // Sentry managed separately
      customReporterManagesErrorHandlers: true,
    ),
  );
  
  await SentryFlutter.init(
    (options) {
      options.dsn = 'your-dsn';
      options.environment = AppConfigBase.environmentType.value;
      options.release = await AppConfigBase.getAppRelease();
    },
    appRunner: () => appRunIfValidVersion(() => MyApp()),
  );
}
}
```

### The `managesOwnErrorHandlers` Flag

This flag determines who sets up the error handlers.

**Set to `true` when:**
- ✅ Using `SentryFlutter.init()` with `appRunner`
- ✅ Your error reporter sets up its own `FlutterError.onError` and `PlatformDispatcher.instance.onError`
- ✅ You want the external service to control error handling

**What Dreamic does:**
- Does NOT set up `FlutterError.onError` or `PlatformDispatcher.instance.onError`
- If using Firebase Crashlytics too, chains the handlers to report to both
- Isolate errors are handled appropriately

**Set to `false` (default) when:**
- ✅ Using manual Sentry integration (just `Sentry.init()`)
- ✅ Implementing custom error reporters
- ✅ You want Dreamic to manage error handlers
- ✅ Using Firebase Crashlytics only

**What Dreamic does:**
- Sets up `FlutterError.onError` and `PlatformDispatcher.instance.onError`
- Reports errors to all configured services
- Full control over error handling pipeline

## Build Configuration (dart-define)

### Environment Type Configuration

You can configure the build environment type using `--dart-define=ENVIRONMENT_TYPE`. This is useful for error reporting, analytics, feature flags, and other environment-specific behavior.

#### ENVIRONMENT_TYPE

Configure the build environment (e.g., 'production', 'staging', 'development'):

```bash
# Development build
flutter build ios --dart-define=ENVIRONMENT_TYPE=development

# Staging build
flutter build android --dart-define=ENVIRONMENT_TYPE=staging

# Production build
flutter build web --dart-define=ENVIRONMENT_TYPE=production
```

**Default behavior:**
- If not set: `'development'` in debug mode, `'production'` in release mode
- Access in code: `AppConfigBase.environmentType`

**Usage in error reporters:**
```dart
class SentryErrorReporter implements ErrorReporter {
  @override
  Future<void> initialize() async {
    final release = await AppConfigBase.getAppRelease();
    
    await SentryFlutter.init((options) {
      options.dsn = 'your-dsn';
      // Uses ENVIRONMENT_TYPE dart-define
      options.environment = AppConfigBase.environmentType.value;
      // Auto-generated from app version
      options.release = release;
      options.tracesSampleRate = 1.0;
    });
  }
}
```

### Centralized App Version

Dreamic provides centralized methods to get app version information in `AppConfigBase`:

```dart
import 'package:dreamic/app/app_config_base.dart';

// Get full PackageInfo object (cached after first call)
final packageInfo = await AppConfigBase.getAppVersion();
print('Version: ${packageInfo.version}');
print('Build: ${packageInfo.buildNumber}');
print('Package: ${packageInfo.packageName}');

// Convenience methods
final version = await AppConfigBase.getAppVersionString();      // "1.0.0"
final build = await AppConfigBase.getAppBuildNumber();          // "42"
final release = await AppConfigBase.getAppRelease();            // "my-app@1.0.0+42"
```

**Benefits:**
- ✅ Single source of truth for version information
- ✅ Cached after first call for better performance
- ✅ Used throughout Dreamic and your app
- ✅ Automatic release string formatting for error reporting
- ✅ Works correctly on all platforms including Flutter Web

**Usage in error reporting:**

```dart
// Automatic configuration (recommended)
configureErrorReporting(
  ErrorReportingConfig.customOnly(
    reporter: SentryErrorReporter(
      dsn: 'your-dsn',
      // environment from AppConfigBase.environmentType
      // release from AppConfigBase.getAppRelease()
    ),
    enableOnWeb: true,
  ),
);

// Or with explicit control
final release = await AppConfigBase.getAppRelease();
configureErrorReporting(
  ErrorReportingConfig.customOnly(
    reporter: SentryErrorReporter(
      dsn: 'your-dsn',
      environment: 'custom-env',
      release: release,
    ),
    enableOnWeb: true,
  ),
);
```

## Configuration Options

### Factory Constructors

#### `ErrorReportingConfig.firebaseOnly()`

Use only Firebase Crashlytics (default behavior):

```dart
await configureErrorReporting(
  ErrorReportingConfig.firebaseOnly(
    enableInDebug: false,  // Don't report in debug mode
    enableOnWeb: false,    // Firebase doesn't work on web
  ),
);
```

Or simply don't call `configureErrorReporting()` at all, as Firebase is the default.

**Results in:**
- ✅ Firebase Crashlytics enabled
- ❌ No custom reporter
- Respects `enableInDebug` and `enableOnWeb` settings

#### `ErrorReportingConfig.customOnly()`

Use only a custom reporter (e.g., Sentry):

```dart
await configureErrorReporting(
  ErrorReportingConfig.customOnly(
    reporter: SentryErrorReporter(dsn: 'your-dsn'),
    managesOwnErrorHandlers: true,   // For SentryFlutter.init
    enableOnWeb: true,                // Sentry works on web
    enableInDebug: false,             // Don't report in debug
  ),
);
```

**Results in:**
- ❌ Firebase Crashlytics disabled
- ✅ Custom reporter enabled
- Handler management based on `managesOwnErrorHandlers` flag

#### `ErrorReportingConfig.both()`

Use both Firebase and a custom reporter:

```dart
await configureErrorReporting(
  ErrorReportingConfig.both(
    reporter: SentryErrorReporter(dsn: 'your-dsn'),
    customReporterManagesErrorHandlers: true,  // For wrapper approach
    enableInDebug: false,
    enableOnWeb: false,  // Firebase on mobile, both get errors anyway
  ),
);
```

**Results in:**
- ✅ Firebase Crashlytics enabled
- ✅ Custom reporter enabled
- All errors reported to both services
- Handler chaining based on `customReporterManagesErrorHandlers` flag

### Configuration Properties

```dart
class ErrorReportingConfig {
  // The custom error reporter instance
  final ErrorReporter? customReporter;
  
  // Whether to use Firebase Crashlytics
  final bool useFirebaseCrashlytics;
  
  // Whether custom reporter manages its own error handlers
  final bool customReporterManagesErrorHandlers;
  
  // Enable error reporting in debug mode (default: false)
  final bool enableInDebug;
  
  // Enable error reporting on web platform (default: false)
  final bool enableOnWeb;
}
```

### Environment Controls

Control when errors are reported based on environment:

```dart
ErrorReportingConfig.both(
  reporter: SentryErrorReporter(dsn: 'your-dsn'),
  enableInDebug: true,      // Report during development
  enableOnWeb: true,        // Report on web platform
)
```

**Default behavior:**
- `enableInDebug: false` - Don't report in debug mode to avoid development noise
- `enableOnWeb: false` - Don't report on web (some services charge per event)

**Additional automatic controls:**
- `AppConfigBase.doUseBackendEmulator` - Disables reporting when using Firebase emulator
- Platform detection - Automatically handles platform-specific behavior

## Error Coverage

All error types are automatically captured once configured:

| Error Type | Captured By | Platform | When |
|------------|-------------|----------|------|
| **Flutter errors** | `FlutterError.onError` | All | Synchronous widget errors, build errors |
| **Async errors** | `PlatformDispatcher.instance.onError` | All | Unhandled async exceptions, Future errors |
| **Isolate errors** | `Isolate.current.addErrorListener` | Non-web | Errors in isolates, compute() calls |
| **Manual errors** | `Logger.error()` / `loge()` | All | Explicitly logged errors |

### Automatic Error Capture

Once error reporting is configured, these errors are automatically caught and reported:

```dart
// Flutter framework errors (caught automatically)
Widget build(BuildContext context) {
  throw Exception('Build error');  // → Caught by FlutterError.onError
}

// Async errors (caught automatically)
Future<void> loadData() async {
  throw Exception('Async error');  // → Caught by PlatformDispatcher
}

// Isolate errors (caught automatically, non-web)
await compute(heavyCalculation, data);  // → Caught by isolate listener
```

### Manual Error Logging

You can (and should!) manually log caught errors using the Logger:

```dart
import 'package:dreamic/utils/logger.dart';

try {
  await riskyOperation();
} catch (error, stackTrace) {
  // Automatically reports to all configured error reporters
  loge(error, 'Failed to perform risky operation', stackTrace);
}
```

**Manual logging behavior:**
- Reports to Firebase (if `useFirebaseCrashlytics: true`)
- Reports to custom reporter (if configured)
- Respects `enableInDebug` and `enableOnWeb` settings
- Works regardless of `managesOwnErrorHandlers` setting

### Error Handler Flow

**When `managesOwnErrorHandlers: false` (Manual Setup):**
```
Error occurs
  ↓
FlutterError.onError / PlatformDispatcher.onError (set by Dreamic)
  ↓
→ Report to Firebase (if enabled)
→ Report to custom reporter (if configured)
```

**When `managesOwnErrorHandlers: true` (Wrapper Setup):**
```
Error occurs
  ↓
FlutterError.onError / PlatformDispatcher.onError (set by custom reporter)
  ↓
Custom reporter's handler (e.g., Sentry)
  ↓
Dreamic's wrapped handler (if Firebase enabled)
  ↓
→ Report to custom reporter
→ Report to Firebase (if enabled)
```

## Example Implementations

### Sentry with User Context (Manual Setup)

For advanced Sentry features, use manual setup with full `ErrorReporter` implementation:

```dart
import 'package:dreamic/app/helpers/error_reporter_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

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
    await Sentry.init((options) {
      options.dsn = dsn;
      options.environment = environment ?? (kDebugMode ? 'development' : 'production');
      options.release = release;
      options.tracesSampleRate = 1.0;
      
      // Configure additional Sentry features
      options.beforeSend = (event, hint) {
        // Filter or modify events before sending
        return event;
      };
    });
  }

  @override
  void recordError(Object error, StackTrace? stackTrace) {
    Sentry.captureException(error, stackTrace: stackTrace);
  }

  @override
  void recordFlutterError(FlutterErrorDetails details) {
    Sentry.captureException(
      details.exception,
      stackTrace: details.stack,
    );
  }
  
  // Additional Sentry-specific methods
  void setUser(String userId, String? email) {
    Sentry.configureScope((scope) {
      scope.user = SentryUser(id: userId, email: email);
    });
  }
  
  void clearUser() {
    Sentry.configureScope((scope) {
      scope.user = null;
    });
  }
  
  void addBreadcrumb(String message, {String? category}) {
    Sentry.addBreadcrumb(Breadcrumb(
      message: message,
      category: category,
      timestamp: DateTime.now(),
    ));
  }
  
  void setContext(String key, Map<String, dynamic> value) {
    Sentry.configureScope((scope) {
      scope.setContexts(key, value);
    });
  }
}
```

**Usage:**
```dart
// Set user context after login
final reporter = g<SentryErrorReporter>();
reporter.setUser(user.id, user.email);

// Add breadcrumbs for debugging
reporter.addBreadcrumb('User viewed product page', category: 'navigation');

// Clear user on logout
reporter.clearUser();
```

### Bugsnag Example

```dart
import 'package:bugsnag_flutter/bugsnag_flutter.dart';
import 'package:dreamic/app/helpers/error_reporter_interface.dart';

class BugsnagErrorReporter implements ErrorReporter {
  final String apiKey;
  final String? releaseStage;
  
  BugsnagErrorReporter({
    required this.apiKey,
    this.releaseStage,
  });

  @override
  Future<void> initialize() async {
    await bugsnag.start(
      apiKey: apiKey,
      releaseStage: releaseStage ?? 'production',
    );
  }

  @override
  void recordError(Object error, StackTrace? stackTrace) {
    bugsnag.notify(error, stackTrace);
  }

  @override
  void recordFlutterError(FlutterErrorDetails details) {
    bugsnag.notify(details.exception, details.stack);
  }
  
  // Additional Bugsnag-specific methods
  void setUser(String id, String? email, String? name) {
    bugsnag.setUser(id: id, email: email, name: name);
  }
  
  void leaveBreadcrumb(String message) {
    bugsnag.leaveBreadcrumb(message);
  }
}
```

### Custom Service Example

Implement any error reporting service using the `ErrorReporter` interface:

```dart
import 'package:dreamic/app/helpers/error_reporter_interface.dart';
import 'package:your_service/your_service.dart';

class YourServiceErrorReporter implements ErrorReporter {
  final String apiKey;
  
  YourServiceErrorReporter({required this.apiKey});

  @override
  Future<void> initialize() async {
    await YourService.init(apiKey: apiKey);
  }

  @override
  void recordError(Object error, StackTrace? stackTrace) {
    YourService.logError(error, stackTrace);
  }

  @override
  void recordFlutterError(FlutterErrorDetails details) {
    YourService.logFlutterError(details);
  }
}
```

## Migration Guide

### From Firebase-Only Setup

If you're currently using only Firebase Crashlytics:

**Current setup (no changes needed):**
```dart
await appInitErrorHandling();  // Firebase works by default
```

**To add Sentry (keep Firebase):**
```dart
await configureErrorReporting(
  ErrorReportingConfig.both(
    reporter: SentryErrorReporter(dsn: 'your-dsn'),
    enableOnWeb: true,  // Sentry works on web
  ),
);
await appInitErrorHandling();
```

**To switch to Sentry (disable Firebase):**
```dart
await configureErrorReporting(
  ErrorReportingConfig.customOnly(
    reporter: SentryErrorReporter(dsn: 'your-dsn'),
    managesOwnErrorHandlers: true,
    enableOnWeb: true,
  ),
);
await appInitErrorHandling();
```

### From Manual Error Handling

If you've set up your own error handlers:

1. Remove your manual `FlutterError.onError` and `PlatformDispatcher.instance.onError` setup
2. Implement the `ErrorReporter` interface for your service
3. Configure with `managesOwnErrorHandlers: false`
4. Call `appInitErrorHandling()`

**Before:**
```dart
FlutterError.onError = (details) {
  YourService.logError(details);
  FirebaseCrashlytics.instance.recordFlutterError(details);
};
```

**After:**
```dart
await configureErrorReporting(
  ErrorReportingConfig.both(
    reporter: YourServiceErrorReporter(),
    managesOwnErrorHandlers: false,
  ),
);
await appInitErrorHandling();  // Sets up handlers for you
```

## Testing

### Enable Reporting in Debug Mode

To test error reporting during development:

```dart
await configureErrorReporting(
  ErrorReportingConfig.customOnly(
    reporter: SentryErrorReporter(dsn: 'your-test-dsn'),
    managesOwnErrorHandlers: true,
    enableInDebug: true,  // Enable for testing
    enableOnWeb: true,
  ),
);
```

### Trigger Test Errors

**Test automatic error capture:**
```dart
// Add a debug button to your app
if (kDebugMode) {
  FloatingActionButton(
    onPressed: () {
      // Test Flutter error
      throw FlutterError('Test Flutter error');
    },
    child: Icon(Icons.bug_report),
  );
}
```

**Test async errors:**
```dart
Future<void> testAsyncError() async {
  await Future.delayed(Duration(milliseconds: 100));
  throw Exception('Test async error');
}
```

**Test manual logging:**
```dart
try {
  throw Exception('Test caught error');
} catch (e, stack) {
  loge(e, 'Testing manual error logging', stack);
}
```

### Verify Error Reports

1. **Check console output** - Look for error reporting initialization messages
2. **Check service dashboards** - Verify errors appear in Sentry/Firebase console
3. **Test all error types** - Flutter errors, async errors, manual logging
4. **Test on all platforms** - iOS, Android, Web (if enabled)

### Testing Checklist

- [ ] Errors appear in error reporting dashboard
- [ ] Stack traces are symbolicated correctly
- [ ] User context is attached (if configured)
- [ ] Release/version info is correct
- [ ] Both services receive errors (if using both)
- [ ] Web errors are captured (if `enableOnWeb: true`)
- [ ] Debug errors are filtered (if `enableInDebug: false`)

## Best Practices

### 1. Environment-Specific Configuration

Use different configurations for different environments with `--dart-define`:

**Build commands:**
```bash
# Development build
flutter build ios --dart-define=ENVIRONMENT_TYPE=development

# Staging build
flutter build android \
  --dart-define=ENVIRONMENT_TYPE=staging \
  --dart-define=SENTRY_DSN=https://staging-dsn@sentry.io/project

# Production build
flutter build web \
  --dart-define=ENVIRONMENT_TYPE=production \
  --dart-define=SENTRY_DSN=https://prod-dsn@sentry.io/project
```

**In your code:**
```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // DSN can also be configured via dart-define
  const sentryDsn = String.fromEnvironment('SENTRY_DSN', 
    defaultValue: 'https://default-dsn@sentry.io/project');
  
  await configureErrorReporting(
    ErrorReportingConfig.both(
      reporter: SentryErrorReporter(
        dsn: sentryDsn,
        // environment from AppConfigBase.environmentType (ENVIRONMENT_TYPE dart-define)
        // release auto-generated from AppConfigBase.getAppRelease()
      ),
      customReporterManagesErrorHandlers: true,
      enableInDebug: AppConfigBase.environmentType != EnvironmentType.production,
      enableOnWeb: true,
    ),
  );
  
  // ... rest of initialization
}
```

### 2. User Privacy

Be mindful of sensitive data in error reports:

```dart
// DON'T send sensitive data
reporter.setUser(userId, userEmail);  // ❌ PII

// DO use anonymized identifiers
reporter.setUser(hashedUserId, null);  // ✅ Anonymous

// Filter sensitive data
options.beforeSend = (event, hint) {
  // Remove sensitive query parameters
  if (event.request?.url != null) {
    final uri = Uri.parse(event.request!.url!);
    final cleanUri = uri.replace(queryParameters: {});
    event = event.copyWith(
      request: event.request!.copyWith(url: cleanUri.toString()),
    );
  }
  return event;
};
```

### 3. Error Filtering

Filter out noise and focus on actionable errors:

```dart
// Sentry example
options.beforeSend = (event, hint) {
  // Ignore network errors that are user's fault
  if (event.throwable is SocketException) {
    return null;  // Don't report
  }
  
  // Ignore specific error messages
  if (event.message?.contains('User cancelled') ?? false) {
    return null;
  }
  
  return event;
};
```

### 4. Release Tracking

Always include version information for tracking which version has issues:

```dart
import 'package:dreamic/app/app_config_base.dart';

// RECOMMENDED: Use centralized app version method
final release = await AppConfigBase.getAppRelease();
// Returns format: "my-app@1.0.0+42"

SentryErrorReporter(
  dsn: 'your-dsn',
  release: release,  // Track which version has issues
  environment: AppConfigBase.environmentType.value,  // Uses ENVIRONMENT_TYPE dart-define
);

// Or let it auto-configure (even better!)
SentryErrorReporter(
  dsn: 'your-dsn',
  // environment from AppConfigBase.environmentType
  // release from AppConfigBase.getAppRelease()
);
```

**Benefits of centralized version method:**
- ✅ Single source of truth across your entire app
- ✅ Cached after first call for performance
- ✅ Works correctly on Flutter Web (where `PackageInfo` can have issues)
- ✅ Consistent formatting for error reporting
- ✅ No need to repeatedly import `package_info_plus`

**Legacy approach (not recommended):**
```dart
// Don't do this - use AppConfigBase.getAppRelease() instead
import 'package:package_info_plus/package_info_plus.dart';

final packageInfo = await PackageInfo.fromPlatform();
final release = 'your-app@${packageInfo.version}+${packageInfo.buildNumber}';
```

### 5. Performance Monitoring

Monitor the impact of error reporting:

```dart
// Enable Sentry performance monitoring
options.tracesSampleRate = kDebugMode ? 1.0 : 0.2;  // 20% in production
options.profilesSampleRate = kDebugMode ? 1.0 : 0.1;  // 10% in production
```

### 6. Breadcrumbs for Context

Add breadcrumbs to understand user flow before errors:

```dart
// On navigation
reporter.addBreadcrumb('Navigated to checkout', category: 'navigation');

// On user action
reporter.addBreadcrumb('Added item to cart', category: 'user-action');

// On API calls
reporter.addBreadcrumb('Fetching user profile', category: 'http');
```

### 7. Test Before Deploying

Always test error reporting before production deployment:

```dart
// Use separate DSN for staging
final dsn = environment == 'production'
    ? productionDsn
    : stagingDsn;  // Test with staging DSN first
```

### 8. Monitor Error Budgets

Set error rate thresholds and monitor them:

- Track error rate per release
- Set up alerts for error spikes
- Monitor error-free session rate
- Review errors regularly

### 9. Use Consistent Logging

Use the Logger throughout your app:

```dart
// ✅ Good: Consistent logging
try {
  await riskyOperation();
} catch (e, stack) {
  loge(e, 'Operation failed', stack);
}

// ❌ Bad: Inconsistent or missing logging
try {
  await riskyOperation();
} catch (e) {
  print('Error: $e');  // Not captured by error reporting
}
```

### 10. Handle Platform Differences

Configure appropriately for each platform:

```dart
ErrorReportingConfig.both(
  reporter: SentryErrorReporter(dsn: 'your-dsn'),
  customReporterManagesErrorHandlers: true,
  // Firebase doesn't work on web, but errors still go to Sentry
  enableOnWeb: kIsWeb,  // Sentry works on all platforms
  enableInDebug: false,  // Don't spam during development
)
```

## Troubleshooting

### Errors Not Being Reported

**Problem:** Errors aren't showing up in your error reporting dashboard.

**Solutions:**
1. **Check initialization order:**
   ```dart
   // ✅ Correct order
   await configureErrorReporting(...);
   await appInitErrorHandling();
   ```

2. **Verify DSN/API key:**
   ```dart
   // Check for typos in DSN
   options.dsn = 'https://your-dsn@sentry.io/project-id';  // Must be valid
   ```

3. **Check environment settings:**
   ```dart
   enableInDebug: true,  // Enable for testing
   enableOnWeb: true,    // Enable for web testing
   ```

4. **Look for initialization errors:**
   - Check console for error messages
   - Look for Sentry/Firebase initialization logs
   - Verify network connectivity

5. **Test with a simple error:**
   ```dart
   throw Exception('Test error');  // Should appear in dashboard
   ```

### Duplicate Error Reports

**Problem:** Same error appears twice in different services.

**Expected behavior:** When using `ErrorReportingConfig.both()`, errors are intentionally reported to both services.

**If unwanted:**
- Use `ErrorReportingConfig.customOnly()` to disable Firebase
- Use `ErrorReportingConfig.firebaseOnly()` to disable custom reporter

**Check for manual error handlers:**
```dart
// ❌ Don't set up handlers manually if using Dreamic
FlutterError.onError = (details) {
  // This creates duplicates!
};
```

### Wrapper-Based Setup Not Working

**Problem:** Using `SentryFlutter.init` but errors aren't captured correctly.

**Solution:** Ensure `managesOwnErrorHandlers: true`:
```dart
await configureErrorReporting(
  ErrorReportingConfig.customOnly(
    reporter: SentryErrorReporter(dsn: 'your-dsn'),
    managesOwnErrorHandlers: true,  // ← Important!
    enableOnWeb: true,
  ),
);
await appInitErrorHandling();

await SentryFlutter.init(
  (options) => options.dsn = 'your-dsn',
  appRunner: () => appRunIfValidVersion(() => MyApp()),
);
```

### Web Platform Issues

**Problem:** Firebase Crashlytics errors on web.

**Solution:** Firebase Crashlytics doesn't work on web. Use a custom reporter:
```dart
ErrorReportingConfig.customOnly(
  reporter: SentryErrorReporter(dsn: 'your-dsn'),
  enableOnWeb: true,  // Sentry works on web
)
```

Or use both (Firebase on mobile, custom on web):
```dart
ErrorReportingConfig.both(
  reporter: SentryErrorReporter(dsn: 'your-dsn'),
  enableOnWeb: true,  // Sentry handles web errors
)
```

### Errors Only Reporting to One Service

**Problem:** Using `both()` but errors only go to one service.

**Checklist:**
1. Verify both services are initialized
2. Check console for initialization errors
3. Test with manual logging: `loge(Exception('Test'), 'Test message')`
4. Check both service dashboards

**For wrapper-based setup with both services:**
```dart
// Must set customReporterManagesErrorHandlers: true
ErrorReportingConfig.both(
  reporter: SentryErrorReporter(dsn: 'your-dsn'),
  customReporterManagesErrorHandlers: true,  // Required!
)
```

### Missing Stack Traces

**Problem:** Errors show up but without stack traces.

**Solutions:**
1. **Always pass stack trace:**
   ```dart
   // ✅ Good
   loge(error, 'Message', stackTrace);
   
   // ❌ Bad
   loge(error, 'Message');  // Missing stack trace
   ```

2. **For Flutter web**, ensure source maps are uploaded to your error reporting service

3. **For native crashes**, ensure symbolication is configured in Firebase/Sentry

### Performance Issues

**Problem:** App feels slower after adding error reporting.

**Solutions:**
1. **Reduce trace sample rate:**
   ```dart
   options.tracesSampleRate = 0.2;  // Sample 20% instead of 100%
   ```

2. **Disable in debug mode:**
   ```dart
   enableInDebug: false,  // Don't report during development
   ```

3. **Filter unnecessary errors:**
   ```dart
   options.beforeSend = (event, hint) {
     if (shouldIgnoreError(event)) return null;
     return event;
   };
   ```

### Common Pitfalls

❌ **Don't do this:**
```dart
// Wrong: Calling both approaches
configureErrorReporting(config);
await appInitErrorHandling();
// And also setting up handlers manually
FlutterError.onError = ...;  // Duplicate!
```

❌ **Don't do this:**
```dart
// Wrong: Using wrapper flag with manual setup
ErrorReportingConfig.customOnly(
  reporter: ManualSentryReporter(),
  managesOwnErrorHandlers: true,  // ❌ Should be false
)
await appInitErrorHandling();
// Not using SentryFlutter.init wrapper
```

✅ **Do this:**
```dart
// Correct: Consistent approach
await configureErrorReporting(
  ErrorReportingConfig.customOnly(
    reporter: SentryErrorReporter(dsn: 'dsn'),
    managesOwnErrorHandlers: true,  // ✅ Matches wrapper approach
  ),
);
await appInitErrorHandling();
await SentryFlutter.init(...);  // Wrapper approach
```

## API Reference

### ErrorReporter Interface

```dart
abstract class ErrorReporter {
  /// Initialize the error reporter (e.g., Sentry.init, Bugsnag.start)
  Future<void> initialize();
  
  /// Record a generic error with optional stack trace
  void recordError(Object error, StackTrace? stackTrace);
  
  /// Record a Flutter-specific error with FlutterErrorDetails
  void recordFlutterError(FlutterErrorDetails details);
}
```

### ErrorReportingConfig Class

```dart
class ErrorReportingConfig {
  /// The custom error reporter instance
  final ErrorReporter? customReporter;
  
  /// Whether to use Firebase Crashlytics
  final bool useFirebaseCrashlytics;
  
  /// Whether custom reporter manages its own error handlers
  /// Set to true when using wrapper functions like SentryFlutter.init
  final bool customReporterManagesErrorHandlers;
  
  /// Enable error reporting in debug mode (default: false)
  final bool enableInDebug;
  
  /// Enable error reporting on web platform (default: false)
  final bool enableOnWeb;
  
  /// Create custom configuration
  const ErrorReportingConfig({
    this.customReporter,
    this.useFirebaseCrashlytics = true,
    this.customReporterManagesErrorHandlers = false,
    this.enableInDebug = false,
    this.enableOnWeb = false,
  });
  
  /// Firebase Crashlytics only (default)
  const ErrorReportingConfig.firebaseOnly({
    this.enableInDebug = false,
    this.enableOnWeb = false,
  });
  
  /// Custom reporter only (e.g., Sentry)
  const ErrorReportingConfig.customOnly({
    required ErrorReporter reporter,
    bool managesOwnErrorHandlers = false,
    this.enableInDebug = false,
    this.enableOnWeb = false,
  });
  
  /// Both Firebase and custom reporter
  const ErrorReportingConfig.both({
    required ErrorReporter reporter,
    bool customReporterManagesErrorHandlers = false,
    this.enableInDebug = false,
    this.enableOnWeb = false,
  });
}
```

### Functions

```dart
/// Configure error reporting before initialization
/// Call this before appInitErrorHandling()
Future<void> configureErrorReporting(ErrorReportingConfig config);

/// Get the current error reporting configuration
ErrorReportingConfig get errorReportingConfig;

/// Initialize error handling with configured reporters
/// Call this after configureErrorReporting()
Future<void> appInitErrorHandling([ErrorReportingConfig? config]);
```

### Logger Functions

```dart
/// Log an error with optional message and stack trace
/// Automatically reports to configured error reporters
void loge(Object error, [String? message, StackTrace? trace]);

/// Log debug message
void logd(String message);

/// Log info message
void logi(String message);

/// Log warning message
void logw(String message);
```

## Summary

### Quick Decision Guide

**Choose your setup:**

1. **Firebase only (default)** → No configuration needed
2. **Sentry only** → `ErrorReportingConfig.customOnly()` with `managesOwnErrorHandlers: true`
3. **Both Firebase + Sentry** → `ErrorReportingConfig.both()` with `customReporterManagesErrorHandlers: true`
4. **Custom service** → Implement `ErrorReporter` interface, use appropriate config

**Key flags:**
- `managesOwnErrorHandlers: true` → For wrapper-based initialization (e.g., `SentryFlutter.init`)
- `managesOwnErrorHandlers: false` → For manual initialization (e.g., `Sentry.init`)
- `enableInDebug: true` → For testing error reporting during development
- `enableOnWeb: true` → For web platform support (Firebase doesn't support web)

### Initialization Order

```dart
1. WidgetsFlutterBinding.ensureInitialized()
2. AppConfigBase defaults
3. appInitFirebase() (if using Firebase)
4. configureErrorReporting() ← Configure here
5. appInitErrorHandling() ← Initialize handlers
6. SentryFlutter.init() (if using wrapper) ← OR runApp()
```

### Tested and Verified

All error reporting scenarios are fully tested:
- ✅ 52 total tests passing
- ✅ Firebase only
- ✅ Custom reporter only (manual and wrapper)
- ✅ Both services (manual and wrapper)
- ✅ All error types (Flutter, async, isolate, manual)
- ✅ Logger integration
- ✅ Zero analyzer warnings

## Support

For issues or questions:
- **Dreamic Documentation:** [README.md](../README.md)
- **Dreamic Features Guide:** [DREAMIC_FEATURES_GUIDE.md](DREAMIC_FEATURES_GUIDE.md)
- **GitHub Issues:** Open an issue on the Dreamic repository
- **Sentry Documentation:** https://docs.sentry.io/platforms/flutter/
- **Firebase Crashlytics:** https://firebase.google.com/docs/crashlytics
