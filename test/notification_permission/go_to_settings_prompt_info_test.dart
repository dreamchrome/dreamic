import 'package:dreamic/notifications/notification_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GoToSettingsPromptInfo', () {
    group('constructor', () {
      test('creates with required fields', () {
        final now = DateTime.now();
        final info = GoToSettingsPromptInfo(
          lastPromptTime: now,
          promptCount: 2,
          lastActionWasOpenSettings: true,
        );

        expect(info.lastPromptTime, equals(now));
        expect(info.promptCount, equals(2));
        expect(info.lastActionWasOpenSettings, isTrue);
      });

      test('creates with lastActionWasOpenSettings false', () {
        final info = GoToSettingsPromptInfo(
          lastPromptTime: DateTime(2024, 1, 1),
          promptCount: 1,
          lastActionWasOpenSettings: false,
        );

        expect(info.lastActionWasOpenSettings, isFalse);
      });
    });

    group('fromJson / toJson', () {
      test('serializes and deserializes correctly', () {
        final original = GoToSettingsPromptInfo(
          lastPromptTime: DateTime(2024, 6, 15, 10, 30, 0),
          promptCount: 3,
          lastActionWasOpenSettings: true,
        );

        final json = original.toJson();
        final deserialized = GoToSettingsPromptInfo.fromJson(json);

        expect(deserialized.lastPromptTime, equals(original.lastPromptTime));
        expect(deserialized.promptCount, equals(original.promptCount));
        expect(deserialized.lastActionWasOpenSettings,
            equals(original.lastActionWasOpenSettings));
      });

      test('serializes to JSON with correct keys', () {
        final now = DateTime(2024, 1, 1, 12, 0, 0);
        final info = GoToSettingsPromptInfo(
          lastPromptTime: now,
          promptCount: 2,
          lastActionWasOpenSettings: false,
        );

        final json = info.toJson();

        expect(json['lastPromptTime'], equals(now.millisecondsSinceEpoch));
        expect(json['promptCount'], equals(2));
        expect(json['lastActionWasOpenSettings'], isFalse);
      });

      test('deserializes from JSON correctly', () {
        final timestamp = DateTime(2024, 3, 15).millisecondsSinceEpoch;
        final json = {
          'lastPromptTime': timestamp,
          'promptCount': 5,
          'lastActionWasOpenSettings': true,
        };

        final info = GoToSettingsPromptInfo.fromJson(json);

        expect(info.lastPromptTime.millisecondsSinceEpoch, equals(timestamp));
        expect(info.promptCount, equals(5));
        expect(info.lastActionWasOpenSettings, isTrue);
      });

      test('round-trips through JSON correctly', () {
        final original = GoToSettingsPromptInfo(
          lastPromptTime: DateTime(2024, 12, 25, 9, 0, 0),
          promptCount: 10,
          lastActionWasOpenSettings: false,
        );

        // Serialize and deserialize
        final json = original.toJson();
        final roundTripped = GoToSettingsPromptInfo.fromJson(json);

        // Verify all fields match
        expect(roundTripped.lastPromptTime, equals(original.lastPromptTime));
        expect(roundTripped.promptCount, equals(original.promptCount));
        expect(roundTripped.lastActionWasOpenSettings,
            equals(original.lastActionWasOpenSettings));
      });
    });

    group('copyWith', () {
      test('creates copy with replaced fields', () {
        final original = GoToSettingsPromptInfo(
          lastPromptTime: DateTime(2024, 1, 1),
          promptCount: 2,
          lastActionWasOpenSettings: false,
        );

        final newTime = DateTime(2024, 6, 15);
        final copy = original.copyWith(
          lastPromptTime: newTime,
          lastActionWasOpenSettings: true,
        );

        expect(copy.lastPromptTime, equals(newTime));
        expect(copy.promptCount, equals(2)); // Unchanged
        expect(copy.lastActionWasOpenSettings, isTrue);
      });

      test('creates copy with replaced promptCount', () {
        final original = GoToSettingsPromptInfo(
          lastPromptTime: DateTime(2024, 1, 1),
          promptCount: 2,
          lastActionWasOpenSettings: false,
        );

        final copy = original.copyWith(promptCount: 5);

        expect(copy.lastPromptTime, equals(original.lastPromptTime));
        expect(copy.promptCount, equals(5));
        expect(copy.lastActionWasOpenSettings, isFalse);
      });

      test('creates identical copy when no fields specified', () {
        final original = GoToSettingsPromptInfo(
          lastPromptTime: DateTime(2024, 1, 1),
          promptCount: 2,
          lastActionWasOpenSettings: true,
        );

        final copy = original.copyWith();

        expect(copy.lastPromptTime, equals(original.lastPromptTime));
        expect(copy.promptCount, equals(original.promptCount));
        expect(copy.lastActionWasOpenSettings,
            equals(original.lastActionWasOpenSettings));
      });
    });

    group('toString', () {
      test('provides readable string representation', () {
        final info = GoToSettingsPromptInfo(
          lastPromptTime: DateTime(2024, 1, 1),
          promptCount: 3,
          lastActionWasOpenSettings: true,
        );

        final str = info.toString();

        expect(str, contains('GoToSettingsPromptInfo'));
        expect(str, contains('promptCount: 3'));
        expect(str, contains('lastActionWasOpenSettings: true'));
      });
    });
  });
}
