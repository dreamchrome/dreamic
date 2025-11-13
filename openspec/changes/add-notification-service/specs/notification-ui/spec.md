# Notification UI Specification

## ADDED Requirements

### Requirement: Notification Permission Bottom Sheet

The system SHALL provide a reusable bottom sheet component for requesting notification permissions.

#### Scenario: Display permission request bottom sheet
- **GIVEN** the app wants to request notification permissions
- **WHEN** `NotificationPermissionBottomSheet.show()` is called
- **THEN** the system SHALL display a bottom sheet with customizable title and description
- **AND** SHALL include "Allow Notifications" and "Not Now" buttons
- **AND** SHALL adapt to the current theme (light/dark mode)

#### Scenario: User allows notifications
- **GIVEN** the permission bottom sheet is displayed
- **WHEN** the user taps "Allow Notifications"
- **THEN** the system SHALL call `NotificationService.requestPermissions()`
- **AND** SHALL dismiss the bottom sheet
- **AND** SHALL call the `onResult` callback with the permission status
- **AND** SHALL show the system permission prompt if needed

#### Scenario: User declines notifications
- **GIVEN** the permission bottom sheet is displayed
- **WHEN** the user taps "Not Now" or dismisses the sheet
- **THEN** the system SHALL dismiss the bottom sheet
- **AND** SHALL call the `onResult` callback with denied status
- **AND** SHALL not show the system permission prompt

#### Scenario: Customize bottom sheet appearance
- **GIVEN** the app has specific branding requirements
- **WHEN** `NotificationPermissionBottomSheet` is initialized with custom parameters
- **THEN** the system SHALL use the provided title, description, button text
- **AND** SHALL apply custom colors for buttons and text
- **AND** SHALL support custom icons

#### Scenario: Show settings prompt for denied permissions
- **GIVEN** the user previously denied permissions
- **WHEN** `NotificationPermissionBottomSheet.show()` is called
- **THEN** the system SHALL detect the denied state
- **AND** SHALL show a modified message explaining how to enable in settings
- **AND** SHALL include an "Open Settings" button
- **AND** SHALL call `NotificationService.openSettings()` when tapped

### Requirement: Permission Status Widget

The system SHALL provide a widget for displaying current notification permission status.

#### Scenario: Display granted permission status
- **GIVEN** the user has granted notification permissions
- **WHEN** `NotificationPermissionStatusWidget` is rendered
- **THEN** the system SHALL display a checkmark icon or success indicator
- **AND** SHALL show "Notifications Enabled" text
- **AND** SHALL use success color (green)

#### Scenario: Display denied permission status
- **GIVEN** the user has denied notification permissions
- **WHEN** `NotificationPermissionStatusWidget` is rendered
- **THEN** the system SHALL display a warning icon
- **AND** SHALL show "Notifications Disabled" text
- **AND** SHALL use warning color (orange/red)
- **AND** SHALL include a "Change in Settings" button

#### Scenario: Display undetermined permission status
- **GIVEN** permissions have not been requested yet
- **WHEN** `NotificationPermissionStatusWidget` is rendered
- **THEN** the system SHALL display a neutral icon
- **AND** SHALL show "Enable Notifications" text
- **AND** SHALL include an "Enable" button to request permissions

#### Scenario: Real-time permission status updates
- **GIVEN** the `NotificationPermissionStatusWidget` is displayed
- **WHEN** the user changes permissions in system settings
- **THEN** the widget SHALL detect the status change
- **AND** SHALL update its display automatically
- **AND** SHALL reflect the new permission state

### Requirement: Notification Settings Page

The system SHALL provide a pre-built settings page for notification preferences.

#### Scenario: Display notification settings page
- **GIVEN** the app wants to show notification settings
- **WHEN** `NotificationSettingsPage` is navigated to
- **THEN** the system SHALL display current permission status
- **AND** SHALL show toggles for notification preferences
- **AND** SHALL include badge count toggle
- **AND** SHALL include sound/vibration toggles

#### Scenario: Toggle notification preferences
- **GIVEN** the settings page is displayed
- **WHEN** the user toggles a preference (e.g., sounds off)
- **THEN** the system SHALL save the preference locally
- **AND** SHALL apply the preference to future notifications
- **AND** SHALL provide visual feedback (toggle animation)

#### Scenario: Request permissions from settings page
- **GIVEN** permissions are not granted
- **WHEN** the user taps "Enable Notifications" on the settings page
- **THEN** the system SHALL show the permission bottom sheet
- **AND** SHALL update the settings page after permission is granted/denied

### Requirement: Notification Permission Builder

The system SHALL provide a headless builder component for custom permission UI.

#### Scenario: Build custom permission UI
- **GIVEN** the app wants full control over permission UI
- **WHEN** `NotificationPermissionBuilder` is used
- **THEN** the system SHALL provide the current permission status via builder callback
- **AND** SHALL provide methods to request permissions
- **AND** SHALL rebuild when permission status changes
- **AND** SHALL allow completely custom UI implementation

#### Scenario: Permission state management
- **GIVEN** a custom UI is built with `NotificationPermissionBuilder`
- **WHEN** the permission status changes
- **THEN** the builder SHALL invoke the builder callback with the new status
- **AND** SHALL allow the app to render appropriate UI
- **AND** SHALL handle permission request results

### 3.2 Permission Rationale Dialog

**MUST** provide a customizable rationale dialog shown before requesting permissions.

**Features**:
- Explain why app needs notification permissions
- Customizable title, message, icon
- Show before first permission request
- Primary button triggers permission request
- Secondary button dismisses (can opt out)

