# Checklist: Deferred FCM Notification Permission Prompt

> **Reference**: See [plan.deferred-permission-pompt.md](plan.deferred-permission-pompt.md) for detailed implementation notes and code samples.

## Phase 0: Prerequisites & Key Migration

### 0.1 SharedPreferences Key Duplication Fix
- [x] Add `_migrateOldKeys()` to `NotificationPermissionHelper` (plan lines 110-160)
- [x] Migrate to `dreamic_` prefixed keys:
  - [x] `dreamic_notification_denial_info` (JSON)
  - [x] `dreamic_notification_settings_prompt_info` (JSON)
  - [x] `dreamic_notification_has_requested` (Boolean)
  - [x] `dreamic_notification_last_reminder_date` (Timestamp)
- [x] Remove duplicate key constants from `NotificationService` (lines 112-115)
- [x] Call migration on `NotificationPermissionHelper` initialization

### 0.2 New Types File
- [x] Create `lib/notifications/notification_types.dart` with:
  - [x] `NotificationInitResult` enum (plan lines 547-566)
  - [x] `NotificationDenialInfo` class with JSON serialization (plan lines 617-641)
  - [x] `GoToSettingsPromptInfo` class with JSON serialization (plan lines 644-657)
  - [x] `NotificationFlowResult` enum (plan lines 887-911)
  - [x] `NotificationFlowStrings` class (plan lines 914-948)
  - [x] `NotificationFlowConfig` class (plan lines 951-1018)

---

## Phase 1: FCM Token Management Migration

### 1.1 Add FCM Token Management to NotificationService
- [x] Add fields: `_cachedFcmToken`, `_tokenRefreshSubscription`, `_onTokenChanged` (plan lines 173-181)
- [x] Add `initializeFcmToken()` method (plan lines 192-231)
- [x] Add `_waitForApnsToken()` for iOS/macOS (plan lines 233-246)
- [x] Add FCM token storage with legacy migration:
  - [x] `_legacyFcmTokenKey` constant (`commonSharedKeyFcmToken`)
  - [x] `_fcmTokenKey` constant (`dreamic_fcm_token`)
  - [x] `_getStoredToken()` with migration (plan lines 252-270)
  - [x] `_storeToken()` (plan lines 272-279)
  - [x] `clearFcmToken()` (plan lines 283-288)

### 1.2 Remove FCM Code from AuthServiceImpl
- [x] Remove `useFirebaseFCM` field (line 39)
- [x] Remove `_hasInitializedFCM` field (line 46)
- [x] Remove `sharedPrefKeyFcmToken` constant (line 26)
- [x] Remove FCM initialization in `handleTokenChanges()` (lines 163-170)
- [x] Remove `initFCM()` method (lines 1698-1779)
- [x] Remove `_updateTokenOnServer()` method (lines 1781-1803)
- [x] Keep `isLoggedInStream` (already in interface)

---

## Phase 2: Configuration Options

### 2.1 AppConfigBase Updates
- [x] Add `useFCMWeb` property (default: `false`) (plan lines 469-480)
- [x] Add `fcmAutoInitialize` property (default: `true`) (plan lines 527-537)
- [x] Update `_getDefaultFCMValue()` to check `useFCMWeb` on web (plan lines 498-508)

---

## Phase 3: NotificationPermissionHelper Enhancements

### 3.1 Add Structured Tracking
- [x] Add `getNotificationDenialInfo()` → returns `NotificationDenialInfo`
- [x] Add `clearNotificationDenialInfo()`
- [x] Add `getGoToSettingsPromptInfo()` → returns `GoToSettingsPromptInfo`
- [x] Add `clearGoToSettingsPromptInfo()`
- [x] Add `recordDenial(isPermanent: bool)` with structured data
- [x] Add `recordBlockedRequest()` (distinct from denial)
- [x] Add `recordGoToSettingsPrompt(openedSettings: bool)`
- [x] Add `autoClearIfGranted()` - clears tracking when permission detected as granted

