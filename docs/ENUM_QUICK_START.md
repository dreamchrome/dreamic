# 5-Minute Quick Start: Enum Converters

Stop your app from crashing when the server adds new enum values. Here's how:

## The Problem

```dart
// Server adds "enterprise" to UserType
// Your app only knows: guest, member, admin
// Result: 💥 CRASH when receiving "enterprise" from server
```

## The Solution (Takes 2 minutes)

### Step 1: Define Your Enum

```dart
enum UserType { guest, member, admin }
// No "unknown" value needed!
```

### Step 2: Create a Converter

Choose one strategy based on your field:

**Option A: Nullable Field** (returns null for unknown)
```dart
class UserTypeConverter extends NullableEnumConverter<UserType> {
  const UserTypeConverter();
  @override
  List<UserType> get enumValues => UserType.values;
}
```

**Option B: Non-Nullable Field** (returns default for unknown)
```dart
class UserTypeConverter extends DefaultEnumConverter<UserType> {
  const UserTypeConverter();
  @override
  List<UserType> get enumValues => UserType.values;
  @override
  UserType get defaultValue => UserType.guest; // Safe default
}
```

**Option C: Need Monitoring** (logs + returns default)
```dart
class UserTypeConverter extends LoggingEnumConverter<UserType> {
  const UserTypeConverter();
  @override
  List<UserType> get enumValues => UserType.values;
  @override
  UserType get defaultValue => UserType.guest;
  @override
  void logUnknownValue(String value) {
    logger.log('Unknown UserType: $value', logType: LogType.warning);
  }
}
```

### Step 3: Use It in Your Model

```dart
@JsonSerializable()
class UserModel extends BaseFirestoreModel {
  @UserTypeConverter()  // Add this annotation
  final UserType? type;
  
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

// 2. Create converter
class OrderStatusConverter extends DefaultEnumConverter<OrderStatus> {
  const OrderStatusConverter();
  @override
  List<OrderStatus> get enumValues => OrderStatus.values;
  @override
  OrderStatus get defaultValue => OrderStatus.pending;
}

// 3. Use in model
@JsonSerializable()
class OrderModel extends BaseFirestoreModel {
  final String id;
  
  @OrderStatusConverter()
  final OrderStatus status;
  
  OrderModel({required this.id, required this.status});
  
  factory OrderModel.fromJson(Map<String, dynamic> json) =>
      _$OrderModelFromJson(json);
  
  @override
  Map<String, dynamic> toJson() => _$OrderModelToJson(this);
}

// Server adds "refunded" status
// Old app receives order with "refunded"
// Converter returns OrderStatus.pending instead of crashing
// App continues working! ✅
```

## What You Get

✅ **No crashes** - Old apps handle new values  
✅ **Clean enums** - No "unknown" values  
✅ **Type-safe** - Full Dart type checking  
✅ **Simple** - Just extend a class  
✅ **Flexible** - Choose the right strategy  

## Import Statement

```dart
import 'package:dreamic/dreamic.dart';
// Includes: NullableEnumConverter, DefaultEnumConverter, LoggingEnumConverter
```

## Next Steps

- See [MODEL_SERIALIZATION_GUIDE.md](MODEL_SERIALIZATION_GUIDE.md) for complete guide including migration and troubleshooting
- See [ENUM_SOLUTION_ARCHITECTURE.md](ENUM_SOLUTION_ARCHITECTURE.md) for design decisions

## Need Help?

Check the [Troubleshooting section](MODEL_SERIALIZATION_GUIDE.md#troubleshooting) or look at [enum_example.dart](../lib/data/models/enum_example.dart) for a complete working example.

---

**That's it!** You now have crash-proof enum serialization. 🎉