**Scenarios**:
1. App shows rationale before first request → Dialog explains benefits, user taps "Allow" → Permission prompt shown
2. User taps "Not Now" → Dialog dismissed, no permission prompt
3. App provides custom message → Dialog shows custom text and icon

### 3.3 Permission Denied Recovery Dialog

**MUST** provide a dialog for recovering from denied permission state.

**Features**:
- Show after user denies permissions
- Explain consequences of denial (won't receive important updates)
- Provide stronger rationale for why permissions needed
- Primary button: "Open Settings" → Calls `NotificationService.openSystemSettings()`
- Secondary button: "Maybe Later" → Dismisses dialog
- Different messaging for iOS (must use settings) vs Android (can retry)
- Customizable title, message, icon, button text

**Scenarios**:
1. iOS user denies permissions → Show dialog with "You'll need to enable notifications in Settings", button opens Settings
2. Android user denies permissions → Show dialog with option to retry or open settings
3. User taps "Open Settings" → Opens system settings, returns to app → App checks status and updates UI
4. User denies multiple times on Android → Show dialog suggesting they really need to enable it
5. App provides custom recovery message → Dialog shows custom text emphasizing importance

### Requirement: Badge Count Display Widget

The system SHALL provide a widget for displaying badge counts in-app.

#### Scenario: Display badge count
- **GIVEN** the app has unread items
- **WHEN** `NotificationBadgeWidget` is rendered with count 5
- **THEN** Badge displays "5"
- **AND** SHALL use a circular or rounded rectangle shape
- **AND** SHALL use the provided background color
- **AND** SHALL position the badge relative to parent widget

**Scenario: Hide badge when count is zero**
- **GIVEN** a `NotificationBadgeWidget` is displayed with count 0
- **WHEN** `hideWhenZero` is true (default)
- **THEN** No badge is shown

**Scenario: Show overflow indicator**
- **WHEN** `NotificationBadgeWidget` is rendered with count 150
- **AND** maxCount is 99 (default)
- **THEN** Badge displays "99+"

### Requirement: Notification Permission Timing Helper

The system SHALL provide utilities for determining optimal permission request timing.

#### Scenario: Check if should request permissions
- **GIVEN** the app wants to know if it should request permissions
- **WHEN** `NotificationPermissionHelper.shouldRequestPermissions()` is called
- **THEN** the system SHALL return true if permissions not determined
- **AND** SHALL return false if permissions already granted
- **AND** SHALL return false if permanently denied (too many requests)

#### Scenario: Track permission request attempts
- **GIVEN** permissions have been requested multiple times
- **WHEN** `NotificationPermissionHelper` tracks request history
- **THEN** the system SHALL count the number of requests
- **AND** SHALL store the timestamp of last request
- **AND** SHALL recommend delaying subsequent requests
- **AND** SHALL prevent permission request fatigue

#### Scenario: Determine optimal request context
- **GIVEN** the app has multiple contexts to request permissions
- **WHEN** `NotificationPermissionHelper.getOptimalContext()` is called
- **THEN** the system SHALL analyze user behavior patterns
- **AND** SHALL suggest contexts where user is likely to grant permissions
- **AND** SHALL provide guidance on messaging (e.g., "after first value moment")

### Requirement: Notification Placeholder Widget

The system SHALL provide a widget for displaying notification-related empty states.

#### Scenario: Display no notifications placeholder
- **GIVEN** the user has no notifications
- **WHEN** `NotificationPlaceholderWidget` is rendered
- **THEN** the system SHALL display an empty state icon
- **AND** SHALL display "No Notifications" title
- **AND** SHALL display optional descriptive text
- **AND** SHALL provide customizable styling

#### Scenario: Display notifications disabled placeholder
- **GIVEN** notification permissions are disabled
- **WHEN** `NotificationPlaceholderWidget` is rendered with disabled state
- **THEN** the system SHALL display a permissions icon
- **AND** SHALL display "Notifications Disabled" title
- **AND** SHALL include an "Enable Notifications" button
- **AND** SHALL link to permission request flow

### Requirement: Notification Action Button Widget

The system SHALL provide a widget for inline notification action buttons.

#### Scenario: Display notification action buttons
- **GIVEN** a notification UI shows inline action options
- **WHEN** `NotificationActionButton` is rendered
- **THEN** the system SHALL display a button with the action label
- **AND** SHALL include an optional icon
- **AND** SHALL apply theme-appropriate styling
- **AND** SHALL provide haptic feedback on press

#### Scenario: Handle action button press
- **GIVEN** a notification action button is displayed
- **WHEN** the user taps the button
- **THEN** the system SHALL call the provided callback
- **AND** SHALL pass the action identifier
- **AND** SHALL optionally dismiss the notification
- **AND** SHALL provide loading state if async

### Requirement: Platform-Specific Permission UI

The system SHALL adapt permission UI to platform-specific requirements.

#### Scenario: Show iOS-specific permission explanation
- **GIVEN** the app is running on iOS
- **WHEN** permission UI is displayed
- **THEN** the system SHALL explain alert, badge, and sound permissions
- **AND** SHALL mention critical alerts if applicable
- **AND** SHALL use iOS-style design patterns (bottom sheet, rounded buttons)

#### Scenario: Show Android-specific permission explanation
- **GIVEN** the app is running on Android 13+
- **WHEN** permission UI is displayed
- **THEN** the system SHALL explain the POST_NOTIFICATIONS permission
- **AND** SHALL mention notification channels
- **AND** SHALL use Material Design components

#### Scenario: Show web-specific permission explanation
- **GIVEN** the app is running on web
- **WHEN** permission UI is displayed
- **THEN** the system SHALL explain browser notification permissions
- **AND** SHALL warn about potential blocking by browser
- **AND** SHALL adapt to web UI patterns
