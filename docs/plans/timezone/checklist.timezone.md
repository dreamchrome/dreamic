# DeviceService & Timezone Tracking - Implementation Checklist

This checklist tracks implementation progress for the DeviceService plan.
See [plan.timezone.md](./plan.timezone.md) for full details.

---

## Phase 1: Data Models & Interface

### 1.1 DeviceInfo Model
- [ ] Create `lib/data/models/device_info.dart`
- [ ] Define `DeviceInfo` class with all fields:
  - `deviceId`, `timezone`, `timezoneOffsetMinutes`
  - `lastActiveAt`, `fcmToken`, `fcmTokenUpdatedAt`
  - `createdAt`, `updatedAt`, `platform`, `appVersion`
  - Optional `deviceInfo` map (model, osVersion)
- [ ] Add JSON serialization (`fromJson`, `toJson`)
- [ ] Add `copyWith` method
- [ ] Export from models barrel file

### 1.2 DeviceServiceInt Interface
- [ ] Create `lib/data/repos/device_service_int.dart`
- [ ] Define interface with all methods:
  - `registerDevice()`
  - `updateTimezoneOrOffsetIfChanged()`
  - `getDeviceId()`
  - `getCurrentTimezone()`
  - `touchDevice()`
  - `updateFcmToken({required String? fcmToken})`
  - `unregisterDevice()`
  - `getMyDevices()`
- [ ] Add comprehensive dartdoc comments
- [ ] Export from repos barrel file

---

## Phase 2: Configuration

### 2.1 AppConfigBase Settings
- [ ] Add `deviceActionFunction` static field (default: `'deviceAction'`)
- [ ] Add throttle/debounce configuration fields:
  - `deviceTimezoneUnchangedSyncMinMinutes` (default: 2880)
  - `deviceTimezoneUnchangedSyncMaxMinutes` (default: 2880)
  - `deviceTimezoneChangeDebounceMinutes` (default: 10)
  - `deviceTouchThrottleMinutes` (default: 60)
- [ ] Add Remote Config key constants:
  - `dreamic_device_timezone_unchanged_sync_min_minutes`
  - `dreamic_device_timezone_unchanged_sync_max_minutes`
  - `dreamic_device_timezone_change_debounce_minutes`
  - `dreamic_device_touch_throttle_minutes`
- [ ] Wire up Remote Config fallback chain

---

## Phase 3: Core Implementation (DeviceServiceImpl)

### 3.1 Device ID Generation & Persistence
- [ ] Create `lib/data/repos/device_service_impl.dart`
- [ ] Implement `getDeviceId()`:
  - Generate UUIDv4 on first call
  - Persist to SharedPreferences (mobile/desktop)
  - Web: IndexedDB → localStorage → in-memory fallback
- [ ] Add SharedPreferences key constant for deviceId

### 3.2 Core Service Implementation
- [ ] Add private state fields:
  - `_cachedTimezone`, `_cachedOffsetMinutes`
  - `_lastServerSyncAt`, `_lastTouchAt`
- [ ] Implement `getCurrentTimezone()` using `FlutterTimezone`
- [ ] Implement `registerDevice()`:
  - Get deviceId, timezone, offset, platform, appVersion
  - Call backend callable with `action: 'register'`
  - Update cached values on success
  - Return `Either<RepositoryFailure, Unit>`
- [ ] Implement `updateTimezoneOrOffsetIfChanged()`:
  - Fast local check (no network if unchanged + throttled)
  - Apply change-debounce (10 min) when changed
  - Apply unchanged throttle (48h) when not changed
  - Call backend on actual update
  - Update cache and `_lastServerSyncAt`
- [ ] Implement `touchDevice()`:
  - Apply throttle (60 min default)
  - Call backend with `action: 'touch'`
  - Update `_lastTouchAt` on success
- [ ] Implement `updateFcmToken({required String? fcmToken})`:
  - Call backend with `action: 'updateToken'`
  - Handle null token (explicit clear)
- [ ] Implement `unregisterDevice()`:
  - Call backend with `action: 'unregister'`
  - Best-effort, don't block on failure
- [ ] Implement `getMyDevices()`:
  - Call backend with `action: 'getMyDevices'`
  - Parse response into `List<DeviceInfo>`

### 3.3 Dependency Injection Setup
- [ ] Register `DeviceServiceInt` in GetIt
- [ ] Add mock implementation for testing (`DeviceServiceMock`)

---

## Phase 4: Auth & Lifecycle Integration

### 4.1 AuthService Integration
- [ ] Implement `connectToAuthService()` method:
  - Accept optional `authService` parameter (resolve from GetIt if null)
  - Accept optional callback overrides
- [ ] Wire `addOnAuthenticatedCallback` → `registerDevice()`
- [ ] Wire `addOnRefreshedCallback` → `registerDevice()`
- [ ] Wire `addOnAboutToLogOutCallback` → `unregisterDevice()`
- [ ] Make repeated `connectToAuthService()` calls idempotent

### 4.2 AppLifecycleService Integration
- [ ] Wire resume stream → `updateTimezoneOrOffsetIfChanged()`
- [ ] Wire resume stream → `touchDevice()` (with throttle)
- [ ] Ensure lifecycle wiring is automatic (no consuming-app setup)

