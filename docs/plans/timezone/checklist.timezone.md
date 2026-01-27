# DeviceService & Timezone Tracking - Implementation Checklist

This checklist tracks implementation progress for the DeviceService plan.
See [plan.timezone.md](./plan.timezone.md) for full details.

---

## Phase 1: Data Models & Interface ✅

### 1.1 DeviceInfo Model ✅
- [x] Create `lib/data/models/device_info.dart`
- [x] Define `DeviceInfo` class with all fields:
  - `deviceId`, `timezone`, `timezoneOffsetMinutes`
  - `lastActiveAt`, `fcmToken`, `fcmTokenUpdatedAt`
  - `createdAt`, `updatedAt`, `platform`, `appVersion`
  - Optional `deviceInfo` map (model, osVersion)
- [x] Add JSON serialization (`fromJson`, `toJson`)
- [x] Add `copyWith` method
- [x] Export from models barrel file
- [x] Also created `DevicePlatform` enum with safe serialization in `lib/data/models/device_platform.dart`
- [x] Also created `DeviceMetadata` class for optional device metadata

### 1.2 DeviceServiceInt Interface ✅
- [x] Create `lib/data/repos/device_service_int.dart`
- [x] Define interface with all methods:
  - `registerDevice()`
  - `updateTimezoneOrOffsetIfChanged()`
  - `getDeviceId()`
  - `getCurrentTimezone()`
  - `touchDevice()`
  - `updateFcmToken({required String? fcmToken})`
  - `unregisterDevice()`
  - `getMyDevices()`
  - `connectToAuthService()` (for lifecycle wiring)
- [x] Add comprehensive dartdoc comments
- [x] Export from repos barrel file

---

## Phase 2: Configuration ✅

### 2.1 AppConfigBase Settings ✅
- [x] Add `deviceActionFunction` static field (default: `'deviceAction'`)
- [x] Add throttle/debounce configuration fields:
  - `deviceTimezoneUnchangedSyncMinMinutes` (default: 2880)
  - `deviceTimezoneUnchangedSyncMaxMinutes` (default: 2880)
  - `deviceTimezoneChangeDebounceMinutes` (default: 10)
  - `deviceTouchThrottleMinutes` (default: 60)
- [x] Add Remote Config key constants:
  - `dreamic_device_timezone_unchanged_sync_min_minutes`
  - `dreamic_device_timezone_unchanged_sync_max_minutes`
  - `dreamic_device_timezone_change_debounce_minutes`
  - `dreamic_device_touch_throttle_minutes`
- [x] Wire up Remote Config fallback chain (Environment → Remote Config → Default)

---

## Phase 3: Core Implementation (DeviceServiceImpl) ✅

### 3.1 Device ID Generation & Persistence ✅
- [x] Create `lib/data/repos/device_service_impl.dart`
- [x] Implement `getDeviceId()`:
  - Generate UUIDv4 on first call
  - Persist to SharedPreferences (mobile/desktop)
  - Web: SharedPreferences with in-memory fallback if storage fails
- [x] Add SharedPreferences key constant for deviceId (`_kDeviceIdKey`)
- [x] Added `uuid: ^4.5.1` dependency to pubspec.yaml

### 3.2 Core Service Implementation ✅
- [x] Add private state fields:
  - `_cachedTimezone`, `_cachedOffsetMinutes`
  - `_lastServerSyncAt`, `_lastTouchAt`
- [x] Implement `getCurrentTimezone()` using `FlutterTimezone`
- [x] Implement `registerDevice()`:
  - Get deviceId, timezone, offset, platform, appVersion
  - Call backend callable with `action: 'register'`
  - Update cached values on success
  - Return `Either<RepositoryFailure, Unit>`
- [x] Implement `updateTimezoneOrOffsetIfChanged()`:
  - Fast local check (no network if unchanged + throttled)
  - Apply change-debounce (10 min) when changed
  - Apply unchanged throttle (48h) when not changed
  - Call backend on actual update
  - Update cache and `_lastServerSyncAt`
- [x] Implement `touchDevice()`:
  - Apply throttle (60 min default)
  - Call backend with `action: 'touch'`
  - Update `_lastTouchAt` on success
- [x] Implement `updateFcmToken({required String? fcmToken})`:
  - Call backend with `action: 'updateToken'`
  - Handle null token (explicit clear)
- [x] Implement `unregisterDevice()`:
  - Call backend with `action: 'unregister'`
  - Best-effort, don't block on failure
- [x] Implement `getMyDevices()`:
  - Call backend with `action: 'getMyDevices'`
  - Parse response into `List<DeviceInfo>`
- [x] Implement `connectToAuthService()`:
  - Accept optional `authService` parameter (resolve from GetIt if null)
  - Accept optional callback overrides
  - Wire authentication/refresh/logout callbacks
  - Make repeated calls idempotent
- [x] Export from `dreamic.dart` barrel file

### 3.3 Dependency Injection Setup
- [x] DI registration is consuming-app responsibility (DeviceServiceImpl is exported)
- [ ] Add mock implementation for testing (`DeviceServiceMock`) - deferred to Phase 8

