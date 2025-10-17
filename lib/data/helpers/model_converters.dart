import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:json_annotation/json_annotation.dart';

class TimestampConverter implements JsonConverter<DateTime, Object> {
  const TimestampConverter();

  @override
  DateTime fromJson(Object timestamp) {
    if (timestamp is Timestamp) {
      return timestamp.toDate();
    } else if (timestamp is Map) {
      Map<Object?, Object?> timestampMap = timestamp;
      int seconds = timestampMap['_seconds'] as int;
      int nanoseconds = timestampMap['_nanoseconds'] as int;
      return DateTime.fromMicrosecondsSinceEpoch(seconds * 1000000 + nanoseconds ~/ 1000);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  @override
  Map<String, dynamic> toJson(DateTime date) {
    final timestamp = Timestamp.fromDate(date);
    return {
      '_seconds': timestamp.seconds,
      '_nanoseconds': timestamp.nanoseconds,
    };
  }
}

//TODO: move to the other file
// Utility functions for Firestore conversion
class FirestoreJsonTimestampConverter {
  static dynamic convertJson(dynamic value) {
    if (value is Map<String, dynamic>) {
      if (value.containsKey('_seconds') && value.containsKey('_nanoseconds')) {
        return Timestamp(value['_seconds'], value['_nanoseconds']);
      }
      return value.map((key, val) => MapEntry(key, convertJson(val)));
    }
    if (value is List) {
      return value.map((e) => convertJson(e)).toList();
    }
    return value;
  }
}

// Usage example:
// final jsonData = myModel.toJson();
// final firestoreData = TimestampUtil.convertForFirestore(jsonData);
// await firestore.collection('items').add(firestoreData);

// class TimestampConverter implements JsonConverter<DateTime, Object> {
//   const TimestampConverter();

//   @override
//   DateTime fromJson(Object timestamp) {
//     if (timestamp is Timestamp) {
//       return timestamp.toDate();
//     } else if (timestamp is Map) {
//       Map<Object?, Object?> timestampMap = timestamp;
//       int seconds = timestampMap['_seconds'] as int;
//       int nanoseconds = timestampMap['_nanoseconds'] as int;
//       DateTime dateTimeUtc =
//           DateTime.fromMicrosecondsSinceEpoch(seconds * 1000000 + nanoseconds ~/ 1000);
//       return dateTimeUtc;
//     } else {
//       return DateTime.fromMillisecondsSinceEpoch(0);
//     }
//   }

//   // @override
//   // Timestamp toJson(DateTime date) => Timestamp.fromDate(date);
//   @override
//   Map<String, dynamic> toJson(DateTime date) {
//     final timestamp = Timestamp.fromDate(date);
//     return {
//       '_seconds': timestamp.seconds,
//       '_nanoseconds': timestamp.nanoseconds,
//     };
//   }
// }

//TODO: fix what happens when null. Today? or what
class TimestampNullableConverter implements JsonConverter<DateTime?, Object?> {
  const TimestampNullableConverter();

  @override
  DateTime? fromJson(Object? timestamp) {
    if (timestamp is Timestamp) {
      return timestamp.toDate();
    } else if (timestamp is Map) {
      Map<Object?, Object?> timestampMap = timestamp;
      int seconds = timestampMap['_seconds'] as int;
      int nanoseconds = timestampMap['_nanoseconds'] as int;
      DateTime dateTimeUtc =
          DateTime.fromMicrosecondsSinceEpoch(seconds * 1000000 + nanoseconds ~/ 1000);
      return dateTimeUtc;
    } else {
      // return DateTime.fromMillisecondsSinceEpoch(0);
      return null;
    }
  }

  // @override
  // Object? toJson(DateTime? date) => date == null ? null : Timestamp.fromDate(date);
  @override
  Map<String, dynamic>? toJson(DateTime? date) {
    if (date == null) return null;
    final timestamp = Timestamp.fromDate(date);
    return {
      '_seconds': timestamp.seconds,
      '_nanoseconds': timestamp.nanoseconds,
    };
  }
}

class TimestampCreationConverter implements JsonConverter<DateTime?, Object?> {
  const TimestampCreationConverter();

  @override
  DateTime? fromJson(Object? timestamp) {
    if (timestamp is Timestamp) {
      return timestamp.toDate();
    } else if (timestamp is Map) {
      Map<Object?, Object?> timestampMap = timestamp;
      int seconds = timestampMap['_seconds'] as int;
      int nanoseconds = timestampMap['_nanoseconds'] as int;
      DateTime dateTimeUtc =
          DateTime.fromMicrosecondsSinceEpoch(seconds * 1000000 + nanoseconds ~/ 1000);
      return dateTimeUtc;
    } else {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  @override
  Object? toJson(DateTime? date) => date == null ? FieldValue.serverTimestamp() : null;
}

class TimestampModifiedConverter implements JsonConverter<DateTime, Object> {
  const TimestampModifiedConverter();

  @override
  DateTime fromJson(Object timestamp) {
    if (timestamp is Timestamp) {
      return timestamp.toDate();
    } else if (timestamp is Map) {
      Map<Object?, Object?> timestampMap = timestamp;
      int seconds = timestampMap['_seconds'] as int;
      int nanoseconds = timestampMap['_nanoseconds'] as int;
      DateTime dateTimeUtc =
          DateTime.fromMicrosecondsSinceEpoch(seconds * 1000000 + nanoseconds ~/ 1000);
      return dateTimeUtc;
    } else {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  @override
  Object toJson(DateTime date) => FieldValue.serverTimestamp();
}

class TimestampNullableModifiedConverter implements JsonConverter<DateTime?, Object?> {
  const TimestampNullableModifiedConverter();

  @override
  DateTime? fromJson(Object? timestamp) {
    if (timestamp is Timestamp) {
      return timestamp.toDate();
    } else if (timestamp is Map) {
      Map<Object?, Object?> timestampMap = timestamp;
      int seconds = timestampMap['_seconds'] as int;
      int nanoseconds = timestampMap['_nanoseconds'] as int;
      DateTime dateTimeUtc =
          DateTime.fromMicrosecondsSinceEpoch(seconds * 1000000 + nanoseconds ~/ 1000);
      return dateTimeUtc;
    } else {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  @override
  Object? toJson(DateTime? date) => FieldValue.serverTimestamp();
}

//TODO: as many others, I had to make this List<dynamic> because of the error. Make sure others are updated
class TimestampNullableListConverter implements JsonConverter<List<DateTime>?, List<dynamic>?> {
  const TimestampNullableListConverter();

  @override
  List<DateTime>? fromJson(List<dynamic>? timestamps) {
    // return timestamps?.map((e as Timestamp) => e.toDate()).toList<Timestamp>();
    return timestamps?.map((e) => (e as Timestamp).toDate()).toList();
  }

  @override
  List<Timestamp>? toJson(List<DateTime>? dates) {
    return dates?.map((e) => Timestamp.fromDate(e)).toList();
  }
}

// ============================================================================
// Function-Safe Timestamp Converters
// ============================================================================
// These converters serialize DateTime to milliseconds (int) which is
// JSON-serializable and works with Firebase Cloud Functions.
// Use these for regular DateTime fields that need to be sent to Cloud Functions.

/// Converts DateTime to/from milliseconds since epoch (function-safe)
class TimestampMillisConverter implements JsonConverter<DateTime, Object> {
  const TimestampMillisConverter();

  @override
  DateTime fromJson(Object timestamp) {
    if (timestamp is Timestamp) {
      return timestamp.toDate();
    } else if (timestamp is int) {
      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    } else if (timestamp is Map) {
      Map<Object?, Object?> timestampMap = timestamp;
      int seconds = timestampMap['_seconds'] as int;
      int nanoseconds = timestampMap['_nanoseconds'] as int;
      return DateTime.fromMicrosecondsSinceEpoch(seconds * 1000000 + nanoseconds ~/ 1000);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  @override
  int toJson(DateTime date) => date.millisecondsSinceEpoch;
}

/// Converts nullable DateTime to/from milliseconds since epoch (function-safe)
class TimestampMillisNullableConverter implements JsonConverter<DateTime?, Object?> {
  const TimestampMillisNullableConverter();

  @override
  DateTime? fromJson(Object? timestamp) {
    if (timestamp == null) return null;
    if (timestamp is Timestamp) {
      return timestamp.toDate();
    } else if (timestamp is int) {
      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    } else if (timestamp is Map) {
      Map<Object?, Object?> timestampMap = timestamp;
      int seconds = timestampMap['_seconds'] as int;
      int nanoseconds = timestampMap['_nanoseconds'] as int;
      return DateTime.fromMicrosecondsSinceEpoch(seconds * 1000000 + nanoseconds ~/ 1000);
    }
    return null;
  }

  @override
  int? toJson(DateTime? date) => date?.millisecondsSinceEpoch;
}

// ============================================================================
// Smart Timestamp Converters (Enhanced for BaseFirestoreModel)
// ============================================================================
// These converters are designed to work with BaseFirestoreModel and handle
// multiple timestamp formats intelligently. They work across all contexts:
// Firestore Timestamps, Cloud Functions Map format, milliseconds, and ISO strings.

/// Smart timestamp converter that handles multiple formats and contexts.
///
/// This converter is the recommended choice for use with [BaseFirestoreModel].
/// It intelligently handles:
/// - Firestore Timestamp objects
/// - Cloud Functions Map format ({_seconds, _nanoseconds})
/// - Milliseconds since epoch (int)
/// - ISO 8601 strings
///
/// For serialization (toJson), it always returns milliseconds, and
/// [BaseFirestoreModel] will handle conversion to FieldValue.serverTimestamp
/// or Timestamp based on the context and field configuration.
///
/// Example:
/// ```dart
/// @SmartTimestampConverter()
/// final DateTime? createdAt;
///
/// @SmartTimestampConverter()
/// final DateTime? updatedAt;
/// ```
class SmartTimestampConverter implements JsonConverter<DateTime?, dynamic> {
  const SmartTimestampConverter();

  @override
  DateTime? fromJson(dynamic data) {
    if (data == null) return null;

    try {
      // Handle Firestore Timestamp
      if (data is Timestamp) {
        return data.toDate();
      }

      // Handle Cloud Functions Map format
      if (data is Map) {
        final seconds = data['_seconds'] ?? data['seconds'];
        final nanoseconds = data['_nanoseconds'] ?? data['nanoseconds'];

        if (seconds != null) {
          return Timestamp(
            seconds as int,
            (nanoseconds as int?) ?? 0,
          ).toDate();
        }
      }

      // Handle milliseconds
      if (data is int) {
        return DateTime.fromMillisecondsSinceEpoch(data);
      }

      // Handle ISO string
      if (data is String) {
        return DateTime.tryParse(data);
      }
    } catch (e) {
      // ignore: avoid_print
      print('Error parsing timestamp: $e');
    }

    return null;
  }

  @override
  dynamic toJson(DateTime? dateTime) {
    if (dateTime == null) return null;

    // Always return as milliseconds for JSON compatibility
    // The BaseFirestoreModel will handle conversion to FieldValue.serverTimestamp
    // or Timestamp based on the context and field configuration
    return dateTime.millisecondsSinceEpoch;
  }
}

/// Non-nullable version of [SmartTimestampConverter].
///
/// Use this for non-nullable DateTime fields. Returns epoch (1970-01-01)
/// if parsing fails.
///
/// Example:
/// ```dart
/// @SmartTimestampConverterNotNull()
/// final DateTime timestamp;
/// ```
class SmartTimestampConverterNotNull implements JsonConverter<DateTime, dynamic> {
  const SmartTimestampConverterNotNull();

  @override
  DateTime fromJson(dynamic data) {
    return const SmartTimestampConverter().fromJson(data) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  @override
  dynamic toJson(DateTime dateTime) {
    return dateTime.millisecondsSinceEpoch;
  }
}
