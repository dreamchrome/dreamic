// ============================================================================
// Enum Serialization Helpers
// ============================================================================
// These helper functions enable safe enum serialization that handles unknown
// enum values gracefully. Use them in enum extensions with static methods
// that are called via @JsonKey annotations.
//
// WHY THIS APPROACH:
// - json_serializable IGNORES @JsonConverter annotations on non-nullable enums
// - The old converter class approach was broken and would crash on unknown values
// - Static methods in extensions are ALWAYS called when specified in @JsonKey
// - This centralizes logic on the enum itself, making it maintainable
//
// USAGE PATTERN:
// 1. Define your enum
// 2. Add an extension with static deserialize/serialize methods
// 3. Use @JsonKey(fromJson: EnumType.deserialize, toJson: EnumType.serialize)
//
// See examples at the bottom of this file for all three strategies.

// ============================================================================
// Core Helper Functions
// ============================================================================

/// Safely deserialize an enum from a JSON string value.
///
/// Handles unknown enum values by returning null or a default value based
/// on the strategy chosen.
///
/// **Parameters:**
/// - `value`: The string value from JSON
/// - `enumValues`: List of all possible enum values (use `EnumType.values`)
/// - `defaultValue`: Value to return for unknown strings (if null, returns null)
/// - `onUnknownValue`: Optional callback for logging unknown values
///
/// **Returns:**
/// The matched enum value, `defaultValue`, or null
///
/// **Example:**
/// ```dart
/// extension PostStatusExtension on PostStatus {
///   static PostStatus? deserialize(String? value) {
///     return safeEnumFromJson(
///       value,
///       PostStatus.values,
///       defaultValue: PostStatus.draft,
///       onUnknownValue: (v) => logw('Unknown PostStatus: $v'),
///     );
///   }
/// }
/// ```
T? safeEnumFromJson<T extends Enum>(
  String? value,
  List<T> enumValues, {
  T? defaultValue,
  void Function(String unknownValue)? onUnknownValue,
}) {
  if (value == null) return null;

  try {
    // Try to find matching enum by name
    return enumValues.firstWhere(
      (e) => e.name == value,
      orElse: () => throw Exception('Unknown enum value: $value'),
    );
  } catch (e) {
    // Unknown value encountered
    if (onUnknownValue != null) {
      onUnknownValue(value);
    }
    return defaultValue;
  }
}

/// Safely serialize an enum to a JSON string value.
///
/// This is straightforward - just returns the enum's name or null.
///
/// **Parameters:**
/// - `value`: The enum value to serialize (can be null)
///
/// **Returns:**
/// The enum's name as a string, or null
///
/// **Example:**
/// ```dart
/// extension PostStatusExtension on PostStatus {
///   static String? serialize(PostStatus? value) {
///     return safeEnumToJson(value);
///   }
/// }
/// ```
String? safeEnumToJson<T extends Enum>(T? value) {
  return value?.name;
}

// ============================================================================
// Usage Examples - Three Strategies
// ============================================================================

// STRATEGY 1: NULLABLE (Unknown → null)
// ============================================
// Use for optional enum fields where null is an acceptable state.
//
// enum UserRole {
//   guest,
//   member,
//   moderator,
//   admin,
// }
//
// extension on UserRole {
//   static UserRole? deserialize(String? value) {
//     return safeEnumFromJson(
//       value,
//       UserRole.values,
//       // No defaultValue - returns null for unknown values
//     );
//   }
//
//   static String? serialize(UserRole? value) {
//     return safeEnumToJson(value);
//   }
// }
//
// @JsonSerializable()
// class UserModel extends BaseFirestoreModel {
//   @JsonKey(fromJson: UserRole.deserialize, toJson: UserRole.serialize)
//   final UserRole? role;  // nullable
//
//   UserModel({this.role});
//
//   factory UserModel.fromJson(Map<String, dynamic> json) =>
//       _$UserModelFromJson(json);
//
//   @override
//   Map<String, dynamic> toJson() => _$UserModelToJson(this);
// }
//
// WHAT HAPPENS:
// - Server sends "superAdmin" (unknown)
// - App receives: role = null
// - No crash! ✅

