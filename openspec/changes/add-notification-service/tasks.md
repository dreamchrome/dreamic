# Implementation Tasks

## 1. Dependencies and Configuration

- [x] Add `flutter_local_notifications: ^18.0.1` to `pubspec.yaml`
- [x] Add `app_badge_plus: ^1.1.5` to `pubspec.yaml`
- [x] Run `flutter pub get` to fetch new dependencies
- [ ] Create `docs/NOTIFICATION_SETUP.md` with platform configuration examples (NOT in package itself):
  - [ ] iOS: Document notification entitlements for `Info.plist` (apps add if needed)
  - [ ] Android: Document notification permissions for `AndroidManifest.xml` (apps add if needed)
  - [ ] Web: Document service worker setup (apps add if needed)
- [ ] Verify that no platform-specific configs are included in the package itself
- [ ] Verify that dependencies support tree-shaking (unused code removal)

## 2. Data Models

- [x] Create `lib/data/models/notification_payload.dart`
  - [x] Define `NotificationPayload` class with `title`, `body`, `imageUrl`, `route`, `data`, `actions`
  - [x] Implement `fromRemoteMessage(RemoteMessage)` factory
  - [x] Implement `fromJson(Map<String, dynamic>)` factory
  - [x] Implement `toJson()` method
  - [x] Add `json_serializable` annotations
  - [x] Run `build_runner` to generate serialization code
- [x] Create `lib/data/models/notification_action.dart`
  - [x] Define `NotificationAction` class with `id`, `label`, `icon`, `requiresAuth`
  - [x] Implement JSON serialization
- [x] Create `lib/data/models/notification_permission_status.dart`
  - [x] Define `NotificationPermissionStatus` enum (authorized, denied, notDetermined, provisional)
- [x] Add tests for `notification_payload.dart` serialization (see section 8)
- [x] Add tests for `notification_action.dart` serialization (see section 8)

## 3. Core Notification Service

- [x] Create `lib/app/helpers/notification_service.dart`
  - [x] Define `NotificationService` class with lazy singleton pattern (no automatic initialization)
  - [x] Add private constructor to prevent automatic instantiation
  - [x] Add `initialize()` method that handles ALL setup (replaces consuming app boilerplate):
    - [x] Initializes `FlutterLocalNotificationsPlugin`
    - [x] Creates default Android notification channel
    - [x] Registers background message handler automatically
    - [x] Sets up `FirebaseMessaging.onMessage` listener (foreground)
    - [x] Sets up `FirebaseMessaging.onMessageOpenedApp` listener
    - [x] Checks `FirebaseMessaging.instance.getInitialMessage()` for cold start
    - [x] Configures iOS foreground presentation options
    - [x] Takes callbacks as parameters: `onNotificationTapped`, `onNotificationAction`
    - [x] Takes optional `onError` callback for error reporting
    - [x] Takes optional `reminderIntervalDays` parameter (default 30) for periodic prompts
  - [x] Ensure constructor and factory have NO side effects
  - [x] Add `requestPermissions()` method
  - [x] Add `getPermissionStatus()` method
  - [x] Add `openSettings()` method
  - [x] Add `showNotificationsInForeground` flag
  - [ ] **Goal: Consuming app only calls `initialize()` with callbacks, no manual stream setup**
- [x] Implement local notification methods:
  - [x] `showNotification(NotificationPayload)` - Display local notification
  - [x] `cancelNotification(int id)` - Cancel single notification
  - [x] `cancelAllNotifications()` - Cancel all notifications
  - [x] `getActiveNotifications()` - Get list of active notifications
- [x] Implement badge management methods:
  - [x] `updateBadgeCount(int count)` - Set badge count
  - [x] `clearBadge()` - Clear badge
  - [x] `getBadgeCount()` - Get current badge count
