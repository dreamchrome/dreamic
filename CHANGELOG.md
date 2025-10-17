## 0.0.5 (Unreleased)

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
  * Complete usage guide (`FIREBASE_SERIALIZATION_GUIDE.md`)
  * Implementation notes (`BASE_FIRESTORE_MODEL_IMPLEMENTATION.md`)
  * Quick reference (`README_FIREBASE_SERIALIZATION.md`)
* Example implementations in `lib/data/models/`
  * 5 example models covering different use cases
  * Complete service implementations with real-world patterns
  * CRUD, batch operations, transactions, and more

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
