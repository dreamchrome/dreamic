import 'package:cloud_firestore/cloud_firestore.dart';

/// For use in reading from a Firebase function result. Not necessary if reading from Firestore directly.
Map<String, dynamic> convertDynamicMapToTypedMap(Map<dynamic, dynamic> input) {
  return input.map((key, value) => MapEntry(key.toString(), _convertValue(value)));
}

dynamic _convertValue(dynamic value) {
  if (value is Map) return convertDynamicMapToTypedMap(value);
  if (value is List) return value.map((e) => _convertValue(e)).toList();
  return value;
}

/// For use in writing to Firestore directly. This isn't necessary if calling a Firebase function.
dynamic convertJsonToTimestamps(dynamic value) {
  if (value is Map<String, dynamic>) {
    if (value.containsKey('_seconds') && value.containsKey('_nanoseconds')) {
      return Timestamp(value['_seconds'], value['_nanoseconds']);
    }
    return value.map((key, val) => MapEntry(key, convertJsonToTimestamps(val)));
  }
  if (value is List) {
    return value.map((e) => convertJsonToTimestamps(e)).toList();
  }
  return value;
}