---

## Phase 4: Auth & Lifecycle Integration ✅

### 4.1 AuthService Integration ✅
- [x] Implement `connectToAuthService()` method:
  - Accept optional `authService` parameter (resolve from GetIt if null)
  - Accept optional callback overrides
- [x] Wire `addOnAuthenticatedCallback` → `registerDevice()`
- [x] Wire `addOnRefreshedCallback` → `registerDevice()`
- [x] Wire `addOnAboutToLogOutCallback` → `unregisterDevice()`
- [x] Make repeated `connectToAuthService()` calls idempotent
- Note: Implemented as part of Phase 3 in `DeviceServiceImpl`

### 4.2 AppLifecycleService Integration ✅
- [x] Wire resume stream → `updateTimezoneOrOffsetIfChanged()`
- [x] Wire resume stream → `touchDevice()` (with throttle)
- [x] Ensure lifecycle wiring is automatic (no consuming-app setup)
- Note: Implemented in `DeviceServiceImpl._connectToLifecycleService()`, called automatically from `connectToAuthService()`

### 4.3 NotificationService Integration ✅
- [x] Update NotificationService to call `DeviceService.updateFcmToken()` on token changes
- [x] Remove any direct backend token writes from NotificationService (fallback only when DeviceService not available)
- [x] Document the integration pattern in code comments
- Note: `_defaultTokenChangedCallback` now auto-detects DeviceServiceInt in GetIt and delegates to it

---

## Phase 5: Offline & Pending Payload Handling ✅

### 5.1 Pending Payload Persistence ✅
- [x] Define pending payload structure:
  - `deviceId` (required)
  - `timezone`, `timezoneOffsetMinutes`, `fcmToken` (optional)
  - `touch` (bool), `pendingUpdatedAt`, `lastAttemptAt`
  - `hasChangedFields` (bool) for backoff bypass logic
- [x] Implement local storage for pending payload:
  - SharedPreferences (mobile/desktop/web - via shared_preferences package)
  - Uses JSON serialization for storage
- [x] Implement merge logic (last-write-wins per field, sticky `touch`, sticky `hasChangedFields`)
- Note: Implemented as `_PendingDevicePayload` internal class in `device_service_impl.dart`

### 5.2 Flush & Retry Logic ✅
- [x] Implement flush on lifecycle triggers (auth, resume, token changes)
  - Flush on authentication callback (with bypass backoff)
  - Flush on touchDevice (when not throttled and authenticated)
  - Flush on updateTimezoneOrOffsetIfChanged (when skipping due to throttle)
- [x] Implement backoff (15 min default between attempts)
  - Added `devicePendingBackoffMinutes` config (Remote Config: `dreamic_device_pending_backoff_minutes`)
- [x] Bypass backoff when timezone/offset/token changed (via `hasChangedFields` flag)
- [x] Clear pending only on successful backend ack
- [x] Handle auth precondition (store pending if not authenticated)
  - All service methods now check `_isUserAuthenticated()` before backend calls
  - Store in pending payload when not authenticated, flush on auth callback

---

## Phase 6: Backend Scaffolding (Firebase Functions) ✅

### 6.1 Directory Structure ✅
- [x] Create `scaffolding/firebase_functions/device/` directory
- [x] Create `index.ts` barrel export

### 6.2 Device Callable ✅
- [x] Create `device_callable.ts`
- [x] Implement `deviceAction` callable with actions:
  - `register`: validate inputs, upsert device doc, return change flags
  - `touch`: update `lastActiveAt` (merge)
  - `updateToken`: update `fcmToken`, run uniqueness cleanup
  - `unregister`: delete device doc
  - `getMyDevices`: query user's devices, return list
- [x] Add input validation (deviceId required, timezone validation)
- [x] Add `@packageVersion` header comment

### 6.3 Timezone Utilities ✅
- [x] Create `timezone_utils.ts`
- [x] Implement `isValidIanaTimezone()` (using Luxon)
- [x] Implement `getOffsetMinutesAtUtcInstant()`
- [x] Implement `getLocalMinutesOfDay()`
- [x] Add Luxon as recommended dependency
- [x] Also implemented: `validateOffsetMinutes()`, `formatOffset()`, `getLocalHour()`, `isHourInTimezone()`, `localTimeToUtc()`

### 6.4 Time Window Queries ✅
- [x] Create `device_time_queries.ts`
- [x] Define `LocalTimeTarget` and `LocalTimeWindowQueryOptions` types
- [x] Implement `queryDeviceCandidatesByLocalTime()`:
  - Calculate offset ranges for target time
  - Handle midnight wrap (1-2 ranges)
  - Apply `offsetQueryBufferMinutes` for DST safety
- [x] Implement `isNowInLocalTimeWindow()`:
  - Authoritative check using IANA timezone
  - Circular distance for midnight wrap
- [x] Also implemented: `getDevicesInLocalTimeWindow()`, `groupByUserMostRecentDevice()`, `groupByUserAllDevices()`

