# Dreamic Model Serialization - Ultimate Guide

> **The complete reference for Firebase model serialization in the Dreamic package**

## Table of Contents

1. [Overview](#overview)
2. [Quick Start](#quick-start)
3. [Core Concepts](#core-concepts)
4. [Method Reference](#method-reference)
5. [Timestamp Converters](#timestamp-converters)
6. [Enum Converters](#enum-converters)
7. [Common Use Cases](#common-use-cases)
8. [Data Migration](#data-migration)
9. [Decision Tree](#decision-tree)
10. [Legacy Converters](#legacy-converters)
11. [Migration Guide](#migration-guide)
12. [Best Practices](#best-practices)
13. [Troubleshooting](#troubleshooting)
14. [Examples](#examples)

---

## Overview

The Dreamic package provides two approaches for Firebase model serialization:

1. **BaseFirestoreModel** (Recommended) - Intelligent, context-aware serialization
2. **Legacy Converters** (Fully Supported) - Original converters for backward compatibility

### Key Benefits

✅ **Automatic timestamp management** - Server timestamps handled intelligently  
✅ **Context-aware serialization** - Different output for Firestore, Cloud Functions, and local storage  
✅ **Explicit create vs update** - Prevents common timestamp bugs  
✅ **Data migration support** - Import historical data with exact timestamps  
✅ **100% backward compatible** - All existing code continues to work  
✅ **Cloud Functions ready** - Automatic field management for callable functions  

---

## Quick Start

### 1. Define Your Model

```dart
import 'package:dreamic/dreamic.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

part 'post_model.g.dart';

@JsonSerializable(explicitToJson: true)
class PostModel extends BaseFirestoreModel {
  @JsonKey(includeFromJson: true, includeToJson: false)
  final String id;
  
  final String title;
  final String content;
  final String authorId;
  
  @SmartTimestampConverter()
  final DateTime? createdAt;
  
  @SmartTimestampConverter()
  final DateTime? updatedAt;
  
  final List<String> tags;
  
  PostModel({
    this.id = '',
    required this.title,
    required this.content,
    required this.authorId,
    this.createdAt,
    this.updatedAt,
    this.tags = const [],
  });
  
  factory PostModel.fromJson(Map<String, dynamic> json) => 
      _$PostModelFromJson(json);
  
  @override
  Map<String, dynamic> toJson() => _$PostModelToJson(this);
  
  factory PostModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return PostModel.fromJson({'id': doc.id, ...data});
  }
  
  PostModel copyWith({
    String? id,
    String? title,
    String? content,
    String? authorId,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<String>? tags,
  }) {
    return PostModel(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      authorId: authorId ?? this.authorId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      tags: tags ?? this.tags,
    );
  }
}
```

### 2. Generate Code

```bash
dart run build_runner build --delete-conflicting-outputs
```

### 3. Use in Your App

```dart
// CREATE - Server sets both timestamps
final post = PostModel(
  title: 'My Post',
  content: 'Content here',
  authorId: 'user123',
);
await firestore.collection('posts').add(post.toFirestoreCreate());

// READ
final doc = await firestore.collection('posts').doc(postId).get();
final post = PostModel.fromFirestore(doc);

// UPDATE - Preserves createdAt, updates updatedAt
final updated = post.copyWith(title: 'Updated Title');
await firestore.collection('posts').doc(postId).update(updated.toFirestoreUpdate());

// DELETE
await firestore.collection('posts').doc(postId).delete();
```

---

## Core Concepts

### Serialization Context

BaseFirestoreModel adapts serialization based on where data is going:

```dart
enum SerializationContext {
  firestore,  // Direct Firestore operations
  callable,   // Firebase Cloud Functions
  local,      // Local storage/caching
}
```

### Timestamp Field Types

**Create-only fields** (e.g., `createdAt`):
- Set automatically on document creation
- Removed entirely on updates to preserve original value

**Always-update fields** (e.g., `updatedAt`):
- Set automatically on creation
- Updated automatically on every change

**User-controlled fields** (e.g., `scheduledPublishDate`):
- Not automatically managed
- Developer sets explicitly when needed

### Method Selection Matrix

**Serialization (Dart → External)**:

| Method | Use Case | `createdAt` | `updatedAt` |
|--------|----------|-------------|-------------|
| `toFirestoreCreate()` | New documents | `FieldValue.serverTimestamp()` | `FieldValue.serverTimestamp()` |
| `toFirestoreUpdate()` | Updates | Removed (preserved) | `FieldValue.serverTimestamp()` |
| `toFirestoreRaw()` | Data migration | Exact DateTime → Timestamp | Exact DateTime → Timestamp |
| `toCallable()` | Cloud Functions (send) | Field removed | Field removed |
| `toJson()` | Local storage | Milliseconds (int) | Milliseconds (int) |

**Deserialization (External → Dart)**:

| Method | Use Case | Handles Formats |
|--------|----------|-----------------|
| `fromJson()` | Firestore, Cloud Functions, Local | Timestamp, `{_seconds, _nanoseconds}`, milliseconds, ISO strings |
| `fromFirestore()` | Firestore documents | Adds document ID, delegates to `fromJson()` |

---

## Method Reference

### toFirestoreCreate()

**Purpose**: Creating new documents with server timestamps

**Signature**:
```dart
Map<String, dynamic> toFirestoreCreate({
  bool useServerTimestamp = true,
  List<String>? fieldsToExclude,
})
```

**Parameters**:
- `useServerTimestamp`: If true (default), uses `FieldValue.serverTimestamp()`. If false, converts DateTime to Timestamp
- `fieldsToExclude`: List of field names to omit from output

**Usage**:
```dart
// Standard creation (99% of cases)
await firestore.collection('posts').add(
  post.toFirestoreCreate()
);
// Result: { title: "...", createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() }

// Data import with historical timestamps
await firestore.collection('posts').add(
  historicalPost.toFirestoreCreate(useServerTimestamp: false)
);
// Result: { title: "...", createdAt: Timestamp(2020-01-15), updatedAt: Timestamp(2021-06-20) }

// Exclude internal fields
await firestore.collection('posts').add(
  post.toFirestoreCreate(fieldsToExclude: ['debugInfo', 'internalNotes'])
);
```

### toFirestoreUpdate()

**Purpose**: Updating existing documents while preserving creation timestamps

**Signature**:
```dart
Map<String, dynamic> toFirestoreUpdate({
  List<String>? fieldsToExclude,
})
```

**Parameters**:
- `fieldsToExclude`: List of field names to omit from output

**Behavior**:
- Removes all fields from `getCreateTimestampFields()` (default: `['createdAt']`)
- Sets fields from `getUpdateTimestampFields()` (default: `['updatedAt']`) to `FieldValue.serverTimestamp()`

**Usage**:
```dart
// Standard update
await firestore.collection('posts').doc(postId).update(
  post.toFirestoreUpdate()
);
// Result: { title: "...", updatedAt: FieldValue.serverTimestamp() }
// Note: createdAt is NOT included

// Partial update
await firestore.collection('posts').doc(postId).update(
  post.toFirestoreUpdate(fieldsToExclude: ['tags', 'content'])
);
```

### toFirestoreRaw()

**Purpose**: Advanced scenarios requiring full control over timestamps

**Signature**:
```dart
Map<String, dynamic> toFirestoreRaw({
  List<String>? fieldsToExclude,
})
```

**Use Cases**:
- Data migration from external systems
- Importing historical data
- Document cloning with specific timestamps
- Batch imports with mixed timestamp sources

**Usage**:
```dart
// Preserve exact timestamps during migration
final historicalPost = PostModel(
  title: 'Old Post',
  createdAt: DateTime(2020, 3, 15, 10, 30),
  updatedAt: DateTime(2021, 6, 20, 14, 45),
);

await firestore.collection('posts').add(
  historicalPost.toFirestoreRaw()
);
// Result: { title: "...", createdAt: Timestamp(2020-03-15 10:30), updatedAt: Timestamp(2021-06-20 14:45) }
```

### toCallable()

**Purpose**: Preparing data for Firebase Cloud Functions

**Signature**:
```dart
Map<String, dynamic> toCallable()
```

**Behavior**:
- Removes all fields from `getCreateTimestampFields()` and `getUpdateTimestampFields()`
- Keeps all other fields as-is (including user-controlled timestamps)
- Server-side function **must** add the timestamp fields

**Why Remove Timestamps?**

`FieldValue.serverTimestamp()` cannot be sent to Cloud Functions because:
1. It's a special sentinel value that only works in direct Firestore writes
2. Cloud Functions receive plain JSON data
3. The server must add timestamps using its own `FieldValue.serverTimestamp()`

**Client-Side Usage**:
```dart
final post = PostModel(
  title: 'My Post',
  content: 'Content here',
  authorId: 'user123',
  scheduledPublishDate: DateTime(2025, 12, 25),  // User-controlled - included
);

final callable = FirebaseFunctions.instance.httpsCallable('createPost');
await callable.call(post.toCallable());

// Sent to server: 
// {
//   title: "My Post",
//   content: "Content here", 
//   authorId: "user123",
//   scheduledPublishDate: 1735084800000,  // Included (user-controlled)
//   // Note: createdAt and updatedAt are NOT included
// }
```

**Server-Side Implementation** (TypeScript):

```typescript
import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

const db = admin.firestore();

// CREATE operation
export const createPost = functions.https.onCall(async (data, context) => {
  // Verify authentication
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'Must be logged in to create posts'
    );
  }
  
  // Data received from client (via toCallable())
  // Does NOT include createdAt or updatedAt
  
  // Server adds timestamp fields
  const postDoc = {
    ...data,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    // Optionally add server-side fields
    uid: context.auth.uid,
    ipAddress: context.rawRequest.ip,
  };
  
  const docRef = await db.collection('posts').add(postDoc);
  
  return {
    success: true,
    postId: docRef.id,
  };
});

// UPDATE operation
export const updatePost = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'Must be logged in to update posts'
    );
  }
  
  const { postId, ...updateData } = data;
  
  if (!postId) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'postId is required'
    );
  }
  
  // Verify ownership
  const postDoc = await db.collection('posts').doc(postId).get();
  
  if (!postDoc.exists) {
    throw new functions.https.HttpsError('not-found', 'Post not found');
  }
  
  if (postDoc.data()?.uid !== context.auth.uid) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Cannot update another user\'s post'
    );
  }
  
  // Update with server timestamp
  // Note: Do NOT include createdAt (preserve original)
  const update = {
    ...updateData,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    // Do NOT include createdAt here
  };
  
  await db.collection('posts').doc(postId).update(update);
  
  return { success: true };
});

// PUBLISH operation (custom timestamp)
export const publishPost = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'Must be logged in'
    );
  }
  
  const { postId } = data;
  
  // Set both publishedAt (custom field) and updatedAt
  await db.collection('posts').doc(postId).update({
    publishedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    isPublished: true,
  });
  
  return { success: true };
});
```

**Server-Side Implementation** (Python):

```python
from firebase_functions import https_fn
from firebase_admin import firestore
import google.cloud.firestore

db = firestore.client()

@https_fn.on_call()
def create_post(req: https_fn.CallableRequest) -> dict:
    """Create a new post with server timestamps."""
    
    # Verify authentication
    if req.auth is None:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.UNAUTHENTICATED,
            message="Must be logged in to create posts"
        )
    
    # Data received from client (via toCallable())
    # Does NOT include createdAt or updatedAt
    data = req.data
    
    # Server adds timestamp fields
    post_doc = {
        **data,
        'createdAt': firestore.SERVER_TIMESTAMP,
        'updatedAt': firestore.SERVER_TIMESTAMP,
        'uid': req.auth.uid,
    }
    
    doc_ref = db.collection('posts').add(post_doc)
    
    return {
        'success': True,
        'postId': doc_ref[1].id,
    }

@https_fn.on_call()
def update_post(req: https_fn.CallableRequest) -> dict:
    """Update a post with server timestamp."""
    
    if req.auth is None:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.UNAUTHENTICATED,
            message="Must be logged in"
        )
    
    data = req.data
    post_id = data.get('postId')
    
    if not post_id:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message="postId is required"
        )
    
    # Remove postId from update data
    update_data = {k: v for k, v in data.items() if k != 'postId'}
    
    # Add server timestamp (do NOT include createdAt)
    update_data['updatedAt'] = firestore.SERVER_TIMESTAMP
    
    db.collection('posts').document(post_id).update(update_data)
    
    return {'success': True}
```

**Important Server-Side Rules**:

1. **Always add timestamps on the server** - Never trust client timestamps for security
2. **CREATE operations** - Add both `createdAt` and `updatedAt`
3. **UPDATE operations** - Only add/update `updatedAt`, never touch `createdAt`
4. **Validate input** - Check authentication and authorization
5. **User-controlled timestamps** - These come from the client (e.g., `scheduledPublishDate`)
6. **Server-controlled timestamps** - Always use `FieldValue.serverTimestamp()`

**Why Server-Side Timestamps?**

✅ **Security**: Clients can't fake creation/modification times  
✅ **Accuracy**: Server clock is authoritative  
✅ **Consistency**: All timestamps come from same time source  
✅ **Audit trail**: Reliable for compliance and debugging  

**What Gets Sent vs Added**:

```dart
// Client sends via toCallable():
{
  "title": "My Post",
  "content": "Content",
  "scheduledPublishDate": 1735084800000,  // User-controlled ✓
  // createdAt: NOT sent (server adds) ✗
  // updatedAt: NOT sent (server adds) ✗
}

// Server adds and writes to Firestore:
{
  "title": "My Post",
  "content": "Content",
  "scheduledPublishDate": Timestamp(2025-12-25),
  "createdAt": FieldValue.serverTimestamp(),      // Server adds ✓
  "updatedAt": FieldValue.serverTimestamp(),      // Server adds ✓
  "uid": "user123",                               // Server adds ✓
}
```

### Receiving Data from Callable Functions

**Purpose**: Deserializing responses from Firebase Cloud Functions

When you call a Firebase callable function, it returns data that needs to be deserialized back into your model. The `SmartTimestampConverter` automatically handles all timestamp formats that Cloud Functions might return.

**Supported Response Formats**:
- `{_seconds: int, _nanoseconds: int}` (Cloud Functions format)
- `{seconds: int, nanoseconds: int}` (standard format)
- Milliseconds since epoch (int)
- ISO 8601 strings

**Usage**:
```dart
// Call the function
final callable = FirebaseFunctions.instance.httpsCallable('getPost');
final result = await callable.call({'postId': 'abc123'});

// Deserialize the response
final post = PostModel.fromJson(result.data as Map<String, dynamic>);

// Access the deserialized data
print(post.title);
print(post.createdAt);  // DateTime object, correctly parsed
```

**Complete Round-Trip Example**:
```dart
class PostService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  // CREATE via callable
  Future<PostModel> createPost(PostModel post) async {
    final callable = _functions.httpsCallable('createPost');

    // Send data (timestamps removed, server will add them)
    final result = await callable.call(post.toCallable());

    // Receive and deserialize response
    return PostModel.fromJson(result.data as Map<String, dynamic>);
  }

  // READ via callable
  Future<PostModel?> getPost(String postId) async {
    final callable = _functions.httpsCallable('getPost');
    final result = await callable.call({'postId': postId});

    if (result.data == null) return null;
    return PostModel.fromJson(result.data as Map<String, dynamic>);
  }

  // UPDATE via callable
  Future<PostModel> updatePost(String postId, PostModel post) async {
    final callable = _functions.httpsCallable('updatePost');

    // toCallable() removes createdAt and updatedAt
    final result = await callable.call({
      'postId': postId,
      ...post.toCallable(),
    });

    return PostModel.fromJson(result.data as Map<String, dynamic>);
  }

  // LIST via callable
  Future<List<PostModel>> listPosts({int limit = 20}) async {
    final callable = _functions.httpsCallable('listPosts');
    final result = await callable.call({'limit': limit});

    final List<dynamic> items = result.data['posts'] as List<dynamic>;
    return items
        .map((item) => PostModel.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}
```

**Server-Side Response Example** (TypeScript):
```typescript
export const getPost = functions.https.onCall(async (data, context) => {
  const { postId } = data;

  const doc = await db.collection('posts').doc(postId).get();

  if (!doc.exists) {
    return null;
  }

  // Return the document data
  // Timestamps are automatically serialized as {_seconds, _nanoseconds}
  return {
    id: doc.id,
    ...doc.data(),
  };
});
```

**Why This Works**:

The `SmartTimestampConverter` in your model handles the deserialization:

```dart
@SmartTimestampConverter()
final DateTime? createdAt;
```

When `fromJson` is called, the converter's `fromJson` method checks the input type:
1. If it's a Map with `_seconds`/`_nanoseconds` → converts to DateTime
2. If it's an int (milliseconds) → converts to DateTime
3. If it's a String (ISO format) → parses to DateTime
4. If it's already a Timestamp → converts to DateTime

This means you don't need a separate `fromCallable()` method—the standard `fromJson()` factory handles all cases automatically.

---

### toJson()

**Purpose**: Local storage, caching, or JSON serialization

**Returns**: Standard JSON with timestamps as milliseconds (int)

**Usage**:
```dart
// Save to local storage
final prefs = await SharedPreferences.getInstance();
await prefs.setString('draft', jsonEncode(post.toJson()));

// Load from local storage
final json = jsonDecode(prefs.getString('draft')!);
final post = PostModel.fromJson(json);
```

---

## Timestamp Converters

### SmartTimestampConverter (Nullable)

**Handles multiple input formats:**
- Firestore `Timestamp` objects
- Cloud Functions Map format: `{_seconds: int, _nanoseconds: int}`
- Standard Map format: `{seconds: int, nanoseconds: int}`
- Milliseconds since epoch (int)
- ISO 8601 strings

**Output**: Always returns milliseconds (int) for JSON compatibility

**Usage**:
```dart
@SmartTimestampConverter()
final DateTime? createdAt;

@SmartTimestampConverter()
final DateTime? updatedAt;

@SmartTimestampConverter()
final DateTime? scheduledPublishDate;  // User-controlled
```

### SmartTimestampConverterNotNull (Non-nullable)

Same as `SmartTimestampConverter` but returns epoch (1970-01-01) if parsing fails.

**Usage**:
```dart
@SmartTimestampConverterNotNull()
final DateTime timestamp;  // Non-nullable
```

### Converter Comparison

| Converter | Nullable | Output Format | Best For |
|-----------|----------|---------------|----------|
| `SmartTimestampConverter` | ✅ | Milliseconds | BaseFirestoreModel (recommended) |
| `SmartTimestampConverterNotNull` | ❌ | Milliseconds | Non-nullable timestamps |
| `TimestampConverter` | ❌ | Timestamp Map | Legacy support |
| `TimestampNullableConverter` | ✅ | Timestamp Map | Legacy support |
| `TimestampMillisConverter` | ❌ | Milliseconds | Function-safe (legacy) |
| `TimestampMillisNullableConverter` | ✅ | Milliseconds | Function-safe (legacy) |
| `TimestampCreationConverter` | ✅ | FieldValue | Auto-creation (legacy) |
| `TimestampModifiedConverter` | ❌ | FieldValue | Auto-update (legacy) |

---

## Enum Converters

### The Problem

Enums can cause apps to crash when the server adds new enum values that older app versions don't recognize. This happens during deserialization when `json_serializable` encounters an unknown enum value.

**Critical Discovery:** `json_serializable` has an undocumented limitation - it **completely ignores** `@JsonConverter` annotations on non-nullable enum fields. Only nullable enum fields respect converter annotations.

**Traditional approach (doesn't work):**
```dart
enum UserType {
  admin,
  moderator,
  standard,
  unknown,  // ❌ Required in every enum
}

@JsonSerializable()
class UserModel {
  // ❌ Must remember this on every enum field
  @JsonKey(unknownEnumValue: UserType.unknown)
  final UserType type;
}
```

**Problems with traditional approach:**
- Easy to forget `@JsonKey(unknownEnumValue: ...)` annotation
- Forces every enum to have an "unknown" value
- Inconsistent handling across the codebase
- No logging or tracking of unknown values
- Clutters domain models with technical values

### The Solution: Safe Enum Helper Functions

The Dreamic package provides `safeEnumFromJson()` and `safeEnumToJson()` helper functions that work with `@JsonKey(fromJson:, toJson:)` - the **only** approach that json_serializable never ignores.

#### Pattern Overview

1. Define enum (clean business values only)
2. Create `_deserialize` and `_serialize` helper functions
3. Use `@JsonKey(fromJson:, toJson:)` on model fields
4. Run build_runner to generate code

#### Strategy 1: Nullable (Recommended for nullable fields)

Use when the enum field is nullable and you want unknown values to be treated as null.

```dart
// 1. Define your enum (no "unknown" value needed!)
enum UserType {
  admin,
  moderator,
  standard,
}

// 2. Create helper functions
UserType? _deserializeUserType(String? value) {
  return safeEnumFromJson(value, UserType.values);
  // No defaultValue - returns null for unknown values
}

String? _serializeUserType(UserType? value) {
  return safeEnumToJson(value);
}

// 3. Use in your model
@JsonSerializable()
class UserModel extends BaseFirestoreModel {
  @JsonKey(fromJson: _deserializeUserType, toJson: _serializeUserType)
  final UserType? type;  // nullable - unknown values become null
  
  UserModel({this.type});
  
  factory UserModel.fromJson(Map<String, dynamic> json) =>
      _$UserModelFromJson(json);
  
  @override
  Map<String, dynamic> toJson() => _$UserModelToJson(this);
}
```

**What happens:**
- Known values (admin, moderator, standard) → Deserialize correctly
- Unknown values (e.g., "superadmin" added by server) → Become `null`
- App doesn't crash when server adds new enum values! ✅

#### Strategy 2: Default (Recommended for non-nullable fields)

Use when the enum field is required and you want unknown values to default to a specific value.

```dart
enum Priority {
  low,
  medium,
  high,
}

// Create helper functions with default value
Priority _deserializePriority(String? value) {
  return safeEnumFromJson(
    value,
    Priority.values,
    defaultValue: Priority.medium,  // Fallback for unknown values
  )!;  // Safe to use ! because defaultValue guarantees non-null
}

String? _serializePriority(Priority? value) {
  return safeEnumToJson(value);
}

@JsonSerializable()
class TaskModel extends BaseFirestoreModel {
  @JsonKey(fromJson: _deserializePriority, toJson: _serializePriority)
  final Priority priority;  // non-nullable - unknown values become 'medium'
  
  TaskModel({required this.priority});
  
  factory TaskModel.fromJson(Map<String, dynamic> json) =>
      _$TaskModelFromJson(json);
  
  @override
  Map<String, dynamic> toJson() => _$TaskModelToJson(this);
}
```

**What happens:**
- Known values (low, medium, high) → Deserialize correctly
- Unknown values (e.g., "urgent" added by server) → Become `Priority.medium`
- App doesn't crash! ✅

#### Strategy 3: Logging (Recommended for debugging/monitoring)

Use when you want to track when unknown values are encountered (useful for debugging or error reporting).

```dart
enum PaymentStatus {
  pending,
  processing,
  completed,
  failed,
}

// Create helper functions with logging
PaymentStatus _deserializePaymentStatus(String? value) {
  return safeEnumFromJson(
    value,
    PaymentStatus.values,
    defaultValue: PaymentStatus.pending,
    onUnknownValue: (v) {
      // Use dreamic's built-in logger
      logw('Unknown PaymentStatus: $v, defaulting to pending');
      
      // Or report to error tracking service
      // errorReporter.logError('Unknown PaymentStatus', extra: {'value': v});
    },
  )!;  // Safe to use ! because defaultValue guarantees non-null
}

String? _serializePaymentStatus(PaymentStatus? value) {
  return safeEnumToJson(value);
}

@JsonSerializable()
class PaymentModel extends BaseFirestoreModel {
  @JsonKey(fromJson: _deserializePaymentStatus, toJson: _serializePaymentStatus)
  final PaymentStatus status;
  
  PaymentModel({required this.status});
  
  factory PaymentModel.fromJson(Map<String, dynamic> json) =>
      _$PaymentModelFromJson(json);
  
  @override
  Map<String, dynamic> toJson() => _$PaymentModelToJson(this);
}
```

**What happens:**
- Known values → Deserialize correctly
- Unknown values → Logged AND default value returned
- You get visibility into which unknown values are being encountered
- App doesn't crash! ✅

### Quick Reference

| Strategy | Field Type | Unknown Value Behavior | Use Case |
|----------|------------|------------------------|----------|
| **Nullable** | Nullable | Returns `null` | Optional enum fields |
| **Default** | Non-nullable | Returns default value | Required enum fields |
| **Logging** | Non-nullable | Logs + returns default | Debugging/monitoring |

### Complete Example

```dart
// 1. Define enums (no "unknown" values needed!)
enum UserRole {
  guest,
  member,
  moderator,
  admin,
}

enum AccountStatus {
  active,
  suspended,
  deleted,
}

enum SubscriptionTier {
  free,
  basic,
  premium,
}

// 2. Create helper functions (one pair per enum)

// Default strategy
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

// Nullable strategy
AccountStatus? _deserializeAccountStatus(String? value) {
  return safeEnumFromJson(value, AccountStatus.values);
}

String? _serializeAccountStatus(AccountStatus? value) {
  return safeEnumToJson(value);
}

// Logging strategy
SubscriptionTier _deserializeSubscriptionTier(String? value) {
  return safeEnumFromJson(
    value,
    SubscriptionTier.values,
    defaultValue: SubscriptionTier.free,
    onUnknownValue: (v) => logw('Unknown SubscriptionTier: $v'),
  )!;
}

String? _serializeSubscriptionTier(SubscriptionTier? value) {
  return safeEnumToJson(value);
}

// 3. Use in model
@JsonSerializable(explicitToJson: true)
class UserModel extends BaseFirestoreModel {
  @JsonKey(includeFromJson: true, includeToJson: false)
  final String id;
  
  final String name;
  final String email;
  
  @JsonKey(fromJson: _deserializeUserRole, toJson: _serializeUserRole)
  final UserRole role;  // Non-nullable, defaults to 'guest'
  
  @JsonKey(fromJson: _deserializeAccountStatus, toJson: _serializeAccountStatus)
  final AccountStatus? status;  // Nullable, unknown becomes null
  
  @JsonKey(fromJson: _deserializeSubscriptionTier, toJson: _serializeSubscriptionTier)
  final SubscriptionTier tier;  // Non-nullable, logged, defaults to 'free'
  
  @SmartTimestampConverter()
  final DateTime? createdAt;
  
  @SmartTimestampConverter()
  final DateTime? updatedAt;
  
  UserModel({
    this.id = '',
    required this.name,
    required this.email,
    required this.role,
    this.status,
    required this.tier,
    this.createdAt,
    this.updatedAt,
  });
  
  factory UserModel.fromJson(Map<String, dynamic> json) =>
      _$UserModelFromJson(json);
  
  @override
  Map<String, dynamic> toJson() => _$UserModelToJson(this);
  
  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserModel.fromJson({'id': doc.id, ...data});
  }
}
```

### Benefits Over Traditional Approach

✅ **No "unknown" values required** - Keep enums clean with only meaningful values  
✅ **Reliable** - Works with ALL enum fields (nullable and non-nullable)  
✅ **Type-safe** - @JsonKey is never ignored by json_serializable  
✅ **Crash-proof** - Old apps don't crash when server adds new enum values  
✅ **Flexible strategies** - Choose null, default, or logging behavior  
✅ **Better debugging** - Optional logging shows when unknown values appear  
✅ **Simple pattern** - Just helper functions, no complex class hierarchies  
✅ **Type-safe** - Full Dart type checking maintained  
✅ **Migration friendly** - Easy to add to existing enums  

### Migration from Traditional Approach

**Before:**
```dart
enum UserType {
  admin,
  moderator,
  standard,
  unknown,  // Had to include this
}

@JsonSerializable()
class UserModel {
  @JsonKey(unknownEnumValue: UserType.unknown)  // Had to remember this
  final UserType type;
}
```

**After:**
```dart
enum UserType {
  admin,
  moderator,
  standard,
  // No "unknown" needed!
}

class UserTypeConverter extends NullableEnumConverter<UserType> {
  const UserTypeConverter();
  @override
  List<UserType> get enumValues => UserType.values;
}

@JsonSerializable()
class UserModel {
  @UserTypeConverter()  // Converter handles everything
  final UserType? type;
}
```

### Best Practices

1. **Create one converter per enum** in a dedicated file:
   ```
   lib/
     data/
       models/
         enums/
           user_type.dart        # enum UserType { ... }
           priority.dart         # enum Priority { ... }
         converters/
           user_type_converter.dart
           priority_converter.dart
   ```

2. **Use NullableEnumConverter for optional fields:**
   ```dart
   @UserTypeConverter()
   final UserType? type;  // Can be null
   ```

3. **Use DefaultEnumConverter for required fields:**
   ```dart
   @PriorityConverter()
   final Priority priority;  // Always has a value
   ```

4. **Use LoggingEnumConverter in critical areas:**
   ```dart
   @PaymentStatusConverter()
   final PaymentStatus status;  // Log when unknown values appear
   ```

5. **Choose sensible defaults:**
   ```dart
   // ✅ Good - safe default
   @override
   UserRole get defaultValue => UserRole.guest;
   
   // ✅ Good - neutral default
   @override
   Priority get defaultValue => Priority.medium;
   
   // ❌ Bad - dangerous default
   @override
   UserRole get defaultValue => UserRole.admin;  // Don't default to admin!
   ```

### Troubleshooting

#### Issue: Converter not being used

**Problem**: json_serializable not finding the converter

**Solution**: Make sure to:
1. Import the converter file
2. Run `dart run build_runner build --delete-conflicting-outputs`
3. Check that converter class is public (not prefixed with `_`)

#### Issue: Still getting crashes

**Problem**: Enum field doesn't have converter annotation

**Solution**: Ensure every enum field has the converter:
```dart
// ❌ Missing converter
final UserType type;

// ✅ Has converter
@UserTypeConverter()
final UserType? type;
```

#### Issue: Want different behavior for different contexts

**Problem**: Need different fallback logic in different models

**Solution**: Create multiple converters for the same enum:
```dart
class UserTypeNullableConverter extends NullableEnumConverter<UserType> {
  const UserTypeNullableConverter();
  @override
  List<UserType> get enumValues => UserType.values;
}

class UserTypeGuestConverter extends DefaultEnumConverter<UserType> {
  const UserTypeGuestConverter();
  @override
  List<UserType> get enumValues => UserType.values;
  @override
  UserType get defaultValue => UserType.guest;
}

class UserTypeMemberConverter extends DefaultEnumConverter<UserType> {
  const UserTypeMemberConverter();
  @override
  List<UserType> get enumValues => UserType.values;
  @override
  UserType get defaultValue => UserType.member;
}
```

---

## Common Use Cases

### 1. Standard CRUD Operations

```dart
class PostService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // CREATE
  Future<String> createPost(PostModel post) async {
    final docRef = await _firestore.collection('posts').add(
      post.toFirestoreCreate()
    );
    return docRef.id;
  }
  
  // READ
  Future<PostModel?> getPost(String postId) async {
    final doc = await _firestore.collection('posts').doc(postId).get();
    if (!doc.exists) return null;
    return PostModel.fromFirestore(doc);
  }
  
  // UPDATE
  Future<void> updatePost(String postId, PostModel post) async {
    await _firestore.collection('posts').doc(postId).update(
      post.toFirestoreUpdate()
    );
  }
  
  // DELETE
  Future<void> deletePost(String postId) async {
    await _firestore.collection('posts').doc(postId).delete();
  }
}
```

### 2. Real-time Updates

```dart
Stream<List<PostModel>> watchPosts() {
  return _firestore
      .collection('posts')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snapshot) => snapshot.docs
          .map((doc) => PostModel.fromFirestore(doc))
          .toList());
}
```

### 3. Batch Operations

```dart
Future<void> createPostsBatch(List<PostModel> posts) async {
  final batch = _firestore.batch();
  
  for (final post in posts) {
    final docRef = _firestore.collection('posts').doc();
    batch.set(docRef, post.toFirestoreCreate());
  }
  
  await batch.commit();
}
```

### 4. Transactions

```dart
Future<void> transferPostOwnership(String postId, String newAuthorId) async {
  await _firestore.runTransaction((transaction) async {
    final docRef = _firestore.collection('posts').doc(postId);
    final doc = await transaction.get(docRef);
    
    final post = PostModel.fromFirestore(doc);
    final updated = post.copyWith(authorId: newAuthorId);
    
    transaction.update(docRef, updated.toFirestoreUpdate());
  });
}
```

### 5. Local Drafts

```dart
class DraftService {
  Future<void> saveDraft(PostModel post) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('draft_${post.id}', jsonEncode(post.toJson()));
  }
  
  Future<PostModel?> loadDraft(String postId) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('draft_$postId');
    if (jsonString == null) return null;
    
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    return PostModel.fromJson(json);
  }
}
```

---

## Data Migration

### Importing Historical Data

```dart
class DataMigrationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  Future<void> importHistoricalPosts(
    List<Map<String, dynamic>> historicalData
  ) async {
    final batch = _firestore.batch();
    
    for (final data in historicalData) {
      final post = PostModel(
        title: data['title'],
        content: data['content'],
        authorId: data['author_id'],
        // Preserve historical timestamps from old system
        createdAt: DateTime.parse(data['created_date']),
        updatedAt: DateTime.parse(data['last_modified']),
        tags: List<String>.from(data['tags'] ?? []),
      );
      
      final docRef = _firestore.collection('posts').doc();
      
      // Use toFirestoreRaw() to preserve exact timestamps
      batch.set(docRef, post.toFirestoreRaw());
    }
    
    await batch.commit();
  }
}
```

### Cloning Documents

```dart
Future<String> clonePost(String postId, {String? newTitle}) async {
  // Read original
  final originalDoc = await _firestore.collection('posts').doc(postId).get();
  final originalPost = PostModel.fromFirestore(originalDoc);
  
  // Create clone with same createdAt
  final clonedPost = originalPost.copyWith(
    id: '',  // Clear for new document
    title: newTitle ?? '${originalPost.title} (Copy)',
  );
  
  // Preserve createdAt, get new updatedAt
  final docRef = await _firestore.collection('posts').add(
    clonedPost.toFirestoreCreate(useServerTimestamp: false)
  );
  
  return docRef.id;
}
```

### Migrating Between Collections

```dart
Future<void> migratePosts({
  required String fromCollection,
  required String toCollection,
  DateTime? cutoffDate,
}) async {
  Query query = _firestore.collection(fromCollection);
  
  if (cutoffDate != null) {
    query = query.where('createdAt', 
        isGreaterThan: Timestamp.fromDate(cutoffDate));
  }
  
  final snapshot = await query.get();
  final batch = _firestore.batch();
  
  for (final doc in snapshot.docs) {
    final post = PostModel.fromFirestore(doc);
    
    // Preserve all timestamps exactly
    batch.set(
      _firestore.collection(toCollection).doc(doc.id),
      post.toFirestoreRaw(),
    );
  }
  
  await batch.commit();
}
```

### Batch Import with Mixed Timestamps

```dart
Future<void> importMixedData(List<Map<String, dynamic>> data) async {
  final batch = _firestore.batch();
  
  for (final item in data) {
    final post = PostModel.fromJson(item);
    final docRef = _firestore.collection('posts').doc();
    
    if (post.createdAt != null) {
      // Has historical timestamp - preserve it
      batch.set(docRef, post.toFirestoreRaw());
    } else {
      // No timestamp - let server set it
      batch.set(docRef, post.toFirestoreCreate());
    }
  }
  
  await batch.commit();
}
```

### Archiving Data

```dart
Future<void> archivePosts({required DateTime before}) async {
  final snapshot = await _firestore
      .collection('posts')
      .where('createdAt', isLessThan: Timestamp.fromDate(before))
      .get();
  
  final batch = _firestore.batch();
  
  for (final doc in snapshot.docs) {
    final post = PostModel.fromFirestore(doc);
    
    // Archive with exact timestamps
    batch.set(
      _firestore.collection('archived_posts').doc(doc.id),
      post.toFirestoreRaw(),  // Preserves everything
    );
    
    // Delete from main collection
    batch.delete(doc.reference);
  }
  
  await batch.commit();
}
```

---

## Decision Tree

### Serialization (Writing Data)

```
┌─────────────────────────────────────┐
│  Need to save/serialize data?       │
└──────────────┬──────────────────────┘
               │
               ├─── To Firestore?
               │    │
               │    ├─── New document?
               │    │    │
               │    │    ├─── Current timestamp? ──→ toFirestoreCreate()
               │    │    │
               │    │    └─── Historical timestamp? ──→ toFirestoreRaw()
               │    │         or toFirestoreCreate(useServerTimestamp: false)
               │    │
               │    └─── Existing document? ──→ toFirestoreUpdate()
               │
               ├─── Via Cloud Function? ──→ toCallable()
               │
               └─── To local storage? ──→ toJson()
```

### Deserialization (Reading Data)

```
┌─────────────────────────────────────┐
│  Need to read/deserialize data?     │
└──────────────┬──────────────────────┘
               │
               ├─── From Firestore DocumentSnapshot?
               │    │
               │    └─── Model.fromFirestore(doc)
               │         (adds doc.id, delegates to fromJson)
               │
               ├─── From Cloud Function response?
               │    │
               │    └─── Model.fromJson(result.data as Map<String, dynamic>)
               │         (SmartTimestampConverter handles all formats)
               │
               └─── From local storage/JSON?
                    │
                    └─── Model.fromJson(jsonDecode(string))
```

### Quick Reference Table

**Writing:**

| Scenario | Method | Why? |
|----------|--------|------|
| Creating a new post | `toFirestoreCreate()` | Server sets both timestamps |
| Updating an existing post | `toFirestoreUpdate()` | Preserves createdAt, updates updatedAt |
| Importing 2020 data | `toFirestoreRaw()` | Keeps exact historical timestamps |
| Sending to cloud function | `toCallable()` | Server handles timestamps |
| Saving draft locally | `toJson()` | JSON-compatible format |
| Cloning a document | `toFirestoreCreate(useServerTimestamp: false)` | Copy createdAt, new updatedAt |
| Archiving data | `toFirestoreRaw()` | Preserve everything exactly |

**Reading:**

| Scenario | Method | Why? |
|----------|--------|------|
| Reading from Firestore | `Model.fromFirestore(doc)` | Handles document ID + data |
| Receiving from cloud function | `Model.fromJson(result.data)` | SmartTimestampConverter handles formats |
| Loading from local storage | `Model.fromJson(json)` | Same converter handles all formats |
| Deserializing any JSON | `Model.fromJson(map)` | Universal entry point |

---

## Legacy Converters

All existing converters are fully supported for backward compatibility.

### TimestampConverter

Non-nullable DateTime converter.

```dart
@TimestampConverter()
final DateTime createdAt;
```

**Output**: `{_seconds: int, _nanoseconds: int}`

### TimestampNullableConverter

Nullable DateTime converter.

```dart
@TimestampNullableConverter()
final DateTime? updatedAt;
```

### TimestampCreationConverter

Automatically uses `FieldValue.serverTimestamp()` on creation.

```dart
@TimestampCreationConverter()
final DateTime? createdAt;
```

**toJson() returns**: `FieldValue.serverTimestamp()`

### TimestampModifiedConverter

Always uses `FieldValue.serverTimestamp()`.

```dart
@TimestampModifiedConverter()
final DateTime updatedAt;
```

### TimestampNullableModifiedConverter

Nullable version that always uses `FieldValue.serverTimestamp()`.

```dart
@TimestampNullableModifiedConverter()
final DateTime? updatedAt;
```

### TimestampMillisConverter

Function-safe converter (milliseconds).

```dart
@TimestampMillisConverter()
final DateTime timestamp;
```

**Output**: Milliseconds (int)

### TimestampMillisNullableConverter

Nullable function-safe converter.

```dart
@TimestampMillisNullableConverter()
final DateTime? timestamp;
```

### TimestampNullableListConverter

For lists of timestamps.

```dart
@TimestampNullableListConverter()
final List<DateTime>? timestamps;
```

### FirestoreJsonTimestampConverter

Utility class for converting JSON timestamps.

```dart
final jsonData = myModel.toJson();
final firestoreData = FirestoreJsonTimestampConverter.convertJson(jsonData);
await firestore.collection('items').add(firestoreData);
```

---

## Migration Guide

### From Legacy Converters to BaseFirestoreModel

#### Step 1: Extend BaseFirestoreModel

```dart
// Before
@JsonSerializable()
class PostModel {
  // ...
}

// After
@JsonSerializable(explicitToJson: true)
class PostModel extends BaseFirestoreModel {
  // ...
}
```

#### Step 2: Replace Converters

```dart
// Before
@TimestampCreationConverter()
final DateTime? createdAt;

@TimestampModifiedConverter()
final DateTime updatedAt;

// After
@SmartTimestampConverter()
final DateTime? createdAt;

@SmartTimestampConverter()
final DateTime? updatedAt;
```

#### Step 3: Update Operations

```dart
// Before - Create
await firestore.collection('posts').add(post.toJson());

// After - Create
await firestore.collection('posts').add(post.toFirestoreCreate());

// Before - Update
await firestore.collection('posts').doc(id).update(post.toJson());

// After - Update
await firestore.collection('posts').doc(id).update(post.toFirestoreUpdate());
```

#### Step 4: Regenerate

```bash
dart run build_runner build --delete-conflicting-outputs
```

### Migration Strategies

**Option 1: No Migration** (Recommended for stable apps)
- Continue using legacy converters
- No changes needed
- Everything works as before

**Option 2: Gradual Migration**
- Migrate models one at a time
- Both approaches coexist peacefully
- Test thoroughly after each migration

**Option 3: New Features Only**
- Use BaseFirestoreModel for new models
- Leave existing models unchanged
- No risk to existing functionality

---

## Best Practices

### 1. Use Appropriate Methods

✅ **DO**: Use `toFirestoreCreate()` for new documents
```dart
await firestore.collection('posts').add(post.toFirestoreCreate());
```

❌ **DON'T**: Use `toJson()` for Firestore operations
```dart
await firestore.collection('posts').add(post.toJson());  // Wrong!
```

### 2. Always Preserve createdAt on Updates

✅ **DO**: Use `toFirestoreUpdate()` which removes createdAt
```dart
await firestore.collection('posts').doc(id).update(post.toFirestoreUpdate());
```

❌ **DON'T**: Use `toFirestoreCreate()` for updates
```dart
await firestore.collection('posts').doc(id).update(post.toFirestoreCreate());  // Wrong!
```

### 3. Document Timestamp Fields

```dart
@JsonSerializable()
class PostModel extends BaseFirestoreModel {
  // Server-managed automatic timestamps
  @SmartTimestampConverter()
  final DateTime? createdAt;
  
  @SmartTimestampConverter()
  final DateTime? updatedAt;
  
  // User-controlled timestamps (NOT auto-managed)
  @SmartTimestampConverter()
  final DateTime? scheduledPublishDate;
  
  @SmartTimestampConverter()
  final DateTime? publishedAt;
  
  @override
  List<String> getCreateTimestampFields() => ['createdAt'];
  
  @override
  List<String> getUpdateTimestampFields() => ['updatedAt'];
}
```

### 4. Test Migration Scenarios

```dart
test('data migration preserves timestamps', () async {
  final historicalPost = PostModel(
    title: 'Old Post',
    createdAt: DateTime(2020, 1, 15),
    updatedAt: DateTime(2021, 6, 20),
  );
  
  final data = historicalPost.toFirestoreRaw();
  
  expect(data['createdAt'], isA<Timestamp>());
  expect(data['updatedAt'], isA<Timestamp>());
  
  final timestamp = data['createdAt'] as Timestamp;
  expect(timestamp.toDate().year, 2020);
});
```

### 5. Use Transactions for Critical Updates

```dart
await firestore.runTransaction((transaction) async {
  final docRef = firestore.collection('posts').doc(postId);
  final doc = await transaction.get(docRef);
  
  final post = PostModel.fromFirestore(doc);
  final updated = post.copyWith(/* changes */);
  
  transaction.update(docRef, updated.toFirestoreUpdate());
});
```

### 6. Consider Index Impact

Server timestamps may cause race conditions with queries:

```dart
// Potential issue: Document might not appear immediately in queries
await firestore.collection('posts').add(post.toFirestoreCreate());

// Query by createdAt might not include it right away
final recent = await firestore
    .collection('posts')
    .orderBy('createdAt', descending: true)
    .limit(10)
    .get();
```

**Solution**: Use client-side timestamp for immediate queries if needed.

### 7. Handle Offline Scenarios

```dart
// Enable offline persistence
await FirebaseFirestore.instance.settings = const Settings(
  persistenceEnabled: true,
);

// Server timestamps work offline - they'll be set when reconnected
await firestore.collection('posts').add(post.toFirestoreCreate());
```

### 8. Cloud Function Server-Side Timestamp Management

**Critical Rules for Cloud Functions**:

✅ **DO**: Always add timestamps on the server
```typescript
// TypeScript
const postDoc = {
  ...data,  // Data from toCallable()
  createdAt: admin.firestore.FieldValue.serverTimestamp(),
  updatedAt: admin.firestore.FieldValue.serverTimestamp(),
};
```

✅ **DO**: Only update `updatedAt` on updates
```typescript
// TypeScript - UPDATE operation
const update = {
  ...updateData,
  updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  // Do NOT include createdAt
};
```

❌ **DON'T**: Trust client-provided timestamps for audit fields
```typescript
// ❌ WRONG - Security vulnerability
const postDoc = {
  ...data,  // Includes client's createdAt - can be faked!
};
```

❌ **DON'T**: Send `toFirestoreCreate()` to Cloud Functions
```dart
// ❌ WRONG - FieldValue objects don't work in Cloud Functions
await callable.call(post.toFirestoreCreate());  // Will fail!

// ✅ CORRECT
await callable.call(post.toCallable());  // Removes FieldValue fields
```

**Security Checklist for Cloud Functions**:

1. ✅ Verify authentication (`context.auth`)
2. ✅ Validate authorization (user can perform action)
3. ✅ Add `createdAt` and `updatedAt` on server
4. ✅ Add `uid` from `context.auth.uid`
5. ✅ Validate input data
6. ✅ Never trust client timestamps for audit fields
7. ✅ Use server timestamps for consistency

**Example Secure Implementation**:

```typescript
export const createPost = functions.https.onCall(async (data, context) => {
  // 1. Verify authentication
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'Must be logged in'
    );
  }
  
  // 2. Validate input
  if (!data.title || !data.content) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'Title and content are required'
    );
  }
  
  // 3. Prepare document with server timestamps
  const postDoc = {
    title: data.title,
    content: data.content,
    tags: data.tags || [],
    // User-controlled timestamps (if any)
    scheduledPublishDate: data.scheduledPublishDate,
    // Server-controlled fields
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    uid: context.auth.uid,  // From auth context
    // Audit trail
    createdBy: context.auth.token.email,
    ipAddress: context.rawRequest.ip,
  };
  
  // 4. Write to Firestore
  const docRef = await db.collection('posts').add(postDoc);
  
  return {
    success: true,
    postId: docRef.id,
  };
});
```

---

## Troubleshooting

### Issue: Timestamps not updating

**Problem**: `updatedAt` not changing when document is updated

**Solution**: Use `toFirestoreUpdate()` instead of `toJson()` or `toFirestoreCreate()`

```dart
// ❌ Wrong
await firestore.collection('posts').doc(id).update(post.toJson());

// ✅ Correct
await firestore.collection('posts').doc(id).update(post.toFirestoreUpdate());
```

### Issue: createdAt changes on update

**Problem**: Original creation timestamp is overwritten

**Solution**: Use `toFirestoreUpdate()` which removes `createdAt` from payload

```dart
// ❌ Wrong - includes createdAt
await firestore.collection('posts').doc(id).update(post.toFirestoreCreate());

// ✅ Correct - excludes createdAt
await firestore.collection('posts').doc(id).update(post.toFirestoreUpdate());
```

### Issue: Cloud Function errors with FieldValue

**Problem**: `FieldValue.serverTimestamp()` doesn't work in callable functions

**Solution**: Use `toCallable()` which removes timestamp fields

```dart
// ❌ Wrong - includes FieldValue objects
await callable.call(post.toFirestoreCreate());

// ✅ Correct - removes timestamp fields
await callable.call(post.toCallable());
```

### Issue: Migration timestamps are wrong

**Problem**: Historical timestamps are replaced with current time

**Solution**: Use `toFirestoreRaw()` or `toFirestoreCreate(useServerTimestamp: false)`

```dart
// ❌ Wrong - uses current server time
await firestore.collection('posts').add(historicalPost.toFirestoreCreate());

// ✅ Correct - preserves historical timestamps
await firestore.collection('posts').add(historicalPost.toFirestoreRaw());

// ✅ Also correct
await firestore.collection('posts').add(
  historicalPost.toFirestoreCreate(useServerTimestamp: false)
);
```

### Issue: Null timestamp errors

**Problem**: Nullable timestamps causing issues

**Solution**: Use appropriate converter

```dart
// For nullable fields
@SmartTimestampConverter()
final DateTime? createdAt;

// For non-nullable fields
@SmartTimestampConverterNotNull()
final DateTime timestamp;
```

### Issue: fromJson not handling Timestamp

**Problem**: Error when reading from Firestore

**Solution**: SmartTimestampConverter handles all formats automatically

```dart
// ✅ Handles all these formats:
// - Timestamp objects
// - {_seconds: int, _nanoseconds: int}
// - {seconds: int, nanoseconds: int}
// - Milliseconds (int)
// - ISO strings

@SmartTimestampConverter()
final DateTime? createdAt;
```

### Issue: Cloud Function missing timestamps

**Problem**: Documents created via Cloud Functions have no `createdAt` or `updatedAt`

**Solution**: Server must add timestamps - `toCallable()` removes them intentionally

```typescript
// ❌ WRONG - Missing timestamps
export const createPost = functions.https.onCall(async (data, context) => {
  await db.collection('posts').add(data);  // Missing timestamps!
});

// ✅ CORRECT - Server adds timestamps
export const createPost = functions.https.onCall(async (data, context) => {
  const postDoc = {
    ...data,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    uid: context.auth?.uid,
  };
  await db.collection('posts').add(postDoc);
});
```

### Issue: Cloud Function fails with FieldValue error

**Problem**: Error like "Cannot encode type FieldValue" in Cloud Function

**Solution**: Use `toCallable()` instead of `toFirestoreCreate()` or `toFirestoreUpdate()`

```dart
// ❌ WRONG - FieldValue can't be sent to Cloud Functions
await callable.call(post.toFirestoreCreate());

// ✅ CORRECT - Removes FieldValue fields
await callable.call(post.toCallable());
```

**Why?** `FieldValue.serverTimestamp()` is a special Firestore client-side sentinel that only works in direct Firestore writes. It cannot be serialized and sent to Cloud Functions.

---

## Examples

### Complete Service Implementation

```dart
class PostService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // CREATE
  Future<String> createPost(PostModel post) async {
    final docRef = await _firestore.collection('posts').add(
      post.toFirestoreCreate()
    );
    return docRef.id;
  }
  
  // READ
  Future<PostModel?> getPost(String postId) async {
    final doc = await _firestore.collection('posts').doc(postId).get();
    if (!doc.exists) return null;
    return PostModel.fromFirestore(doc);
  }
  
  // UPDATE
  Future<void> updatePost(String postId, PostModel post) async {
    await _firestore.collection('posts').doc(postId).update(
      post.toFirestoreUpdate()
    );
  }
  
  // DELETE
  Future<void> deletePost(String postId) async {
    await _firestore.collection('posts').doc(postId).delete();
  }
  
  // WATCH (Real-time)
  Stream<List<PostModel>> watchPosts() {
    return _firestore
        .collection('posts')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => PostModel.fromFirestore(doc))
            .toList());
  }
  
  // BATCH CREATE
  Future<void> createPostsBatch(List<PostModel> posts) async {
    final batch = _firestore.batch();
    
    for (final post in posts) {
      final docRef = _firestore.collection('posts').doc();
      batch.set(docRef, post.toFirestoreCreate());
    }
    
    await batch.commit();
  }
}
```

### Custom Timestamp Management

```dart
@JsonSerializable()
class MessageModel extends BaseFirestoreModel {
  @JsonKey(includeFromJson: true, includeToJson: false)
  final String id;
  
  final String text;
  final String senderId;
  final String recipientId;
  
  @SmartTimestampConverter()
  final DateTime? sentAt;
  
  @SmartTimestampConverter()
  final DateTime? deliveredAt;
  
  @SmartTimestampConverter()
  final DateTime? readAt;
  
  MessageModel({
    this.id = '',
    required this.text,
    required this.senderId,
    required this.recipientId,
    this.sentAt,
    this.deliveredAt,
    this.readAt,
  });
  
  factory MessageModel.fromJson(Map<String, dynamic> json) =>
      _$MessageModelFromJson(json);
  
  @override
  Map<String, dynamic> toJson() => _$MessageModelToJson(this);
  
  factory MessageModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MessageModel.fromJson({'id': doc.id, ...data});
  }
  
  @override
  List<String> getCreateTimestampFields() => ['sentAt'];
  
  @override
  List<String> getUpdateTimestampFields() => [];  // No auto-updates
  
  // Custom update methods
  Map<String, dynamic> toDeliveredUpdate() {
    return {'deliveredAt': FieldValue.serverTimestamp()};
  }
  
  Map<String, dynamic> toReadUpdate() {
    return {
      'readAt': FieldValue.serverTimestamp(),
      if (deliveredAt == null) 'deliveredAt': FieldValue.serverTimestamp(),
    };
  }
}

// Usage
class MessageService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  Future<String> sendMessage(MessageModel message) async {
    final docRef = await _firestore.collection('messages').add(
      message.toFirestoreCreate()  // Sets sentAt
    );
    return docRef.id;
  }
  
  Future<void> markAsDelivered(String messageId) async {
    final doc = await _firestore.collection('messages').doc(messageId).get();
    final message = MessageModel.fromFirestore(doc);
    
    await _firestore.collection('messages').doc(messageId).update(
      message.toDeliveredUpdate()  // Sets deliveredAt only
    );
  }
  
  Future<void> markAsRead(String messageId) async {
    final doc = await _firestore.collection('messages').doc(messageId).get();
    final message = MessageModel.fromFirestore(doc);
    
    await _firestore.collection('messages').doc(messageId).update(
      message.toReadUpdate()  // Sets readAt and deliveredAt if needed
    );
  }
}
```

### Custom Post-Processing

```dart
@JsonSerializable()
class AuditLogModel extends BaseFirestoreModel {
  final String action;
  final String userId;
  final Map<String, dynamic>? metadata;
  
  @SmartTimestampConverterNotNull()
  final DateTime timestamp;
  
  AuditLogModel({
    required this.action,
    required this.userId,
    this.metadata,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
  
  factory AuditLogModel.fromJson(Map<String, dynamic> json) =>
      _$AuditLogModelFromJson(json);
  
  @override
  Map<String, dynamic> toJson() => _$AuditLogModelToJson(this);
  
  @override
  List<String> getCreateTimestampFields() => ['timestamp'];
  
  @override
  List<String> getUpdateTimestampFields() => [];  // Logs never update
  
  @override
  Map<String, dynamic> postProcessJson(
    Map<String, dynamic> json,
    SerializationContext context,
  ) {
    // Add system metadata only for Firestore operations
    if (context == SerializationContext.firestore) {
      json['_systemMetadata'] = {
        'clientVersion': '1.0.0',
        'platform': 'flutter',
      };
    }
    return json;
  }
}
```

---

## Additional Resources

### Example Files in Package

- `lib/data/models/example_models.dart` - 5 complete example models
- `lib/data/models/example_usage.dart` - Real-world service implementations

### Reference Documentation

- [BaseFirestoreModel API](../lib/data/models_bases/base_firestore_model.dart)
- [Model Converters](../lib/data/helpers/model_converters.dart)
- [Implementation Notes](BASE_FIRESTORE_MODEL_IMPLEMENTATION.md)

### Testing Examples

```dart
test('toFirestoreCreate sets server timestamps', () {
  final post = PostModel(title: 'Test', content: 'Content');
  final data = post.toFirestoreCreate();
  
  expect(data['createdAt'], isA<FieldValue>());
  expect(data['updatedAt'], isA<FieldValue>());
});

test('toFirestoreUpdate removes createdAt', () {
  final post = PostModel(title: 'Test', content: 'Content');
  final data = post.toFirestoreUpdate();
  
  expect(data.containsKey('createdAt'), false);
  expect(data['updatedAt'], isA<FieldValue>());
});

test('toFirestoreRaw preserves exact timestamps', () {
  final post = PostModel(
    title: 'Test',
    content: 'Content',
    createdAt: DateTime(2020, 1, 15),
    updatedAt: DateTime(2021, 6, 20),
  );
  
  final data = post.toFirestoreRaw();
  
  expect(data['createdAt'], isA<Timestamp>());
  expect(data['updatedAt'], isA<Timestamp>());
  
  final createdTimestamp = data['createdAt'] as Timestamp;
  expect(createdTimestamp.toDate().year, 2020);
});
```

---

## Summary

### Key Takeaways

1. ✅ Use `toFirestoreCreate()` for new documents
2. ✅ Use `toFirestoreUpdate()` for updates
3. ✅ Use `toFirestoreRaw()` for data migration
4. ✅ Use `toCallable()` for Cloud Functions
5. ✅ Use `toJson()` for local storage
6. ✅ Use `SmartTimestampConverter` for all timestamps
7. ✅ Test thoroughly when migrating
8. ✅ Legacy converters still work perfectly

### Quick Comparison

| Aspect | BaseFirestoreModel | Legacy Converters |
|--------|-------------------|-------------------|
| Complexity | More methods, more control | Simple, direct |
| Timestamp Control | Explicit create vs update | Manual management |
| Data Migration | Built-in support | Manual handling |
| Cloud Functions | Automatic field removal | Manual removal |
| Learning Curve | Medium | Low |
| Flexibility | High | Medium |
| Backward Compatibility | 100% | N/A |
| Recommended For | New projects, complex needs | Simple projects, existing code |

---

**For questions, issues, or contributions**: [github.com/dreamchrome/dreamic](https://github.com/dreamchrome/dreamic)