### 3.2 Enhance Existing Methods
- [x] Update `shouldShowSettingsPrompt()` to use `NotificationFlowConfig` limits
- [x] Update `shouldRequestPermissions()` to integrate with `NotificationFlowConfig`

---

## Phase 4: NotificationService Core Methods

### 4.1 Permission Methods
- [x] Add/enhance `getPermissionStatus()` with auto-clear behavior (plan lines 588-592)
- [x] Add `initializeNotifications()` method (plan lines 694-722)
- [x] Add `openNotificationSettings()` with web handling (plan lines 1704-1714)
- [x] Expose `permissionHelper` getter

### 4.2 Convenience Wrappers (delegate to helper)
- [x] `getNotificationDenialInfo()`
- [x] `clearNotificationDenialInfo()`
- [x] `getGoToSettingsPromptInfo()`
- [x] `clearGoToSettingsPromptInfo()`

### 4.3 Auth Integration
- [x] Add `connectToAuthService()` or auto-wire via GetIt (plan lines 356-366)
- [x] Implement pre-logout cleanup: `preLogoutCleanup()` (plan lines 361-366)
- [x] Handle `fcmAutoInitialize` check in auth connection (plan lines 664-684)

### 4.4 App-Level Toggle
- [x] Add `disableNotifications()` (plan lines 371-372)
- [x] Add `enableNotifications()` (plan lines 372-373)
- [x] Add `isNotificationsEnabled()` (plan lines 373-374)

### 4.5 Remove Duplicate Methods from NotificationService
- [x] Remove `_trackPermissionRequest()` (line 655)
- [x] Remove `_trackPermissionDenial()` (line 667)
- [x] Remove `getPermissionRequestCount()` (line 678) - now delegates to helper
- [x] Remove `getPermissionDenialCount()` (line 689) - now delegates to helper
- [x] Remove `shouldShowPeriodicReminder()` (line 700) - now delegates to helper
- [x] Remove `updateLastReminderDate()` (line 720) - now delegates to helper
- [x] Remove TODO at line 615 (auth notification - wrong direction)
- [x] Update `requestPermissions()` to use helper for tracking

---

## Phase 5: High-Level Permission Flow

### 5.1 Flow Implementation
- [x] Add `runNotificationPermissionFlow()` method (plan lines 1047-1131)
- [x] Add `_shouldAskAgain()` helper (plan lines 1150-1157)
- [x] Add `_shouldShowGoToSettingsPrompt()` helper (plan lines 1133-1148)
- [x] Add `_mapInitResultToFlowResult()` helper
- [x] Add `_showGoToSettingsPromptWithTracking()` helper

### 5.2 Lifecycle Handling
- [x] Add `_waitingForSettingsReturn` flag
- [x] Add `_lifecycleSubscription`
- [x] Add `_setupLifecycleListener()` using `AppLifecycleService` (plan lines 1363-1370)
- [x] Add `_handleResumeAfterSettings()` (plan lines 1372-1380)

### 5.3 Web-Specific Handling
- [x] Add web settings instructions strings to `NotificationFlowStrings` (plan lines 1723-1738)
- [x] Add `_showWebSettingsInstructionsDialog()` (plan lines 1743-1763)
- [x] Handle `openNotificationSettings()` returning `false` on web

---

## Phase 6: Dialog Helpers

### 6.1 Create Dialog Helpers File
- [x] Create `lib/presentation/helpers/notification_permission_dialogs.dart`
- [x] Add `showNotificationValuePropositionDialog()` (plan lines 1172-1184)
- [x] Add `showNotificationGoToSettingsDialog()` (plan lines 1186-1198)
- [x] Add `showNotificationAskAgainDialog()` (plan lines 1200-1213)

---

## Phase 7: Documentation