### 6.5 Optional Scheduled/Trigger Functions ✅
- [x] Create `device_scheduled.ts` (optional template):
  - `sendMorningNotifications` example
  - `cleanupStaleDevices` example
  - `weeklyDeviceReport` example
- [x] Create `device_triggers.ts` (optional template):
  - `onDeviceTimezoneChange` example
  - `onDeviceCreated` example
  - `onDeviceDeleted` example
  - `onDeviceTokenChange` example

### 6.6 Scaffolding Documentation ✅
- [x] Create `scaffolding/firebase_functions/device/README.md`
- [x] Document setup steps (copy, export, install luxon, deploy)
- [x] Document required Firestore indexes
- [x] Create `scaffolding/firebase_functions/device/CHANGELOG.md`

---

## Phase 7: Documentation ✅

### 7.1 User Documentation ✅
- [x] Create `docs/DEVICE_SERVICE_GUIDE.md`
- [x] Include sections:
  - Overview (what and why)
  - Setup (initialization, integration)
  - Usage Examples
  - Firestore Structure
  - Integration with NotificationService
  - Backend Integration (Cloud Functions)
  - Privacy Considerations
  - Troubleshooting

### 7.2 Code Documentation ✅
- [x] Add comprehensive dartdoc to `DeviceServiceInt` (completed in Phase 1)
- [x] Add implementation notes to `DeviceServiceImpl`
- [x] Add example usage in class-level docs

---

## Phase 8: Testing ✅

### 8.1 Unit Tests (Flutter) ✅
- [x] Test `getDeviceId()` generation and persistence
  - File: `test/data/device_service/device_service_integration_test.dart`
- [x] Test `updateTimezoneOrOffsetIfChanged()` throttling logic
  - File: `test/data/device_service/throttling_logic_test.dart`
- [x] Test `touchDevice()` throttling
  - File: `test/data/device_service/throttling_logic_test.dart`
- [x] Test pending payload merge logic
  - File: `test/data/device_service/pending_payload_test.dart`
- [x] Test offline → online flush behavior
  - File: `test/data/device_service/device_service_integration_test.dart`
- [x] Additional: DeviceInfo model tests
  - File: `test/data/device_service/device_info_test.dart`
- [x] Additional: DevicePlatform enum tests
  - File: `test/data/device_service/device_platform_test.dart`

### 8.2 Unit Tests (Backend) ✅
- [x] Test `isValidIanaTimezone()` with valid/invalid inputs
  - File: `scaffolding/firebase_functions/device/timezone_utils.test.ts`
- [x] Test `getLocalMinutesOfDay()` accuracy
  - File: `scaffolding/firebase_functions/device/timezone_utils.test.ts`
- [x] Test `isNowInLocalTimeWindow()`:
  - Standard cases ✅
  - Midnight wrap ✅
  - DST transitions ✅
  - Half-hour offsets (e.g., India, Nepal) ✅
  - File: `scaffolding/firebase_functions/device/device_time_queries.test.ts`
- [x] Test offset range calculation
  - File: `scaffolding/firebase_functions/device/device_time_queries.test.ts`
- Note: Backend tests require `npm install -D mocha chai @types/mocha @types/chai ts-node`

### 8.3 Integration/Smoke Tests ✅
- [x] Test first login flow (register device)
- [x] Test token granted later flow
- [x] Test token rotation flow
- [x] Test logout offline scenario
- [x] Test account switch on same device
- [x] Test timezone change detection (travel)
- [x] Test DST offset change detection
- [x] Test error recovery with retry
- [x] Test concurrent flush handling
- File: `test/data/device_service/device_service_integration_test.dart`
- Note: Uses mock implementation; true integration tests require Firebase Emulator Suite

---

## Phase 9: Cleanup & Migration

### 9.1 Migration from Current Implementation
- [ ] Keep existing timezone passing in auth callables (for redundancy)
- [ ] Add `registerDevice()` call in parallel with existing flows
- [ ] Deprecate old timezone SharedPreferences storage (with warning)
- [ ] Plan removal of deprecated code for future version

### 9.2 Final Verification
- [ ] Verify success criteria:
  - [ ] Device timezone accurately tracked in Firestore
  - [ ] Timezone updates on travel
  - [ ] Multi-device users have separate records
  - [ ] Backend can query by timezone
  - [ ] Works independently of notification permissions
  - [ ] Minimal battery/network impact

---

## Notes

- **Phase 1-3**: Can be developed and tested locally with mocks
- **Phase 4**: Requires existing AuthService and lifecycle infrastructure
- **Phase 5**: Can be deferred if offline support isn't critical for v1
- **Phase 6**: Required before any integration testing with real backend
- **Phase 7-8**: Should be done alongside or immediately after each phase
- **Phase 9**: Only after all other phases are stable

---

## Dependencies to Add

```yaml
dependencies:
  uuid: ^4.0.0              # For deviceId generation
  flutter_timezone: ^1.0.8  # Already in use
  device_info_plus: ^10.0.0 # Optional, for device metadata
```

```bash
# Backend (consuming app functions)
npm install luxon
npm install -D @types/luxon
```
