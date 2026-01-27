import 'package:flutter_test/flutter_test.dart';
import 'package:dreamic/data/models/device_platform.dart';

/// Tests for the DevicePlatform enum and its serialization.
///
/// These tests verify:
/// - Safe serialization/deserialization
/// - Handling of unknown platform values
/// - Platform extension methods (displayName, isMobile, etc.)
void main() {
  group('DevicePlatformSerialization', () {
    group('serialize', () {
      test('serializes all platforms to lowercase strings', () {
        expect(DevicePlatformSerialization.serialize(DevicePlatform.ios), 'ios');
        expect(
            DevicePlatformSerialization.serialize(DevicePlatform.android), 'android');
        expect(DevicePlatformSerialization.serialize(DevicePlatform.web), 'web');
        expect(
            DevicePlatformSerialization.serialize(DevicePlatform.macos), 'macos');
        expect(
            DevicePlatformSerialization.serialize(DevicePlatform.windows), 'windows');
        expect(
            DevicePlatformSerialization.serialize(DevicePlatform.linux), 'linux');
      });

      test('serializes null to null', () {
        expect(DevicePlatformSerialization.serialize(null), isNull);
      });
    });

    group('deserialize', () {
      test('deserializes all valid platform strings', () {
        expect(DevicePlatformSerialization.deserialize('ios'), DevicePlatform.ios);
        expect(
            DevicePlatformSerialization.deserialize('android'), DevicePlatform.android);
        expect(DevicePlatformSerialization.deserialize('web'), DevicePlatform.web);
        expect(
            DevicePlatformSerialization.deserialize('macos'), DevicePlatform.macos);
        expect(
            DevicePlatformSerialization.deserialize('windows'), DevicePlatform.windows);
        expect(
            DevicePlatformSerialization.deserialize('linux'), DevicePlatform.linux);
      });

      test('deserializes null to null', () {
        expect(DevicePlatformSerialization.deserialize(null), isNull);
      });

      test('deserializes unknown value to null (safe)', () {
        expect(DevicePlatformSerialization.deserialize('unknown_platform'), isNull);
        expect(DevicePlatformSerialization.deserialize('future_os'), isNull);
        expect(DevicePlatformSerialization.deserialize('chromeos'), isNull);
      });

      test('handles case-sensitive matching', () {
        // Only exact lowercase matches should work
        expect(DevicePlatformSerialization.deserialize('iOS'), isNull);
        expect(DevicePlatformSerialization.deserialize('IOS'), isNull);
        expect(DevicePlatformSerialization.deserialize('Android'), isNull);
        expect(DevicePlatformSerialization.deserialize('ANDROID'), isNull);
        expect(DevicePlatformSerialization.deserialize('Web'), isNull);
        expect(DevicePlatformSerialization.deserialize('MacOS'), isNull);
        expect(DevicePlatformSerialization.deserialize('Windows'), isNull);
        expect(DevicePlatformSerialization.deserialize('Linux'), isNull);
      });

      test('handles empty string', () {
        expect(DevicePlatformSerialization.deserialize(''), isNull);
      });

      test('handles whitespace', () {
        expect(DevicePlatformSerialization.deserialize(' ios '), isNull);
        expect(DevicePlatformSerialization.deserialize('  '), isNull);
      });
    });

    group('roundtrip', () {
      test('roundtrip preserves all platforms', () {
        for (final platform in DevicePlatform.values) {
          final serialized = DevicePlatformSerialization.serialize(platform);
          final deserialized = DevicePlatformSerialization.deserialize(serialized);
          expect(deserialized, platform,
              reason: 'Roundtrip should preserve $platform');
        }
      });
    });
  });

  group('DevicePlatformExtension', () {
    group('displayName', () {
      test('returns correct display names', () {
        expect(DevicePlatform.ios.displayName, 'iOS');
        expect(DevicePlatform.android.displayName, 'Android');
        expect(DevicePlatform.web.displayName, 'Web');
        expect(DevicePlatform.macos.displayName, 'macOS');
        expect(DevicePlatform.windows.displayName, 'Windows');
        expect(DevicePlatform.linux.displayName, 'Linux');
      });
    });

    group('isMobile', () {
      test('returns true for mobile platforms', () {
        expect(DevicePlatform.ios.isMobile, true);
        expect(DevicePlatform.android.isMobile, true);
      });

      test('returns false for non-mobile platforms', () {
        expect(DevicePlatform.web.isMobile, false);
        expect(DevicePlatform.macos.isMobile, false);
        expect(DevicePlatform.windows.isMobile, false);
        expect(DevicePlatform.linux.isMobile, false);
      });
    });

    group('isDesktop', () {
      test('returns true for desktop platforms', () {
        expect(DevicePlatform.macos.isDesktop, true);
        expect(DevicePlatform.windows.isDesktop, true);
        expect(DevicePlatform.linux.isDesktop, true);
      });

      test('returns false for non-desktop platforms', () {
        expect(DevicePlatform.ios.isDesktop, false);
        expect(DevicePlatform.android.isDesktop, false);
        expect(DevicePlatform.web.isDesktop, false);
      });
    });

    group('isWeb', () {
      test('returns true only for web', () {
        expect(DevicePlatform.web.isWeb, true);
      });

      test('returns false for non-web platforms', () {
        expect(DevicePlatform.ios.isWeb, false);
        expect(DevicePlatform.android.isWeb, false);
        expect(DevicePlatform.macos.isWeb, false);
        expect(DevicePlatform.windows.isWeb, false);
        expect(DevicePlatform.linux.isWeb, false);
      });
    });

    group('platform categories are mutually exclusive', () {
      test('each platform belongs to exactly one category', () {
        for (final platform in DevicePlatform.values) {
          final categories = [
            platform.isMobile,
            platform.isDesktop,
            platform.isWeb,
          ].where((b) => b).length;

          expect(categories, 1,
              reason: '$platform should belong to exactly one category');
        }
      });

      test('all platforms are covered', () {
        for (final platform in DevicePlatform.values) {
          final isCategorized =
              platform.isMobile || platform.isDesktop || platform.isWeb;

          expect(isCategorized, true,
              reason: '$platform should be categorized');
        }
      });
    });
  });

  group('DevicePlatform Edge Cases', () {
    test('enum has expected number of values', () {
      // This test will fail if new platforms are added without updating tests
      expect(DevicePlatform.values.length, 6);
    });

    test('all values have unique serialized forms', () {
      final serialized =
          DevicePlatform.values.map(DevicePlatformSerialization.serialize).toSet();
      expect(serialized.length, DevicePlatform.values.length);
    });

    test('all values have unique display names', () {
      final displayNames =
          DevicePlatform.values.map((p) => p.displayName).toSet();
      expect(displayNames.length, DevicePlatform.values.length);
    });
  });
}
