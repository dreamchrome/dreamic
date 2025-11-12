# Implementation Tasks

## 1. Dependencies and Configuration

- [ ] Add `flutter_local_notifications: ^18.0.1` to `pubspec.yaml`
- [ ] Add `app_badge_plus: ^1.1.5` to `pubspec.yaml`
- [ ] Run `flutter pub get` to fetch new dependencies
- [ ] Create `docs/NOTIFICATION_SETUP.md` with platform configuration examples (NOT in package itself):
  - [ ] iOS: Document notification entitlements for `Info.plist` (apps add if needed)
  - [ ] Android: Document notification permissions for `AndroidManifest.xml` (apps add if needed)
  - [ ] Web: Document service worker setup (apps add if needed)
- [ ] Verify that no platform-specific configs are included in the package itself
- [ ] Verify that dependencies support tree-shaking (unused code removal)

## 2. Data Models

- [ ] Create `lib/data/models/notification_payload.dart`
  - [ ] Define `NotificationPayload` class with `title`, `body`, `imageUrl`, `route`, `data`, `actions`
  - [ ] Implement `fromRemoteMessage(RemoteMessage)` factory
  - [ ] Implement `fromJson(Map<String, dynamic>)` factory
  - [ ] Implement `toJson()` method
  - [ ] Add `json_serializable` annotations
  - [ ] Run `build_runner` to generate serialization code
- [ ] Create `lib/data/models/notification_action.dart`
  - [ ] Define `NotificationAction` class with `id`, `label`, `icon`, `requiresAuth`
  - [ ] Implement JSON serialization
- [ ] Create `lib/data/models/notification_permission_status.dart`
  - [ ] Define `NotificationPermissionStatus` enum (authorized, denied, notDetermined, provisional)
- [ ] Add tests for `notification_payload.dart` serialization
- [ ] Add tests for `notification_action.dart` serialization

## 3. Core Notification Service

- [ ] Create `lib/app/helpers/notification_service.dart`
  - [ ] Define `NotificationService` class with lazy singleton pattern (no automatic initialization)
  - [ ] Add private constructor to prevent automatic instantiation
  - [ ] Add `initialize()` method that handles ALL setup (replaces consuming app boilerplate):
    - [ ] Initializes `FlutterLocalNotificationsPlugin`
    - [ ] Creates default Android notification channel
    - [ ] Registers background message handler automatically
    - [ ] Sets up `FirebaseMessaging.onMessage` listener (foreground)
    - [ ] Sets up `FirebaseMessaging.onMessageOpenedApp` listener
    - [ ] Checks `FirebaseMessaging.instance.getInitialMessage()` for cold start
    - [ ] Configures iOS foreground presentation options
    - [ ] Takes callbacks as parameters: `onNotificationTapped`, `onNotificationAction`
    - [ ] Takes optional `reminderIntervalDays` parameter (default 30) for periodic prompts
  - [ ] Ensure constructor and factory have NO side effects
  - [ ] Add `requestPermissions()` method
  - [ ] Add `getPermissionStatus()` method
  - [ ] Add `openSettings()` method
  - [ ] Add `showNotificationsInForeground` flag
  - [ ] **Goal: Consuming app only calls `initialize()` with callbacks, no manual stream setup**
- [ ] Implement local notification methods:
  - [ ] `showNotification(NotificationPayload)` - Display local notification
  - [ ] `cancelNotification(int id)` - Cancel single notification
  - [ ] `cancelAllNotifications()` - Cancel all notifications
  - [ ] `getActiveNotifications()` - Get list of active notifications
- [ ] Implement badge management methods:
  - [ ] `updateBadgeCount(int count)` - Set badge count
  - [ ] `clearBadge()` - Clear badge
  - [ ] `getBadgeCount()` - Get current badge count
- [ ] Implement FCM message handling (token management stays in AuthServiceImpl):
  - [ ] Register `onBackgroundMessage` handler for incoming FCM messages
  - [ ] Handle foreground messages via `onMessage` stream
  - [ ] Handle notification taps via `onMessageOpenedApp` stream  
  - [ ] Handle notification taps when app is terminated via `getInitialMessage()`
  - [ ] Parse `RemoteMessage` to `NotificationPayload`
  - [ ] Note: Token registration/refresh remains in `AuthServiceImpl.initFCM()`
- [ ] Add unit tests for `NotificationService` core logic

## 4. Platform-Specific Implementations

- [ ] Create `lib/app/helpers/notification_service_platform.dart` (platform interface)
- [ ] Create `lib/app/helpers/notification_service_ios.dart`
  - [ ] Implement iOS-specific notification display
  - [ ] Implement iOS badge management via `app_badge_plus`
  - [ ] Handle iOS notification categories and actions
  - [ ] Handle critical alerts (if enabled)
