## 0.2.0

### ✨ New Feature: Comprehensive Notification Service

#### Overview
Added a complete, production-ready notification system that abstracts away FCM complexity and eliminates ~300 lines of boilerplate code from consuming apps.

#### Added
* **NotificationService** - Central service for managing all notification functionality
  * Lazy initialization (no side effects until explicitly initialized)
  * Automatic FCM message handling (foreground, background, terminated states)
  * Local notification display with platform-specific customization
  * Permission request management with iOS/Android/web support
  * Notification routing with deep link support
  * Badge count management across platforms
  * Permission state tracking and analytics
  * Periodic reminder system for denied permissions

* **Notification Models** (`lib/data/models/`)
  * `NotificationPayload` - Complete notification data structure
  * `NotificationAction` - Action button definitions
  * `NotificationPermissionStatus` - Unified permission state enum

* **NotificationPermissionHelper** - Permission management utilities
  * Permission status checking
  * Optimal timing suggestions for permission requests
  * Permission request history tracking
  * Platform-aware permission capabilities

* **Background Handler** - Top-level FCM background message handler
  * `dreamicNotificationBackgroundHandler` - Ready-to-use background handler
  * Isolate-safe with automatic Firebase initialization
  * Extensible for custom background logic

* **UI Components** (`lib/presentation/elements/`)
  * `NotificationPermissionBottomSheet` - Beautiful permission request UI
    * Platform-native dialogs (Cupertino on iOS, Material on Android) via `adaptive_dialog`
    * Full text customization for localization support
    * Handles denied state with settings prompt
  * `NotificationPermissionStatusWidget` - Real-time permission status display
  * `NotificationPermissionBuilder` - Headless builder for custom UIs
    * Provides permission status and request method via callback
    * Automatically rebuilds on status changes
    * Enables fully custom permission UIs
  * `NotificationBadgeWidget` - Notification count badge overlay
    * Automatic sync with NotificationService badge count
    * Manual mode for custom counts
    * Automatic overflow handling ("99+")
    * Customizable colors, size, and position
    * Optional hide-when-zero behavior
    * Configurable polling interval
  * Customizable styling and messaging
  * Automatic platform-specific behavior

* **Documentation**
  * `NOTIFICATION_GUIDE.md` - Comprehensive usage guide with examples
  * Before/after code comparisons showing boilerplate reduction
  * Platform configuration guides
  * Permission strategy best practices

#### Key Benefits
* **Massive Boilerplate Reduction**: ~300 lines → 1 `initialize()` call
* **Better Permission UX**: Controlled timing, contextual prompts, recovery flows
* **Optional Feature**: Zero impact on apps that don't use notifications
* **Production Ready**: Error handling, logging, platform-specific optimizations
* **Framework Agnostic**: Works with any navigation system (Navigator 1.0/2.0, go_router, etc.)

#### Dependencies Added
* `flutter_local_notifications: ^18.0.1` - Local notification display
* `app_badge_plus: ^1.1.5` - Badge count management
* `adaptive_dialog: ^2.2.0` - Platform-native dialogs (iOS/Android)

#### Migration
No breaking changes. This is a new optional feature. See `NOTIFICATION_GUIDE.md` for setup instructions.

## 0.1.0

### 🎉 Major Improvement: Full Web Platform Support for Real-Time Remote Config

#### Background
Firebase Remote Config `onConfigUpdated` listener is now fully supported on web platforms as of **firebase_remote_config 6.1.0**! Previously, this package used polling-based workarounds (periodic refresh every 5 minutes) since the listener wasn't available on web.

#### Breaking Changes
* **None** - This release maintains full backward compatibility

#### Removed/Deprecated
* **WebRemoteConfigRefreshService** - Marked as `@Deprecated` (kept for backward compatibility, will be removed in 1.0.0)
  * No longer needed - the real-time `onConfigUpdated` listener now works on web
  * Periodic polling (every 5 minutes) replaced by instant real-time updates
  * File kept for backward compatibility but removed from package exports
* **webForceInitialFetch()** - Removed from `app_remote_config_init.dart`
  * No longer needed - initial fetch and updates handled automatically by listener

