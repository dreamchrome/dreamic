# Project Context

## Purpose

Dreamic is a comprehensive, general-purpose Flutter/Firebase package that provides production-ready infrastructure for building robust mobile and web applications. The package encapsulates best practices and reusable patterns for:

- Firebase integration (Auth, Firestore, Storage, Cloud Functions, Remote Config, Crashlytics, Messaging)
- State management using BLoC/Cubit architecture
- Error handling and reporting
- Model serialization with intelligent timestamp management
- Network connectivity management
- App lifecycle and version management
- Authentication flows with multiple providers
- Testing utilities for complex widget scenarios

**Goals:**
- Reduce boilerplate and setup time for new Flutter/Firebase projects
- Provide crash-resistant patterns (especially for enum serialization)
- Maintain backward compatibility while adding new features
- Support both mobile (iOS/Android) and web platforms
- Enable rapid prototyping with production-ready code

## Tech Stack

### Core Technologies
- **Flutter** (SDK ^3.5.4+) - Cross-platform UI framework
- **Dart** (SDK ^3.5.4) - Programming language
- **Firebase** - Backend services suite
  - Firebase Auth (^6.1.1) - Authentication
  - Cloud Firestore (^6.0.3) - NoSQL database
  - Cloud Functions (^6.0.3) - Serverless functions
  - Firebase Storage (^13.0.3) - File storage
  - Firebase Remote Config (^6.1.0) - Feature flags and configuration
  - Firebase Crashlytics (^5.0.3) - Crash reporting
  - Firebase Cloud Messaging (^16.0.3) - Push notifications

### State Management & Architecture
- **flutter_bloc** (^9.1.1) & **bloc** (^9.1.0) - BLoC pattern implementation
- **get_it** (^9.0.5) - Dependency injection
- **equatable** (^2.0.7) - Value equality for state objects

### Data & Serialization
- **json_annotation** (^4.9.0) & **json_serializable** (^6.11.1) - JSON serialization
- **dartz** (^0.10.1) - Functional programming (Either, Option types)

### Platform & Device
- **device_info_plus** (^12.2.0) - Device information
- **package_info_plus** (^9.0.0) - App version info
- **connectivity_plus** (^6.1.5) - Network connectivity monitoring
- **internet_connection_checker** (^3.0.1) - Internet connection validation
- **shared_preferences** (^2.5.3) - Local key-value storage
- **path_provider** (^2.1.5) - File system paths
- **wakelock_plus** (^1.4.0) - Prevent device sleep

### Utilities
- **http** (^1.5.0) - HTTP client
- **url_launcher** (^6.3.2) - Launch URLs
- **exponential_back_off** (^0.1.0+2) - Retry logic
- **tap_debouncer** (^2.2.0) - Debouncing
- **flutter_timezone** (^5.0.1) - Timezone handling
- **percent_indicator** (^4.2.5) - Progress indicators
- **open_file** (^3.5.10) - File opening
- **web** (^1.1.1) - Web platform support

### Development Tools
- **flutter_test** - Testing framework
- **flutter_lints** (^6.0.0) - Lint rules
- **build_runner** (^2.10.1) - Code generation

## Project Conventions

### Code Style

**Formatting:**
- **Formatter**: Dart formatter with trailing commas preserved
- **Page width**: 100 characters max
- **Lint rules**: Uses `package:flutter_lints/flutter.yaml` as base
- **Trailing commas**: Always preserve for better diffs and formatting

**Naming Conventions:**
- Files: `snake_case.dart`
- Classes: `PascalCase`
- Functions/variables: `camelCase`
- Private members: `_leadingUnderscore`
- Constants: `camelCase` or `SCREAMING_SNAKE_CASE` for compile-time constants
- Enums: `PascalCase` enum types, `camelCase` values

**Documentation:**
- All public APIs should have doc comments
- Comprehensive guides in `docs/` directory for major features
- Examples included in documentation

### Architecture Patterns

**BLoC/Cubit Pattern:**
- Use `Cubit` for simpler state management (most common)
- Use full `Bloc` only when events provide clarity
- State classes extend `Equatable` for value equality
- All state changes go through `emitSafe()` mixin to prevent closed cubit emissions

**Repository Pattern:**
- Data layer (`lib/data/repos/`) handles all external data access
- Repositories return `Either<Failure, T>` from dartz for error handling
- Use `*ServiceImpl` for implementations and `*ServiceInt` for interfaces
- Firestore operations use `BaseFirestoreModel` for intelligent serialization

**Model Serialization:**
- Use `BaseFirestoreModel` for Firestore models (recommended approach)
- Implements context-aware serialization (create vs update vs Cloud Functions)
- Automatic server timestamp handling
- Supports data migration with exact timestamps
- Enum converters inherit from `RobustEnumConverter` to handle unknown values gracefully

