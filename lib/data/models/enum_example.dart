/// Example: Real-world enum serialization with helper functions
///
/// This example demonstrates the helper function pattern for safe enum
/// serialization that handles unknown values gracefully.
///
/// KEY INSIGHT: json_serializable IGNORES @Converter annotations on non-nullable
/// enums. We must use @JsonKey(fromJson:, toJson:) to explicitly tell it to
/// call our helper functions.
///
/// PATTERN:
/// 1. Define enum (no "unknown" values needed)
/// 2. Create top-level _deserialize and _serialize functions for each enum
/// 3. Use @JsonKey(fromJson: _deserializeFoo, toJson: _serializeFoo) on fields

import 'package:dreamic/dreamic.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

part 'enum_example.g.dart';

// ============================================================================
// 1. Define Enums (No "unknown" values needed!)
// ============================================================================

enum UserRole {
  guest,
  member,
  moderator,
  admin,
}

enum PostStatus {
  draft,
  published,
  archived,
}

enum PostVisibility {
  public,
  friendsOnly,
  private,
}

enum NotificationPriority {
  low,
  medium,
  high,
}

enum AccountVerificationStatus {
  unverified,
  pending,
  verified,
}

// ============================================================================
// 2. Add Serialization Helper Functions for Each Enum
// ============================================================================
// These functions wrap the generic safeEnumFromJson to provide type-specific
// deserialization for each enum with appropriate strategies.

/// STRATEGY 1: Nullable (Unknown → null)
/// Use for optional fields where null is acceptable
UserRole? _deserializeUserRole(String? value) {
  return safeEnumFromJson(
    value,
    UserRole.values,
    // No defaultValue - returns null for unknown values
  );
}

String? _serializeUserRole(UserRole? value) {
  return safeEnumToJson(value);
}

/// STRATEGY 2: Default Value (Unknown → draft)
/// Use for required fields with a safe fallback
PostStatus _deserializePostStatus(String? value) {
  return safeEnumFromJson(
    value,
    PostStatus.values,
    defaultValue: PostStatus.draft,
  )!; // Safe to use ! because default is provided
}

String? _serializePostStatus(PostStatus? value) {
  return safeEnumToJson(value);
}

/// STRATEGY 2: Default Value (Unknown → private for safety)
/// Private is the most secure default for visibility
PostVisibility _deserializePostVisibility(String? value) {
  return safeEnumFromJson(
    value,
    PostVisibility.values,
    defaultValue: PostVisibility.private,
  )!; // Safe to use ! because default is provided
}

String? _serializePostVisibility(PostVisibility? value) {
  return safeEnumToJson(value);
}

/// STRATEGY 3: Logging + Default (Unknown → log + medium)
/// Use for critical fields where you want visibility
NotificationPriority _deserializeNotificationPriority(String? value) {
  return safeEnumFromJson(
    value,
    NotificationPriority.values,
    defaultValue: NotificationPriority.medium,
    onUnknownValue: (v) {
      // Use dreamic's logging
      logw('Unknown NotificationPriority: $v, defaulting to medium');
    },
  )!; // Safe to use ! because default is provided
}

String? _serializeNotificationPriority(NotificationPriority? value) {
  return safeEnumToJson(value);
}

/// STRATEGY 1: Nullable (Unknown → null)
/// Verification status is optional
AccountVerificationStatus? _deserializeAccountVerificationStatus(String? value) {
  return safeEnumFromJson(
    value,
    AccountVerificationStatus.values,
  );
}

String? _serializeAccountVerificationStatus(AccountVerificationStatus? value) {
  return safeEnumToJson(value);
}

// ============================================================================
// 3. Define Models Using @JsonKey with Static Methods
// ============================================================================

@JsonSerializable(explicitToJson: true)
class UserProfileModel extends BaseFirestoreModel {
  @JsonKey(includeFromJson: true, includeToJson: false)
  final String id;

  final String username;
  final String email;
  final String? bio;
  final String? avatarUrl;

  /// Nullable role - if server adds new role, old app gets null
  @JsonKey(fromJson: _deserializeUserRole, toJson: _serializeUserRole)
  final UserRole? role;

