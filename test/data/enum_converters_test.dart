import 'package:dreamic/dreamic.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for Robust Enum Converters
///
/// These tests verify that enum converters handle unknown values gracefully
/// without crashing the app.
void main() {
  group('RobustEnumConverter', () {
    group('NullableEnumConverter', () {
      test('converts known enum value correctly', () {
        const converter = TestNullableConverter();
        final result = converter.fromJson('value1');
        expect(result, TestEnum.value1);
      });

      test('converts all enum values correctly', () {
        const converter = TestNullableConverter();
        expect(converter.fromJson('value1'), TestEnum.value1);
        expect(converter.fromJson('value2'), TestEnum.value2);
        expect(converter.fromJson('value3'), TestEnum.value3);
      });

      test('returns null for unknown enum value', () {
        const converter = TestNullableConverter();
        final result = converter.fromJson('unknownValue');
        expect(result, isNull);
      });

      test('returns null for null input', () {
        const converter = TestNullableConverter();
        final result = converter.fromJson(null);
        expect(result, isNull);
      });

      test('toJson returns enum name', () {
        const converter = TestNullableConverter();
        final result = converter.toJson(TestEnum.value2);
        expect(result, 'value2');
      });

      test('toJson returns null for null input', () {
        const converter = TestNullableConverter();
        final result = converter.toJson(null);
        expect(result, isNull);
      });

      test('handles future server enum values gracefully', () {
        const converter = TestNullableConverter();

        // Simulate server adding new enum values that old app doesn't know about
        final newValue1 = converter.fromJson('value4'); // Future value
        final newValue2 = converter.fromJson('premiumUser'); // Future value
        final newValue3 = converter.fromJson('superAdmin'); // Future value

        // Old app should not crash, should return null
        expect(newValue1, isNull);
        expect(newValue2, isNull);
        expect(newValue3, isNull);
      });
    });

    group('DefaultEnumConverter', () {
      test('converts known enum value correctly', () {
        const converter = TestDefaultConverter();
        final result = converter.fromJson('value1');
        expect(result, TestEnum.value1);
      });

      test('converts all enum values correctly', () {
        const converter = TestDefaultConverter();
        expect(converter.fromJson('value1'), TestEnum.value1);
        expect(converter.fromJson('value2'), TestEnum.value2);
        expect(converter.fromJson('value3'), TestEnum.value3);
      });

      test('returns default value for unknown enum value', () {
        const converter = TestDefaultConverter();
        final result = converter.fromJson('unknownValue');
        expect(result, TestEnum.value1); // default value
      });

      test('returns null for null input', () {
        const converter = TestDefaultConverter();
        final result = converter.fromJson(null);
        expect(result, isNull);
      });

      test('toJson returns enum name', () {
        const converter = TestDefaultConverter();
        final result = converter.toJson(TestEnum.value3);
        expect(result, 'value3');
      });

      test('toJson returns null for null input', () {
        const converter = TestDefaultConverter();
        final result = converter.toJson(null);
        expect(result, isNull);
      });

      test('handles future server enum values gracefully', () {
        const converter = TestDefaultConverter();

        // Simulate server adding new enum values that old app doesn't know about
        final newValue1 = converter.fromJson('value4'); // Future value
        final newValue2 = converter.fromJson('premiumUser'); // Future value

        // Old app should not crash, should return default
        expect(newValue1, TestEnum.value1);
        expect(newValue2, TestEnum.value1);
      });
    });

    group('LoggingEnumConverter', () {
      test('converts known enum value correctly', () {
        final converter = TestLoggingConverter();
        final result = converter.fromJson('value2');
        expect(result, TestEnum.value2);
        expect(converter.loggedValues, isEmpty);
      });

      test('logs unknown values', () {
        final converter = TestLoggingConverter();
        final result = converter.fromJson('unknownValue');
        expect(result, TestEnum.value3); // default value
        expect(converter.loggedValues, contains('unknownValue'));
      });

      test('logs multiple unknown values', () {
        final converter = TestLoggingConverter();
        converter.fromJson('unknown1');
        converter.fromJson('unknown2');
        converter.fromJson('value1'); // known value
        converter.fromJson('unknown3');

        expect(converter.loggedValues.length, 3);
        expect(converter.loggedValues, contains('unknown1'));
        expect(converter.loggedValues, contains('unknown2'));
        expect(converter.loggedValues, contains('unknown3'));
        expect(converter.loggedValues, isNot(contains('value1')));
      });

      test('does not log null values', () {
        final converter = TestLoggingConverter();
        converter.fromJson(null);
        expect(converter.loggedValues, isEmpty);
      });
    });

    group('Real-world scenarios', () {
      test('old app receives new enum value from server - nullable field', () {
        // Scenario: Server adds 'enterprise' to UserType enum
        // Old app only knows: guest, member, admin
        // Server sends: enterprise (unknown to old app)

        const converter = UserTypeNullableConverter();
        final result = converter.fromJson('enterprise');

        // Old app should not crash
        expect(result, isNull);
      });

      test('old app receives new enum value from server - default field', () {
        // Scenario: Server adds 'critical' to Priority enum
        // Old app only knows: low, medium, high
        // Server sends: critical (unknown to old app)

        const converter = PriorityConverter();
        final result = converter.fromJson('critical');

        // Old app should not crash, uses default
        expect(result, Priority.medium);
      });

      test('handles typos or corrupted data gracefully', () {
        const converter = UserTypeNullableConverter();

        // Various corrupted/invalid data
        expect(converter.fromJson('ADMIN'), isNull); // Wrong case
        expect(converter.fromJson('admi'), isNull); // Typo
        expect(converter.fromJson(''), isNull); // Empty string
        expect(converter.fromJson('123'), isNull); // Invalid
      });

      test('mixed known and unknown values in list', () {
        const converter = UserTypeNullableConverter();

        final values = ['guest', 'member', 'newValue', 'admin', 'anotherNew'];
        final results = values.map((v) => converter.fromJson(v)).toList();

        expect(results[0], UserType.guest);
        expect(results[1], UserType.member);
        expect(results[2], isNull); // unknown
        expect(results[3], UserType.admin);
        expect(results[4], isNull); // unknown
      });
    });

    group('Edge cases', () {
      test('handles empty string', () {
        const converter = TestNullableConverter();
        expect(converter.fromJson(''), isNull);
      });

      test('handles whitespace', () {
        const converter = TestNullableConverter();
        expect(converter.fromJson(' '), isNull);
        expect(converter.fromJson('  value1  '), isNull); // exact match required
      });

      test('case sensitive matching', () {
        const converter = TestNullableConverter();
        expect(converter.fromJson('VALUE1'), isNull);
        expect(converter.fromJson('Value1'), isNull);
        expect(converter.fromJson('value1'), TestEnum.value1);
      });

      test('roundtrip conversion', () {
        const converter = TestNullableConverter();

        // Convert to JSON and back
        for (final value in TestEnum.values) {
          final json = converter.toJson(value);
          final restored = converter.fromJson(json);
          expect(restored, value);
        }
      });
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

// Test converters
class TestNullableConverter extends NullableEnumConverter<TestEnum> {
  const TestNullableConverter();

  @override
  List<TestEnum> get enumValues => TestEnum.values;
}

class TestDefaultConverter extends DefaultEnumConverter<TestEnum> {
  const TestDefaultConverter();

  @override
  List<TestEnum> get enumValues => TestEnum.values;

  @override
  TestEnum get defaultValue => TestEnum.value1;
}

class TestLoggingConverter extends LoggingEnumConverter<TestEnum> {
  TestLoggingConverter();

  final List<String> loggedValues = [];

  @override
  List<TestEnum> get enumValues => TestEnum.values;

  @override
  TestEnum get defaultValue => TestEnum.value3;

  @override
  void logUnknownValue(String value) {
    loggedValues.add(value);
  }
}

class UserTypeNullableConverter extends NullableEnumConverter<UserType> {
  const UserTypeNullableConverter();

  @override
  List<UserType> get enumValues => UserType.values;
}

class PriorityConverter extends DefaultEnumConverter<Priority> {
  const PriorityConverter();

  @override
  List<Priority> get enumValues => Priority.values;

  @override
  Priority get defaultValue => Priority.medium;
}