- [ ] Create `lib/app/helpers/notification_service_android.dart`
  - [ ] Implement Android notification channels
  - [ ] Create default notification channel
  - [ ] Handle notification importance levels
  - [ ] Implement Android badge management
- [ ] Create `lib/app/helpers/notification_service_web.dart`
  - [ ] Implement browser notification API integration
  - [ ] Handle web permission prompts
  - [ ] Implement fallback for unsupported features (e.g., no badges)
- [ ] Test platform-specific implementations on physical devices

## 5. Rich Notification Support

- [ ] Implement image download for rich notifications:
  - [ ] Create `lib/app/helpers/notification_image_loader.dart`
  - [ ] Add async image download with timeout
  - [ ] Add image caching with `path_provider`
  - [ ] Handle download failures gracefully
- [ ] Implement action button support:
  - [ ] Register notification actions with platform
  - [ ] Handle action button taps
  - [ ] Pass action ID to `onNotificationAction` callback
- [ ] Add support for notification attachments (audio, video)
- [ ] Add tests for image loading and error handling

## 6. Notification Channels (Android)

- [ ] Create `lib/app/helpers/notification_channel_manager.dart`
  - [ ] Define default notification channel constants
  - [ ] Implement `createChannel(NotificationChannel)` method
  - [ ] Implement `deleteChannel(String channelId)` method
  - [ ] Implement `getChannels()` method
  - [ ] Create default channels on initialization (high, medium, low importance)
- [ ] Add tests for notification channel management

## 7. Permission UI Components

- [ ] Create `lib/presentation/elements/notification_permission_bottom_sheet.dart`
  - [ ] Implement bottom sheet UI with title, description, buttons
  - [ ] Add `show()` static method
  - [ ] Add customization parameters (colors, text, icons)
  - [ ] Handle "Allow Notifications" button tap → request permissions
  - [ ] Handle "Not Now" button tap → dismiss
  - [ ] Handle already-denied state → show settings prompt
  - [ ] Add widget tests
- [ ] Create `lib/presentation/elements/notification_permission_denied_dialog.dart`
  - [ ] Show after user denies permissions
  - [ ] Platform-aware messaging (iOS: "must use settings", Android: "try again or settings")
  - [ ] Primary button: "Open Settings" → calls `openSystemSettings()`
  - [ ] Secondary button: "Maybe Later" → dismisses
  - [ ] Android only: "Try Again" button if `canRequestPermission()` returns true
  - [ ] Customizable title, message, icon, button text
  - [ ] Stronger rationale explaining consequences of denial
  - [ ] Track denial count and escalate messaging for repeated denials
  - [ ] Add widget tests
- [ ] Create `lib/presentation/elements/notification_permission_status_widget.dart`
  - [ ] Display current permission status with icon and text
  - [ ] Show "Enable" button for notDetermined state
  - [ ] Show "Open Settings" button for denied state
  - [ ] Auto-update when permission status changes
  - [ ] Add widget tests
- [ ] Create `lib/presentation/elements/notification_settings_page.dart`
  - [ ] Display permission status at top
  - [ ] Add toggles for notification preferences (sound, vibration, badge)
  - [ ] Save preferences to `SharedPreferences`
  - [ ] Add "Enable Notifications" button if can prompt
  - [ ] Add "Open Settings" button if denied
  - [ ] Show denial count and last request time
  - [ ] Add widget tests

## 8. Additional UI Components

- [ ] Create `lib/presentation/elements/notification_permission_builder.dart`
  - [ ] Implement headless builder pattern
  - [ ] Provide permission status via callback
  - [ ] Provide `requestPermissions()` method
  - [ ] Rebuild on permission status changes
  - [ ] Add widget tests
- [ ] Create `lib/presentation/elements/notification_rationale_dialog.dart`
  - [ ] Implement dialog with custom explanation
  - [ ] Add benefit bullet points with icons
  - [ ] Add "Continue" and "Maybe Later" buttons
  - [ ] Add widget tests
- [ ] Create `lib/presentation/elements/badge_count_widget.dart`
  - [ ] Display badge with count
  - [ ] Support `hideWhenZero` parameter
  - [ ] Handle count overflow (99+)
  - [ ] Support custom colors and shapes
  - [ ] Add widget tests
- [ ] Create `lib/presentation/elements/notification_placeholder_widget.dart`
  - [ ] Empty state for no notifications
  - [ ] Disabled state for denied permissions
  - [ ] Add widget tests

## 9. Notification Permission Helper

