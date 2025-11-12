# Design: Notification Service Architecture

## Overview

The notification service provides a comprehensive, platform-aware notification system for Dreamic-based applications. It bridges Firebase Cloud Messaging (FCM) with local notifications, handles permissions gracefully, manages badges, and routes notification actions to appropriate app destinations.

## Architecture Decisions

### 0. Optional Feature - No Entitlement Impact

**Decision**: Notification features are completely optional with lazy initialization and zero impact on apps that don't use them.

**Rationale**:
- Apps using Dreamic may not need notifications at all
- Adding notification entitlements when not needed can:
  - Trigger unnecessary App Store review scrutiny
  - Violate privacy policies if not actually used
  - Complicate app submission process
- Tree-shaking should remove unused notification code from builds
- No initialization code should run unless explicitly invoked

**Implementation**:
```dart
class NotificationService {
  static NotificationService? _instance;
  
  // Only creates instance when explicitly requested
  factory NotificationService() {
    if (_instance == null) {
      _instance = NotificationService._internal();
    }
    return _instance!;
  }
  
  // Private constructor - no automatic initialization
  NotificationService._internal();
  
  // Must be explicitly called by consuming app
  Future<void> initialize() async {
    // Only at this point does anything notification-related happen
  }
}
```

**Consuming App Usage**:
- **Without notifications**: Don't import notification files, don't call NotificationService
- **With notifications**: Import and call `NotificationService().initialize()` in app startup

**Platform Configuration**:
- Platform-specific configs (entitlements, permissions) documented in setup guide
- Apps only add these if they use notifications
- No platform configs shipped with the package itself
- **iOS AppDelegate modifications are in consuming app, not this package**
- Package does not modify native platform files automatically

### 1. Service Separation

**Decision**: Create a dedicated `NotificationService` separate from `AuthServiceImpl`.

**Rationale**:
- `AuthServiceImpl` already handles FCM token registration (closely tied to user identity)
- Notification handling (display, routing, badges) is functionally distinct from authentication
- Separation of concerns: authentication vs notification presentation/routing
- Easier testing and maintenance

**Implementation**:
- `AuthServiceImpl.initFCM()` remains responsible for token lifecycle
- New `NotificationService` handles everything else (local notifications, routing, badges)
- Services communicate via callbacks and `GetIt` dependency injection

### 2. Notification Routing Strategy

**Decision**: Use a callback-based routing system with deep link support.

**Rationale**:
- Apps using Dreamic have different navigation systems (Navigator 1.0, 2.0, go_router, etc.)
- Callback pattern is framework-agnostic
- Allows apps to define their own routing logic
- Supports both foreground and background notification taps

**Implementation**:
```dart
typedef NotificationActionCallback = Future<void> Function(
  String? route,
  Map<String, dynamic>? data,
);

class NotificationService {
  NotificationActionCallback? onNotificationTapped;
  NotificationActionCallback? onNotificationAction;
}
```

### 3. Platform Abstraction

**Decision**: Create platform-specific implementations with a common interface.

**Rationale**:
- iOS, Android, and web have fundamentally different notification capabilities
- Badge management APIs differ across platforms
- Permission flows vary by platform
- Clear separation prevents platform-specific code leakage

**Implementation**:
- Core `NotificationService` uses conditional imports
- Platform-specific helpers: `_NotificationServiceIOS`, `_NotificationServiceAndroid`, `_NotificationServiceWeb`
- Common interface ensures consistent behavior where possible
- Graceful degradation on unsupported platforms

### 4. Permission Handling

**Decision**: Provide reusable UI components with customizable styling.

**Rationale**:
- Permission requests must be contextual and well-explained to users
- Different apps need different visual presentations
- Bottom sheets work well across mobile and web
- Allow apps to customize messaging and branding

**Implementation**:
- `NotificationPermissionBottomSheet` - Pre-built, customizable component
- `NotificationPermissionBuilder` - Headless component for custom UI
- Props for title, description, button text, colors
- Automatic platform detection (iOS critical alerts, Android post-13 runtime permissions)

### 5. Badge Management

**Decision**: Centralize badge management in `NotificationService` with AppCubit integration.

**Rationale**:
- Badge count often reflects app-wide state (unread messages, pending tasks)
- `AppCubit` already tracks `unreadNotificationsCount` in state
- Centralized management prevents badge drift
- Easy to update from anywhere in the app

**Implementation**:
- `NotificationService.updateBadgeCount(int count)` - Single source of truth
- Optional automatic sync with `AppCubit.state.unreadNotificationsCount`
- Platform-specific badge APIs abstracted away
- Web support via Page Title API fallback

### 6. Rich Notification Support

**Decision**: Support images, attachments, and action buttons via `flutter_local_notifications`.