**Dependency Injection:**
- Use `get_it` for service locator pattern
- Register dependencies at app startup
- Prefer singleton registration for services
- Use factories for objects that need per-instance state

**Error Handling:**
- All errors reported through `ErrorReporterInterface`
- Use `loge()` for logging errors (automatically reports to configured service)
- Either<Failure, Success> pattern for operations that can fail
- Graceful degradation for network failures

**Enum Handling (Critical Pattern):**
- **Never** add "unknown" values to domain enums
- Use `RobustEnumConverter` subclasses:
  - `NullableEnumConverter` - Optional fields (unknown → null)
  - `DefaultEnumConverter` - Required fields (unknown → default value)
  - `LoggingEnumConverter` - Critical fields (unknown → log + default)
- Prevents crashes when server adds new enum values

### Testing Strategy

**Test Structure:**
- Unit tests in `test/` mirror `lib/` structure
- Widget tests use `wrapWithMockAppCubit()` for context
- Always call `initializeTappableActionForTesting()` in `setUpAll()` for widgets using `TappableAction`

**Testing Utilities:**
- `MockAppCubit` - Mock app state with controllable network/auth status
- `wrapWithMockAppCubit()` - Provides BlocProvider context for testing
- `initializeTappableActionForTesting()` - Prevents timer-related test failures

**Coverage:**
- Test core business logic with unit tests
- Test UI components with widget tests
- Test state management with cubit tests
- Test serialization with model tests

**Key Testing Patterns:**
- Mock network connectivity states
- Mock authentication states
- Test loading states and error states
- Verify proper error reporting

### Git Workflow

- **Repository**: https://github.com/dreamchrome/dreamic
- **Main branch**: `main`
- **Issue tracking**: GitHub Issues
- **Versioning**: Semantic versioning (MAJOR.MINOR.PATCH)
- **Changelog**: Maintained in `CHANGELOG.md`

## Domain Context

### Firebase Model Lifecycle
Models go through distinct lifecycle states that affect serialization:
- **Create**: Initial document creation (uses FieldValue.serverTimestamp())
- **Update**: Modifying existing documents (preserves original timestamps)
- **Cloud Functions**: Server-side operations (different field expectations)
- **Migration**: Historical data import (uses exact DateTime values)

### Authentication Flows
The package supports multiple authentication patterns:
- Email/Password with validation
- Phone authentication with SMS
- Email link (passwordless)
- Anonymous authentication
- Custom tokens
- Access code systems
- Development-only auth modes

### App Lifecycle States
Applications using Dreamic have these key states (AppStatus enum):
- `loading` - Initial data load
- `normal` - Standard operation
- `overlayLoading` - Showing loading overlay
- `overlayProgressing` - Progress indicator overlay
- `overlyFullScreen` - Full-screen overlay content
- `networkError` - No internet connection
- `outdated` - App version too old, update required

### Network Awareness
The package automatically monitors:
- Internet connectivity state
- Network quality/availability
- Auto-retry logic for failed operations
- Graceful offline mode handling

## Important Constraints

### Platform Support
- **Mobile**: Full support for iOS and Android
- **Web**: Full support with specific adaptations (web_device_utils)
- **Desktop**: Partial support (depends on Firebase SDK availability)

### Firebase Limitations
- Server timestamp behavior differs between create and update operations
- Firestore transaction limits (500 writes per transaction)
- Cloud Functions callable timeout (60 seconds default)
- Remote Config fetch limits (rate limiting applies)

### Breaking Change Policy
- Maintain backward compatibility whenever possible
- Legacy converters remain fully supported
- Major version bumps only for truly breaking changes
- Migration guides provided for any breaking changes

### Performance Considerations
- Token validation cached for 5 minutes to reduce Firebase calls
- Network checks debounced to prevent excessive polling
- Lazy initialization of services when possible
- Efficient state updates using Equatable

### Web-Specific Constraints
- Firebase Auth cookie management for federated auth
- localStorage used instead of SharedPreferences on web
- APNS token handling not available on web
- Different device info API surface

## External Dependencies

### Firebase Services
- **Firebase Console**: Project configuration, Remote Config, Crashlytics dashboards
- **Cloud Firestore**: Primary data store
- **Firebase Authentication**: User identity management
- **Cloud Functions**: Serverless backend logic (callable functions expected)
- **Firebase Storage**: File and media storage
- **Firebase Cloud Messaging**: Push notifications (iOS/Android)
- **Firebase Remote Config**: Feature flags and runtime configuration

### Third-Party Error Reporting (Optional)
- **Sentry**: Configurable through `ErrorReporterInterface`
- **Bugsnag**: Configurable through `ErrorReporterInterface`
- Custom reporters can be implemented via interface

### Development Services
- **pub.dev**: Package distribution and dependency management
- **GitHub**: Source control, issue tracking, CI/CD potential

### Build-Time Dependencies
- Code generation via `build_runner` for JSON serialization
- Flutter SDK tools for platform-specific builds
