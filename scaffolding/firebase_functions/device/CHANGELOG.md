# DeviceService Scaffolding Changelog

All notable changes to the DeviceService Firebase Functions scaffolding are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [0.4.0] - 2024-XX-XX

### Added

- Initial release of DeviceService Firebase Functions scaffolding
- `device_callable.ts`: Unified `deviceAction` callable with actions:
  - `register`: Create/update device with timezone, platform, version
  - `touch`: Update lastActiveAt timestamp
  - `updateToken`: Update FCM token with uniqueness cleanup
  - `unregister`: Delete device document
  - `getMyDevices`: Retrieve user's devices
- `timezone_utils.ts`: DST-safe timezone utilities:
  - `isValidIanaTimezone()`: IANA timezone validation
  - `getOffsetMinutesAtUtcInstant()`: Compute offset at specific instant
  - `getLocalMinutesOfDay()`: Convert UTC to local minutes-of-day
  - `validateOffsetMinutes()`: Validate offset range
  - Additional helpers for local time conversion
- `device_time_queries.ts`: Time-window query utilities:
  - `queryDeviceCandidatesByLocalTime()`: Efficient Firestore query
  - `isNowInLocalTimeWindow()`: Authoritative DST-safe check
  - `getDevicesInLocalTimeWindow()`: Combined query + filter
  - `groupByUserMostRecentDevice()`: Delivery pattern helper
  - `groupByUserAllDevices()`: Delivery pattern helper
- `device_scheduled.ts`: Optional scheduled function templates:
  - `sendMorningNotifications`: 9 AM local time example
  - `cleanupStaleDevices`: 90-day stale device cleanup
  - `weeklyDeviceReport`: Analytics report example
- `device_triggers.ts`: Optional Firestore trigger templates:
  - `onDeviceTimezoneChange`: Log timezone changes
  - `onDeviceCreated`: Handle new device registration
  - `onDeviceDeleted`: Handle device unregistration
  - `onDeviceTokenChange`: Log FCM token changes
- `index.ts`: Barrel export with utilities and types
- `README.md`: Comprehensive setup and usage documentation
- `CHANGELOG.md`: This file

### Security

- All callable operations require Firebase Authentication
- Input validation prevents injection attacks
- UUIDv4 validation for device IDs
- IANA timezone validation using Luxon
- Timezone offset range validation (UTC-14 to UTC+14)
- FCM token length limits
- Device info sanitization

### Notes

- Requires `luxon` package for timezone handling
- Requires Firestore collection group indexes (see README.md)
- Compatible with dreamic ^0.4.0

---

## Upgrade Guide

### From Pre-Scaffolding

If you were manually implementing DeviceService backend code:

1. Back up your existing implementation
2. Compare your code with the scaffolding
3. Migrate custom logic to the scaffolding structure
4. Update Firestore indexes as documented
5. Test thoroughly before deploying

### Version Compatibility

| Scaffolding Version | dreamic Package Version |
|---------------------|------------------------|
| 0.4.0               | ^0.4.0                 |

### Breaking Changes Policy

We follow semantic versioning for the scaffolding:

- **Patch** (0.4.x): Bug fixes, documentation updates
- **Minor** (0.x.0): New features, backward-compatible changes
- **Major** (x.0.0): Breaking changes requiring code updates

When upgrading, always check this changelog and the `@packageVersion` headers in each file.