- [x] Implement FCM message handling (token management stays in AuthServiceImpl):
  - [x] Register `onBackgroundMessage` handler for incoming FCM messages
  - [x] Handle foreground messages via `onMessage` stream
  - [x] Handle notification taps via `onMessageOpenedApp` stream  
  - [x] Handle notification taps when app is terminated via `getInitialMessage()`
  - [x] Parse `RemoteMessage` to `NotificationPayload`
  - [x] Note: Token registration/refresh remains in `AuthServiceImpl.initFCM()`
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

- [x] Create `lib/app/helpers/notification_channel_manager.dart`
  - [x] Define default notification channel constants
  - [x] Implement `createChannel(NotificationChannel)` method
  - [x] Implement `deleteChannel(String channelId)` method
  - [x] Implement `getChannels()` method
  - [x] Create default channels on initialization (high, default, low, silent)
  - [x] Integrate with NotificationService
  - [x] Export in main library
- [ ] Add tests for notification channel management

## 8. Unit Tests

- [x] Create `test/data/notification_payload_test.dart`
  - [x] Test JSON serialization/deserialization (round-trip)
  - [x] Test `fromRemoteMessage` factory with various Firebase message formats
  - [x] Test route extraction from multiple possible fields
  - [x] Test image URL extraction from platform-specific fields
  - [x] Test null handling and default values
  - [x] Test nested data structures (actions list)
  - [x] Test `copyWith` method
  - [x] Test equality operator
  - [x] Test `toString` method
- [x] Create `test/data/notification_action_test.dart`
  - [x] Test JSON serialization/deserialization
  - [x] Test constructor with all field combinations
  - [x] Test default values (requiresAuth, launchesApp)
  - [x] Test equality operator with various scenarios
  - [x] Test `toString` method
  - [x] Test edge cases (empty strings, null icon)
- [x] Fix JSON serialization issue with nested objects
  - [x] Add `explicitToJson: true` to `@JsonSerializable` annotation
  - [x] Regenerate code with build_runner
  - [x] Verify all 122 tests pass

## 7. Permission UI Components

- [x] Create `lib/presentation/elements/notification_permission_bottom_sheet.dart`
  - [x] Implement bottom sheet UI with title, description, buttons
  - [x] Add `show()` static method
  - [x] Add customization parameters (colors, text, icons)
  - [x] Handle "Allow Notifications" button tap → request permissions
  - [x] Handle "Not Now" button tap → dismiss
  - [x] Handle already-denied state → show settings prompt
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
- [x] Create `lib/presentation/elements/notification_permission_status_widget.dart`
  - [x] Display current permission status with icon and text
  - [x] Show "Enable" button for notDetermined state
  - [x] Show "Open Settings" button for denied state
  - [x] Auto-update when permission status changes
  - [ ] Add widget tests
- [ ] Create `lib/presentation/elements/notification_settings_page.dart`
  - [ ] Display permission status at top
  - [ ] Add toggles for notification preferences (sound, vibration, badge)
  - [ ] Save preferences to `SharedPreferences`
  - [ ] Add "Enable Notifications" button if can prompt
  - [ ] Add "Open Settings" button if denied
  - [ ] Show denial count and last request time
  - [ ] Add widget tests

## 9. Additional UI Components

- [x] Create `lib/presentation/elements/notification_permission_builder.dart`
  - [x] Implement headless builder pattern
  - [x] Provide permission status via callback
  - [x] Provide `requestPermissions()` method
  - [x] Rebuild on permission status changes
  - [ ] Add widget tests
- [ ] Create `lib/presentation/elements/notification_rationale_dialog.dart`
  - [ ] Implement dialog with custom explanation
  - [ ] Add benefit bullet points with icons
  - [ ] Add "Continue" and "Maybe Later" buttons
  - [ ] Add widget tests
- [x] Create `lib/presentation/elements/notification_badge_widget.dart`
  - [x] Display badge with count
  - [x] Support `hideWhenZero` parameter
  - [x] Handle count overflow (99+)
  - [x] Support custom colors and shapes
  - [ ] Add widget tests
