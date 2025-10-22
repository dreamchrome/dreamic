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