**Rationale**:
- Modern apps expect rich notifications (images, progress bars, actions)
- FCM data messages alone are insufficient for local display
- `flutter_local_notifications` provides comprehensive platform support
- Enables notification customization per app

**Implementation**:
- `NotificationPayload` model with support for image URLs, attachments, actions
- Automatic image downloading for remote images
- Action button configuration with custom identifiers
- Notification channels for Android (importance levels, sounds, vibration)

### 7. Foreground vs Background Handling

**Decision**: Separate handlers for foreground and background notifications.

**Rationale**:
- Foreground notifications should optionally be silent or shown differently
- Background notifications always show system UI
- Apps may want to update UI directly when in foreground
- Different UX expectations based on app state

**Implementation**:
```dart
class NotificationService {
  // Called when app is in foreground
  Future<void> onForegroundMessage(RemoteMessage message);
  
  // Called when notification tapped (background or terminated)
  Future<void> onBackgroundMessageTapped(RemoteMessage message);
  
  // Flag to control foreground display
  bool showNotificationsInForeground = true;
}
```

### 8. Notification Data Model

**Decision**: Create a strongly-typed `NotificationPayload` model.

**Rationale**:
- Type safety for notification data
- Consistent serialization/deserialization
- Easy to extend with new fields
- Clear contract between server and client

**Implementation**:
```dart
class NotificationPayload {
  final String? title;
  final String? body;
  final String? imageUrl;
  final String? route;
  final Map<String, dynamic>? data;
  final List<NotificationAction>? actions;
  
  // fromRemoteMessage, fromJson, toJson
}
```

## Integration Points

### With Firebase Cloud Messaging
- FCM token registration remains in `AuthServiceImpl.initFCM()`
- Token updates trigger `NotificationService.updateFCMToken()`
- Background message handler registered at app initialization
- FCM data payload converted to `NotificationPayload`

### With AppCubit
- `AppCubit.onNotificationTapped()` - Routing callback
- `AppCubit.updateBadgeCount()` - Badge synchronization
- State updates trigger badge refresh
- Network-aware notification handling

### With Get-It
- `NotificationService` registered as singleton
- Lazy initialization on first access
- Injected into cubits and widgets as needed

## Error Handling

### Permission Denied
- Gracefully handle denied permissions
- Show settings deep link on repeated denial
- Log permission state changes
- Don't crash or block app functionality

### Network Failures
- Queue badge updates for retry
- Cache last known badge count
- Offline-first notification display
- Show local notifications even without FCM

### Platform Limitations
- Detect web notification support
- Fallback to basic notifications on unsupported platforms
- Log unsupported feature usage
- Graceful degradation (e.g., no badges on web)

### No Automatic Initialization
- NotificationService MUST NOT initialize automatically
- NotificationService MUST NOT be registered in GetIt by default
- AppCubit MUST NOT create NotificationService instances
- Apps must explicitly opt-in by calling `NotificationService().initialize()`
- Documentation must clearly show setup is optional
- No platform configurations (entitlements, permissions) in package itself

## Testing Strategy

### Unit Tests
- `NotificationPayload` serialization/deserialization
- Badge count calculations
- Permission state tracking
- Route parsing from notification data

### Widget Tests
- Permission UI components render correctly
- Button callbacks fire appropriately
- Styling props applied correctly
- Platform-specific UI variations

### Integration Tests
- Mock `flutter_local_notifications` plugin
- Test notification display flow
- Test action button handling
- Test badge updates

## Security Considerations

### Data Validation
- Sanitize notification data from FCM
- Validate deep link routes before navigation
- Prevent malicious image URLs
- Limit notification payload size

### Permission Requests
- Request permissions only when needed (contextual)
- Explain why permissions are needed
- Don't repeatedly prompt if denied
- Respect user preferences

## Performance Considerations

### Image Loading
- Asynchronous image download for rich notifications
- Image size limits (resize if too large)
- Cache downloaded images
- Timeout for slow downloads

### Badge Updates
- Debounce rapid badge count changes
- Batch updates when possible
- Minimize platform API calls
- Use local cache for count

### Initialization
- Lazy initialization of NotificationService
- Defer heavy setup until first notification
- Async initialization to not block app startup

## Platform-Specific Notes

### iOS
- Critical alerts require special entitlement
- Notification categories must be registered at startup
- Badge managed via `UNUserNotificationCenter`
- Background fetch for silent notifications

### Android
- Notification channels required (API 26+)
- Runtime permissions required (API 33+)
- Badge support via adaptive icons
- Foreground service notifications for long-running tasks

### Web
- Service worker required for background notifications
- Browser notification permissions
- No native badge support (use page title/favicon)
- Limited rich notification support

## Future Enhancements

- Notification grouping/stacking
- Scheduled local notifications
- Notification sound customization
- Interactive notifications (reply inline)
- Notification history/inbox
- Push notification analytics