- [ ] Create `lib/presentation/elements/notification_placeholder_widget.dart`
  - [ ] Empty state for no notifications
  - [ ] Disabled state for denied permissions
  - [ ] Add widget tests

## 10. Notification Permission Helper

- [x] Create `lib/app/helpers/notification_permission_helper.dart`
  - [x] Implement `isPermissionGranted()` - Returns bool
  - [x] Implement `isPermissionDenied()` - Returns bool
  - [x] Implement `isPermissionNotDetermined()` - Returns bool
  - [x] Implement `hasRequestedPermissionBefore()` - Returns bool
  - [x] Implement `shouldShowPermissionRationale()` - Returns bool
  - [x] Implement `canPromptForPermission()` - Platform-aware (false on iOS after denial)
  - [x] Implement `shouldShowSettingsPrompt()` - Returns true if denied and can't prompt
  - [x] Implement `getPermissionDenialCount()` - Returns int
  - [x] Implement `shouldShowPeriodicReminder(int intervalDays)` - Returns true if interval passed since last reminder
  - [x] Implement `shouldRequestPermissions()` - Check if should request based on state and history
  - [x] Implement `trackPermissionRequest()` - Track request attempts and denials
  - [x] Implement `updateLastReminderDate()` - Update timestamp when reminder shown
  - [x] Implement `getOptimalContext()` - Suggest optimal timing based on user patterns
  - [x] Store request history in `SharedPreferences` (count, denials, timestamp, lastReminderDate)
  - [ ] Cache permission state to avoid repeated checks
  - [ ] Add unit tests

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

## 11. Background Message Handler

- [x] Create `lib/app/helpers/notification_background_handler.dart`
  - [x] Define top-level function `dreamicFirebaseMessagingBackgroundHandler(RemoteMessage)`
  - [x] Mark with `@pragma('vm:entry-point')` for tree-shaking protection
  - [x] Initialize Firebase in background isolate
  - [x] Parse message and display local notification
  - [x] Ensure handler is isolate-safe (no UI dependencies)
  - [ ] Handle Remote Config initialization if needed
- [x] **Note: Consuming apps MUST register handler in main()** (Dart limitation):
  - [x] Document that `FirebaseMessaging.onBackgroundMessage(dreamicNotificationBackgroundHandler)` must be called in main()
  - [x] This is required before runApp() due to top-level function requirement
  - [x] Still massive simplification: 1 line vs ~100 lines of handler implementation
- [x] Provide documentation on background handler requirements (must be top-level)
- [ ] Test background message handling on physical devices

## 12. Background Message Handler

- [x] Create background message handler in `NotificationService`:
  - [x] Define top-level function `dreamicFirebaseMessagingBackgroundHandler(RemoteMessage)`
  - [x] Mark with `@pragma('vm:entry-point')` for tree-shaking protection
  - [x] Initialize Firebase in background isolate
  - [x] Parse message and display local notification
  - [x] Ensure handler is isolate-safe (no UI dependencies)
  - [ ] Handle Remote Config initialization if needed
- [x] **Note: Consuming apps MUST register handler in main()** (Dart limitation):
  - [x] Document that `FirebaseMessaging.onBackgroundMessage(dreamicNotificationBackgroundHandler)` must be called in main()
  - [x] This is required before runApp() due to top-level function requirement
  - [x] Still massive simplification: 1 line vs ~100 lines of handler implementation
- [x] Provide documentation on background handler requirements (must be top-level)
- [ ] Test background message handling on physical devices

## 13. Documentation

