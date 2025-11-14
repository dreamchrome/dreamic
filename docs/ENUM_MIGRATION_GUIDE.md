# Enum Serialization Migration Guide

**For AI Assistants: This guide provides complete instructions for migrating Dart/Flutter projects from the broken enum converter pattern to the working helper function pattern.**

## 🚨 The Problem

**Critical Bug**: `json_serializable` has an undocumented bug where it **completely ignores** `@JsonConverter` annotations on **non-nullable enum fields** (the most common case). This causes crashes when the server sends enum values the client doesn't recognize.

### What Breaks

```dart
// ❌ THIS DOES NOT WORK - json_serializable ignores @JsonConverter on non-nullable enums
class UserProfileConverter extends NullableEnumConverter<UserRole> {
  const UserProfileConverter() : super(UserRole.values);
}

@JsonSerializable()
class UserProfile {
  @UserProfileConverter()  // ⚠️ IGNORED by json_serializable!
  final UserRole role;     // Non-nullable enum - converter is completely ignored
}

// Generated code uses built-in $enumDecode which CRASHES on unknown values:
UserProfile _$UserProfileFromJson(Map<String, dynamic> json) => UserProfile(
  role: $enumDecode(_$UserRoleEnumMap, json['role']),  // 💥 CRASH!
);
```

**Result**: App crashes with `ArgumentError` when server adds new enum values.

### Why It Fails

1. `json_serializable` only respects `@JsonConverter` on **nullable** enum fields (`UserRole?`)
2. For non-nullable enums, it always uses the built-in `$enumDecode()` function
3. `$enumDecode()` throws an exception on unknown enum values
4. There is no way to make `@JsonConverter` work on non-nullable enums

## ✅ The Solution

**Use `@JsonKey` with helper functions** instead of `@JsonConverter` classes. The `@JsonKey` annotation is **ALWAYS** respected by `json_serializable`.

### Pattern Overview

```dart
// 1. Define your enum
enum UserRole { admin, moderator, user, guest }

// 2. Create helper functions (top-level, not in a class)
UserRole _deserializeUserRole(String? value) {
  return safeEnumFromJson(
    value,
    UserRole.values,
    defaultValue: UserRole.guest,
  )!;
}

String? _serializeUserRole(UserRole? value) {
  return safeEnumToJson(value);
}

// 3. Use @JsonKey annotation (NOT @JsonConverter)
@JsonSerializable()
class UserProfile {
  @JsonKey(fromJson: _deserializeUserRole, toJson: _serializeUserRole)
  final UserRole role;  // ✅ Works perfectly!
  
  UserProfile({required this.role});
  
  factory UserProfile.fromJson(Map<String, dynamic> json) =>
      _$UserProfileFromJson(json);
  Map<String, dynamic> toJson() => _$UserProfileToJson(this);
}
```

## 🔧 Migration Steps

### Step 1: Add Core Helper Functions

First, ensure you have the core `safeEnumFromJson` and `safeEnumToJson` functions available. In the Dreamic package, these are in `lib/data/helpers/enum_converters.dart`:

```dart
/// Safely deserialize enum from JSON with fallback handling
T? safeEnumFromJson<T>(
  String? value,
  List<T> enumValues, {
  T? defaultValue,
  void Function(String)? onUnknownValue,
}) {
  if (value == null) return defaultValue;
  
  try {
    return enumValues.firstWhere(
      (e) => e.toString().split('.').last == value,
    );
  } catch (_) {
    onUnknownValue?.call(value);
    return defaultValue;
  }
}

/// Safely serialize enum to JSON
String? safeEnumToJson<T>(T? value) {
  return value?.toString().split('.').last;
}
```

**For non-Dreamic projects**: Copy these functions into your project or install the Dreamic package.

### Step 2: Choose Your Strategy

Pick one of three strategies based on your requirements:

#### Strategy A: Nullable (Unknown → null)

**Use when**: Field is optional and you can handle null values.

```dart
enum PostStatus { draft, published, archived }

// Helper returns nullable type
PostStatus? _deserializePostStatus(String? value) {
  return safeEnumFromJson(value, PostStatus.values);
}

String? _serializePostStatus(PostStatus? value) {
  return safeEnumToJson(value);
}

@JsonSerializable()
class Post {
  @JsonKey(fromJson: _deserializePostStatus, toJson: _serializePostStatus)
  final PostStatus? status;  // Nullable field
}
```

**Behavior**: Unknown values → `null` (e.g., `"future_status"` → `null`)

#### Strategy B: Default (Unknown → Default Value)

**Use when**: Field is required and you need a safe fallback.

