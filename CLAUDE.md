<!-- OPENSPEC:START -->
# OpenSpec Instructions

These instructions are for AI assistants working in this project.

Always open `@/openspec/AGENTS.md` when the request:
- Mentions planning or proposals (words like proposal, spec, change, plan)
- Introduces new capabilities, breaking changes, architecture shifts, or big performance/security work
- Sounds ambiguous and you need the authoritative spec before coding

Use `@/openspec/AGENTS.md` to learn:
- How to create and apply change proposals
- Spec format and conventions
- Project structure and guidelines

Keep this managed block so 'openspec update' can refresh the instructions.

<!-- OPENSPEC:END -->

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

### Development

**Required Practices:**
- **ALWAYS** utilize the Dart and Flutter MCP server for enhanced AI assistance
- **LEVERAGE** MCP server capabilities for:
  - Code analysis and error detection
  - Package management
  - Test running
  - Widget tree inspection
  - Pub.dev package search

```bash
# Install dependencies
flutter pub get

# Run the application
flutter run

# Run with production backend
flutter run --dart-define BACKEND_REGION=us-east4

# Analyze code
flutter analyze

# Run tests
flutter test

# Generate code (for JSON serialization, etc.)
flutter packages pub run build_runner build

# Production iOS build
flutter build ipa --dart-define BACKEND_REGION=us-east4
```

## Architecture

This is a foundational Flutter package designed as a base for other Flutter projects. It provides comprehensive Firebase integration, state management, and configuration capabilities.

### Core Architecture Layers

1. **App Layer** (`lib/app/`): Application-wide state management using BLoC/Cubit pattern
   - `AppCubit` manages global application state
   - `CubitBase` with `SafeEmitMixin` provides safe state emissions
   - Configuration management with three-tier fallback: Environment → Firebase Remote Config → Defaults

2. **Data Layer** (`lib/data/`): Repository pattern implementation
   - Models in `models/` with JSON serialization
   - Repository interfaces in `models_bases/`
   - Repository implementations in `repos/` with mock support for testing

3. **Presentation Layer** (`lib/presentation/`): UI components
   - Reusable elements in `elements/`
   - Debug widgets for testing in `debug/`
   - Helper utilities for UI in `helpers/`

### Key Patterns and Dependencies

- **State Management**: BLoC/Cubit pattern with `flutter_bloc`
- **Dependency Injection**: Service locator pattern using `get_it`
- **Functional Programming**: `dartz` for Either types and error handling
- **Firebase Integration**: Complete Firebase suite (Auth, Firestore, Functions, Remote Config, etc.)
- **Platform Abstraction**: Separate implementations for iOS, Android, and Web

### Critical Services

1. **App Update System**: Automatic version checking via Firebase Remote Config with blocking/non-blocking update types
2. **Authentication**: Firebase Auth with anonymous and federated support, automatic token management
3. **Network Management**: Connection checking, emulator discovery, retry logic with exponential backoff
4. **Configuration**: Multi-tier configuration system with compile-time and runtime options
5. **Logging**: Configurable log levels with Firebase Crashlytics integration

### Development Notes

- **Emulator Support**: Automatic Firebase emulator discovery for local development
- **Mock Implementations**: Repository mocks available for offline development
- **Debug Widgets**: Special UI components for testing app updates and configuration changes
- **Platform Detection**: Smart detection of simulators vs physical devices
- **Rate Limiting**: App update checks designed to stay under Firebase's 5 fetches/hour limit

When modifying code:
- Maintain the existing BLoC/Cubit pattern for state management
- Use the repository pattern for data operations
- Follow the three-layer architecture (app/data/presentation)
- Ensure proper error handling with Either types
- Test with Firebase emulators when possible
- Use existing base classes (`CubitBase`, `CubitBaseState`) for consistency