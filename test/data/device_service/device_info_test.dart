import 'package:flutter_test/flutter_test.dart';
import 'package:dreamic/data/models/device_info.dart';
import 'package:dreamic/data/models/device_platform.dart';

/// Tests for the DeviceInfo model used by DeviceService.
///
/// These tests verify:
/// - JSON serialization/deserialization
/// - Handling of various timestamp formats (Firestore, ISO 8601, milliseconds)
/// - Platform enum handling with unknown values
/// - copyWith functionality
/// - Equality and hashCode
void main() {
  group('DeviceInfo JSON Serialization', () {
    test('serializes all fields correctly', () {
      final device = DeviceInfo(
        deviceId: '550e8400-e29b-41d4-a716-446655440000',
        timezone: 'America/New_York',
        timezoneOffsetMinutes: -300,
        lastActiveAt: DateTime(2024, 1, 15, 10, 30),
        fcmToken: 'test-fcm-token-abc123',
        fcmTokenUpdatedAt: DateTime(2024, 1, 15, 10, 0),
        createdAt: DateTime(2024, 1, 1, 0, 0),
        updatedAt: DateTime(2024, 1, 15, 10, 30),
        platform: DevicePlatform.ios,
        appVersion: '1.2.3',
        deviceInfo: const DeviceMetadata(
          model: 'iPhone 14 Pro',
          osVersion: 'iOS 17.2',
        ),
      );

      final json = device.toJson();

      expect(json['deviceId'], '550e8400-e29b-41d4-a716-446655440000');
      expect(json['timezone'], 'America/New_York');
      expect(json['timezoneOffsetMinutes'], -300);
      expect(json['fcmToken'], 'test-fcm-token-abc123');
      expect(json['platform'], 'ios');
      expect(json['appVersion'], '1.2.3');
      expect(json['deviceInfo'], isNotNull);
      expect(json['deviceInfo']['model'], 'iPhone 14 Pro');
      expect(json['deviceInfo']['osVersion'], 'iOS 17.2');
    });

    test('deserializes from JSON with all fields', () {
      final json = {
        'deviceId': '550e8400-e29b-41d4-a716-446655440000',
        'timezone': 'America/New_York',
        'timezoneOffsetMinutes': -300,
        'lastActiveAt': DateTime(2024, 1, 15, 10, 30).millisecondsSinceEpoch,
        'fcmToken': 'test-fcm-token-abc123',
        'fcmTokenUpdatedAt': DateTime(2024, 1, 15, 10, 0).millisecondsSinceEpoch,
        'createdAt': DateTime(2024, 1, 1, 0, 0).millisecondsSinceEpoch,
        'updatedAt': DateTime(2024, 1, 15, 10, 30).millisecondsSinceEpoch,
        'platform': 'ios',
        'appVersion': '1.2.3',
        'deviceInfo': {
          'model': 'iPhone 14 Pro',
          'osVersion': 'iOS 17.2',
        },
      };

      final device = DeviceInfo.fromJson(json);

      expect(device.deviceId, '550e8400-e29b-41d4-a716-446655440000');
      expect(device.timezone, 'America/New_York');
      expect(device.timezoneOffsetMinutes, -300);
      expect(device.fcmToken, 'test-fcm-token-abc123');
      expect(device.platform, DevicePlatform.ios);
      expect(device.appVersion, '1.2.3');
      expect(device.deviceInfo?.model, 'iPhone 14 Pro');
      expect(device.deviceInfo?.osVersion, 'iOS 17.2');
    });

    test('handles null optional fields', () {
      final json = {
        'deviceId': '550e8400-e29b-41d4-a716-446655440000',
        'timezone': 'America/New_York',
        'timezoneOffsetMinutes': -300,
        // All optional fields missing
      };

      final device = DeviceInfo.fromJson(json);

      expect(device.deviceId, '550e8400-e29b-41d4-a716-446655440000');
      expect(device.timezone, 'America/New_York');
      expect(device.timezoneOffsetMinutes, -300);
      expect(device.lastActiveAt, isNull);
      expect(device.fcmToken, isNull);
      expect(device.fcmTokenUpdatedAt, isNull);
      expect(device.createdAt, isNull);
      expect(device.updatedAt, isNull);
      expect(device.platform, isNull);
      expect(device.appVersion, isNull);
      expect(device.deviceInfo, isNull);
    });

    test('roundtrip serialization preserves all data', () {
      final original = DeviceInfo(
        deviceId: '550e8400-e29b-41d4-a716-446655440000',
        timezone: 'Europe/London',
        timezoneOffsetMinutes: 0,
        lastActiveAt: DateTime(2024, 1, 15, 10, 30),
        fcmToken: 'test-token',
        platform: DevicePlatform.android,
        appVersion: '2.0.0',
      );

      final json = original.toJson();
      final restored = DeviceInfo.fromJson(json);

      expect(restored.deviceId, original.deviceId);
      expect(restored.timezone, original.timezone);
      expect(restored.timezoneOffsetMinutes, original.timezoneOffsetMinutes);
      expect(restored.fcmToken, original.fcmToken);
      expect(restored.platform, original.platform);
      expect(restored.appVersion, original.appVersion);
    });
  });

  group('DeviceInfo Timestamp Handling', () {
    test('handles milliseconds since epoch', () {
      final timestamp = DateTime(2024, 1, 15, 10, 30);
      final json = {
        'deviceId': 'test-device',
        'timezone': 'UTC',
        'timezoneOffsetMinutes': 0,
        'lastActiveAt': timestamp.millisecondsSinceEpoch,
      };

      final device = DeviceInfo.fromJson(json);

      expect(device.lastActiveAt, isNotNull);
      expect(device.lastActiveAt!.year, 2024);
      expect(device.lastActiveAt!.month, 1);
      expect(device.lastActiveAt!.day, 15);
    });

    test('handles ISO 8601 string', () {
      final json = {
        'deviceId': 'test-device',
        'timezone': 'UTC',
        'timezoneOffsetMinutes': 0,
        'lastActiveAt': '2024-01-15T10:30:00Z',
      };

      final device = DeviceInfo.fromJson(json);

      expect(device.lastActiveAt, isNotNull);
      expect(device.lastActiveAt!.year, 2024);
      expect(device.lastActiveAt!.month, 1);
      expect(device.lastActiveAt!.day, 15);
    });

    test('handles Firestore-style map with _seconds', () {
      final json = {
        'deviceId': 'test-device',
        'timezone': 'UTC',
        'timezoneOffsetMinutes': 0,
        'lastActiveAt': {
          '_seconds': 1705315800,
          '_nanoseconds': 0,
        },
      };

      final device = DeviceInfo.fromJson(json);

      expect(device.lastActiveAt, isNotNull);
    });

    test('handles null timestamp', () {
      final json = {
        'deviceId': 'test-device',
        'timezone': 'UTC',
        'timezoneOffsetMinutes': 0,
        'lastActiveAt': null,
      };

      final device = DeviceInfo.fromJson(json);

      expect(device.lastActiveAt, isNull);
    });
  });

  group('DeviceInfo Platform Handling', () {
    test('deserializes all valid platforms', () {
      final platforms = ['ios', 'android', 'web', 'macos', 'windows', 'linux'];

      for (final platformString in platforms) {
        final json = {
          'deviceId': 'test-device',
          'timezone': 'UTC',
          'timezoneOffsetMinutes': 0,
          'platform': platformString,
        };

        final device = DeviceInfo.fromJson(json);
        expect(device.platform, isNotNull,
            reason: 'Platform $platformString should deserialize');
      }
    });

    test('handles unknown platform gracefully', () {
      final json = {
        'deviceId': 'test-device',
        'timezone': 'UTC',
        'timezoneOffsetMinutes': 0,
        'platform': 'future_platform_unknown',
      };

      // Should not throw
      final device = DeviceInfo.fromJson(json);

      // Unknown values should result in null (safe enum deserialization)
      expect(device.platform, isNull);
    });

    test('handles null platform', () {
      final json = {
        'deviceId': 'test-device',
        'timezone': 'UTC',
        'timezoneOffsetMinutes': 0,
        'platform': null,
      };

      final device = DeviceInfo.fromJson(json);

      expect(device.platform, isNull);
    });

    test('serializes platform to lowercase string', () {
      final device = DeviceInfo(
        deviceId: 'test-device',
        timezone: 'UTC',
        timezoneOffsetMinutes: 0,
        platform: DevicePlatform.ios,
      );

      final json = device.toJson();

      expect(json['platform'], 'ios');
    });
  });

  group('DeviceInfo copyWith', () {
    test('creates copy with single field changed', () {
      final original = DeviceInfo(
        deviceId: 'test-device',
        timezone: 'America/New_York',
        timezoneOffsetMinutes: -300,
        platform: DevicePlatform.ios,
      );

      final copy = original.copyWith(timezone: 'Europe/London');

      expect(copy.deviceId, original.deviceId);
      expect(copy.timezone, 'Europe/London');
      expect(copy.timezoneOffsetMinutes, original.timezoneOffsetMinutes);
      expect(copy.platform, original.platform);
    });

    test('creates copy with multiple fields changed', () {
      final original = DeviceInfo(
        deviceId: 'test-device',
        timezone: 'America/New_York',
        timezoneOffsetMinutes: -300,
        platform: DevicePlatform.ios,
        appVersion: '1.0.0',
      );

      final copy = original.copyWith(
        timezone: 'Europe/London',
        timezoneOffsetMinutes: 0,
        appVersion: '2.0.0',
      );

      expect(copy.deviceId, original.deviceId);
      expect(copy.timezone, 'Europe/London');
      expect(copy.timezoneOffsetMinutes, 0);
      expect(copy.platform, original.platform);
      expect(copy.appVersion, '2.0.0');
    });

    test('creates identical copy when no fields specified', () {
      final original = DeviceInfo(
        deviceId: 'test-device',
        timezone: 'America/New_York',
        timezoneOffsetMinutes: -300,
        platform: DevicePlatform.ios,
      );

      final copy = original.copyWith();

      expect(copy, original);
    });
  });

  group('DeviceInfo Equality', () {
    test('equal devices have same hashCode', () {
      final device1 = DeviceInfo(
        deviceId: 'test-device',
        timezone: 'America/New_York',
        timezoneOffsetMinutes: -300,
      );

      final device2 = DeviceInfo(
        deviceId: 'test-device',
        timezone: 'America/New_York',
        timezoneOffsetMinutes: -300,
      );

      expect(device1, device2);
      expect(device1.hashCode, device2.hashCode);
    });

    test('different deviceId means not equal', () {
      final device1 = DeviceInfo(
        deviceId: 'device-1',
        timezone: 'America/New_York',
        timezoneOffsetMinutes: -300,
      );

      final device2 = DeviceInfo(
        deviceId: 'device-2',
        timezone: 'America/New_York',
        timezoneOffsetMinutes: -300,
      );

      expect(device1, isNot(device2));
    });

    test('different timezone means not equal', () {
      final device1 = DeviceInfo(
        deviceId: 'test-device',
        timezone: 'America/New_York',
        timezoneOffsetMinutes: -300,
      );

      final device2 = DeviceInfo(
        deviceId: 'test-device',
        timezone: 'Europe/London',
        timezoneOffsetMinutes: 0,
      );

      expect(device1, isNot(device2));
    });
  });

  group('DeviceInfo toString', () {
    test('masks fcmToken in toString', () {
      final device = DeviceInfo(
        deviceId: 'test-device',
        timezone: 'America/New_York',
        timezoneOffsetMinutes: -300,
        fcmToken: 'secret-token-should-not-be-visible',
      );

      final str = device.toString();

      expect(str, contains('test-device'));
      expect(str, contains('America/New_York'));
      expect(str, isNot(contains('secret-token-should-not-be-visible')));
      expect(str, contains('***')); // Masked token indicator
    });

    test('shows null for missing fcmToken', () {
      final device = DeviceInfo(
        deviceId: 'test-device',
        timezone: 'America/New_York',
        timezoneOffsetMinutes: -300,
      );

      final str = device.toString();

      expect(str, contains('fcmToken: null'));
    });
  });

  group('DeviceMetadata', () {
    test('serializes and deserializes correctly', () {
      const metadata = DeviceMetadata(
        model: 'iPhone 14 Pro',
        osVersion: 'iOS 17.2',
      );

      final json = metadata.toJson();
      final restored = DeviceMetadata.fromJson(json);

      expect(restored.model, 'iPhone 14 Pro');
      expect(restored.osVersion, 'iOS 17.2');
    });

    test('handles null fields', () {
      const metadata = DeviceMetadata();

      final json = metadata.toJson();
      final restored = DeviceMetadata.fromJson(json);

      expect(restored.model, isNull);
      expect(restored.osVersion, isNull);
    });

    test('copyWith creates correct copy', () {
      const original = DeviceMetadata(
        model: 'iPhone 14',
        osVersion: 'iOS 17.0',
      );

      final copy = original.copyWith(osVersion: 'iOS 17.2');

      expect(copy.model, 'iPhone 14');
      expect(copy.osVersion, 'iOS 17.2');
    });

    test('equality works correctly', () {
      const metadata1 = DeviceMetadata(
        model: 'iPhone 14',
        osVersion: 'iOS 17.0',
      );

      const metadata2 = DeviceMetadata(
        model: 'iPhone 14',
        osVersion: 'iOS 17.0',
      );

      expect(metadata1, metadata2);
      expect(metadata1.hashCode, metadata2.hashCode);
    });
  });

  group('DeviceInfo Timezone Edge Cases', () {
    test('handles half-hour offset (India)', () {
      final device = DeviceInfo(
        deviceId: 'test-device',
        timezone: 'Asia/Kolkata',
        timezoneOffsetMinutes: 330, // UTC+5:30
      );

      expect(device.timezoneOffsetMinutes, 330);

      final json = device.toJson();
      expect(json['timezoneOffsetMinutes'], 330);
    });

    test('handles 45-minute offset (Nepal)', () {
      final device = DeviceInfo(
        deviceId: 'test-device',
        timezone: 'Asia/Kathmandu',
        timezoneOffsetMinutes: 345, // UTC+5:45
      );

      expect(device.timezoneOffsetMinutes, 345);

      final json = device.toJson();
      expect(json['timezoneOffsetMinutes'], 345);
    });

    test('handles negative offset (US Eastern)', () {
      final device = DeviceInfo(
        deviceId: 'test-device',
        timezone: 'America/New_York',
        timezoneOffsetMinutes: -300, // UTC-5
      );

      expect(device.timezoneOffsetMinutes, -300);
    });

    test('handles extreme positive offset (Line Islands)', () {
      final device = DeviceInfo(
        deviceId: 'test-device',
        timezone: 'Pacific/Kiritimati',
        timezoneOffsetMinutes: 840, // UTC+14
      );

      expect(device.timezoneOffsetMinutes, 840);
    });

    test('handles extreme negative offset (Baker Island)', () {
      final device = DeviceInfo(
        deviceId: 'test-device',
        timezone: 'Etc/GMT+12',
        timezoneOffsetMinutes: -720, // UTC-12
      );

      expect(device.timezoneOffsetMinutes, -720);
    });
  });
}
