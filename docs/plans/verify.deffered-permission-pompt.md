# Task List: Fixes for Deferred Permission Prompt Findings

Date: 2026-01-19
Scope: Convert verification findings into actionable tasks.

## A) Implementation Order (Dependency-Optimized)

- [x] **Auto-wire auth in `NotificationService.initialize()`**
   - Add guarded GetIt resolution for `AuthServiceInt`.
   - Set `_onTokenChanged` to default callable when caller didn't pass one.
   - Connect auth stream or call `connectToAuthService()` internally.
   - Files: [lib/notifications/notification_service.dart](lib/notifications/notification_service.dart#L227-L318)

- [x] **Logout flow triggers local cleanup automatically**
   - In `connectToAuthService()`, perform local token cleanup when `isLoggedIn` becomes false.
   - Local cleanup only (no backend call since user is already logged out; server prunes stale tokens on send failures).
   - Updated doc comments to explain automatic vs manual cleanup behavior.
   - Files: [lib/notifications/notification_service.dart](lib/notifications/notification_service.dart#L928-L958)

- [x] **Align web settings result semantics**
   - Added new `NotificationFlowResult.shownWebInstructions` enum value.
   - Removed `&& !kIsWeb` from `isPermanentDenied` calculation so web denial routes through go-to-settings flow.
   - Added explicit `kIsWeb` check in `_handlePermanentlyDeniedFlow` to return `shownWebInstructions`.
   - Returns `openedSettings` only when settings were actually opened (mobile platforms).
   - Updated NOTIFICATION_GUIDE.md with example handling and web-specific documentation.
   - Files: [lib/notifications/notification_types.dart](lib/notifications/notification_types.dart#L69-L72), [lib/notifications/notification_service.dart](lib/notifications/notification_service.dart#L1316-L1320), [lib/notifications/notification_service.dart](lib/notifications/notification_service.dart#L1404-L1417), [docs/NOTIFICATION_GUIDE.md](docs/NOTIFICATION_GUIDE.md#L295-L299)

- [x] **Web settings instructions behavior**
   - Added `simulateOpenNotificationSettings()` helper function with tests verifying false on web, true on mobile.
   - Updated `simulateFlowDecision()` with `isWeb` parameter to test web-specific flow.
   - Added 8 tests covering: web instructions result, mobile vs web behavior, config limits on web, user decline on web.
   - Updated enum completeness test to include `shownWebInstructions`.
   - Files: [test/notification_permission/notification_permission_flow_test.dart](test/notification_permission/notification_permission_flow_test.dart#L147-L161), [test/notification_permission/notification_permission_flow_test.dart](test/notification_permission/notification_permission_flow_test.dart#L463-L602)

- [x] **App-level notification toggles**
   - Added tests for `enableNotifications()`, `disableNotifications()`, and `isNotificationsEnabled()`.
   - Verified SharedPreferences flag behavior (18 tests covering default values, persistence, toggling, independence from other prefs).
   - Note: Full Firebase token cleanup testing requires Firebase mocking; tests focus on SharedPreferences layer.
   - Files: [test/notification_permission/notification_toggle_test.dart](test/notification_permission/notification_toggle_test.dart), [test/notification_permission/mocks/mock_shared_preferences.dart](test/notification_permission/mocks/mock_shared_preferences.dart)

- [x] **Reduce dialog helper duplication**
   - Chose Option 2: Remove presentation helper file, keep service's private methods.
   - Rationale: `NotificationFlowConfig` already provides localization via `NotificationFlowStrings` and full customization via `*Builder` callbacks. Exporting separate dialog helpers would add redundant API surface.
   - Deleted `lib/presentation/helpers/notification_permission_dialogs.dart`.
   - Files: [lib/notifications/notification_service.dart](lib/notifications/notification_service.dart#L1476-L1538)

- [x] **Expose helper wrappers (optional parity)**
   - Skipped: `NotificationPermissionHelper` is already exported, so consumers who need advanced methods can use `permissionHelper` directly. Keeps service API surface lean.

- [x] **Export helper dialogs if part of public API**
   - N/A: Decided not to export dialog helpers; removed the file in "Reduce dialog helper duplication" task above.

- [x] **Correct logout behavior in NOTIFICATION_GUIDE**
   - Updated "Behavior" section to clarify: auto-logout does local cleanup only (no backend call).
   - Added note pointing to `preLogoutCleanup()` for backend unregistration before signOut.
   - File: [docs/NOTIFICATION_GUIDE.md](docs/NOTIFICATION_GUIDE.md#L570-L575)

- [ ] **Remove `useFirebaseFCM` references in docs**
   - Replace outdated constructor snippets in DREAMIC_FEATURES_GUIDE.
   - Update simulator guidance to use `useFCM` + platform checks instead.
   - Files:
      - [docs/DREAMIC_FEATURES_GUIDE.md](docs/DREAMIC_FEATURES_GUIDE.md#L114-L150)
      - [docs/DREAMIC_FEATURES_GUIDE.md](docs/DREAMIC_FEATURES_GUIDE.md#L2290-L2315)
      - [docs/DREAMIC_FEATURES_GUIDE.md](docs/DREAMIC_FEATURES_GUIDE.md#L2648-L2660)
      - [docs/DREAMIC_FEATURES_GUIDE.md](docs/DREAMIC_FEATURES_GUIDE.md#L2738-L2750)

- [ ] **Update CHANGELOG for breaking changes**
   - Add entries for:
      - FCM token management moved to `NotificationService`
      - `useFirebaseFCM` removed
      - `useFCMWeb` default false (web FCM opt-in)
   - Ensure version section aligns with actual release (likely 0.3.0+).
   - File: [CHANGELOG.md](CHANGELOG.md#L110-L310)

- [ ] **Add `onAboutToLogOut` callback to AuthServiceImpl**
   - Add `Future<void> Function()? onAboutToLogOut` to constructor (alongside existing `onAuthenticated`, `onRefreshed`, `onLoggedOut`).
   - Call in `signOut()` BEFORE `_fbAuth.signOut()` with 5-second timeout.
   - Update `NotificationService.connectToAuthService()` to register this callback for backend token unregistration.
   - This makes backend cleanup automatic (no manual `preLogoutCleanup()` needed).
   - Update NOTIFICATION_GUIDE.md to reflect automatic backend cleanup on logout.
   - Files: [lib/data/repos/auth_service_impl.dart](lib/data/repos/auth_service_impl.dart#L82-L99), [lib/data/repos/auth_service_int.dart](lib/data/repos/auth_service_int.dart), [lib/notifications/notification_service.dart](lib/notifications/notification_service.dart#L928-L958), [docs/NOTIFICATION_GUIDE.md](docs/NOTIFICATION_GUIDE.md#L570-L605)

- [ ] **Add integration test for auto-clear on resume**
   - Simulate permission grant and ensure denial info cleared.
   - File: [test/notification_permission/integration/notification_permission_integration_test.dart](test/notification_permission/integration/notification_permission_integration_test.dart#L1-L210)
# Verification: Deferred FCM Permission Prompt

Date: 2026-01-19
Scope: Implementation verification against plan.deferred-permission-pompt.md

## Findings (Recorded)

### Implemented as Planned ✅
- `AppConfigBase.useFCMWeb` (default false) and `AppConfigBase.fcmAutoInitialize` (default true) are present. `_getDefaultFCMValue()` gates web via `useFCMWeb`. See [lib/app/app_config_base.dart](lib/app/app_config_base.dart#L621-L682).
- `NotificationPermissionHelper` owns all `dreamic_` pref keys, migrates legacy keys, tracks denials/blocked requests, and auto-clears on grant. See [lib/notifications/notification_permission_helper.dart](lib/notifications/notification_permission_helper.dart#L20-L577).
- FCM token management moved into `NotificationService` with legacy key migration, token refresh listener, pre-logout cleanup, and app-level enable/disable. See [lib/notifications/notification_service.dart](lib/notifications/notification_service.dart#L120-L1760).
- New permission flow types (`NotificationInitResult`, `NotificationFlowResult`, `NotificationFlowConfig`, etc.) exist in [lib/notifications/notification_types.dart](lib/notifications/notification_types.dart#L7-L435).
- FCM code removed from `AuthServiceImpl`; `handleTokenChanges()` only logs the migration note. See [lib/data/repos/auth_service_impl.dart](lib/data/repos/auth_service_impl.dart#L143-L160).

### Potential Gaps / Divergences ⚠️
1) `NotificationService.initialize()` does not auto-wire auth or set a default `_onTokenChanged` callback. The plan called for auth resolution within `initialize()` (guarded) and default token sync wiring. Currently only `connectToAuthService()` handles it. See [lib/notifications/notification_service.dart](lib/notifications/notification_service.dart#L227-L318) and [lib/notifications/notification_service.dart](lib/notifications/notification_service.dart#L863-L938).
2) `connectToAuthService()` does not call `preLogoutCleanup()` on logout; it only logs. The plan expected automatic cleanup on logout. See [lib/notifications/notification_service.dart](lib/notifications/notification_service.dart#L888-L900).
3) Built-in dialog helpers exist both in `NotificationService` and in presentation helper file; the service does not use the presentation helper functions. This is redundant vs plan’s “presentation layer helpers” intent. See [lib/notifications/notification_service.dart](lib/notifications/notification_service.dart#L1340-L1470) and [lib/presentation/helpers/notification_permission_dialogs.dart](lib/presentation/helpers/notification_permission_dialogs.dart).
4) `NotificationService` only exposes some helper wrappers (counts/info), not methods like `shouldShowSettingsPrompt()` or `shouldRequestPermissions()`; those require direct `permissionHelper` access. If plan intended full wrapper parity, this is partial. See [lib/notifications/notification_service.dart](lib/notifications/notification_service.dart#L1160-L1230).
5) Web go-to-settings flow returns `NotificationFlowResult.openedSettings` even though `openNotificationSettings()` returns false on web, which is a semantics mismatch with “opened settings.” See [lib/notifications/notification_service.dart](lib/notifications/notification_service.dart#L1288-L1328) and [lib/notifications/notification_service.dart](lib/notifications/notification_service.dart#L740-L760).

---

## Next Scan Targets
- Verify docs updates for BREAKING CHANGE and config flags.
- Verify test coverage for new permission flow and helper migrations.
- Verify any remaining AuthServiceImpl references to deprecated FCM behavior.

---

## Docs & Tests Scan (Phase 2)

### Docs: Implemented ✅
- Deferred prompt + config flags are documented in NOTIFICATION_GUIDE/SETUP. See [docs/NOTIFICATION_GUIDE.md](docs/NOTIFICATION_GUIDE.md#L300-L350) and [docs/NOTIFICATION_SETUP.md](docs/NOTIFICATION_SETUP.md#L126-L190).

### Docs: Gaps / Inconsistencies ⚠️
1) DREAMIC_FEATURES_GUIDE still references `useFirebaseFCM` in `AuthServiceImpl` constructor examples, which no longer exists. This conflicts with the breaking change. See [docs/DREAMIC_FEATURES_GUIDE.md](docs/DREAMIC_FEATURES_GUIDE.md#L114-L150) and other occurrences (e.g. later snippets around `useFirebaseFCM`).
2) CHANGELOG has no mention of this plan’s breaking changes (FCM moved to `NotificationService`, `useFCMWeb` default false, `useFirebaseFCM` removed). The 0.3.0 section explicitly says “No breaking changes.” See [CHANGELOG.md](CHANGELOG.md#L286-L298).
3) NOTIFICATION_GUIDE “Automatic Auth Integration” claims logout unregisters token automatically, but `connectToAuthService()` does not call `preLogoutCleanup()` on logout (it only logs). See [docs/NOTIFICATION_GUIDE.md](docs/NOTIFICATION_GUIDE.md#L560-L590) vs [lib/notifications/notification_service.dart](lib/notifications/notification_service.dart#L888-L900).
4) Built-in dialog helpers file exists but is not referenced by `NotificationService` and is not exported in `dreamic.dart`. If intended as a public helper API, it may be unreachable via package exports. See [lib/presentation/helpers/notification_permission_dialogs.dart](lib/presentation/helpers/notification_permission_dialogs.dart) and [lib/dreamic.dart](lib/dreamic.dart#L1-L80).

Additional `useFirebaseFCM` references in docs:
- [docs/DREAMIC_FEATURES_GUIDE.md](docs/DREAMIC_FEATURES_GUIDE.md#L2290-L2315)
- [docs/DREAMIC_FEATURES_GUIDE.md](docs/DREAMIC_FEATURES_GUIDE.md#L2648-L2660)
- [docs/DREAMIC_FEATURES_GUIDE.md](docs/DREAMIC_FEATURES_GUIDE.md#L2738-L2750)

### Tests: Implemented ✅
- Unit tests exist for denial info serialization, settings prompt info, flow config, helper migration, and flow decision logic. See [test/notification_permission/notification_permission_flow_test.dart](test/notification_permission/notification_permission_flow_test.dart#L1-L120) and [test/notification_permission/notification_permission_helper_test.dart](test/notification_permission/notification_permission_helper_test.dart#L1-L220).
- Integration tests cover SharedPreferences persistence and legacy key migration. See [test/notification_permission/integration/notification_permission_integration_test.dart](test/notification_permission/integration/notification_permission_integration_test.dart#L1-L210).

### Tests: Potential Gaps ⚠️
- No direct tests for web-specific settings instructions or `openNotificationSettings()` returning false on web (behavior is implemented but not exercised).
- No tests for app-level notification toggle APIs (`enableNotifications`, `disableNotifications`, `isNotificationsEnabled`).