### 4.3 NotificationService Integration
- [ ] Update NotificationService to call `DeviceService.updateFcmToken()` on token changes
- [ ] Remove any direct backend token writes from NotificationService
- [ ] Document the integration pattern in code comments

---

## Phase 5: Offline & Pending Payload Handling

### 5.1 Pending Payload Persistence
- [ ] Define pending payload structure:
  - `deviceId` (required)
  - `timezone`, `timezoneOffsetMinutes`, `fcmToken` (optional)
  - `touch` (bool), `pendingUpdatedAt`, `lastAttemptAt`
- [ ] Implement local storage for pending payload:
  - SharedPreferences (mobile/desktop)
  - IndexedDB → localStorage → in-memory (web)
- [ ] Implement merge logic (last-write-wins per field, sticky `touch`)

### 5.2 Flush & Retry Logic
- [ ] Implement flush on lifecycle triggers (auth, resume, token changes)
- [ ] Implement backoff (10-15 min between attempts)
- [ ] Bypass backoff when timezone/offset/token changed
- [ ] Clear pending only on successful backend ack
- [ ] Handle auth precondition (store pending if not authenticated)

---

## Phase 6: Backend Scaffolding (Firebase Functions)

### 6.1 Directory Structure
- [ ] Create `scaffolding/firebase_functions/device/` directory
- [ ] Create `index.ts` barrel export

### 6.2 Device Callable
- [ ] Create `device_callable.ts`
- [ ] Implement `deviceAction` callable with actions:
  - `register`: validate inputs, upsert device doc, return change flags
  - `touch`: update `lastActiveAt` (merge)
  - `updateToken`: update `fcmToken`, run uniqueness cleanup
  - `unregister`: delete device doc
  - `getMyDevices`: query user's devices, return list
- [ ] Add input validation (deviceId required, timezone validation)
- [ ] Add `@packageVersion` header comment

### 6.3 Timezone Utilities
- [ ] Create `timezone_utils.ts`
- [ ] Implement `isValidIanaTimezone()` (using Luxon or Intl)
- [ ] Implement `getOffsetMinutesAtUtcInstant()`
- [ ] Implement `getLocalMinutesOfDay()`
- [ ] Add Luxon as recommended dependency

### 6.4 Time Window Queries
- [ ] Create `device_time_queries.ts`
- [ ] Define `LocalTimeTarget` and `LocalTimeWindowQueryOptions` types
- [ ] Implement `queryDeviceCandidatesByLocalTime()`:
  - Calculate offset ranges for target time
  - Handle midnight wrap (1-2 ranges)
  - Apply `offsetQueryBufferMinutes` for DST safety
- [ ] Implement `isNowInLocalTimeWindow()`:
  - Authoritative check using IANA timezone
  - Circular distance for midnight wrap

### 6.5 Optional Scheduled/Trigger Functions
- [ ] Create `device_scheduled.ts` (optional template):
  - `sendMorningNotifications` example
  - `cleanupStaleDevices` example
- [ ] Create `device_triggers.ts` (optional template):
  - `onDeviceTimezoneChange` example

### 6.6 Scaffolding Documentation
- [ ] Create `scaffolding/firebase_functions/device/README.md`
- [ ] Document setup steps (copy, export, install luxon, deploy)
- [ ] Document required Firestore indexes
- [ ] Create `scaffolding/firebase_functions/device/CHANGELOG.md`

---

## Phase 7: Documentation

### 7.1 User Documentation
- [ ] Create `docs/device_service.md`
- [ ] Include sections:
  - Overview (what and why)
  - Setup (initialization, integration)
  - Usage Examples
  - Firestore Structure
  - Integration with NotificationService
  - Backend Integration (Cloud Functions)
  - Privacy Considerations
  - Troubleshooting

### 7.2 Code Documentation
- [ ] Add comprehensive dartdoc to `DeviceServiceInt`
- [ ] Add implementation notes to `DeviceServiceImpl`
- [ ] Add example usage in class-level docs

---

## Phase 8: Testing

### 8.1 Unit Tests (Flutter)
- [ ] Test `getDeviceId()` generation and persistence
- [ ] Test `updateTimezoneOrOffsetIfChanged()` throttling logic
- [ ] Test `touchDevice()` throttling
- [ ] Test pending payload merge logic
- [ ] Test offline → online flush behavior

### 8.2 Unit Tests (Backend)
- [ ] Test `isValidIanaTimezone()` with valid/invalid inputs
- [ ] Test `getLocalMinutesOfDay()` accuracy
- [ ] Test `isNowInLocalTimeWindow()`:
  - Standard cases
  - Midnight wrap
  - DST transitions
  - Half-hour offsets (e.g., India, Nepal)
- [ ] Test `queryDeviceCandidatesByLocalTime()` offset range calculation

### 8.3 Integration/Smoke Tests
- [ ] Test first login flow (register device)
- [ ] Test token granted later flow
- [ ] Test token rotation flow
- [ ] Test logout offline scenario
- [ ] Test account switch on same device

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
