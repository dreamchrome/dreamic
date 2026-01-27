# DeviceService Firebase Functions Scaffolding

Firebase Functions scaffolding for the dreamic `DeviceService`. This provides the backend callable and utilities for device registration, timezone tracking, and time-based notification scheduling.

**Package Version Compatibility:** dreamic ^0.4.0

## Quick Start

### 1. Copy Files

Copy this entire `device/` folder to your Firebase Functions `src/` directory:

```
your-project/
└── functions/
    └── src/
        └── device/           <- Copy here
            ├── index.ts
            ├── device_callable.ts
            ├── device_time_queries.ts
            ├── device_scheduled.ts
            ├── device_triggers.ts
            ├── timezone_utils.ts
            ├── README.md
            └── CHANGELOG.md
```

### 2. Install Dependencies

```bash
cd functions
npm install luxon
npm install -D @types/luxon
```

### 3. Export Functions

Add to your main `functions/src/index.ts`:

```typescript
// Required: Client-facing callable
export * from "./device";

// Optional: Scheduled functions (uncomment if needed)
// export { sendMorningNotifications, cleanupStaleDevices } from "./device/device_scheduled";

// Optional: Firestore triggers (uncomment if needed)
// export { onDeviceTimezoneChange, onDeviceCreated } from "./device/device_triggers";
```

### 4. Create Firestore Indexes

Create the required indexes in `firestore.indexes.json`:

```json
{
  "indexes": [],
  "fieldOverrides": [
    {
      "collectionGroup": "devices",
      "fieldPath": "fcmToken",
      "indexes": [
        { "order": "ASCENDING", "queryScope": "COLLECTION_GROUP" }
      ]
    },
    {
      "collectionGroup": "devices",
      "fieldPath": "timezoneOffsetMinutes",
      "indexes": [
        { "order": "ASCENDING", "queryScope": "COLLECTION_GROUP" }
      ]
    },
    {
      "collectionGroup": "devices",
      "fieldPath": "lastActiveAt",
      "indexes": [
        { "order": "ASCENDING", "queryScope": "COLLECTION_GROUP" },
        { "order": "DESCENDING", "queryScope": "COLLECTION_GROUP" }
      ]
    }
  ]
}
```

For scheduled notification queries, you may also need a composite index:

```json
{
  "collectionGroup": "devices",
  "queryScope": "COLLECTION_GROUP",
  "fields": [
    { "fieldPath": "timezoneOffsetMinutes", "order": "ASCENDING" },
    { "fieldPath": "lastActiveAt", "order": "ASCENDING" }
  ]
}
```

### 5. Configure Firestore Rules

Add to your `firestore.rules`:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Device documents are managed by Firebase Functions only
    // Deny all direct client writes
    match /users/{userId}/devices/{deviceId} {
      // Allow reads if you want clients to list their own devices
      // Otherwise, use the getMyDevices callable
      allow read: if request.auth != null && request.auth.uid == userId;

      // Deny all client writes - use Functions only
      allow write: if false;
    }
  }
}
```

### 6. Deploy

```bash
firebase deploy --only functions
```

## Files Overview

| File | Description |
|------|-------------|
| `index.ts` | Barrel export for the module |
| `device_callable.ts` | **Required.** Client-facing `deviceAction` callable |
| `timezone_utils.ts` | **Required.** IANA timezone validation and utilities |
| `device_time_queries.ts` | Time-window queries for scheduled notifications |
| `device_scheduled.ts` | *Optional.* Example scheduled functions |
| `device_triggers.ts` | *Optional.* Example Firestore triggers |

## Client-Facing Callable

The `deviceAction` callable handles all device operations:

### Actions

| Action | Description | Required Fields |
|--------|-------------|-----------------|
| `register` | Create/update device | `deviceId`, `timezone`, `timezoneOffsetMinutes`, `platform`, `appVersion` |
| `touch` | Update lastActiveAt | `deviceId` |
| `updateToken` | Update FCM token | `deviceId`, `fcmToken` (nullable) |
| `unregister` | Delete device | `deviceId` |
| `getMyDevices` | List user's devices | `deviceId` |

### Example Usage (Flutter)

```dart
final callable = FirebaseFunctions.instance.httpsCallable('deviceAction');

// Register device
await callable.call({
  'action': 'register',
  'deviceId': '550e8400-e29b-41d4-a716-446655440000',
  'timezone': 'America/New_York',
  'timezoneOffsetMinutes': -300,
  'platform': 'ios',
  'appVersion': '1.0.0',
});

