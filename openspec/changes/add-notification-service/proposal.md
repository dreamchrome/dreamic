# Change: Add Comprehensive Notification Service

## Why

The Dreamic package currently has basic FCM initialization in `AuthServiceImpl`, but lacks a comprehensive notification infrastructure that apps need for production use. 

### Current Pain Points (Real Example)

Apps using Dreamic currently must implement ~300 lines of boilerplate code in `main.dart` and `app.dart`:

**In `main.dart`:**
- Create `setupFlutterNotifications()` function
- Define top-level `_firebaseMessagingBackgroundHandler()`
- Create `AndroidNotificationChannel` manually
- Initialize `FlutterLocalNotificationsPlugin`
- Register background message handler
- Request iOS permissions
- Create notification channels

**In `app.dart`:**
- Handle `FirebaseMessaging.instance.getInitialMessage()`
- Listen to `FirebaseMessaging.onMessage`
- Listen to `FirebaseMessaging.onMessageOpenedApp`
- Implement notification tap navigation logic
- Refresh user data after notifications
- Display foreground notifications manually

**Poor Permission UX:**
- `AuthServiceImpl.initFCM()` automatically calls `requestPermission()` on sign-in
- iOS permission prompt appears immediately after authentication
- No control over when/where to ask for permissions
- Can't provide context or rationale before prompting
- Hurts App Store review outcomes and user trust

### What Apps Actually Need

```dart
// In main.dart - ONE LINE
await NotificationService().initialize(
  onNotificationTapped: (route, data) => appRouter.navigateNamed(route),
);

// When you want to ask for permissions - ONE LINE with automatic recovery
await NotificationService().requestPermissionWithAutoRecovery(
  context: context,
  customMessage: "Get notified about important updates",
);

// Periodic reminder (e.g., once a month) - ONE LINE
// Shows dialog only if denied AND 30+ days since last ask
await NotificationService().showPermissionDialogIfNeeded(
  context: context,
);
```

All the boilerplate should be hidden in Dreamic's `NotificationService`.

## What Changes

- **NEW**: `NotificationService` class in `lib/app/helpers/` for centralized notification management
- **NEW**: Notification permission handling UI components in `lib/presentation/elements/`
- **NEW**: Notification action routing system with deep link support
- **NEW**: Badge management utilities for iOS, Android, and web platforms
- **NEW**: Rich notification support (images, attachments, action buttons)
- **NEW**: Notification data models in `lib/data/models/`
- **NEW**: Documentation guide in `docs/NOTIFICATION_GUIDE.md`
- **MODIFIED**: `AuthServiceImpl.initFCM()` to integrate with new `NotificationService`
- **MODIFIED**: `AppCubit` to support notification-driven state updates
- **MODIFIED**: `pubspec.yaml` to add required notification dependencies

## Impact

### Affected Specs
- **notification-service** (NEW) - Core notification handling service
- **notification-ui** (NEW) - Permission request and notification UI components

### Affected Code
- `lib/app/helpers/auth_service_impl.dart` - Integrate with NotificationService
- `lib/app/app_cubit.dart` - Add notification routing and badge management
- `lib/app/app_cubit_state.dart` - Already has `unreadNotificationsCount`, extend for notifications
- `lib/presentation/elements/` - New notification UI components
- `pubspec.yaml` - Add `flutter_local_notifications`, `app_badge_plus`

### Dependencies Added
- `flutter_local_notifications: ^18.0.1` - Local notification support
- `app_badge_plus: ^1.1.5` - Badge management across platforms

### Breaking Changes
None. This is an additive feature that existing apps can opt into.

### Optional Feature Design
**Critical**: Notifications are completely optional. Apps that don't use notification features will:
- Have **zero** impact on required entitlements (the dependencies themselves don't require entitlements)
- Not require notification-related platform configurations in consuming app
- Not include notification dependencies in their build if tree-shaking is effective
- Not trigger any notification permission requests
- Not initialize any notification services automatically
- Not execute any notification-related code paths

**Key Facts about Dependencies**:
- `flutter_local_notifications` does NOT require entitlements to be added to iOS apps
- `flutter_local_notifications` does NOT modify Info.plist automatically
- Runtime permission requests only happen when explicitly called by app code
- All iOS setup (AppDelegate modifications) is in consuming app code, not this package
- Apps control when/if to initialize notification features

The feature is designed with lazy initialization - notification services only activate when explicitly called by consuming apps.

### Migration Path
Not applicable - new feature with no breaking changes.

## Capabilities

This change introduces two new capabilities:

1. **notification-service**: Core service handling FCM, local notifications, routing, and badge management
2. **notification-ui**: Reusable UI components for permission requests and notification settings
