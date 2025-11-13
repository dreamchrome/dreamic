// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notification_action.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

NotificationAction _$NotificationActionFromJson(Map<String, dynamic> json) =>
    NotificationAction(
      id: json['id'] as String,
      label: json['label'] as String,
      icon: json['icon'] as String?,
      requiresAuth: json['requiresAuth'] as bool? ?? false,
      launchesApp: json['launchesApp'] as bool? ?? true,
    );

Map<String, dynamic> _$NotificationActionToJson(NotificationAction instance) =>
    <String, dynamic>{
      'id': instance.id,
      'label': instance.label,
      'icon': instance.icon,
      'requiresAuth': instance.requiresAuth,
      'launchesApp': instance.launchesApp,
    };