// Update FCM token
await callable.call({
  'action': 'updateToken',
  'deviceId': '550e8400-e29b-41d4-a716-446655440000',
  'fcmToken': 'your-fcm-token-here',
});
```

## Time-Window Queries

For scheduled notifications at specific local times (e.g., "9 AM local"):

```typescript
import { getDevicesInLocalTimeWindow } from "./device";

// Find devices where it's 9:00 AM +/- 15 minutes
const devices = await getDevicesInLocalTimeWindow(
  admin.firestore(),
  { hour: 9, minute: 0 },
  {
    windowMinutes: 15,
    requireToken: true,
    activeWithinDays: 60,
  }
);

// Send notifications
for (const device of devices) {
  await admin.messaging().send({
    token: device.fcmToken!,
    notification: { title: "Good morning!" },
  });
}
```

## DST Safety

The time-window queries use a two-stage approach:

1. **Candidate Query**: Uses cached `timezoneOffsetMinutes` (fast, indexed)
2. **Authoritative Filter**: Uses IANA `timezone` string (accurate, DST-safe)

This ensures notifications are sent at the correct time even when:
- DST transitions occur
- The app wasn't opened near a DST transition
- Cached offsets are stale

## Security Considerations

1. **Authentication Required**: All operations require Firebase Authentication
2. **User Isolation**: Users can only access their own devices (enforced by uid)
3. **Input Validation**: All inputs are validated and sanitized
4. **App Check**: Enable `enforceAppCheck: true` in production for additional security

## Customization

### Changing the Function Name

If you need a different function name, update:

1. The export in `device_callable.ts`
2. The `AppConfigBase.deviceActionFunction` in your Flutter app

### Adding Custom Fields

To add custom device metadata:

1. Add fields to the `deviceInfo` object in `device_callable.ts`
2. Update the sanitization logic in `sanitizeDeviceInfo()`
3. Update the Flutter `DeviceServiceImpl` to send the new fields

## Troubleshooting

### "Missing index" errors

Run:
```bash
firebase firestore:indexes
```

And create any missing indexes shown in the error message.

### Token uniqueness cleanup fails

Ensure you have a collection group index on `devices.fcmToken`.

### Timezone validation fails

The timezone must be a valid IANA timezone identifier (e.g., `America/New_York`, not `EST`).
Valid timezones can be found at: https://en.wikipedia.org/wiki/List_of_tz_database_time_zones

## Testing

The scaffolding includes comprehensive test files for the timezone utilities and time-window queries. These tests are critical for hospital-grade reliability.

### Test Files

| File | Description |
|------|-------------|
| `timezone_utils.test.ts` | Tests for timezone validation, offset calculation, DST handling |
| `device_time_queries.test.ts` | Tests for `isNowInLocalTimeWindow`, midnight wrap, grouping functions |

### Running Tests

1. **Install test dependencies**:
```bash
cd functions
npm install -D mocha chai @types/mocha @types/chai ts-node
```

2. **Add test script to package.json**:
```json
{
  "scripts": {
    "test": "mocha --require ts-node/register 'src/**/*.test.ts'"
  }
}
```

3. **Run tests**:
```bash
npm test
```

4. **Run specific test file**:
```bash
npm test -- --grep "timezone_utils"
npm test -- --grep "device_time_queries"
```

### Test Coverage

The tests cover:
- **IANA Timezone Validation**: Valid/invalid timezones, edge cases
- **Offset Calculation**: DST transitions, half-hour offsets (India, Nepal), extreme offsets
- **Local Time Calculation**: Day boundary crossing, minute-level accuracy
- **Time Window Logic**: Standard cases, midnight wrap-around, DST safety
- **Offset Range Calculation**: Single and split ranges for Firestore queries
- **Device Grouping**: Most-recent device selection, all-devices grouping

### Critical Tests for Hospital Use

Pay special attention to these tests when validating for medical applications:
- DST transition tests (spring forward, fall back)
- Midnight wrap-around tests
- Half-hour offset tests (India UTC+5:30, Nepal UTC+5:45)
- Invalid timezone handling (should fail gracefully, never crash)

## Upgrade Notes

When upgrading the dreamic package:

1. Check the `CHANGELOG.md` in this folder for breaking changes
2. Compare `@packageVersion` headers in each file
3. Re-copy modified files from the new scaffolding
4. Test thoroughly before deploying

## Support

For issues with this scaffolding, check:
- [dreamic GitHub Issues](https://github.com/your-org/dreamic/issues)
- The `@packageVersion` header in each file for version compatibility