#### Changed
* **AppVersionUpdateService** - Now uses real-time listener on ALL platforms including web
  * Removed `if (kIsWeb) return;` check that prevented listener setup on web
  * Added platform-aware logging for better debugging
  * Web apps now receive Remote Config updates instantly (< 1 second) instead of waiting up to 5 minutes
* **app_remote_config_init.dart** - Simplified initialization logic
  * Removed web-specific initialization code
  * Unified initialization flow across all platforms
  * Updated documentation to reflect real-time support on all platforms

#### Benefits
* **Real-Time Updates on Web**: Config changes appear instantly (< 1 second vs 0-5 minutes)
* **Better Performance**: No unnecessary polling - network calls only when configs change
* **Lower Bandwidth**: ~98% reduction in network usage on web (~720 KB/day → ~12 KB/day per user)
* **Unified Codebase**: Single code path for all platforms, easier to maintain
* **Cleaner Code**: ~230 lines of workaround code removed/deprecated

#### Dependencies Updated
```yaml
firebase_remote_config: ^6.1.0  # Now supports onConfigUpdated on web
```

#### Migration Guide
Apps using this package don't need any changes - improvements are internal! However:
* If you were manually using `WebRemoteConfigRefreshService`, stop using it (deprecated)
* If you were calling `webForceInitialFetch()`, remove those calls (function removed)
* The `AppVersionUpdateService` now automatically handles all platforms including web

See `REMOTE_CONFIG_WEB_MIGRATION.md` for detailed migration information.

#### Files Modified
* `lib/app/helpers/app_version_update_service.dart` - Enabled listener on web, updated comments
* `lib/app/helpers/app_remote_config_init.dart` - Removed web workarounds, simplified logic
* `lib/app/helpers/web_remote_config_refresh_service.dart` - Marked as deprecated
* `lib/dreamic.dart` - Removed export of deprecated service

#### Documentation Added
* `REMOTE_CONFIG_WEB_MIGRATION.md` - Comprehensive migration guide
* `CHANGELOG_WEB_SUPPORT.md` - Detailed technical changelog

---

## 0.0.12

### Added
* **Robust Enum Converters** - Crash-proof enum serialization that handles unknown values gracefully
  * Added `RobustEnumConverter<T>` base class for creating enum converters
  * Added `NullableEnumConverter<T>` - returns null for unknown enum values (recommended for nullable fields)
  * Added `DefaultEnumConverter<T>` - returns a default value for unknown enum values (recommended for non-nullable fields)
  * Added `LoggingEnumConverter<T>` - logs unknown values before returning default (recommended for monitoring)
  * Solves the problem of old app versions crashing when server adds new enum values
  * No need for `@JsonKey(unknownEnumValue: ...)` on every field
  * No need for "unknown" value in every enum
  * Forward compatible - old apps gracefully handle new server enum values

### Documentation
* **ENUM_QUICK_START.md** - 5-minute quick start guide
  * Simple step-by-step instructions
  * Strategy selection guide
  * Real-world examples
  * Clear and concise format
* **ENUM_SOLUTION_ARCHITECTURE.md** - Design decisions document
  * Problem analysis and solution rationale
  * Architecture decisions and trade-offs
  * Implementation structure overview
* **MODEL_SERIALIZATION_GUIDE.md** - Added comprehensive "Enum Converters" section
  * Problem explanation and traditional approach issues
  * Detailed guide for each converter type
  * Real-world scenarios and use cases
  * Benefits over traditional approach
  * Migration guide and best practices
  * Troubleshooting section
* **enum_example.dart** - Complete real-world example showing:
  * Multiple enum types in one application
  * Different converter strategies for different use cases
  * Service layer integration
  * Backward compatibility scenarios

### Tests
* **enum_converters_test.dart** - Comprehensive test suite for enum converters
  * Tests for all three converter types (Nullable, Default, Logging)
  * Real-world backward compatibility scenarios
  * Edge cases (empty strings, whitespace, case sensitivity)
  * Multiple unknown values handling
  * Roundtrip conversion tests

## 0.0.11

### Added
* **Test Utilities** - New testing support for widgets that use Dreamic components
  * Added `MockAppCubit` class for widget testing with configurable network, auth, and app states
  * Added `initializeTappableActionForTesting()` to prevent timer-related test failures
  * Added `wrapWithMockAppCubit()` helper for easy test setup with BlocProvider
  * Exported test utilities from main package for consumer access
  * Supports dynamic state changes during tests via setter methods

