import 'package:json_annotation/json_annotation.dart';

// ============================================================================
// Robust Enum Converters
// ============================================================================
// These converters handle unknown enum values gracefully without requiring
// an "unknown" value in every enum or manual @JsonKey annotations.
//
// Benefits:
// - No need for @JsonKey(unknownEnumValue: ...) on every field
// - No need for an "unknown" value in every enum
// - Centralized handling of deserialization failures
// - Choose between nullable or default value strategies
// - Better error reporting and logging

/// Base class for enum converters that handle unknown values gracefully.
///
/// Instead of throwing an exception when encountering an unknown enum value
/// (which would crash older app versions when the server adds new enum values),
/// this converter provides fallback strategies.
///
/// **Type Parameters:**
/// - `T`: The enum type to convert
///
/// **Abstract Methods:**
/// - `enumValues`: Returns all possible enum values for type T
/// - `handleUnknownValue`: Defines what to do when an unknown value is encountered
///
/// Example:
/// ```dart
/// class UserTypeConverter extends RobustEnumConverter<UserType> {
///   const UserTypeConverter();
///
///   @override
///   List<UserType> get enumValues => UserType.values;
///
///   @override
///   UserType? handleUnknownValue(String? value) {
///     // Option 1: Return a default value
///     return UserType.standard;
///
///     // Option 2: Return null (for nullable fields)
///     // return null;
///
///     // Option 3: Log and return default
///     // logger.warning('Unknown UserType: $value, defaulting to standard');
///     // return UserType.standard;
///   }
/// }
/// ```
abstract class RobustEnumConverter<T extends Enum> implements JsonConverter<T?, String?> {
  const RobustEnumConverter();

  /// Returns all possible values for the enum type T.
  /// Should return `T.values` in your implementation.
  List<T> get enumValues;

  /// Defines the fallback behavior when an unknown value is encountered.
  ///
  /// **Options:**
  /// 1. Return a default enum value (recommended for non-nullable fields)
  /// 2. Return null (recommended for nullable fields)
  /// 3. Log the issue and return a default/null
  ///
  /// **Parameters:**
  /// - `value`: The unknown string value from JSON
  ///
  /// **Returns:**
  /// The fallback enum value or null
  T? handleUnknownValue(String? value);

  @override
  T? fromJson(String? json) {
    if (json == null) return null;

    try {
      // Try to find matching enum by name
      return enumValues.firstWhere(
        (e) => e.name == json,
        orElse: () => throw Exception('Unknown enum value'),
      );
    } catch (e) {
      // Unknown value encountered - use the fallback strategy
      return handleUnknownValue(json);
    }
  }

  @override
  String? toJson(T? value) => value?.name;
}

// ============================================================================
// Convenience Converters for Common Patterns
// ============================================================================

/// A nullable enum converter that returns null for unknown values.
///
/// Use this for nullable enum fields where you want unknown values
/// to be treated as null.
///
/// Example:
/// ```dart
/// enum UserType {
///   admin,
///   moderator,
///   standard,
/// }
///
/// class UserTypeNullableConverter extends NullableEnumConverter<UserType> {
///   const UserTypeNullableConverter();
///
///   @override
///   List<UserType> get enumValues => UserType.values;
/// }
///
/// // Usage in model:
/// @JsonSerializable()
/// class UserModel {
///   @UserTypeNullableConverter()
///   final UserType? type;
/// }
/// ```
abstract class NullableEnumConverter<T extends Enum> extends RobustEnumConverter<T> {
  const NullableEnumConverter();

  @override
  T? handleUnknownValue(String? value) {
    // Return null for unknown values
    // Optionally log for debugging:
    // if (value != null) {
    //   debugPrint('Unknown enum value for ${T}: $value');
    // }
    return null;
  }
}

/// A default value enum converter that returns a specified default for unknown values.
///
/// Use this for non-nullable enum fields where you want unknown values
/// to default to a specific value.
///
/// Example:
/// ```dart
/// enum UserType {
///   admin,
///   moderator,
///   standard,
/// }
///
/// class UserTypeConverter extends DefaultEnumConverter<UserType> {
///   const UserTypeConverter();
///
///   @override
///   List<UserType> get enumValues => UserType.values;
///
///   @override
///   UserType get defaultValue => UserType.standard;
/// }
///
/// // Usage in model:
/// @JsonSerializable()
/// class UserModel {
///   @UserTypeConverter()
///   final UserType type;
/// }
/// ```
abstract class DefaultEnumConverter<T extends Enum> extends RobustEnumConverter<T> {
  const DefaultEnumConverter();

  /// The default value to return for unknown enum values.
  T get defaultValue;

  @override
  T? handleUnknownValue(String? value) {
    // Optionally log for debugging:
    // if (value != null) {
    //   debugPrint('Unknown enum value for ${T}: $value, using default: ${defaultValue.name}');
    // }
    return defaultValue;
  }
}

