# Checklist: Deferred FCM Notification Permission Prompt

> **Reference**: See [plan.deferred-permission-pompt.md](plan.deferred-permission-pompt.md) for detailed implementation notes and code samples.

## Phase 0: Prerequisites & Key Migration

### 0.1 SharedPreferences Key Duplication Fix
- [ ] Add `_migrateOldKeys()` to `NotificationPermissionHelper` (plan lines 110-160)
- [ ] Migrate to `dreamic_` prefixed keys:
  - [ ] `dreamic_notification_denial_info` (JSON)
  - [ ] `dreamic_notification_settings_prompt_info` (JSON)
  - [ ] `dreamic_notification_has_requested` (Boolean)
  - [ ] `dreamic_notification_last_reminder_date` (Timestamp)
- [ ] Remove duplicate key constants from `NotificationService` (lines 112-115)
- [ ] Call migration on `NotificationPermissionHelper` initialization

### 0.2 New Types File
- [ ] Create `lib/notifications/notification_types.dart` with:
  - [ ] `NotificationInitResult` enum (plan lines 547-566)
  - [ ] `NotificationDenialInfo` class with JSON serialization (plan lines 617-641)
  - [ ] `GoToSettingsPromptInfo` class with JSON serialization (plan lines 644-657)
  - [ ] `NotificationFlowResult` enum (plan lines 887-911)
  - [ ] `NotificationFlowStrings` class (plan lines 914-948)
  - [ ] `NotificationFlowConfig` class (plan lines 951-1018)

---

## Phase 1: FCM Token Management Migration

### 1.1 Add FCM Token Management to NotificationService
- [ ] Add fields: `_cachedFcmToken`, `_tokenRefreshSubscription`, `_onTokenChanged` (plan lines 173-181)
- [ ] Add `initializeFcmToken()` method (plan lines 192-231)
- [ ] Add `_waitForApnsToken()` for iOS/macOS (plan lines 233-246)
- [ ] Add FCM token storage with legacy migration:
  - [ ] `_legacyFcmTokenKey` constant (`commonSharedKeyFcmToken`)
  - [ ] `_fcmTokenKey` constant (`dreamic_fcm_token`)
  - [ ] `_getStoredToken()` with migration (plan lines 252-270)
  - [ ] `_storeToken()` (plan lines 272-279)
  - [ ] `clearFcmToken()` (plan lines 283-288)

### 1.2 Remove FCM Code from AuthServiceImpl
- [ ] Remove `useFirebaseFCM` field (line 39)
- [ ] Remove `_hasInitializedFCM` field (line 46)
- [ ] Remove `sharedPrefKeyFcmToken` constant (line 26)
- [ ] Remove FCM initialization in `handleTokenChanges()` (lines 163-170)
- [ ] Remove `initFCM()` method (lines 1698-1779)
- [ ] Remove `_updateTokenOnServer()` method (lines 1781-1803)
- [ ] Keep `isLoggedInStream` (already in interface)

---

## Phase 2: Configuration Options

### 2.1 AppConfigBase Updates
- [ ] Add `useFCMWeb` property (default: `false`) (plan lines 469-480)
- [ ] Add `fcmAutoInitialize` property (default: `true`) (plan lines 527-537)
- [ ] Update `_getDefaultFCMValue()` to check `useFCMWeb` on web (plan lines 498-508)

---

## Phase 3: NotificationPermissionHelper Enhancements

### 3.1 Add Structured Tracking
- [ ] Add `getNotificationDenialInfo()` → returns `NotificationDenialInfo`
- [ ] Add `clearNotificationDenialInfo()`
- [ ] Add `getGoToSettingsPromptInfo()` → returns `GoToSettingsPromptInfo`
- [ ] Add `clearGoToSettingsPromptInfo()`
- [ ] Add `recordDenial(isPermanent: bool)` with structured data
- [ ] Add `recordBlockedRequest()` (distinct from denial)
- [ ] Add `recordGoToSettingsPrompt(openedSettings: bool)`
- [ ] Add `autoClearIfGranted()` - clears tracking when permission detected as granted

### 3.2 Enhance Existing Methods
- [ ] Update `shouldShowSettingsPrompt()` to use `NotificationFlowConfig` limits
- [ ] Update `shouldRequestPermissions()` to integrate with `NotificationFlowConfig`

---

## Phase 4: NotificationService Core Methods

### 4.1 Permission Methods
- [ ] Add/enhance `getPermissionStatus()` with auto-clear behavior (plan lines 588-592)
- [ ] Add `initializeNotifications()` method (plan lines 694-722)
- [ ] Add `openNotificationSettings()` with web handling (plan lines 1704-1714)
- [ ] Expose `permissionHelper` getter

### 4.2 Convenience Wrappers (delegate to helper)
- [ ] `getNotificationDenialInfo()`
- [ ] `clearNotificationDenialInfo()`
- [ ] `getGoToSettingsPromptInfo()`
- [ ] `clearGoToSettingsPromptInfo()`

