import 'package:dreamic/notifications/notification_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ValuePropDeclineInfo', () {
    group('constructor', () {
      test('creates with required fields', () {
        final now = DateTime.now();
        final info = ValuePropDeclineInfo(
          lastDeclineTime: now,
          declineCount: 2,
        );

        expect(info.lastDeclineTime, equals(now));
        expect(info.declineCount, equals(2));
      });

      test('creates with declineCount of 1 (first decline)', () {
        final info = ValuePropDeclineInfo(
          lastDeclineTime: DateTime(2024, 1, 1),
          declineCount: 1,
        );

        expect(info.declineCount, equals(1));
      });
    });

    group('fromJson / toJson', () {
      test('serializes and deserializes correctly', () {
        final original = ValuePropDeclineInfo(
          lastDeclineTime: DateTime(2024, 6, 15, 10, 30, 0),
          declineCount: 3,
        );

        final json = original.toJson();
        final deserialized = ValuePropDeclineInfo.fromJson(json);

        expect(deserialized.lastDeclineTime, equals(original.lastDeclineTime));
        expect(deserialized.declineCount, equals(original.declineCount));
      });

      test('serializes to JSON with correct keys', () {
        final now = DateTime(2024, 1, 1, 12, 0, 0);
        final info = ValuePropDeclineInfo(
          lastDeclineTime: now,
          declineCount: 2,
        );

        final json = info.toJson();

        expect(json['lastDeclineTime'], equals(now.millisecondsSinceEpoch));
        expect(json['declineCount'], equals(2));
      });

      test('deserializes from JSON correctly', () {
        final timestamp = DateTime(2024, 3, 15).millisecondsSinceEpoch;
        final json = {
          'lastDeclineTime': timestamp,
          'declineCount': 5,
        };

        final info = ValuePropDeclineInfo.fromJson(json);

        expect(info.lastDeclineTime.millisecondsSinceEpoch, equals(timestamp));
        expect(info.declineCount, equals(5));
      });

      test('round-trips through JSON correctly', () {
        final original = ValuePropDeclineInfo(
          lastDeclineTime: DateTime(2024, 12, 25, 9, 0, 0),
          declineCount: 10,
        );

        final json = original.toJson();
        final roundTripped = ValuePropDeclineInfo.fromJson(json);

        expect(roundTripped.lastDeclineTime, equals(original.lastDeclineTime));
        expect(roundTripped.declineCount, equals(original.declineCount));
      });
    });

    group('copyWith', () {
      test('creates copy with replaced fields', () {
        final original = ValuePropDeclineInfo(
          lastDeclineTime: DateTime(2024, 1, 1),
          declineCount: 2,
        );

        final newTime = DateTime(2024, 6, 15);
        final copy = original.copyWith(
          lastDeclineTime: newTime,
          declineCount: 3,
        );

        expect(copy.lastDeclineTime, equals(newTime));
        expect(copy.declineCount, equals(3));
      });

      test('creates copy with replaced declineCount only', () {
        final original = ValuePropDeclineInfo(
          lastDeclineTime: DateTime(2024, 1, 1),
          declineCount: 2,
        );

        final copy = original.copyWith(declineCount: 5);

        expect(copy.lastDeclineTime, equals(original.lastDeclineTime));
        expect(copy.declineCount, equals(5));
      });

      test('creates copy with replaced lastDeclineTime only', () {
        final original = ValuePropDeclineInfo(
          lastDeclineTime: DateTime(2024, 1, 1),
          declineCount: 2,
        );

        final newTime = DateTime(2024, 6, 15);
        final copy = original.copyWith(lastDeclineTime: newTime);

        expect(copy.lastDeclineTime, equals(newTime));
        expect(copy.declineCount, equals(original.declineCount));
      });

      test('creates identical copy when no fields specified', () {
        final original = ValuePropDeclineInfo(
          lastDeclineTime: DateTime(2024, 1, 1),
          declineCount: 2,
        );

        final copy = original.copyWith();

        expect(copy.lastDeclineTime, equals(original.lastDeclineTime));
        expect(copy.declineCount, equals(original.declineCount));
      });
    });

    group('toString', () {
      test('provides readable string representation', () {
        final info = ValuePropDeclineInfo(
          lastDeclineTime: DateTime(2024, 1, 1),
          declineCount: 3,
        );

        final str = info.toString();

        expect(str, contains('ValuePropDeclineInfo'));
        expect(str, contains('declineCount: 3'));
        expect(str, contains('lastDeclineTime'));
      });
    });
  });
}