- [ ] Create `lib/app/helpers/notification_permission_helper.dart`
  - [ ] Implement `isPermissionGranted()` - Returns bool
  - [ ] Implement `isPermissionDenied()` - Returns bool
  - [ ] Implement `isPermissionNotDetermined()` - Returns bool
  - [ ] Implement `hasRequestedPermissionBefore()` - Returns bool
  - [ ] Implement `shouldShowPermissionRationale()` - Returns bool
  - [ ] Implement `canPromptForPermission()` - Platform-aware (false on iOS after denial)
  - [ ] Implement `shouldShowSettingsPrompt()` - Returns true if denied and can't prompt
  - [ ] Implement `getPermissionDenialCount()` - Returns int
  - [ ] Implement `shouldShowPeriodicReminder(int intervalDays)` - Returns true if interval passed since last reminder
  - [ ] Implement `shouldRequestPermissions()` - Check if should request based on state and history
  - [ ] Implement `trackPermissionRequest()` - Track request attempts and denials
  - [ ] Implement `updateLastReminderDate()` - Update timestamp when reminder shown
  - [ ] Implement `getOptimalContext()` - Suggest optimal timing based on user patterns
  - [ ] Store request history in `SharedPreferences` (count, denials, timestamp, lastReminderDate)
  - [ ] Cache permission state to avoid repeated checks
  - [ ] Add unit tests

## 10. AppCubit Integration

- [ ] Modify `lib/app/app_cubit.dart`:
  - [ ] Add `onNotificationTapped(String? route, Map<String, dynamic>? data)` method
  - [ ] Add `updateBadgeCount(int count)` method to sync with `NotificationService`
  - [ ] Add `setupNotificationCallbacks()` method that apps can optionally call
  - [ ] **DO NOT** automatically initialize NotificationService
  - [ ] **DO NOT** automatically register callbacks
  - [ ] Route notifications based on app navigation system
  - [ ] Add tests for notification routing
- [ ] Document that apps must call `appCubit.setupNotificationCallbacks()` if using notifications
- [ ] Test badge count synchronization with `AppCubitState.unreadNotificationsCount`

## 11. Integrate with AuthServiceImpl