### 4.3 Auth Integration
- [ ] Add `connectToAuthService()` or auto-wire via GetIt (plan lines 356-366)
- [ ] Implement pre-logout cleanup: `preLogoutCleanup()` (plan lines 361-366)
- [ ] Handle `fcmAutoInitialize` check in auth connection (plan lines 664-684)

### 4.4 App-Level Toggle
- [ ] Add `disableNotifications()` (plan lines 371-372)
- [ ] Add `enableNotifications()` (plan lines 372-373)
- [ ] Add `isNotificationsEnabled()` (plan lines 373-374)

### 4.5 Remove Duplicate Methods from NotificationService
- [ ] Remove `_trackPermissionRequest()` (line 655)
- [ ] Remove `_trackPermissionDenial()` (line 667)
- [ ] Remove `getPermissionRequestCount()` (line 678)
- [ ] Remove `getPermissionDenialCount()` (line 689)
- [ ] Remove `shouldShowPeriodicReminder()` (line 700)
- [ ] Remove `updateLastReminderDate()` (line 720)
- [ ] Remove TODO at line 615 (auth notification - wrong direction)
- [ ] Update `requestPermissions()` to use helper for tracking

---

## Phase 5: High-Level Permission Flow

### 5.1 Flow Implementation
- [ ] Add `runNotificationPermissionFlow()` method (plan lines 1047-1131)
- [ ] Add `_shouldAskAgain()` helper (plan lines 1150-1157)
- [ ] Add `_shouldShowGoToSettingsPrompt()` helper (plan lines 1133-1148)
- [ ] Add `_mapInitResultToFlowResult()` helper
- [ ] Add `_showGoToSettingsPromptWithTracking()` helper

### 5.2 Lifecycle Handling
- [ ] Add `_waitingForSettingsReturn` flag
- [ ] Add `_lifecycleSubscription`
- [ ] Add `_setupLifecycleListener()` using `AppLifecycleService` (plan lines 1363-1370)
- [ ] Add `_handleResumeAfterSettings()` (plan lines 1372-1380)

### 5.3 Web-Specific Handling
- [ ] Add web settings instructions strings to `NotificationFlowStrings` (plan lines 1723-1738)
- [ ] Add `_showWebSettingsInstructionsDialog()` (plan lines 1743-1763)
- [ ] Handle `openNotificationSettings()` returning `false` on web

---

## Phase 6: Dialog Helpers

### 6.1 Create Dialog Helpers File
- [ ] Create `lib/presentation/helpers/notification_permission_dialogs.dart`
- [ ] Add `showNotificationValuePropositionDialog()` (plan lines 1172-1184)
- [ ] Add `showNotificationGoToSettingsDialog()` (plan lines 1186-1198)
- [ ] Add `showNotificationAskAgainDialog()` (plan lines 1200-1213)

---

## Phase 7: Documentation

### 7.1 Update Existing Docs
- [ ] Update `docs/DREAMIC_FEATURES_GUIDE.md` - Notifications section (plan lines 828-833)
- [ ] Update `docs/NOTIFICATION_GUIDE.md` - Major updates (plan lines 835-841)
- [ ] Update `docs/NOTIFICATION_SETUP.md` - Config options (plan lines 843-848)

### 7.2 Breaking Changes Documentation
- [ ] Document `useFirebaseFCM` removal from AuthServiceImpl
- [ ] Document `useFCMWeb` default change (web FCM now opt-in)
- [ ] Add migration checklist for consuming apps (plan lines 349-354)

---

## Phase 8: Testing

### 8.1 Create Test Directory Structure
- [ ] Create `test/notification_permission/` directory
- [ ] Create `test/notification_permission/mocks/` directory
- [ ] Create `test/notification_permission/integration/` directory

### 8.2 Unit Tests
- [ ] `notification_denial_info_test.dart` (plan lines 1888-1920)
- [ ] `go_to_settings_prompt_info_test.dart`
- [ ] `notification_flow_config_test.dart`
- [ ] `should_ask_again_test.dart` (plan lines 1924-1963)
- [ ] `should_show_go_to_settings_test.dart` (plan lines 1967-2011)
- [ ] `notification_permission_helper_test.dart`
- [ ] `notification_permission_flow_test.dart` (plan lines 2013-2093)

### 8.3 Mock Helpers
- [ ] `mock_permission_handler.dart` (plan lines 2198-2233)
- [ ] `mock_shared_preferences.dart`

### 8.4 Integration Tests
- [ ] `notification_permission_integration_test.dart` (plan lines 2096-2193)

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
| 0 | Prerequisites & Key Migration | Not Started |
| 1 | FCM Token Management Migration | Not Started |
| 2 | Configuration Options | Not Started |
| 3 | NotificationPermissionHelper Enhancements | Not Started |
| 4 | NotificationService Core Methods | Not Started |
| 5 | High-Level Permission Flow | Not Started |
| 6 | Dialog Helpers | Not Started |
| 7 | Documentation | Not Started |
| 8 | Testing | Not Started |
| 9 | Verification | Not Started |