- [x] Create `docs/NOTIFICATION_GUIDE.md`
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
  - [ ]   - [ ] Document reminder interval configuration (default 30 days)
  - [ ] Add testing section:
    - [ ] How to use MockNotificationService
    - [ ] Example test cases
    - [ ] Test fixtures and helpers
  - [ ] Add troubleshooting section:
    - [ ] Common issues and solutions
    - [ ] Debugging notification delivery
    - [ ] Platform-specific gotchas

  - [ ] Advanced usage (rich notifications, action buttons, custom routing)
  - [ ] UI component examples
  - [ ] Badge management examples
  - [ ] Troubleshooting section (common issues, platform limitations)
  - [ ] Platform-specific notes (iOS, Android, web)
  - [ ] Migration guide from manual setup to NotificationService
- [ ] Add notification examples to main `README.md`
- [ ] Add inline documentation (dartdoc comments) to all public APIs
- [x] Update `CHANGELOG.md` with notification feature addition

## 14. Additional Testing

- [x] Unit tests for `NotificationPayload` serialization (see section 8)
- [ ] Unit tests for `NotificationService` methods
- [ ] Unit tests for `NotificationPermissionHelper`
- [ ] Widget tests for all UI components

- [ ] Integration tests for notification routing flow
- [ ] Integration tests for badge count synchronization
- [ ] Manual testing on physical iOS device
- [ ] Manual testing on physical Android device (API 33+ and <33)
- [ ] Manual testing on web browser
- [ ] Test background notification handling
- [ ] Test notification taps from various app states (foreground, background, terminated)

## 15. Testing Utilities and Mocking Support

- [ ] Create `lib/test_utils/mock_notification_service.dart`
  - [ ] Implement `MockNotificationService` extending `NotificationService`
  - [ ] Mock all public methods with trackable calls
  - [ ] Provide test helpers:
    - [ ] `simulateNotificationReceived(NotificationPayload)` - Simulate incoming notification
    - [ ] `simulateNotificationTap(String route, Map data)` - Simulate user tap
    - [ ] `simulatePermissionChange(NotificationPermissionStatus)` - Change permission state
    - [ ] `getRequestedPermissionCount()` - Track how many times requested
    - [ ] `getDisplayedNotifications()` - Get list of shown notifications
    - [ ] `clearHistory()` - Reset mock state
  - [ ] Support callback verification
  - [ ] Add documentation on how to use in tests
- [ ] Create test fixtures:
  - [ ] Sample `NotificationPayload` objects for different scenarios
  - [ ] Sample FCM `RemoteMessage` objects
  - [ ] Sample permission states and transitions
- [ ] Add example tests showing usage

## 16. Example Implementation

- [ ] Create example implementation in scaffolding or docs:
  - [ ] Show notification service initialization
  - [ ] Show permission request flow
  - [ ] Show notification display
  - [ ] Show action button handling
  - [ ] Show routing configuration
  - [ ] Show badge management
- [ ] Create example screenshots for documentation

## 17. Migration Guide
  - [ ] How to test notification routing in app
  - [ ] How to test permission request flows
  - [ ] How to verify badge count updates
  - [ ] How to test background handler
- [ ] Create `MockFlutterLocalNotificationsPlugin` for isolating platform dependencies
- [ ] Create `MockFirebaseMessaging` for testing FCM interactions
- [ ] Document testing best practices in `docs/NOTIFICATION_GUIDE.md`