### 7.1 Update Existing Docs
- [x] Update `docs/DREAMIC_FEATURES_GUIDE.md` - Notifications section (plan lines 828-833)
- [x] Update `docs/NOTIFICATION_GUIDE.md` - Major updates (plan lines 835-841)
- [x] Update `docs/NOTIFICATION_SETUP.md` - Config options (plan lines 843-848)

### 7.2 Breaking Changes Documentation
- [x] Document `useFirebaseFCM` removal from AuthServiceImpl
- [x] Document `useFCMWeb` default change (web FCM now opt-in)
- [x] Add migration checklist for consuming apps (plan lines 349-354)

---

## Phase 8: Testing

### 8.1 Create Test Directory Structure
- [x] Create `test/notification_permission/` directory
- [x] Create `test/notification_permission/mocks/` directory
- [x] Create `test/notification_permission/integration/` directory

### 8.2 Unit Tests
- [x] `notification_denial_info_test.dart` (plan lines 1888-1920)
- [x] `go_to_settings_prompt_info_test.dart`
- [x] `notification_flow_config_test.dart`
- [x] `should_ask_again_test.dart` (plan lines 1924-1963)
- [x] `should_show_go_to_settings_test.dart` (plan lines 1967-2011)
- [x] `notification_permission_helper_test.dart`
- [x] `notification_permission_flow_test.dart` (plan lines 2013-2093) - tests flow logic without Firebase dependencies

### 8.3 Mock Helpers
- [x] `mock_permission_handler.dart` (plan lines 2198-2233)
- [x] `mock_shared_preferences.dart`

### 8.4 Integration Tests
- [x] `notification_permission_integration_test.dart` (plan lines 2096-2193)

---

## Phase 9: Verification

### 9.1 Basic Flow (plan lines 1778-1784)
- [ ] Default settings - permission prompt appears on login
- [ ] `fcmAutoInitializeDefault = false` - no prompt on login
- [ ] Manual `initializeNotifications()` - prompt appears

### 9.2 Permission Already Granted (plan lines 1784-1785)
- [ ] Subsequent launch with permission granted initializes silently

### 9.3 iOS Denial Flow (plan lines 1786-1792)
- [ ] Deny → status is `permanentlyDenied`
- [ ] `openNotificationSettings()` opens iOS Settings

### 9.4 Android Denial Flow (plan lines 1793-1801)
- [ ] First denial → status is `denied`, can re-request
- [ ] Second denial → status is `permanentlyDenied`

### 9.5 Go-to-Settings Configuration (plan lines 1809-1824)
- [ ] `showGoToSettingsPrompt: false` → `skippedGoToSettings`
- [ ] `goToSettingsMaxAskCount: 1` → limit respected
- [ ] `goToSettingsAskAgainAfter` timing respected

### 9.6 Web-Specific Flow (plan lines 1825-1835)
- [ ] Default `useFCMWeb = false` → FCM not initialized
- [ ] `useFCMWebDefault = true` → FCM initialized
- [ ] Web denied → instructions dialog shown

### 9.7 Edge Cases (plan lines 1837-1859)
- [ ] Blocked permission request detection
- [ ] System exception handling
- [ ] Auto-clear on permission granted via settings
- [ ] Denial count vs request attempt tracking

---

## Summary

| Phase | Description | Status |
|-------|-------------|--------|
| 0 | Prerequisites & Key Migration | ✅ Complete |
| 1 | FCM Token Management Migration | ✅ Complete |
| 2 | Configuration Options | ✅ Complete |
| 3 | NotificationPermissionHelper Enhancements | ✅ Complete |
| 4 | NotificationService Core Methods | ✅ Complete |
| 5 | High-Level Permission Flow | ✅ Complete |
| 6 | Dialog Helpers | ✅ Complete |
| 7 | Documentation | ✅ Complete |
| 8 | Testing | ✅ Complete (156 tests passing) |
| 9 | Verification | Not Started |
