# Notification Service Specification

## ADDED Requirements

### Requirement: Abstract Notification Setup Boilerplate

The system SHALL handle all notification setup complexity internally, requiring minimal code from consuming apps.

#### Scenario: Simple initialization from consuming app
- **GIVEN** a consuming app wants to enable notifications
- **WHEN** the app calls `NotificationService().initialize()` with routing callbacks
- **THEN** the service SHALL automatically:
  - Initialize `FlutterLocalNotificationsPlugin`
  - Create default notification channels (Android)
  - Register background message handler
  - Set up foreground message listener
  - Set up notification tap listener (`onMessageOpenedApp`)
  - Handle app launch from notification (`getInitialMessage`)
  - Configure iOS foreground presentation options
- **AND** the app SHALL NOT need to manually set up any FCM streams or handlers
- **AND** the app SHALL only provide routing/navigation callbacks

#### Scenario: Background handler registration
- **GIVEN** NotificationService provides a top-level background handler function
- **WHEN** consuming app calls `FirebaseMessaging.onBackgroundMessage(dreamicNotificationBackgroundHandler)` in main()
- **THEN** the Dreamic-provided handler SHALL be registered with FCM
- **AND** SHALL ensure the handler is isolate-safe
- **AND** SHALL handle Firebase initialization in background isolate
- **AND** the consuming app SHALL NOT implement its own handler logic (uses Dreamic's)

#### Scenario: Automatic channel creation (Android)
- **GIVEN** the app is running on Android
- **WHEN** NotificationService initializes
- **THEN** the service SHALL create a default high-importance notification channel
- **AND** SHALL configure the channel with appropriate sound, vibration, lights
- **AND** SHALL register the channel with the system
- **AND** the app SHALL NOT manually create `AndroidNotificationChannel` instances

#### Scenario: Foreground notification display
- **GIVEN** the app is in foreground and receives an FCM message
- **WHEN** the message arrives
- **THEN** the service SHALL automatically display a local notification
- **AND** SHALL parse the message into a NotificationPayload
- **AND** SHALL respect the `showNotificationsInForeground` flag
- **AND** the app SHALL NOT manually listen to `FirebaseMessaging.onMessage`

#### Scenario: Notification tap handling
- **GIVEN** a notification is tapped (from any app state)
- **WHEN** the user taps the notification
- **THEN** the service SHALL extract route and data from the notification
- **AND** SHALL call the app's `onNotificationTapped` callback
- **AND** the app SHALL NOT manually handle `onMessageOpenedApp` or `getInitialMessage`

### Requirement: Optional Feature with No Side Effects

The system SHALL ensure notification features are completely optional and have zero impact on apps that don't use them.

#### Scenario: App does not use notifications
- **GIVEN** a consuming app does not import or use NotificationService
- **WHEN** the app is built and run
- **THEN** no notification code SHALL be included in the final bundle (tree-shaking)
- **AND** no notification permissions SHALL be requested
- **AND** no notification-related entitlements SHALL be required
- **AND** the app SHALL function normally without any notification code

#### Scenario: NotificationService exists but is not initialized
- **GIVEN** NotificationService is imported but `initialize()` is not called
- **WHEN** the app runs
- **THEN** no notification permissions SHALL be requested
- **AND** no notification handlers SHALL be registered
- **AND** no FCM token SHALL be requested
- **AND** the service SHALL remain dormant with no side effects

#### Scenario: Lazy initialization on first use
- **GIVEN** NotificationService has never been initialized
- **WHEN** `NotificationService().initialize()` is called for the first time
- **THEN** the service SHALL set up notification handlers
- **AND** SHALL only at this point interact with platform notification APIs
- **AND** SHALL not have had any initialization side effects prior to this call

#### Scenario: Platform configuration not present
- **GIVEN** an app does not include notification entitlements or permissions in platform configs
- **WHEN** NotificationService is imported but not used
- **THEN** the app SHALL build successfully
- **AND** the app SHALL pass App Store review
- **AND** SHALL not trigger any "unused entitlement" warnings

### Requirement: Error Handling

The system SHALL handle errors gracefully and report them to consuming apps.

#### Scenario: Notification image download fails
- **GIVEN** a notification includes an image URL
- **WHEN** the image download fails or times out
- **THEN** the service SHALL display the notification without the image
- **AND** SHALL log the error
- **AND** SHALL optionally call error callback if provided
- **AND** SHALL not delay notification display

#### Scenario: Platform API error
- **GIVEN** a platform notification API throws an error
- **WHEN** trying to display a notification
- **THEN** the service SHALL catch the error
- **AND** SHALL log detailed error information
- **AND** SHALL call optional `onError` callback
- **AND** SHALL not crash the app

#### Scenario: Invalid notification data
- **GIVEN** a notification has malformed or missing required data
- **WHEN** processing the notification
- **THEN** the service SHALL use sensible defaults
- **AND** SHALL log a warning
- **AND** SHALL still attempt to display the notification
- **AND** SHALL not crash the app

#### Scenario: Handle permission denial
- **GIVEN** notification permissions are requested
- **WHEN** the user denies permissions
- **THEN** the service SHALL return a denied status
- **AND** SHALL log the denial for diagnostics
- **AND** SHALL not crash or throw exceptions
- **AND** SHALL allow the app to continue functioning

### Requirement: Notification ID Management

The system SHALL manage notification IDs to prevent conflicts and allow targeted operations.

#### Scenario: Auto-generate notification ID
- **GIVEN** a notification is being displayed without explicit ID
- **WHEN** `showNotification()` is called
- **THEN** the service SHALL generate a unique notification ID
- **AND** SHALL use timestamp + hash for uniqueness
- **AND** SHALL return the generated ID

#### Scenario: Use custom notification ID
- **GIVEN** app wants to update or replace a specific notification
- **WHEN** `showNotification(id: 123)` is called
- **THEN** the service SHALL use the provided ID
- **AND** SHALL replace any existing notification with that ID

#### Scenario: Clear specific notification
- **GIVEN** a notification is displayed with known ID
- **WHEN** `clearNotification(id)` is called
- **THEN** the service SHALL remove only that notification
- **AND** SHALL not affect other notifications

### Requirement: Testing and Mocking Support

The system SHALL provide test utilities and mocks for consuming apps to test notification functionality.

#### Scenario: Mock notification service in tests
- **GIVEN** an app wants to test notification handling
- **WHEN** using `MockNotificationService` in tests
- **THEN** the mock SHALL provide all public methods
- **AND** SHALL track method calls for verification
- **AND** SHALL allow simulating notification events

#### Scenario: Simulate notification received
- **GIVEN** a test needs to simulate a notification
- **WHEN** `mockService.simulateNotificationReceived(payload)` is called
- **THEN** the mock SHALL trigger the `onNotificationTapped` callback
- **AND** SHALL allow verification of app's response

#### Scenario: Verify permission requests
- **GIVEN** a test checks if permissions were requested
- **WHEN** `mockService.getRequestedPermissionCount()` is called
- **THEN** the mock SHALL return accurate count
- **AND** SHALL include details of each request

#### Scenario: Test with mock Firebase Messaging
- **GIVEN** tests need to isolate from FCM
- **WHEN** using provided `MockFirebaseMessaging`
- **THEN** tests SHALL not require Firebase setup
- **AND** SHALL allow full offline testing

### Requirement: Migration Support

The system SHALL provide clear migration path for apps with existing notification code.

#### Scenario: Migrate from custom notification setup
- **GIVEN** an app has ~300 lines of custom notification code
- **WHEN** following the migration guide
- **THEN** the guide SHALL provide step-by-step instructions
- **AND** SHALL include before/after code examples
- **AND** SHALL identify code to remove
- **AND** SHALL show how to map existing logic to NotificationService

#### Scenario: Identify breaking changes
- **GIVEN** an app is considering migration
- **WHEN** reviewing migration guide
- **THEN** the guide SHALL clearly state no breaking changes
- **AND** SHALL explain opt-in nature
- **AND** SHALL provide rollback plan

#### Scenario: Handle migration issues
- **GIVEN** migration encounters problems
- **WHEN** consulting troubleshooting section
- **THEN** the guide SHALL list common issues
- **AND** SHALL provide solutions for each
- **AND** SHALL include debugging steps

### Requirement: Deep Link and Route Parsing

The system SHALL parse notification data into routing information following documented conventions.

#### Scenario: Parse route from notification data
- **GIVEN** a notification with data `{"route": "/profile/123", "userId": "123"}`
- **WHEN** the notification is tapped
- **THEN** the service SHALL extract `route` field as primary route
- **AND** SHALL pass all data to `onNotificationTapped` callback
- **AND** SHALL allow app to handle custom routing logic

#### Scenario: Handle missing route data
- **GIVEN** a notification without a `route` field
- **WHEN** the notification is tapped
- **THEN** the service SHALL call `onNotificationTapped` with null route
- **AND** SHALL still pass all available data
- **AND** SHALL allow app to determine default behavior

#### Scenario: Support multiple route formats
- **GIVEN** notifications may come from different sources
- **WHEN** processing notification data
- **THEN** the service SHALL check multiple route fields: `route`, `screen`, `deepLink`, `url`
- **AND** SHALL use first available route field
- **AND** SHALL document field priority order

### Requirement: Core Notification Service

The system SHALL provide a `NotificationService` class that manages local and remote notifications across platforms.

#### Scenario: Initialize notification service
- **GIVEN** the app is starting up
- **WHEN** `NotificationService.initialize()` is called
- **THEN** the service SHALL register notification handlers
- **AND** SHALL initialize local notification channels (Android)
- **AND** SHALL register notification categories (iOS)
- **AND** SHALL NOT automatically request permissions (must be explicit via requestPermission())

#### Scenario: Handle remote notification in foreground
- **GIVEN** the app is in the foreground
- **WHEN** a remote notification is received via FCM
- **THEN** the service SHALL parse the notification payload
- **AND** SHALL display a local notification if `showNotificationsInForeground` is true
- **AND** SHALL call the `onForegroundMessage` callback with the payload

#### Scenario: Handle notification tap from background
- **GIVEN** the app is in the background or terminated
- **WHEN** the user taps a notification
- **THEN** the service SHALL extract the route and data from the notification
- **AND** SHALL call the `onNotificationTapped` callback with the route and data
- **AND** SHALL allow the app to navigate to the appropriate destination

#### Scenario: Handle notification tap from foreground
- **GIVEN** the app is in the foreground with a notification displayed
- **WHEN** the user taps the notification
- **THEN** the service SHALL call the `onNotificationTapped` callback
- **AND** SHALL dismiss the notification from the notification center

### 2.2 Permissions Management

**MUST** provide methods to:
- Check current notification permission status without prompting
- Request notification permissions with platform-appropriate dialogs
- Return permission status (authorized, denied, not determined, provisional)
- Trigger FCM token registration after permissions granted

**MUST** handle platform differences:
- iOS: Support provisional authorization
- Android: Handle runtime permissions correctly
- Web: Handle browser notification API

**MUST NOT** automatically request permissions without explicit app request.

**MUST** coordinate with AuthServiceImpl:
- Modify `AuthServiceImpl.initFCM()` to check permissions before requesting
- Only register FCM token if permissions already granted
- When `NotificationService.requestPermission()` succeeds, notify AuthServiceImpl to complete FCM registration
- Preserve existing FCM token management in AuthServiceImpl (backend registration, refresh handling)

**Scenarios**:
1. User signs in, permissions not determined → No prompt shown, no FCM token registered
2. User signs in, permissions already granted → FCM token registered silently
3. App calls `requestPermission()` → Shows prompt, on grant triggers FCM registration
4. User denies permissions → FCM token not registered, returns denied status
5. App calls `requestPermission()` again after denial → On iOS returns denied (can't prompt again), on Android can prompt again
6. App calls `openSystemSettings()` → Opens system settings for app, user can enable permissions manually
7. User grants permissions in settings, app calls `checkPermissionStatus()` → Detects granted, triggers FCM registration
8. App using old flow (not calling NotificationService) → Existing behavior preserved (auto-prompt on sign-in if permissions not determined)
9. App calls `requestPermissionWithAutoRecovery()` → Shows prompt, user denies, automatically shows recovery dialog with settings button
10. App calls `showPermissionDialogIfNeeded()` first time → Permissions not determined, shows rationale and requests
11. App calls `showPermissionDialogIfNeeded()` after denial (day 1) → Too soon, does nothing
12. App calls `showPermissionDialogIfNeeded()` after denial (day 31) → Shows recovery dialog with settings button
13. App calls `showPermissionDialogIfNeeded()` when already granted → Does nothing, returns granted status

**MUST** provide permission recovery methods:
- `openSystemSettings()` - Opens app settings page (iOS Settings app, Android app info)
- `shouldShowRationale()` - Returns true if should explain why permissions needed (Android only)
- `canRequestPermission()` - Returns true if can show permission prompt (false after denial on iOS)
- `shouldShowPeriodicReminder()` - Returns true if enough time passed since last denial (default 30 days)
- `requestPermissionWithAutoRecovery({BuildContext, customMessage})` - All-in-one method that:
  - Requests permissions
  - Automatically shows recovery dialog if denied
  - Handles settings navigation
  - Returns final permission status
- `showPermissionDialogIfNeeded({BuildContext, customMessage})` - Smart method that:
  - Shows permission request if not determined
  - Shows recovery dialog if denied and reminder interval passed
  - Does nothing if granted or reminder too soon
  - Perfect for periodic "please enable notifications" prompts

**MUST** support permission retry flow:
- After denial, app can call `requestPermission(force: true)` to attempt again on Android
- On iOS after denial, only `openSystemSettings()` can help (OS limitation)
- Provide clear return values indicating whether prompt was shown or settings navigation needed
- Track last reminder date in SharedPreferences to enable periodic prompting
- Provide `reminderIntervalDays` config (default 30) for how often to allow reminders

### Requirement: Badge Management

The system SHALL provide cross-platform badge count management with fallbacks.

#### Scenario: Update badge count on iOS
- **GIVEN** the app is running on iOS
- **WHEN** `NotificationService.updateBadgeCount(5)` is called
- **THEN** the service SHALL update the app icon badge to 5
- **AND** SHALL persist the count for app restarts

#### Scenario: Update badge count on Android
- **GIVEN** the app is running on Android
- **WHEN** `NotificationService.updateBadgeCount(3)` is called
- **THEN** the service SHALL update the launcher icon badge to 3
- **AND** SHALL use `app_badge_plus` for cross-launcher support

#### Scenario: Clear badge count
- **GIVEN** the app has a badge count displayed
- **WHEN** `NotificationService.clearBadge()` is called
- **THEN** the service SHALL set the badge count to 0
- **AND** SHALL remove the visual badge indicator

#### Scenario: Badge count on unsupported platform
- **GIVEN** the app is running on a platform without badge support (e.g., web)
- **WHEN** `NotificationService.updateBadgeCount(2)` is called
- **THEN** the service SHALL log the request
- **AND** SHALL not throw an error
- **AND** SHALL gracefully no-op

### Requirement: Local Notification Display

The system SHALL display local notifications with rich content support.

#### Scenario: Show basic notification
- **GIVEN** the app wants to show a notification
- **WHEN** `NotificationService.showNotification()` is called with title and body
- **THEN** the service SHALL display a notification with the provided title and body
- **AND** SHALL use the default notification channel/category
- **AND** SHALL assign a unique notification ID

#### Scenario: Show notification with image
- **GIVEN** the app wants to show a rich notification
- **WHEN** `NotificationService.showNotification()` is called with an image URL
- **THEN** the service SHALL download the image asynchronously
- **AND** SHALL display the notification with the image attached
- **AND** SHALL handle image download failures gracefully (show without image)

#### Scenario: Show notification with action buttons
- **GIVEN** the app wants interactive notifications
- **WHEN** `NotificationService.showNotification()` is called with action buttons
- **THEN** the service SHALL register the actions with the platform
- **AND** SHALL display the notification with visible action buttons
- **AND** SHALL call `onNotificationAction` when an action is tapped

#### Scenario: Cancel notification
- **GIVEN** a notification is displayed in the notification center
- **WHEN** `NotificationService.cancelNotification(id)` is called
- **THEN** the service SHALL remove the notification with the given ID
- **AND** SHALL not affect other notifications

#### Scenario: Cancel all notifications
- **GIVEN** multiple notifications are displayed
- **WHEN** `NotificationService.cancelAllNotifications()` is called
- **THEN** the service SHALL remove all active notifications
- **AND** SHALL clear the notification center for the app

### Requirement: Notification Routing

The system SHALL route notification actions to app destinations via callbacks.

#### Scenario: Route notification to specific screen
- **GIVEN** a notification contains a route parameter (e.g., `/messages/123`)
- **WHEN** the user taps the notification
- **THEN** the service SHALL extract the route parameter
- **AND** SHALL call the `onNotificationTapped` callback with the route
- **AND** SHALL allow the app's navigation system to handle the route

#### Scenario: Route notification with custom data
- **GIVEN** a notification contains custom data payload
- **WHEN** the user taps the notification
- **THEN** the service SHALL parse the data payload
- **AND** SHALL call the `onNotificationTapped` callback with both route and data
- **AND** SHALL preserve all data types (strings, numbers, booleans)

#### Scenario: Handle action button tap
- **GIVEN** a notification has action buttons
- **WHEN** the user taps an action button
- **THEN** the service SHALL call the `onNotificationAction` callback
- **AND** SHALL pass the action identifier and notification data
- **AND** SHALL not launch the app if the action is configured as background

### Requirement: Notification Payload Model

The system SHALL provide a strongly-typed model for notification data.

#### Scenario: Parse FCM remote message
- **GIVEN** a remote message is received from FCM
- **WHEN** `NotificationPayload.fromRemoteMessage()` is called
- **THEN** the system SHALL extract title, body, image, route, and data
- **AND** SHALL handle missing fields gracefully with null values
- **AND** SHALL return a valid `NotificationPayload` instance

#### Scenario: Serialize notification to JSON
- **GIVEN** a `NotificationPayload` instance
- **WHEN** `payload.toJson()` is called
- **THEN** the system SHALL return a JSON-serializable map
- **AND** SHALL include all non-null fields
- **AND** SHALL support round-trip serialization (toJson → fromJson)

#### Scenario: Deserialize notification from JSON
- **GIVEN** a JSON map representing a notification
- **WHEN** `NotificationPayload.fromJson(map)` is called
- **THEN** the system SHALL create a valid payload instance
- **AND** SHALL handle missing or invalid fields gracefully
- **AND** SHALL not throw exceptions for malformed data

### Requirement: Background Message Handling

The system SHALL handle FCM messages when the app is in the background or terminated.

#### Scenario: Register background message handler
- **GIVEN** the app is initializing
- **WHEN** `FirebaseMessaging.onBackgroundMessage()` is configured
- **THEN** the system SHALL register a top-level function handler
- **AND** SHALL ensure the handler can run in a separate isolate
- **AND** SHALL not rely on app state or UI

#### Scenario: Process background notification
- **GIVEN** the app is in the background
- **WHEN** a notification-only message is received
- **THEN** the platform SHALL automatically display the notification
- **AND** SHALL not invoke custom Dart code until the notification is tapped

#### Scenario: Process background data message
- **GIVEN** the app is in the background
- **WHEN** a data-only message is received
- **THEN** the background handler SHALL execute
- **AND** MAY display a local notification
- **AND** MAY update local data or perform background work

### Requirement: Notification Channels (Android)

The system SHALL create and manage notification channels on Android.

#### Scenario: Create default notification channel
- **GIVEN** the app is initializing on Android
- **WHEN** `NotificationService.initialize()` is called
- **THEN** the service SHALL create a default notification channel
- **AND** SHALL set the channel name, description, and importance level
- **AND** SHALL configure sound, vibration, and lights

#### Scenario: Create custom notification channels
- **GIVEN** the app needs multiple notification types
- **WHEN** `NotificationService.createChannel()` is called with channel config
- **THEN** the service SHALL create a new channel with the given ID and settings
- **AND** SHALL make the channel available for future notifications
- **AND** SHALL not recreate existing channels

#### Scenario: Delete notification channel
- **GIVEN** a notification channel exists
- **WHEN** `NotificationService.deleteChannel(channelId)` is called
- **THEN** the service SHALL remove the channel from the system
- **AND** SHALL not affect notifications already posted to that channel

### Requirement: FCM Token Integration

The system SHALL integrate with existing FCM token management in `AuthServiceImpl`.

#### Scenario: Update notification service when token changes
- **GIVEN** `AuthServiceImpl` receives a new FCM token
- **WHEN** the token is updated on the server
- **THEN** `AuthServiceImpl` SHALL notify `NotificationService` of the new token
- **AND** `NotificationService` SHALL update its internal state
- **AND** SHALL be available for diagnostic purposes

#### Scenario: Initialize notifications without authentication
- **GIVEN** the user is not logged in
- **WHEN** `NotificationService.initialize()` is called
- **THEN** the service SHALL initialize local notifications
- **AND** SHALL defer FCM token registration until authentication completes
- **AND** SHALL not block initialization on authentication



### Requirement: Platform Compatibility

The system SHALL support iOS, Android, and web platforms with appropriate fallbacks.

#### Scenario: Detect platform capabilities
- **GIVEN** the app is running on any platform
- **WHEN** `NotificationService.isSupported()` is called
- **THEN** the service SHALL return true if notifications are supported
- **AND** SHALL return false on platforms without notification support

#### Scenario: Graceful degradation on web
- **GIVEN** the app is running on web
- **WHEN** notification features are used
- **THEN** the service SHALL use browser notification API if available
- **AND** SHALL show a permission prompt in the browser
- **AND** SHALL fallback gracefully if notifications are blocked

#### Scenario: Handle iOS simulator limitations
- **GIVEN** the app is running on iOS simulator
- **WHEN** FCM token is requested
- **THEN** the service SHALL detect the simulator environment
- **AND** SHALL log a warning about limited FCM support
- **AND** SHALL allow local notifications to work
