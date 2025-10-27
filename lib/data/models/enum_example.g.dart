// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'enum_example.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UserProfileModel _$UserProfileModelFromJson(Map<String, dynamic> json) =>
    UserProfileModel(
      id: json['id'] as String? ?? '',
      username: json['username'] as String,
      email: json['email'] as String,
      bio: json['bio'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      role: const UserRoleConverter().fromJson(json['role'] as String?),
      verificationStatus: const AccountVerificationStatusConverter()
          .fromJson(json['verificationStatus'] as String?),
      createdAt: const SmartTimestampConverter().fromJson(json['createdAt']),
      updatedAt: const SmartTimestampConverter().fromJson(json['updatedAt']),
    );

Map<String, dynamic> _$UserProfileModelToJson(UserProfileModel instance) =>
    <String, dynamic>{
      'username': instance.username,
      'email': instance.email,
      'bio': instance.bio,
      'avatarUrl': instance.avatarUrl,
      'role': const UserRoleConverter().toJson(instance.role),
      'verificationStatus': const AccountVerificationStatusConverter()
          .toJson(instance.verificationStatus),
      'createdAt': const SmartTimestampConverter().toJson(instance.createdAt),
      'updatedAt': const SmartTimestampConverter().toJson(instance.updatedAt),
    };

PostModel _$PostModelFromJson(Map<String, dynamic> json) => PostModel(
      id: json['id'] as String? ?? '',
      title: json['title'] as String,
      content: json['content'] as String,
      authorId: json['authorId'] as String,
      tags:
          (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ??
              const [],
      status: $enumDecodeNullable(_$PostStatusEnumMap, json['status']) ??
          PostStatus.draft,
      visibility:
          $enumDecodeNullable(_$PostVisibilityEnumMap, json['visibility']) ??
              PostVisibility.private,
      createdAt: const SmartTimestampConverter().fromJson(json['createdAt']),
      updatedAt: const SmartTimestampConverter().fromJson(json['updatedAt']),
      publishedAt:
          const SmartTimestampConverter().fromJson(json['publishedAt']),
    );

Map<String, dynamic> _$PostModelToJson(PostModel instance) => <String, dynamic>{
      'title': instance.title,
      'content': instance.content,
      'authorId': instance.authorId,
      'tags': instance.tags,
      'status': _$PostStatusEnumMap[instance.status]!,
      'visibility': _$PostVisibilityEnumMap[instance.visibility]!,
      'createdAt': const SmartTimestampConverter().toJson(instance.createdAt),
      'updatedAt': const SmartTimestampConverter().toJson(instance.updatedAt),
      'publishedAt':
          const SmartTimestampConverter().toJson(instance.publishedAt),
    };

const _$PostStatusEnumMap = {
  PostStatus.draft: 'draft',
  PostStatus.published: 'published',
  PostStatus.archived: 'archived',
};

const _$PostVisibilityEnumMap = {
  PostVisibility.public: 'public',
  PostVisibility.friendsOnly: 'friendsOnly',
  PostVisibility.private: 'private',
};

NotificationModel _$NotificationModelFromJson(Map<String, dynamic> json) =>
    NotificationModel(
      id: json['id'] as String? ?? '',
      title: json['title'] as String,
      message: json['message'] as String,
      userId: json['userId'] as String,
      isRead: json['isRead'] as bool? ?? false,
      priority: $enumDecodeNullable(
              _$NotificationPriorityEnumMap, json['priority']) ??
          NotificationPriority.medium,
      createdAt: const SmartTimestampConverter().fromJson(json['createdAt']),
    );

Map<String, dynamic> _$NotificationModelToJson(NotificationModel instance) =>
    <String, dynamic>{
      'title': instance.title,
      'message': instance.message,
      'userId': instance.userId,
      'isRead': instance.isRead,
      'priority': _$NotificationPriorityEnumMap[instance.priority]!,
      'createdAt': const SmartTimestampConverter().toJson(instance.createdAt),
    };

const _$NotificationPriorityEnumMap = {
  NotificationPriority.low: 'low',
  NotificationPriority.medium: 'medium',
  NotificationPriority.high: 'high',
};