### Documentation
* **TESTING_GUIDE.md** - Comprehensive testing guide with examples for:
  * Testing TappableAction widgets with various configurations
  * Testing network-dependent features and state transitions
  * Testing authentication-dependent features
  * Testing loading states and error scenarios
  * Advanced patterns including async operations, golden tests, and complex state combinations
  * Complete working examples and common issue solutions
* **DREAMIC_FEATURES_GUIDE.md** - Added Testing section with quick start guide and best practices
* **SETUP_NEW_PROJECT.md** - Renamed from SETUP_DREAMIC.md for clarity

## 0.0.10

### Fixed
* **Test Compatibility** - Logger and AppConfigBase now handle GetIt not being initialized (e.g., in test environments)
  * Added try-catch blocks to safely handle cases where RemoteConfigRepoInt is not available
  * Logger defaults to debug level when AppConfigBase.logLevel cannot be retrieved
  * Prevents crashes when using logging utilities in unit tests without full app initialization

## 0.0.9

### Changed
* **Reduced Log Verbosity** - Version checking and app lifecycle logs now use verbose level (`logv`) instead of debug level (`logd`)
  * App resume/pause lifecycle events moved to verbose logging
  * Version check details and comparisons moved to verbose logging
  * Remote Config status checks moved to verbose logging
  * Only critical events remain at debug level: actual version updates (required/recommended) and Remote Config changes
  * Significantly reduces log noise during normal app operation

## 0.0.8

### Fixed
* **Web Platform Logging** - Logger now uses `print()` instead of `debugPrint()` in release mode on web to ensure logs appear in browser console (debugPrint is compiled away in release builds)
* **Firebase Crashlytics Web Support** - Added platform checks to prevent runtime errors on web where Crashlytics is not supported

### Changed
* **Error Reporting Configuration** - Added detailed configuration logging in `appInitErrorHandling()` to help verify error reporting setup
* **Firebase Initialization** - Removed automatic Firebase initialization from `appInitErrorHandling()`. Firebase must now be initialized via `appInitFirebase()` first when using Crashlytics

### Documentation
* Updated ERROR_REPORTING_GUIDE.md with Quick Start Checklist and clearer Sentry integration best practices
* Enhanced error_reporter_example.dart with step-by-step integration examples

## 0.0.7

### Documentation
* Updated ERROR_REPORTING_GUIDE.md and error_reporter_example.dart with improved Sentry integration examples

## 0.0.6

### Added
* **EnvironmentType Enum** - Type-safe environment configuration
  * New `EnvironmentType` enum with five values: `emulator`, `development`, `test`, `staging`, `production`
  * `AppConfigBase.environmentType` now returns enum type instead of string
  * Added `AppConfigBase.environmentTypeString` convenience getter for string value
  * Includes `fromString()` method for parsing `--dart-define` values
  * Provides IDE autocomplete support and compile-time type checking
  * Exhaustive switch statement checking for better code safety
* **Centralized App Version Methods** in `AppConfigBase`
  * `getAppVersion()` - Returns cached `PackageInfo` instance
  * `getAppVersionString()` - Returns version string (e.g., "1.0.0")
  * `getAppBuildNumber()` - Returns build number string (e.g., "42")
  * `getAppRelease()` - Returns formatted release string (e.g., "my-app@1.0.0+42")
  * Cached implementation for better performance
  * Works correctly on Flutter Web where `PackageInfo` can have issues
* **Exported AppConfigBase** in main library file (`dreamic.dart`)
  * Makes `AppConfigBase` and `EnvironmentType` available to package users

### Changed
* **Updated Sentry Integration Documentation** - Comprehensive updates across all docs
  * All examples now use Sentry's recommended `appRunner` pattern with `SentryFlutter.init()`
  * Integrated `appRunIfValidVersion()` in all `appRunner` examples for automatic version checking
  * Updated `ERROR_REPORTING_GUIDE.md` with three clear integration approaches:
    * Approach A: `appRunner` (RECOMMENDED) - Simplest, no custom ErrorReporter needed
    * Approach B: `appRunner` with Dreamic Config - For integration with Dreamic's configuration system
    * Approach C: Manual Integration (Advanced) - Full control with ErrorReporter interface
  * Updated `DREAMIC_FEATURES_GUIDE.md` with complete examples using `appRunner` and version checking
  * Updated `error_reporter_example.dart` with detailed documentation for all three approaches
  * All examples now use `AppConfigBase.environmentType.value` and `AppConfigBase.getAppRelease()`
