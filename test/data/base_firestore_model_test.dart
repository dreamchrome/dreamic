import 'package:dreamic/dreamic.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Tests for BaseFirestoreModel
///
/// These tests verify the core functionality of BaseFirestoreModel
/// and SmartTimestampConverter.
void main() {
  group('BaseFirestoreModel', () {
    test('SerializationContext enum has all expected values', () {
      expect(SerializationContext.values.length, 3);
      expect(SerializationContext.firestore, isNotNull);
      expect(SerializationContext.callable, isNotNull);
      expect(SerializationContext.local, isNotNull);
    });

    test('getCreateTimestampFields returns default value', () {
      final model = TestModel();
      expect(model.getCreateTimestampFields(), ['createdAt']);
    });

    test('getUpdateTimestampFields returns default value', () {
      final model = TestModel();
      expect(model.getUpdateTimestampFields(), ['updatedAt']);
    });

    test('postProcessJson returns json unchanged by default', () {
      final model = TestModel();
      final json = {'field': 'value'};
      final result = model.postProcessJson(json, SerializationContext.local);
      expect(result, equals(json));
    });

    test('toFirestore with isUpdate=false calls toFirestoreCreate', () {
      final model = TestModel();
      // ignore: deprecated_member_use_from_same_package
      final result = model.toFirestore(isUpdate: false);
      expect(result, isA<Map<String, dynamic>>());
    });

    test('toFirestore with isUpdate=true calls toFirestoreUpdate', () {
      final model = TestModel();
      // ignore: deprecated_member_use_from_same_package
      final result = model.toFirestore(isUpdate: true);
      expect(result, isA<Map<String, dynamic>>());
    });

    test('toFirestoreCreate returns map without null values', () {
      final model = TestModelWithNulls();
      final result = model.toFirestoreCreate();
      expect(result.containsKey('nullField'), false);
    });

    test('toFirestoreUpdate returns map without null values', () {
      final model = TestModelWithNulls();
      final result = model.toFirestoreUpdate();
      expect(result.containsKey('nullField'), false);
    });

    test('toFirestoreCreate excludes specified fields', () {
      final model = TestModelWithFields();
      final result = model.toFirestoreCreate(
        fieldsToExclude: ['excludeMe'],
      );
      expect(result.containsKey('excludeMe'), false);
      expect(result.containsKey('keepMe'), true);
    });

    test('toFirestoreUpdate excludes specified fields', () {
      final model = TestModelWithFields();
      final result = model.toFirestoreUpdate(
        fieldsToExclude: ['excludeMe'],
      );
      expect(result.containsKey('excludeMe'), false);
      expect(result.containsKey('keepMe'), true);
    });

    test('toFirestoreRaw preserves all non-null fields', () {
      final model = TestModelWithFields();
      final result = model.toFirestoreRaw();
      expect(result.containsKey('keepMe'), true);
      expect(result.containsKey('excludeMe'), true);
    });

    test('toCallable returns map', () {
      final model = TestModel();
      final result = model.toCallable();
      expect(result, isA<Map<String, dynamic>>());
    });
  });

  group('SmartTimestampConverter', () {
    const converter = SmartTimestampConverter();

    test('fromJson returns null for null input', () {
      expect(converter.fromJson(null), isNull);
    });

    test('fromJson handles Timestamp', () {
      final timestamp = Timestamp.fromDate(DateTime(2024, 1, 15, 10, 30));
      final result = converter.fromJson(timestamp);
      expect(result, isNotNull);
      expect(result!.year, 2024);
      expect(result.month, 1);
      expect(result.day, 15);
    });

    test('fromJson handles milliseconds (int)', () {
      final millis = DateTime(2024, 1, 15, 10, 30).millisecondsSinceEpoch;
      final result = converter.fromJson(millis);
      expect(result, isNotNull);
      expect(result!.year, 2024);
      expect(result.month, 1);
      expect(result.day, 15);
    });

    test('fromJson handles Map with _seconds and _nanoseconds', () {
      final timestamp = Timestamp.fromDate(DateTime(2024, 1, 15, 10, 30));
      final map = {
        '_seconds': timestamp.seconds,
        '_nanoseconds': timestamp.nanoseconds,
      };
      final result = converter.fromJson(map);
      expect(result, isNotNull);
      expect(result!.year, 2024);
      expect(result.month, 1);
      expect(result.day, 15);
    });

    test('fromJson handles Map with seconds and nanoseconds', () {
      final timestamp = Timestamp.fromDate(DateTime(2024, 1, 15, 10, 30));
      final map = {
        'seconds': timestamp.seconds,
        'nanoseconds': timestamp.nanoseconds,
      };
      final result = converter.fromJson(map);
      expect(result, isNotNull);
      expect(result!.year, 2024);
      expect(result.month, 1);
      expect(result.day, 15);
    });

    test('fromJson handles ISO 8601 string', () {
      final isoString = '2024-01-15T10:30:00.000Z';
      final result = converter.fromJson(isoString);
      expect(result, isNotNull);
      expect(result!.year, 2024);
      expect(result.month, 1);
      expect(result.day, 15);
    });

    test('toJson returns null for null input', () {
      expect(converter.toJson(null), isNull);
    });

    test('toJson returns milliseconds for DateTime', () {
      final dateTime = DateTime(2024, 1, 15, 10, 30);
      final result = converter.toJson(dateTime);
      expect(result, equals(dateTime.millisecondsSinceEpoch));
    });
  });

  group('SmartTimestampConverterNotNull', () {
    const converter = SmartTimestampConverterNotNull();

    test('fromJson returns epoch for null input', () {
      final result = converter.fromJson(null);
      expect(result.millisecondsSinceEpoch, 0);
    });

    test('fromJson handles valid input', () {
      final millis = DateTime(2024, 1, 15, 10, 30).millisecondsSinceEpoch;
      final result = converter.fromJson(millis);
      expect(result.year, 2024);
      expect(result.month, 1);
      expect(result.day, 15);
    });

    test('toJson returns milliseconds', () {
      final dateTime = DateTime(2024, 1, 15, 10, 30);
      final result = converter.toJson(dateTime);
      expect(result, equals(dateTime.millisecondsSinceEpoch));
    });
  });
}

// Test models

class TestModel extends BaseFirestoreModel {
  @override
  Map<String, dynamic> toJson() {
    return {'field': 'value'};
  }
}

class TestModelWithNulls extends BaseFirestoreModel {
  @override
  Map<String, dynamic> toJson() {
    return {
      'field': 'value',
      'nullField': null,
    };
  }
}

class TestModelWithFields extends BaseFirestoreModel {
  @override
  Map<String, dynamic> toJson() {
    return {
      'keepMe': 'value1',
      'excludeMe': 'value2',
    };
  }
}
