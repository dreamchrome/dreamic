import 'package:dreamic/notifications/notification_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NotificationDenialInfo', () {
    group('constructor', () {
      test('creates with required fields', () {
        final now = DateTime.now();
        final info = NotificationDenialInfo(
          lastDenialTime: now,
          denialCount: 2,
          isPermanent: false,
        );

        expect(info.lastDenialTime, equals(now));
        expect(info.denialCount, equals(2));
        expect(info.isPermanent, isFalse);
        expect(info.requestAttemptCount, equals(0)); // default
        expect(info.lastRequestAttemptTime, isNull); // default
        expect(info.lastRequestWasBlocked, isFalse); // default
      });

      test('creates with all fields', () {
        final denialTime = DateTime(2024, 1, 15);
        final attemptTime = DateTime(2024, 1, 16);
        final info = NotificationDenialInfo(
          lastDenialTime: denialTime,
          denialCount: 3,
          isPermanent: true,
          requestAttemptCount: 5,
          lastRequestAttemptTime: attemptTime,
          lastRequestWasBlocked: true,
        );

        expect(info.lastDenialTime, equals(denialTime));
        expect(info.denialCount, equals(3));
        expect(info.isPermanent, isTrue);
        expect(info.requestAttemptCount, equals(5));
        expect(info.lastRequestAttemptTime, equals(attemptTime));
        expect(info.lastRequestWasBlocked, isTrue);
      });
    });

    group('fromJson / toJson', () {
      test('serializes and deserializes correctly with all fields', () {
        final original = NotificationDenialInfo(
          lastDenialTime: DateTime(2024, 6, 15, 10, 30, 0),
          denialCount: 2,
          isPermanent: true,
          requestAttemptCount: 3,
          lastRequestAttemptTime: DateTime(2024, 6, 16, 11, 0, 0),
          lastRequestWasBlocked: true,
        );

        final json = original.toJson();
        final deserialized = NotificationDenialInfo.fromJson(json);

        expect(deserialized.lastDenialTime, equals(original.lastDenialTime));
        expect(deserialized.denialCount, equals(original.denialCount));
        expect(deserialized.isPermanent, equals(original.isPermanent));
        expect(
            deserialized.requestAttemptCount, equals(original.requestAttemptCount));
        expect(deserialized.lastRequestAttemptTime,
            equals(original.lastRequestAttemptTime));
        expect(deserialized.lastRequestWasBlocked,
            equals(original.lastRequestWasBlocked));
      });

      test('serializes to JSON with correct keys', () {
        final now = DateTime(2024, 1, 1, 12, 0, 0);
        final info = NotificationDenialInfo(
          lastDenialTime: now,
          denialCount: 2,
          isPermanent: false,
        );

        final json = info.toJson();

        expect(json['lastDenialTime'], equals(now.millisecondsSinceEpoch));
        expect(json['denialCount'], equals(2));
        expect(json['isPermanent'], isFalse);
        expect(json['requestAttemptCount'], equals(0));
        expect(json['lastRequestAttemptTime'], isNull);
        expect(json['lastRequestWasBlocked'], isFalse);
      });

      test('handles missing optional fields in JSON', () {
        final json = {
          'lastDenialTime': DateTime(2024, 1, 1).millisecondsSinceEpoch,
          'denialCount': 1,
          'isPermanent': true,
        };

        final info = NotificationDenialInfo.fromJson(json);

        expect(info.requestAttemptCount, equals(0));
        expect(info.lastRequestAttemptTime, isNull);
        expect(info.lastRequestWasBlocked, isFalse);
      });

      test('handles null lastRequestAttemptTime in JSON', () {
        final json = {
          'lastDenialTime': DateTime(2024, 1, 1).millisecondsSinceEpoch,
          'denialCount': 1,
          'isPermanent': false,
          'requestAttemptCount': 2,
          'lastRequestAttemptTime': null,
          'lastRequestWasBlocked': false,
        };

        final info = NotificationDenialInfo.fromJson(json);

        expect(info.lastRequestAttemptTime, isNull);
      });
    });

    group('copyWith', () {
      test('creates copy with replaced fields', () {
        final original = NotificationDenialInfo(
          lastDenialTime: DateTime(2024, 1, 1),
          denialCount: 2,
          isPermanent: false,
          requestAttemptCount: 3,
        );

        final newTime = DateTime(2024, 6, 15);
        final copy = original.copyWith(
          lastDenialTime: newTime,
          isPermanent: true,
        );

        expect(copy.lastDenialTime, equals(newTime));
        expect(copy.denialCount, equals(2)); // Unchanged
        expect(copy.isPermanent, isTrue);
        expect(copy.requestAttemptCount, equals(3)); // Unchanged
      });

      test('creates identical copy when no fields specified', () {
        final original = NotificationDenialInfo(
          lastDenialTime: DateTime(2024, 1, 1),
          denialCount: 2,
          isPermanent: false,
        );

        final copy = original.copyWith();

        expect(copy.lastDenialTime, equals(original.lastDenialTime));
        expect(copy.denialCount, equals(original.denialCount));
        expect(copy.isPermanent, equals(original.isPermanent));
        expect(copy.requestAttemptCount, equals(original.requestAttemptCount));
      });
    });

    group('toString', () {
      test('provides readable string representation', () {
        final info = NotificationDenialInfo(
          lastDenialTime: DateTime(2024, 1, 1),
          denialCount: 2,
          isPermanent: true,
          requestAttemptCount: 3,
          lastRequestWasBlocked: false,
        );

        final str = info.toString();

        expect(str, contains('NotificationDenialInfo'));
        expect(str, contains('denialCount: 2'));
        expect(str, contains('isPermanent: true'));
        expect(str, contains('requestAttemptCount: 3'));
      });
    });
  });
}
