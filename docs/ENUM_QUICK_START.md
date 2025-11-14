# 5-Minute Quick Start: Safe Enum Serialization

Stop your app from crashing when the server adds new enum values. Here's how:

## The Problem

```dart
// Server adds "enterprise" to UserType
// Your app only knows: guest, member, admin
// Result: 💥 CRASH when receiving "enterprise" from server
```

**Why it crashes:** `json_serializable` ignores `@JsonConverter` on non-nullable enums and uses the built-in `$enumDecode()` which throws exceptions on unknown values.

## The Solution (Takes 2 minutes)

### Step 1: Define Your Enum

```dart
enum UserType { guest, member, admin }
// No "unknown" value needed!
```

### Step 2: Create Helper Functions

Choose one strategy based on your field:

**Option A: Nullable Field** (returns null for unknown)
```dart
UserType? _deserializeUserType(String? value) {
  return safeEnumFromJson(value, UserType.values);
}

String? _serializeUserType(UserType? value) {
  return safeEnumToJson(value);
}
```

**Option B: Non-Nullable Field** (returns default for unknown)
```dart
UserType _deserializeUserType(String? value) {
  return safeEnumFromJson(
    value,
    UserType.values,
    defaultValue: UserType.guest,  // Safe default
  )!;  // Safe to use ! because defaultValue is provided
}

String? _serializeUserType(UserType? value) {
  return safeEnumToJson(value);
}
```

**Option C: Need Monitoring** (logs + returns default)
```dart
UserType _deserializeUserType(String? value) {
  return safeEnumFromJson(
    value,
    UserType.values,
    defaultValue: UserType.guest,
    onUnknownValue: (v) {
      logw('Unknown UserType: $v, defaulting to guest');
    },
  )!;  // Safe to use ! because defaultValue is provided
}

String? _serializeUserType(UserType? value) {
  return safeEnumToJson(value);
}
```

### Step 3: Use It in Your Model

```dart
@JsonSerializable()
class UserModel extends BaseFirestoreModel {
  @JsonKey(fromJson: _deserializeUserType, toJson: _serializeUserType)
  final UserType? type;  // Or non-nullable for options B & C
  
  // ... rest of your model
}
```

### Step 4: Run build_runner

```bash
dart run build_runner build --delete-conflicting-outputs
```

## Done! 🎉

Your app now handles unknown enum values gracefully:

```dart
// Server sends "enterprise" (unknown to your app)
final user = UserModel.fromJson({'type': 'enterprise', ...});

// Option A (Nullable): user.type == null ✅
// Option B (Default): user.type == UserType.guest ✅  
// Option C (Logging): Logs warning + user.type == UserType.guest ✅

// No crash! Old app continues working while you update it.
```

## Which Strategy Should I Use?

| Field Type | Strategy | Use When |
|------------|----------|----------|
| `UserType?` | **Nullable** | Field is optional, null is acceptable |
| `UserType` | **Default** | Field is required, have safe default |
| `UserType` | **Logging** | Want to monitor unknown values |

## Real-World Example

```dart
// 1. Define enum
enum OrderStatus { pending, processing, shipped, delivered, cancelled }

// 2. Create helper functions (default strategy)
OrderStatus _deserializeOrderStatus(String? value) {
  return safeEnumFromJson(
    value,
    OrderStatus.values,
    defaultValue: OrderStatus.pending,
  )!;
}

String? _serializeOrderStatus(OrderStatus? value) {
  return safeEnumToJson(value);
}

// 3. Use in model
@JsonSerializable()
class OrderModel extends BaseFirestoreModel {
  final String id;
  
  @JsonKey(fromJson: _deserializeOrderStatus, toJson: _serializeOrderStatus)
  final OrderStatus status;
  
  OrderModel({required this.id, required this.status});
  
  factory OrderModel.fromJson(Map<String, dynamic> json) =>
      _$OrderModelFromJson(json);
  
  @override
  Map<String, dynamic> toJson() => _$OrderModelToJson(this);
}

// Server adds "refunded" status
// Old app receives order with "refunded"
// Helper returns OrderStatus.pending instead of crashing
// App continues working! ✅
```

## What You Get

✅ **No crashes** - Old apps handle new values gracefully  
✅ **Clean enums** - No "unknown" values cluttering your domain  
✅ **Type-safe** - Full Dart compile-time type checking  
✅ **Simple** - Just helper functions, no complex hierarchies  
✅ **Flexible** - Three strategies for different needs  
✅ **Reliable** - Works with ALL enum fields (nullable and non-nullable)

## Import Statement

```dart
import 'package:dreamic/dreamic.dart';
// Includes: safeEnumFromJson, safeEnumToJson, logw
```

## Next Steps

- See [MODEL_SERIALIZATION_GUIDE.md](MODEL_SERIALIZATION_GUIDE.md) for complete guide including migration and troubleshooting
- See [ENUM_SOLUTION_ARCHITECTURE.md](ENUM_SOLUTION_ARCHITECTURE.md) for design decisions

## Need Help?

Check the [Troubleshooting section](MODEL_SERIALIZATION_GUIDE.md#troubleshooting) or look at [enum_example.dart](../lib/data/models/enum_example.dart) for a complete working example.

---

**That's it!** You now have crash-proof enum serialization. 🎉