```dart
enum UserRole { admin, moderator, user, guest }

// Helper returns non-null with default
UserRole _deserializeUserRole(String? value) {
  return safeEnumFromJson(
    value,
    UserRole.values,
    defaultValue: UserRole.guest,  // Fallback value
  )!;
}

String? _serializeUserRole(UserRole? value) {
  return safeEnumToJson(value);
}

@JsonSerializable()
class UserProfile {
  @JsonKey(fromJson: _deserializeUserRole, toJson: _serializeUserRole)
  final UserRole role;  // Non-nullable field
}
```

**Behavior**: Unknown values → `UserRole.guest` (e.g., `"superadmin"` → `guest`)

#### Strategy C: Logging (Unknown → Log + Default)

**Use when**: You want to monitor unknown values in production.

```dart
enum NotificationPriority { critical, high, normal, low }

// Helper logs unknown values before defaulting
NotificationPriority _deserializeNotificationPriority(String? value) {
  return safeEnumFromJson(
    value,
    NotificationPriority.values,
    defaultValue: NotificationPriority.normal,
    onUnknownValue: (v) {
      logw('Unknown NotificationPriority: $v, using normal');
    },
  )!;
}

String? _serializeNotificationPriority(NotificationPriority? value) {
  return safeEnumToJson(value);
}

@JsonSerializable()
class Notification {
  @JsonKey(
    fromJson: _deserializeNotificationPriority,
    toJson: _serializeNotificationPriority,
  )
  final NotificationPriority priority;
}
```

**Behavior**: Unknown values → Log warning + `NotificationPriority.normal`

### Step 3: Automated Migration

Use the migration script to automatically convert your codebase:

```bash
# Preview changes without modifying files
dart run migration_scripts/migrate_enum_converters.dart --dry-run

# Apply migration to all files
dart run migration_scripts/migrate_enum_converters.dart

# Apply to specific directory
dart run migration_scripts/migrate_enum_converters.dart lib/data/models/
```

The script automatically:
- Finds all converter class definitions
- Removes converter classes
- Generates appropriate helper functions
- Updates `@Converter()` annotations to `@JsonKey(fromJson:, toJson:)`
- Preserves strategy type and default values

### Step 4: Manual Migration (if needed)

If you prefer manual migration or the script doesn't handle your specific case:

1. **Identify converter classes**:
```dart
// OLD - Find all classes like this:
class MyConverter extends NullableEnumConverter<MyEnum> { }
class MyConverter extends DefaultEnumConverter<MyEnum> { }
class MyConverter extends LoggingEnumConverter<MyEnum> { }
```

2. **Create helper functions** (use patterns from Step 2 above)

3. **Update field annotations**:
```dart
// OLD
@MyConverter()
final MyEnum field;

// NEW
@JsonKey(fromJson: _deserializeMyEnum, toJson: _serializeMyEnum)
final MyEnum field;
```

4. **Remove converter classes** - Delete the entire class definition

### Step 5: Regenerate Code

After migration, regenerate the JSON serialization code:

```bash
dart run build_runner build --delete-conflicting-outputs
```

### Step 6: Test Thoroughly

Verify the migration works correctly:

```dart
// Test with unknown enum values
final json = {'status': 'unknown_future_value'};
final model = MyModel.fromJson(json);  // Should not crash

// Verify behavior matches your strategy
expect(model.status, isNotNull);  // or isNull for nullable strategy
```

## 📋 AI Assistant Instructions

**When migrating a project**, follow this checklist:

1. ✅ Add `safeEnumFromJson` and `safeEnumToJson` helper functions to the project
2. ✅ For each enum used in JSON serialization:
   - Create top-level `_deserialize[EnumName]` function
   - Create top-level `_serialize[EnumName]` function
   - Choose strategy: nullable, default, or logging
3. ✅ Replace all `@ConverterClass()` with `@JsonKey(fromJson: ..., toJson: ...)`
4. ✅ Remove all converter class definitions
5. ✅ Run `dart run build_runner build --delete-conflicting-outputs`
6. ✅ Verify generated code calls helper functions (check `.g.dart` files)
7. ✅ Test with unknown enum values to ensure no crashes

## 🔍 Verification

### Check Generated Code

After migration, verify the generated `.g.dart` files contain calls to your helper functions:

```dart
// ✅ CORRECT - Uses your helper function
UserProfile _$UserProfileFromJson(Map<String, dynamic> json) => UserProfile(
  role: _deserializeUserRole(json['role'] as String?),
);

// ❌ WRONG - Still uses $enumDecode (migration failed)
UserProfile _$UserProfileFromJson(Map<String, dynamic> json) => UserProfile(
  role: $enumDecode(_$UserRoleEnumMap, json['role']),
);
```

If you see `$enumDecode` in generated code, the migration didn't work. Check:
- Are you using `@JsonKey` not `@JsonConverter`?
- Are helper functions top-level (not in a class)?
- Did you run `build_runner` after changes?

