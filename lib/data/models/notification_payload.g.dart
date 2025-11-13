// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notification_payload.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

NotificationPayload _$NotificationPayloadFromJson(Map<String, dynamic> json) =>
    NotificationPayload(
      title: json['title'] as String?,
      body: json['body'] as String?,
      imageUrl: json['imageUrl'] as String?,
      route: json['route'] as String?,
      data: json['data'] as Map<String, dynamic>? ?? {},
      actions: (json['actions'] as List<dynamic>?)
              ?.map(
                  (e) => NotificationAction.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      id: (json['id'] as num?)?.toInt(),
      channelId: json['channelId'] as String?,
      category: json['category'] as String?,
      sound: json['sound'] as String?,
      badge: (json['badge'] as num?)?.toInt(),
      ttl: (json['ttl'] as num?)?.toInt(),
      priority: json['priority'] as String?,
    );

Map<String, dynamic> _$NotificationPayloadToJson(
        NotificationPayload instance) =>
    <String, dynamic>{
      'title': instance.title,
      'body': instance.body,
      'imageUrl': instance.imageUrl,
      'route': instance.route,
      'data': instance.data,
      'actions': instance.actions,
      'id': instance.id,
      'channelId': instance.channelId,
      'category': instance.category,
      'sound': instance.sound,
      'badge': instance.badge,
      'ttl': instance.ttl,
      'priority': instance.priority,
    };
