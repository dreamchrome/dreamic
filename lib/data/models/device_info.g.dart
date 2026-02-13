// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DeviceMetadata _$DeviceMetadataFromJson(Map<String, dynamic> json) =>
    DeviceMetadata(
      model: json['model'] as String?,
      osVersion: json['osVersion'] as String?,
    );

Map<String, dynamic> _$DeviceMetadataToJson(DeviceMetadata instance) =>
    <String, dynamic>{
      'model': instance.model,
      'osVersion': instance.osVersion,
    };

DeviceInfo _$DeviceInfoFromJson(Map<String, dynamic> json) => DeviceInfo(
      deviceId: json['deviceId'] as String,
      timezone: json['timezone'] as String,
      timezoneOffsetMinutes: (json['timezoneOffsetMinutes'] as num).toInt(),
      lastActiveAt:
          const SmartTimestampConverter().fromJson(json['lastActiveAt']),
      fcmToken: json['fcmToken'] as String?,
      fcmTokenUpdatedAt:
          const SmartTimestampConverter().fromJson(json['fcmTokenUpdatedAt']),
      createdAt: const SmartTimestampConverter().fromJson(json['createdAt']),
      updatedAt: const SmartTimestampConverter().fromJson(json['updatedAt']),
      platform:
          DevicePlatformSerialization.deserialize(json['platform'] as String?),
      formFactor: DeviceFormFactorSerialization.deserialize(
          json['formFactor'] as String?),
      appVersion: json['appVersion'] as String?,
      deviceInfo: json['deviceInfo'] == null
          ? null
          : DeviceMetadata.fromJson(json['deviceInfo'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$DeviceInfoToJson(DeviceInfo instance) =>
    <String, dynamic>{
      'deviceId': instance.deviceId,
      'timezone': instance.timezone,
      'timezoneOffsetMinutes': instance.timezoneOffsetMinutes,
      'lastActiveAt':
          const SmartTimestampConverter().toJson(instance.lastActiveAt),
      'fcmToken': instance.fcmToken,
      'fcmTokenUpdatedAt':
          const SmartTimestampConverter().toJson(instance.fcmTokenUpdatedAt),
      'createdAt': const SmartTimestampConverter().toJson(instance.createdAt),
      'updatedAt': const SmartTimestampConverter().toJson(instance.updatedAt),
      'platform': DevicePlatformSerialization.serialize(instance.platform),
      'formFactor':
          DeviceFormFactorSerialization.serialize(instance.formFactor),
      'appVersion': instance.appVersion,
      'deviceInfo': instance.deviceInfo?.toJson(),
    };
