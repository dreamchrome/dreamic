import 'package:dreamic/dreamic.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for Safe Enum Serialization Helper Functions
///
/// These tests verify that safeEnumFromJson handles unknown values gracefully
/// without crashing the app.
void main() {
  group('safeEnumFromJson', () {
    group('Nullable Strategy (no default)', () {
      test('converts known enum value correctly', () {
        final result = safeEnumFromJson('value1', TestEnum.values);
        expect(result, TestEnum.value1);
      });

      test('converts all enum values correctly', () {
        expect(safeEnumFromJson('value1', TestEnum.values), TestEnum.value1);
        expect(safeEnumFromJson('value2', TestEnum.values), TestEnum.value2);
        expect(safeEnumFromJson('value3', TestEnum.values), TestEnum.value3);
      });

      test('returns null for unknown enum value', () {
        final result = safeEnumFromJson('unknownValue', TestEnum.values);
        expect(result, isNull);
      });

      test('returns null for null input', () {
        final result = safeEnumFromJson(null, TestEnum.values);
        expect(result, isNull);
      });

      test('handles future server enum values gracefully', () {
        // Simulate server adding new enum values that old app doesn't know about
        final newValue1 = safeEnumFromJson('value4', TestEnum.values);
        final newValue2 = safeEnumFromJson('premiumUser', TestEnum.values);
        final newValue3 = safeEnumFromJson('superAdmin', TestEnum.values);

        // Old app should not crash, should return null
        expect(newValue1, isNull);
        expect(newValue2, isNull);
        expect(newValue3, isNull);
      });

      test('handles empty string', () {
        expect(safeEnumFromJson('', TestEnum.values), isNull);
      });

      test('handles whitespace', () {
        expect(safeEnumFromJson(' ', TestEnum.values), isNull);
        expect(safeEnumFromJson('  value1  ', TestEnum.values), isNull);
      });

      test('case sensitive matching', () {
        expect(safeEnumFromJson('VALUE1', TestEnum.values), isNull);
        expect(safeEnumFromJson('Value1', TestEnum.values), isNull);
        expect(safeEnumFromJson('value1', TestEnum.values), TestEnum.value1);
      });
    });

    group('Default Strategy (with default value)', () {
      test('converts known enum value correctly', () {
        final result = safeEnumFromJson(
          'value1',
          TestEnum.values,
          defaultValue: TestEnum.value1,
        );
        expect(result, TestEnum.value1);
      });

      test('converts all enum values correctly', () {
        expect(
          safeEnumFromJson('value1', TestEnum.values, defaultValue: TestEnum.value1),
          TestEnum.value1,
        );
        expect(
          safeEnumFromJson('value2', TestEnum.values, defaultValue: TestEnum.value1),
          TestEnum.value2,
        );
        expect(
          safeEnumFromJson('value3', TestEnum.values, defaultValue: TestEnum.value1),
          TestEnum.value3,
        );
      });

      test('returns default value for unknown enum value', () {
        final result = safeEnumFromJson(
          'unknownValue',
          TestEnum.values,
          defaultValue: TestEnum.value2,
        );
        expect(result, TestEnum.value2);
      });

      test('returns null for null input even with default', () {
        // null input should stay null to distinguish from unknown strings
        final result = safeEnumFromJson(
          null,
          TestEnum.values,
          defaultValue: TestEnum.value3,
        );
        expect(result, isNull);
      });

      test('handles future server enum values gracefully', () {
        // Simulate server adding new enum values that old app doesn't know about
        final newValue1 = safeEnumFromJson(
          'value4',
          TestEnum.values,
          defaultValue: TestEnum.value1,
        );
        final newValue2 = safeEnumFromJson(
          'premiumUser',
          TestEnum.values,
          defaultValue: TestEnum.value1,
        );

        // Old app should not crash, should return default
        expect(newValue1, TestEnum.value1);
        expect(newValue2, TestEnum.value1);
      });
    });

    group('Logging Strategy (with callback)', () {
      test('converts known enum value correctly without logging', () {
        final loggedValues = <String>[];
        final result = safeEnumFromJson(
          'value2',
          TestEnum.values,
          defaultValue: TestEnum.value3,
          onUnknownValue: loggedValues.add,
        );
        expect(result, TestEnum.value2);
        expect(loggedValues, isEmpty);
      });

      test('logs unknown values', () {
        final loggedValues = <String>[];
        final result = safeEnumFromJson(
          'unknownValue',
          TestEnum.values,
          defaultValue: TestEnum.value3,
          onUnknownValue: loggedValues.add,
        );
        expect(result, TestEnum.value3);
        expect(loggedValues, contains('unknownValue'));
      });

      test('logs multiple unknown values', () {
        final loggedValues = <String>[];
        
        safeEnumFromJson(
          'unknown1',
          TestEnum.values,
          defaultValue: TestEnum.value1,
          onUnknownValue: loggedValues.add,
        );
        safeEnumFromJson(
          'unknown2',
          TestEnum.values,
          defaultValue: TestEnum.value1,
          onUnknownValue: loggedValues.add,
        );
        safeEnumFromJson(
          'value1',
          TestEnum.values,
          defaultValue: TestEnum.value1,
          onUnknownValue: loggedValues.add,
        ); // known value
        safeEnumFromJson(
          'unknown3',
          TestEnum.values,
          defaultValue: TestEnum.value1,
          onUnknownValue: loggedValues.add,
        );

        expect(loggedValues.length, 3);
        expect(loggedValues, contains('unknown1'));
        expect(loggedValues, contains('unknown2'));
        expect(loggedValues, contains('unknown3'));
        expect(loggedValues, isNot(contains('value1')));
      });

      test('does not log null values', () {
        final loggedValues = <String>[];
        safeEnumFromJson(
          null,
          TestEnum.values,
          defaultValue: TestEnum.value1,
          onUnknownValue: loggedValues.add,
        );
        expect(loggedValues, isEmpty);
      });
    });

    group('Real-world scenarios', () {
      test('old app receives new enum value from server - nullable field', () {
        // Scenario: Server adds 'enterprise' to UserType enum
        // Old app only knows: guest, member, admin
        // Server sends: enterprise (unknown to old app)

        final result = safeEnumFromJson('enterprise', UserType.values);

        // Old app should not crash
        expect(result, isNull);
      });

      test('old app receives new enum value from server - default field', () {
        // Scenario: Server adds 'critical' to Priority enum
        // Old app only knows: low, medium, high
        // Server sends: critical (unknown to old app)

        final result = safeEnumFromJson(
          'critical',
          Priority.values,
          defaultValue: Priority.medium,
        );

        // Old app should not crash, uses default
        expect(result, Priority.medium);
      });

      test('handles typos or corrupted data gracefully', () {
        // Various corrupted/invalid data
        expect(safeEnumFromJson('ADMIN', UserType.values), isNull); // Wrong case
        expect(safeEnumFromJson('admi', UserType.values), isNull); // Typo
        expect(safeEnumFromJson('', UserType.values), isNull); // Empty string
        expect(safeEnumFromJson('123', UserType.values), isNull); // Invalid
      });

      test('mixed known and unknown values in list', () {
        final values = ['guest', 'member', 'newValue', 'admin', 'anotherNew'];
        final results = values
            .map((v) => safeEnumFromJson(v, UserType.values))
            .toList();

        expect(results[0], UserType.guest);
        expect(results[1], UserType.member);
        expect(results[2], isNull); // unknown
        expect(results[3], UserType.admin);
        expect(results[4], isNull); // unknown
      });
    });
  });

  group('safeEnumToJson', () {
    test('returns enum name for valid enum', () {
      expect(safeEnumToJson(TestEnum.value1), 'value1');
      expect(safeEnumToJson(TestEnum.value2), 'value2');
      expect(safeEnumToJson(TestEnum.value3), 'value3');
    });

    test('returns null for null input', () {
      expect(safeEnumToJson<TestEnum>(null), isNull);
    });

    test('works with all test enums', () {
      expect(safeEnumToJson(UserType.guest), 'guest');
      expect(safeEnumToJson(UserType.member), 'member');
      expect(safeEnumToJson(UserType.admin), 'admin');

      expect(safeEnumToJson(Priority.low), 'low');
      expect(safeEnumToJson(Priority.medium), 'medium');
      expect(safeEnumToJson(Priority.high), 'high');
    });

    test('roundtrip conversion - nullable', () {
      // Convert to JSON and back
      for (final value in TestEnum.values) {
        final json = safeEnumToJson(value);
        final restored = safeEnumFromJson(json, TestEnum.values);
        expect(restored, value);
      }
    });

    test('roundtrip conversion - with default', () {
      // Convert to JSON and back
      for (final value in Priority.values) {
        final json = safeEnumToJson(value);
        final restored = safeEnumFromJson(
          json,
          Priority.values,
          defaultValue: Priority.medium,
        );
        expect(restored, value);
      }
    });
  });
}

// Test enums
enum TestEnum {
  value1,
  value2,
  value3,
}

enum UserType {
  guest,
  member,
  admin,
}

enum Priority {
  low,
  medium,
  high,
}