// STRATEGY 2: DEFAULT VALUE (Unknown → default)
// ===============================================
// Use for required enum fields where you want a safe fallback value.
//
// enum PostStatus {
//   draft,
//   published,
//   archived,
// }
//
// extension on PostStatus {
//   static PostStatus? deserialize(String? value) {
//     return safeEnumFromJson(
//       value,
//       PostStatus.values,
//       defaultValue: PostStatus.draft,  // Safe default
//     );
//   }
//
//   static String? serialize(PostStatus? value) {
//     return safeEnumToJson(value);
//   }
// }
//
// @JsonSerializable()
// class PostModel extends BaseFirestoreModel {
//   @JsonKey(fromJson: PostStatus.deserialize, toJson: PostStatus.serialize)
//   final PostStatus status;  // non-nullable with default
//
//   PostModel({required this.status});
//
//   factory PostModel.fromJson(Map<String, dynamic> json) =>
//       _$PostModelFromJson(json);
//
//   @override
//   Map<String, dynamic> toJson() => _$PostModelToJson(this);
// }
//
// WHAT HAPPENS:
// - Server sends "scheduled" (unknown)
// - App receives: status = PostStatus.draft
// - No crash! ✅

// STRATEGY 3: LOGGING + DEFAULT (Unknown → log + default)
// =========================================================
// Use for critical fields where you want visibility into unknown values.
//
// enum PaymentStatus {
//   pending,
//   processing,
//   completed,
//   failed,
// }
//
// extension on PaymentStatus {
//   static PaymentStatus? deserialize(String? value) {
//     return safeEnumFromJson(
//       value,
//       PaymentStatus.values,
//       defaultValue: PaymentStatus.pending,
//       onUnknownValue: (v) {
//         // Use dreamic's logging
//         logw('Unknown PaymentStatus: $v, defaulting to pending');
//       },
//     );
//   }
//
//   static String? serialize(PaymentStatus? value) {
//     return safeEnumToJson(value);
//   }
// }
//
// @JsonSerializable()
// class PaymentModel extends BaseFirestoreModel {
//   @JsonKey(fromJson: PaymentStatus.deserialize, toJson: PaymentStatus.serialize)
//   final PaymentStatus status;  // non-nullable with logging
//
//   PaymentModel({required this.status});
//
//   factory PaymentModel.fromJson(Map<String, dynamic> json) =>
//       _$PaymentModelFromJson(json);
//
//   @override
//   Map<String, dynamic> toJson() => _$PaymentModelToJson(this);
// }
//
// WHAT HAPPENS:
// - Server sends "refunded" (unknown)
// - App logs: "Unknown PaymentStatus: refunded, defaulting to pending"
// - App receives: status = PaymentStatus.pending
// - No crash! ✅
//
// You can also send this to error reporting:
// onUnknownValue: (v) {
//   loge('Critical: Unknown PaymentStatus: $v');
//   // This will report to configured error reporter (Sentry, etc.)
// }

// ============================================================================
// Real-World Scenario
// ============================================================================
//
// TIMELINE:
// 1. App v1.0 ships with PostStatus { draft, published, archived }
// 2. Server update adds PostStatus.scheduled
// 3. App v1.0 users receive posts with status: "scheduled"
//
// WITHOUT THIS SOLUTION:
// - json_serializable encounters "scheduled"
// - Throws exception: "Unknown enum value"
// - App crashes 💥
//
// WITH THIS SOLUTION (using extension + @JsonKey):
// - Extension's deserialize() method is called
// - safeEnumFromJson() catches unknown value
// - Returns PostStatus.draft (or null, depending on strategy)
// - App continues working ✅
//
// KEY INSIGHT:
// @JsonKey explicitly tells json_serializable to call YOUR method,
// bypassing its built-in enum handling that would crash.

// ============================================================================
// AI Implementation Guide
// ============================================================================
//
// When creating a new enum that needs safe serialization:
//
// 1. Define the enum:
//    ```dart
//    enum Priority { low, medium, high }
//    ```
//
// 2. Add unnamed extension with static methods:
//    ```dart
//    extension on Priority {
//      static Priority? deserialize(String? value) {
//        return safeEnumFromJson(
//          value,
//          Priority.values,
//          defaultValue: Priority.medium,  // or omit for nullable
//          onUnknownValue: (v) => logw('Unknown Priority: $v'),  // optional
//        );
//      }
//
//      static String? serialize(Priority? value) {
//        return safeEnumToJson(value);
//      }
//    }
//    ```
//
// 3. In your model, use @JsonKey:
//    ```dart
//    @JsonKey(fromJson: Priority.deserialize, toJson: Priority.serialize)
//    final Priority priority;
//    ```
//
// 4. Run build_runner:
//    ```bash
//    dart run build_runner build --delete-conflicting-outputs
//    ```
//
// IMPORTANT: Always use @JsonKey(fromJson:, toJson:) for enums.
// Never use just the enum type alone - json_serializable's default
// enum handling will crash on unknown values!