- [ ] Create `docs/NOTIFICATION_MIGRATION_GUIDE.md`
  - [ ] **Section: Apps Already Using Dreamic with Custom Notifications**
    - [ ] Step 1: Inventory existing notification code
      - [ ] List all files with notification setup (main.dart, app.dart, helpers)
      - [ ] Identify custom notification logic to preserve
      - [ ] Note any custom notification channels or categories
    - [ ] Step 2: Add NotificationService dependencies
      - [ ] Update pubspec.yaml with new dependencies
      - [ ] Run `flutter pub get`
    - [ ] Step 3: Replace background handler
      - [ ] Remove custom `@pragma('vm:entry-point')` handler
      - [ ] Import `dreamicNotificationBackgroundHandler` from Dreamic
      - [ ] Update main() to register Dreamic's handler
      - [ ] Show before/after code comparison
    - [ ] Step 4: Remove manual setup code
      - [ ] Delete `setupFlutterNotifications()` function
      - [ ] Remove manual `FlutterLocalNotificationsPlugin` initialization
      - [ ] Remove manual channel creation
      - [ ] Remove FCM stream listeners from StatefulWidget
      - [ ] Show line-by-line removal guide
    - [ ] Step 5: Initialize NotificationService
      - [ ] Add `NotificationService().initialize()` call
      - [ ] Map existing notification tap logic to `onNotificationTapped` callback
      - [ ] Map existing action logic to `onNotificationAction` callback
    - [ ] Step 6: Migrate permission handling
      - [ ] Remove direct `requestPermission()` calls to FCM
      - [ ] Use `NotificationService.requestPermissionWithAutoRecovery()`
      - [ ] Add permission UI components if desired
    - [ ] Step 7: Test thoroughly
      - [ ] Test all notification flows (foreground, background, terminated)
      - [ ] Test permission flows
      - [ ] Test notification taps and routing
      - [ ] Verify badge counts
  - [ ] **Section: Apps Using Dreamic Without Notifications**
    - [ ] Verify no breaking changes
    - [ ] Confirm FCM token registration still works (if using)
    - [ ] No action needed if notifications not desired
  - [ ] **Section: Common Migration Issues**
    - [ ] Issue: "Background handler not firing"
      - [ ] Solution: Ensure handler registered before runApp()
    - [ ] Issue: "Notifications not showing in foreground"
      - [ ] Solution: Check `showNotificationsInForeground` flag
    - [ ] Issue: "Routing not working"
      - [ ] Solution: Verify notification data includes `route` field
    - [ ] Issue: "Permission prompt showing immediately"
      - [ ] Solution: Don't call `requestPermission()` in initState
  - [ ] **Section: Before/After Code Examples**
    - [ ] Show full main.dart before migration (~150 lines)
    - [ ] Show full main.dart after migration (~20 lines)
    - [ ] Show app.dart before migration (~100 lines)
    - [ ] Show app.dart after migration (no notification code)
    - [ ] Highlight the ~300 line reduction
  - [ ] **Section: Breaking Changes (None)**
    - [ ] Confirm this is non-breaking
    - [ ] Explain opt-in nature
  - [ ] **Section: Rollback Plan**
    - [ ] How to revert if issues occur
    - [ ] Keep old code in comments during transition
    - [ ] Test in staging before production

## 18. Validation and Testing

- [ ] Test on physical devices:
  - [ ] iOS device with various iOS versions (16+, 17+, 18+)
  - [ ] Android device with API 33+ (runtime permissions)
  - [ ] Android device with API 32- (no runtime permissions)
  - [ ] Test on web browser (Chrome, Safari, Firefox)
- [ ] Test notification flows:
  - [ ] App in foreground
  - [ ] App in background
  - [ ] App terminated
  - [ ] Cold start from notification
  - [ ] Notification tap navigation
- [ ] Test permission flows:
  - [ ] First request (not determined)
  - [ ] Denied state
  - [ ] Granted state
  - [ ] Settings navigation
  - [ ] Periodic reminders (30+ days)
  - [ ] Auto-recovery dialogs
- [ ] Test badge management across platforms
- [ ] Test rich notifications (images, actions)
- [ ] Test notification channels (Android)
- [ ] Test error handling:
  - [ ] Image download failures
  - [ ] Invalid notification data
  - [ ] Platform API errors
- [ ] Test mock utilities:
  - [ ] Run example tests with MockNotificationService
  - [ ] Verify all mock methods work correctly
- [ ] Test migration:
  - [ ] Follow migration guide with real app
  - [ ] Verify all features work after migration
  - [ ] Confirm line count reduction
- [ ] Verify tree-shaking: Build app without NotificationService import, verify no notification code in bundle
- [ ] Run all unit and widget tests
- [ ] Update CHANGELOG.md with new features

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