/// A logging enum converter that logs unknown values before returning a default.
///
/// Use this during development or when you want to track when unknown
/// enum values are encountered in production.
///
/// **Note:** You'll need to implement the logging based on your app's logger.
///
/// Example:
/// ```dart
/// enum UserType {
///   admin,
///   moderator,
///   standard,
/// }
///
/// class UserTypeConverter extends LoggingEnumConverter<UserType> {
///   const UserTypeConverter();
///
///   @override
///   List<UserType> get enumValues => UserType.values;
///
///   @override
///   UserType get defaultValue => UserType.standard;
///
///   @override
///   void logUnknownValue(String value) {
///     // Use your app's logger
///     logger.warning('Unknown UserType encountered: $value');
///     // Or report to error tracking
///     // errorReporter.logError('Unknown UserType: $value');
///   }
/// }
/// ```
abstract class LoggingEnumConverter<T extends Enum> extends DefaultEnumConverter<T> {
  const LoggingEnumConverter();

  /// Override this to log unknown values using your app's logger.
  void logUnknownValue(String value);

  @override
  T? handleUnknownValue(String? value) {
    if (value != null) {
      logUnknownValue(value);
    }
    return defaultValue;
  }
}

// ============================================================================
// Batch Converter Generator (Advanced)
// ============================================================================

/// Helper function to create a simple nullable enum converter.
///
/// This is useful for quickly creating converters without defining a class.
///
/// **Note:** Due to Dart's const constructor requirements, you'll still need
/// to create actual converter classes for use with @JsonKey annotations.
/// This is provided as a reference implementation.
///
/// Example:
/// ```dart
/// // This won't work directly with @JsonKey due to const requirements:
/// // @JsonKey(converter: createNullableEnumConverter<UserType>())  // ❌
///
/// // But you can use it as a pattern to create your converters:
/// class UserTypeConverter extends NullableEnumConverter<UserType> {
///   const UserTypeConverter();
///   @override
///   List<UserType> get enumValues => UserType.values;
/// }
/// ```
JsonConverter<T?, String?> createNullableEnumConverter<T extends Enum>(
  List<T> enumValues,
) {
  return _NullableEnumConverterImpl<T>(enumValues);
}

class _NullableEnumConverterImpl<T extends Enum> extends NullableEnumConverter<T> {
  final List<T> _enumValues;

  const _NullableEnumConverterImpl(this._enumValues);

  @override
  List<T> get enumValues => _enumValues;
}

// ============================================================================
// Usage Examples
// ============================================================================

// Example 1: Nullable enum (returns null for unknown values)
// ------------------------------------------------------------
// enum NotificationPriority {
//   low,
//   medium,
//   high,
//   urgent,
// }
//
// class NotificationPriorityConverter extends NullableEnumConverter<NotificationPriority> {
//   const NotificationPriorityConverter();
//
//   @override
//   List<NotificationPriority> get enumValues => NotificationPriority.values;
// }
//
// @JsonSerializable()
// class NotificationModel {
//   final String message;
//
//   @NotificationPriorityConverter()
//   final NotificationPriority? priority;  // nullable - unknown values become null
//
//   NotificationModel({
//     required this.message,
//     this.priority,
//   });
// }

// Example 2: Non-nullable enum with default value
// ------------------------------------------------
// enum UserRole {
//   guest,
//   member,
//   moderator,
//   admin,
// }
//
// class UserRoleConverter extends DefaultEnumConverter<UserRole> {
//   const UserRoleConverter();
//
//   @override
//   List<UserRole> get enumValues => UserRole.values;
//
//   @override
//   UserRole get defaultValue => UserRole.guest;  // Unknown values become 'guest'
// }
//
// @JsonSerializable()
// class UserModel {
//   final String name;
//
//   @UserRoleConverter()
//   final UserRole role;  // non-nullable - unknown values become 'guest'
//
//   UserModel({
//     required this.name,
//     required this.role,
//   });
// }

// Example 3: Enum with logging (for debugging/monitoring)
// --------------------------------------------------------
// enum PaymentStatus {
//   pending,
//   processing,
//   completed,
//   failed,
// }
//
// class PaymentStatusConverter extends LoggingEnumConverter<PaymentStatus> {
//   const PaymentStatusConverter();
//
//   @override
//   List<PaymentStatus> get enumValues => PaymentStatus.values;
//
//   @override
//   PaymentStatus get defaultValue => PaymentStatus.pending;
//
//   @override
//   void logUnknownValue(String value) {
//     // Use your app's logger - example with dreamic logger:
//     logger.log(
//       'Unknown PaymentStatus value: $value, defaulting to pending',
//       logType: LogType.error,
//     );
//   }
// }
//
// @JsonSerializable()
// class PaymentModel {
//   final String id;
//   final double amount;
//
//   @PaymentStatusConverter()
//   final PaymentStatus status;
//
//   PaymentModel({
//     required this.id,
//     required this.amount,
//     required this.status,
//   });
// }

// Example 4: Multiple enums in one model
// ---------------------------------------
// @JsonSerializable()
// class ContentModel {
//   final String id;
//   final String title;
//
//   @ContentTypeConverter()
//   final ContentType type;
//
//   @ContentStatusConverter()
//   final ContentStatus? status;
//
//   @ContentVisibilityConverter()
//   final ContentVisibility visibility;
//
//   ContentModel({
//     required this.id,
//     required this.title,
//     required this.type,
//     this.status,
//     required this.visibility,
//   });
// }