  /// Optional verification status
  @JsonKey(
    fromJson: _deserializeAccountVerificationStatus,
    toJson: _serializeAccountVerificationStatus,
  )
  final AccountVerificationStatus? verificationStatus;

  @SmartTimestampConverter()
  final DateTime? createdAt;

  @SmartTimestampConverter()
  final DateTime? updatedAt;

  UserProfileModel({
    this.id = '',
    required this.username,
    required this.email,
    this.bio,
    this.avatarUrl,
    this.role,
    this.verificationStatus,
    this.createdAt,
    this.updatedAt,
  });

  factory UserProfileModel.fromJson(Map<String, dynamic> json) => _$UserProfileModelFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$UserProfileModelToJson(this);

  factory UserProfileModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserProfileModel.fromJson({'id': doc.id, ...data});
  }

  UserProfileModel copyWith({
    String? id,
    String? username,
    String? email,
    String? bio,
    String? avatarUrl,
    UserRole? role,
    AccountVerificationStatus? verificationStatus,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserProfileModel(
      id: id ?? this.id,
      username: username ?? this.username,
      email: email ?? this.email,
      bio: bio ?? this.bio,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      role: role ?? this.role,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<String> getCreateTimestampFields() => ['createdAt'];

  @override
  List<String> getUpdateTimestampFields() => ['updatedAt'];
}

@JsonSerializable(explicitToJson: true)
class PostModel extends BaseFirestoreModel {
  @JsonKey(includeFromJson: true, includeToJson: false)
  final String id;

  final String title;
  final String content;
  final String authorId;
  final List<String> tags;

  /// Non-nullable status with safe default
  @JsonKey(fromJson: _deserializePostStatus, toJson: _serializePostStatus)
  final PostStatus status;

  /// Non-nullable visibility with private as safe default
  @JsonKey(fromJson: _deserializePostVisibility, toJson: _serializePostVisibility)
  final PostVisibility visibility;

  @SmartTimestampConverter()
  final DateTime? createdAt;

  @SmartTimestampConverter()
  final DateTime? updatedAt;

  @SmartTimestampConverter()
  final DateTime? publishedAt;

  PostModel({
    this.id = '',
    required this.title,
    required this.content,
    required this.authorId,
    this.tags = const [],
    this.status = PostStatus.draft,
    this.visibility = PostVisibility.private,
    this.createdAt,
    this.updatedAt,
    this.publishedAt,
  });

  factory PostModel.fromJson(Map<String, dynamic> json) => _$PostModelFromJson(json);

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
    List<String>? tags,
    PostStatus? status,
    PostVisibility? visibility,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? publishedAt,
  }) {
    return PostModel(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      authorId: authorId ?? this.authorId,
      tags: tags ?? this.tags,
      status: status ?? this.status,
      visibility: visibility ?? this.visibility,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      publishedAt: publishedAt ?? this.publishedAt,
    );
  }

  @override
  List<String> getCreateTimestampFields() => ['createdAt'];

  @override
  List<String> getUpdateTimestampFields() => ['updatedAt'];
}

@JsonSerializable(explicitToJson: true)
class NotificationModel extends BaseFirestoreModel {
  @JsonKey(includeFromJson: true, includeToJson: false)
  final String id;

  final String title;
  final String message;
  final String userId;
  final bool isRead;

  /// Uses logging strategy to track when unknown priorities appear
  @JsonKey(
    fromJson: _deserializeNotificationPriority,
    toJson: _serializeNotificationPriority,
  )
  final NotificationPriority priority;

  @SmartTimestampConverter()
  final DateTime? createdAt;

  NotificationModel({
    this.id = '',
    required this.title,
    required this.message,
    required this.userId,
    this.isRead = false,
    this.priority = NotificationPriority.medium,
    this.createdAt,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) =>
      _$NotificationModelFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$NotificationModelToJson(this);

  factory NotificationModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return NotificationModel.fromJson({'id': doc.id, ...data});
  }

