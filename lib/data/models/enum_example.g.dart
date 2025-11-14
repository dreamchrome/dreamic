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
      role: _deserializeUserRole(json['role'] as String?),
      verificationStatus: _deserializeAccountVerificationStatus(
          json['verificationStatus'] as String?),
      createdAt: const SmartTimestampConverter().fromJson(json['createdAt']),
      updatedAt: const SmartTimestampConverter().fromJson(json['updatedAt']),
    );

Map<String, dynamic> _$UserProfileModelToJson(UserProfileModel instance) =>
    <String, dynamic>{
      'username': instance.username,
      'email': instance.email,
      'bio': instance.bio,
      'avatarUrl': instance.avatarUrl,
      'role': _serializeUserRole(instance.role),
      'verificationStatus':
          _serializeAccountVerificationStatus(instance.verificationStatus),
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
      status: json['status'] == null
          ? PostStatus.draft
          : _deserializePostStatus(json['status'] as String?),
      visibility: json['visibility'] == null
          ? PostVisibility.private
          : _deserializePostVisibility(json['visibility'] as String?),
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
      'status': _serializePostStatus(instance.status),
      'visibility': _serializePostVisibility(instance.visibility),
      'createdAt': const SmartTimestampConverter().toJson(instance.createdAt),
      'updatedAt': const SmartTimestampConverter().toJson(instance.updatedAt),
      'publishedAt':
          const SmartTimestampConverter().toJson(instance.publishedAt),
    };

NotificationModel _$NotificationModelFromJson(Map<String, dynamic> json) =>
    NotificationModel(
      id: json['id'] as String? ?? '',
      title: json['title'] as String,
      message: json['message'] as String,
      userId: json['userId'] as String,
      isRead: json['isRead'] as bool? ?? false,
      priority: json['priority'] == null
          ? NotificationPriority.medium
          : _deserializeNotificationPriority(json['priority'] as String?),
      createdAt: const SmartTimestampConverter().fromJson(json['createdAt']),
    );

Map<String, dynamic> _$NotificationModelToJson(NotificationModel instance) =>
    <String, dynamic>{
      'title': instance.title,
      'message': instance.message,
      'userId': instance.userId,
      'isRead': instance.isRead,
      'priority': _serializeNotificationPriority(instance.priority),
      'createdAt': const SmartTimestampConverter().toJson(instance.createdAt),
    };