- [ ] **Modify `AuthServiceImpl.initFCM()` for permission control**
  - [ ] Add permission status check at start of `initFCM()`
  - [ ] Use `FirebaseMessaging.instance.getNotificationSettings()` to check current status
  - [ ] Only proceed with token registration if `authorizationStatus == AuthorizationStatus.authorized`
  - [ ] If not authorized, log and return early (don't call `requestPermission()`)
  - [ ] Remove automatic `requestPermission()` call from `initFCM()`
  - [ ] Add public method `AuthServiceImpl.completeFCMRegistration()` for NotificationService to call after permissions granted
  - [ ] Preserve all existing token management logic (backend registration, refresh handling, storage)
- [ ] **Add callback from NotificationService to AuthServiceImpl**
  - [ ] After `NotificationService.requestPermission()` succeeds, call `AuthServiceImpl.completeFCMRegistration()`
  - [ ] Handle case where AuthServiceImpl not registered (notification-only mode)
  - [ ] Document the flow: NotificationService prompts → User grants → Triggers FCM registration
- [ ] **Add optional notification when FCM token updates**
  - [ ] Check if NotificationService is registered in GetIt
  - [ ] If registered, notify about token updates
  - [ ] Don't break if NotificationService not registered
- [ ] **Backward compatibility**
  - [ ] Apps not using NotificationService still work (FCM init happens if permissions already granted)
  - [ ] Apps can opt into controlled prompting by using NotificationService
- [ ] Document the relationship between AuthServiceImpl and NotificationService
  - [ ] AuthServiceImpl: Manages FCM token lifecycle (get, register with backend, refresh)
  - [ ] NotificationService: Manages notification display, permissions, routing, badges
  - [ ] Permission control: NotificationService owns prompting, triggers FCM registration after grant
  - [ ] Optional integration: NotificationService can listen to token updates

## 12. Background Message Handler

- [ ] Create `lib/app/helpers/notification_background_handler.dart`
  - [ ] Define top-level function `dreamicFirebaseMessagingBackgroundHandler(RemoteMessage)`
  - [ ] Mark with `@pragma('vm:entry-point')` for tree-shaking protection
  - [ ] Initialize Firebase in background isolate
  - [ ] Parse message and display local notification
  - [ ] Ensure handler is isolate-safe (no UI dependencies)
  - [ ] Handle Remote Config initialization if needed
- [ ] Auto-register handler in `NotificationService.initialize()`
  - [ ] Call `FirebaseMessaging.onBackgroundMessage(dreamicFirebaseMessagingBackgroundHandler)`
  - [ ] Consuming apps should NOT need to manually register this
- [ ] Provide documentation on background handler requirements (must be top-level)
- [ ] Test background message handling on physical devices

## 13. Documentation

- [ ] Create `docs/NOTIFICATION_GUIDE.md`
  - [ ] Getting Started section with **clear opt-in instructions**
  - [ ] Explicitly state: "This feature is completely optional. Your app will not require notification entitlements unless you follow these setup steps."
  - [ ] **Show before/after comparison**:
    - [ ] "Before: ~300 lines of boilerplate in main.dart and app.dart"
    - [ ] "After: One `initialize()` call with routing callback"
  - [ ] Setup instructions (dependencies, platform config) - mark as "Only needed if using notifications"
  - [ ] Minimal initialization example:
    ```dart
    await NotificationService().initialize(
      onNotificationTapped: (route, data) {
        if (route != null) appRouter.navigateNamed(route);
      },
    );
    ```
  - [ ] Explain what's automatically handled (channels, handlers, streams)
  - [ ] Document convenience methods:
    - [ ] `requestPermissionWithAutoRecovery()` - One-line request + automatic recovery dialog
    - [ ] `showPermissionDialogIfNeeded()` - Perfect for periodic "please enable" prompts
    - [ ] Show example: "Ask once a month" pattern
  - [ ] Document reminder interval configuration (default 30 days)
  - [ ] Advanced usage (rich notifications, action buttons, custom routing)
  - [ ] UI component examples
  - [ ] Badge management examples
  - [ ] Troubleshooting section (common issues, platform limitations)
  - [ ] Platform-specific notes (iOS, Android, web)
  - [ ] Migration guide from manual setup to NotificationService
- [ ] Add notification examples to main `README.md`
- [ ] Add inline documentation (dartdoc comments) to all public APIs
- [ ] Update `CHANGELOG.md` with notification feature addition

## 14. Testing

- [ ] Unit tests for `NotificationPayload` serialization
- [ ] Unit tests for `NotificationService` methods
- [ ] Unit tests for `NotificationPermissionHelper`
- [ ] Widget tests for all UI components
- [ ] Widget tests using `MockAppCubit` for context
- [ ] Integration tests for notification routing flow
- [ ] Integration tests for badge count synchronization
- [ ] Manual testing on physical iOS device
- [ ] Manual testing on physical Android device (API 33+ and <33)
- [ ] Manual testing on web browser
- [ ] Test background notification handling
- [ ] Test notification taps from various app states (foreground, background, terminated)

## 15. Example Implementation

- [ ] Create example implementation in scaffolding or docs:
  - [ ] Show notification service initialization
  - [ ] Show permission request flow
  - [ ] Show notification display
  - [ ] Show action button handling
  - [ ] Show routing configuration
  - [ ] Show badge management
- [ ] Create example screenshots for documentation

## 16. Final Validation

- [ ] Run `flutter analyze` and fix any issues
- [ ] Run all tests and ensure they pass
- [ ] Test on iOS simulator and physical device
- [ ] Test on Android emulator and physical device
- [ ] Test on web browser (Chrome, Safari, Firefox)
- [ ] Verify badge counts update correctly
- [ ] Verify notification routing works from all app states
- [ ] Verify rich notifications display correctly (images, actions)
- [ ] Verify permission UI adapts to platform
- [ ] Run `openspec validate add-notification-service --strict` and confirm no errors
- [ ] Update version number in `pubspec.yaml`
- [ ] Update `CHANGELOG.md` with release notes

## Dependencies Between Tasks

- Tasks 1 must complete before any other tasks
- Tasks 2-3 can be done in parallel
- Task 4 depends on Task 3
- Tasks 5-9 depend on Task 4
- Task 10 depends on Task 4
- Task 11 depends on Task 4
- Task 12 depends on Task 4
- Task 13 can be done in parallel with implementation
- Task 14 depends on completion of Tasks 2-12
- Task 15 depends on completion of Tasks 2-12
- Task 16 must be done last after all other tasks

## Verification Checklist

After implementation, verify:

### Optional Feature Verification
- [ ] Create test app WITHOUT notification imports - verify it builds and runs
- [ ] Verify no notification code in release build when not used (check binary size)
- [ ] Verify no notification permissions in `AndroidManifest.xml` or `Info.plist` in package
- [ ] Verify NotificationService constructor has zero side effects
- [ ] Verify NotificationService.initialize() is required before any functionality
- [ ] Create test app WITH notifications - verify explicit setup works
- [ ] Document clear "opt-in" steps in notification guide

### Code Quality
- [ ] All public APIs have dartdoc comments
- [ ] All components follow Dreamic code style conventions
- [ ] All components use `emitSafe()` for Cubit state changes
- [ ] Error handling uses `loge()` for error reporting
- [ ] Platform checks use `defaultTargetPlatform` or `kIsWeb`
- [ ] All async operations have timeouts
- [ ] All UI components support light and dark themes
- [ ] All tests pass (`flutter test`)
- [ ] No linter warnings (`flutter analyze`)
- [ ] Documentation is complete and accurate