  NotificationModel copyWith({
    String? id,
    String? title,
    String? message,
    String? userId,
    bool? isRead,
    NotificationPriority? priority,
    DateTime? createdAt,
  }) {
    return NotificationModel(
      id: id ?? this.id,
      title: title ?? this.title,
      message: message ?? this.message,
      userId: userId ?? this.userId,
      isRead: isRead ?? this.isRead,
      priority: priority ?? this.priority,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<String> getCreateTimestampFields() => ['createdAt'];

  @override
  List<String> getUpdateTimestampFields() => [];
}

// ============================================================================
// 4. Real-World Usage Examples
// ============================================================================

/// Example service showing how these models handle enum updates gracefully
class SocialMediaService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Scenario 1: Server adds new UserRole "superAdmin"
  // Old app doesn't know about "superAdmin", but won't crash
  Future<UserProfileModel?> getUserProfile(String userId) async {
    final doc = await _firestore.collection('users').doc(userId).get();
    if (!doc.exists) return null;

    final user = UserProfileModel.fromFirestore(doc);
    // If server sent role: "superAdmin", user.role will be null (safe!)
    // App continues working, and you can handle null role in UI

    return user;
  }

  // Scenario 2: Server adds new PostStatus "scheduled"
  // Old app defaults to "draft" and continues working
  Future<List<PostModel>> getUserPosts(String userId) async {
    final snapshot =
        await _firestore.collection('posts').where('authorId', isEqualTo: userId).get();

    return snapshot.docs.map((doc) {
      final post = PostModel.fromFirestore(doc);
      // If server sent status: "scheduled", post.status will be PostStatus.draft
      // App continues working with safe default
      return post;
    }).toList();
  }

  // Scenario 3: Server adds new NotificationPriority "urgent"
  // Old app logs the unknown value and defaults to "medium"
  Future<List<NotificationModel>> getUserNotifications(String userId) async {
    final snapshot = await _firestore
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .get();

    return snapshot.docs.map((doc) {
      final notification = NotificationModel.fromFirestore(doc);
      // If server sent priority: "urgent", it will:
      // 1. Log: "Unknown NotificationPriority: urgent, using default: medium"
      // 2. Set priority to NotificationPriority.medium
      // 3. App continues working AND you know unknown values are appearing
      return notification;
    }).toList();
  }

  // Example: Creating new content
  Future<String> createPost(PostModel post) async {
    final docRef = await _firestore.collection('posts').add(
          post.toFirestoreCreate(),
        );
    return docRef.id;
  }

  // Example: Updating content
  Future<void> updatePost(String postId, PostModel post) async {
    await _firestore.collection('posts').doc(postId).update(
          post.toFirestoreUpdate(),
        );
  }

  // Example: Publishing a post
  Future<void> publishPost(String postId) async {
    final doc = await _firestore.collection('posts').doc(postId).get();
    final post = PostModel.fromFirestore(doc);

    final published = post.copyWith(
      status: PostStatus.published,
      publishedAt: DateTime.now(),
    );

    await _firestore.collection('posts').doc(postId).update(
          published.toFirestoreUpdate(),
        );
  }
}

// ============================================================================
// 5. Benefits Demonstrated
// ============================================================================

/// This example shows:
///
/// 1. **Backward Compatibility**: Old app versions don't crash when server
///    adds new enum values. They either get null or a safe default.
///
/// 2. **No Maintenance Burden**: No need to add "unknown" to every enum or
///    remember @JsonKey annotations on every field.
///
/// 3. **Flexible Strategies**: Different fields use different strategies:
///    - UserRole: nullable (unknown → null)
///    - PostStatus: default value (unknown → draft)
///    - NotificationPriority: logged default (unknown → medium + log)
///
/// 4. **Safe Defaults**: Critical fields like PostVisibility default to
///    "private" (most secure option) if unknown value appears.
///
/// 5. **Monitoring**: LoggingEnumConverter lets you track when unknown
///    values appear in production, helping you know when to update the app.
///
/// 6. **Type Safety**: Full Dart type checking maintained throughout.
///
/// 7. **Clean Code**: Enums only contain meaningful business values,
///    no technical "unknown" values cluttering your domain model.