* **Centralized Version Information** - Refactored to use `AppConfigBase` methods
  * Updated `app_version_check.dart` to use `AppConfigBase.getAppVersion()`
  * Updated `app_version_update_service.dart` to use centralized version method
  * Updated `app_cubit.dart` to use centralized version method
  * Updated `app_update_debug_widget.dart` to use `AppConfigBase.getAppVersionString()`
  * Removed duplicate `package_info_plus` imports across 5 files

### Fixed
* **Environment Configuration** - More flexible and type-safe
  * Environment type now supports all standard environments (emulator, dev, test, staging, prod)
  * Backward compatible with existing `--dart-define=ENVIRONMENT_TYPE=value` configuration
  * Smart defaults: `development` in debug mode, `production` in release mode

### Documentation
* **ERROR_REPORTING_GUIDE.md**
  * Added "Build Configuration (dart-define)" section with ENVIRONMENT_TYPE documentation
  * Restructured Sentry Integration section with clear approach comparisons
  * Added examples showing `appRunIfValidVersion()` integration
  * Updated all code examples to use type-safe `EnvironmentType` enum
  * Added troubleshooting section for wrapper-based setup
* **DREAMIC_FEATURES_GUIDE.md**
  * Added environment type documentation with enum examples
  * Updated all Sentry examples to show `appRunner` pattern
  * Added "Complete Example" sections showing recommended patterns
  * Updated build configuration examples with proper environment and release usage

### Notes
* **100% Backward Compatible** - All existing code continues to work
  * String values via `--dart-define=ENVIRONMENT_TYPE=production` still work exactly the same
  * Existing error reporting configurations unchanged
  * No breaking changes to any APIs
* **Migration Path** - Easy upgrade from string to enum
  * Use `.value` property to get string value when needed
  * Use `environmentTypeString` getter as convenience method
  * Existing configurations work without modification

## 0.0.5

### Added
* **BaseFirestoreModel** - New abstract base class for intelligent Firebase serialization
  * Context-aware serialization (Firestore, Cloud Functions, local storage)
  * Separate methods for create vs update operations (`toFirestoreCreate()`, `toFirestoreUpdate()`)
  * Support for data migration with `toFirestoreRaw()`
  * Cloud Functions integration with `toCallable()`
  * Configurable timestamp field management
  * Custom post-processing hooks
* **SmartTimestampConverter** - Enhanced timestamp converter supporting multiple formats
  * Handles Firestore Timestamp objects
  * Supports Cloud Functions Map format
  * Works with milliseconds and ISO strings
  * Nullable and non-nullable variants
* **ConnectionToaster** - Optional network status toast notifications
  * Shows "Connecting..." toast when network connection is lost
  * Automatically dismisses when connection is restored
  * Smart behavior: doesn't show during app startup/resume by default
  * Configurable delay before showing toast (defaults to immediate)
  * Optional `showOnInitialConnection` flag for showing during app load
  * Integrated into `AppRootWidget` as opt-in feature
* Comprehensive documentation in `docs/`
  * Complete usage guide with examples (`MODEL_SERIALIZATION_GUIDE.md`)
  * Embedded example models covering different use cases
  * Service implementations with real-world patterns (CRUD, batch operations, transactions, and more)

### Changed
* Enhanced `model_converters.dart` with new Smart converters
* Exported data models and converters in main library file
* **AppRootWidget** now supports optional `ConnectionToaster` integration
  * Added `useConnectionToaster` parameter (defaults to `false` for backward compatibility)
  * Added `showConnectionToastOnInitialConnection` parameter to control toast behavior during app startup
  * Added `connectionToastDelay` parameter for customizing toast display timing
  * ConnectionToaster wraps entire app content at top level when enabled, ensuring toasts appear above all UI

### Notes
* **100% Backward Compatible** - All existing converters continue to work exactly as before
* No breaking changes to existing APIs
* New features are opt-in only
* Both old and new approaches can coexist in the same project

## 0.0.4

* Upgraded dependencies

## 0.0.3

* Initial public release.