### Test Unknown Values

Create a test to verify unknown enum values don't crash:

```dart
test('handles unknown enum values gracefully', () {
  final json = {'role': 'future_role_that_does_not_exist'};
  
  // Should not throw
  final profile = UserProfile.fromJson(json);
  
  // Verify fallback behavior
  expect(profile.role, UserRole.guest);  // or isNull for nullable strategy
});
```

## 📊 Strategy Comparison

| Strategy | Unknown Value Behavior | Use Case | Nullable Field |
|----------|----------------------|----------|----------------|
| **Nullable** | Returns `null` | Optional fields where absence is acceptable | Yes (`MyEnum?`) |
| **Default** | Returns default value | Required fields needing safe fallback | No (`MyEnum`) |
| **Logging** | Logs warning + returns default | Production monitoring of unknown values | No (`MyEnum`) |

## 🎯 Key Takeaways

1. **Never use `@JsonConverter`** on non-nullable enum fields - it doesn't work
2. **Always use `@JsonKey(fromJson:, toJson:)`** - it always works
3. **Helper functions must be top-level** - not methods in a class
4. **Choose the right strategy** - nullable, default, or logging based on your needs
5. **Verify generated code** - check `.g.dart` files call your helper functions
6. **Test with unknown values** - ensure graceful handling, not crashes

## 🔗 Additional Resources

- **Architecture Details**: See `ENUM_SOLUTION_ARCHITECTURE.md` for technical deep dive
- **Quick Start**: See `ENUM_QUICK_START.md` for fast implementation
- **Comprehensive Guide**: See `MODEL_SERIALIZATION_GUIDE.md` for full context
- **Migration Script**: Use `migration_scripts/migrate_enum_converters.dart` for automation

## 📝 Example: Complete Migration

### Before (Broken)

```dart
// Converter class
class UserRoleConverter extends DefaultEnumConverter<UserRole> {
  const UserRoleConverter() : super(UserRole.values);
  @override
  UserRole get defaultValue => UserRole.guest;
}

// Model
@JsonSerializable()
class UserProfile {
  @UserRoleConverter()  // ⚠️ IGNORED by json_serializable!
  final UserRole role;
  
  UserProfile({required this.role});
  
  factory UserProfile.fromJson(Map<String, dynamic> json) =>
      _$UserProfileFromJson(json);
  Map<String, dynamic> toJson() => _$UserProfileToJson(this);
}

// Generated code (CRASHES on unknown values)
UserProfile _$UserProfileFromJson(Map<String, dynamic> json) => UserProfile(
  role: $enumDecode(_$UserRoleEnumMap, json['role']),  // 💥 CRASH
);
```

### After (Working)

```dart
// Helper functions (no converter class needed)
UserRole _deserializeUserRole(String? value) {
  return safeEnumFromJson(
    value,
    UserRole.values,
    defaultValue: UserRole.guest,
  )!;
}

String? _serializeUserRole(UserRole? value) {
  return safeEnumToJson(value);
}

// Model
@JsonSerializable()
class UserProfile {
  @JsonKey(fromJson: _deserializeUserRole, toJson: _serializeUserRole)
  final UserRole role;  // ✅ Works!
  
  UserProfile({required this.role});
  
  factory UserProfile.fromJson(Map<String, dynamic> json) =>
      _$UserProfileFromJson(json);
  Map<String, dynamic> toJson() => _$UserProfileToJson(this);
}

// Generated code (safe, no crashes)
UserProfile _$UserProfileFromJson(Map<String, dynamic> json) => UserProfile(
  role: _deserializeUserRole(json['role'] as String?),  // ✅ Safe
);
```

## 🆘 Troubleshooting

### "Generated code still uses $enumDecode"

**Solution**: 
- Ensure you're using `@JsonKey` not `@JsonConverter`
- Helper functions must be top-level (not class methods)
- Run `build_runner build --delete-conflicting-outputs`

### "Type 'Null' doesn't conform to bound 'Enum'"

**Solution**: Add explicit type parameter when calling with potential null:
```dart
// ❌ Wrong
safeEnumToJson(null)

// ✅ Correct
safeEnumToJson<MyEnum>(null)
```

### "Converter classes still exist in code"

**Solution**: Remove all converter class definitions. They're not needed and won't work anyway. The helper functions replace them entirely.

### "Tests failing after migration"

**Solution**: Update tests to expect new behavior:
```dart
// Nullable strategy: unknown → null
expect(model.field, isNull);

// Default strategy: unknown → default value
expect(model.field, MyEnum.defaultValue);
```

---

**Migration Complete**: After following these steps, your enum serialization will be robust, crash-proof, and handle unknown server values gracefully.
