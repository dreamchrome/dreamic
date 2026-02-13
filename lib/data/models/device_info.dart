import 'package:dreamic/data/helpers/model_converters.dart';
import 'package:dreamic/data/models/device_form_factor.dart';
import 'package:dreamic/data/models/device_platform.dart';
import 'package:dreamic/data/models_bases/base_firestore_model.dart';
import 'package:json_annotation/json_annotation.dart';

part 'device_info.g.dart';

/// Additional device metadata stored in the optional `deviceInfo` field.
///
/// Contains non-essential device information that may be useful for
/// debugging, analytics, or device identification.
@JsonSerializable()
class DeviceMetadata {
  /// Device model name (e.g., "iPhone 14 Pro", "Pixel 7")
  final String? model;

  /// Operating system version (e.g., "iOS 17.2", "Android 14")
  final String? osVersion;

  const DeviceMetadata({
    this.model,
    this.osVersion,
  });

  /// Creates a [DeviceMetadata] from JSON data.
  factory DeviceMetadata.fromJson(Map<String, dynamic> json) =>
      _$DeviceMetadataFromJson(json);

  /// Converts this [DeviceMetadata] to JSON data.
  Map<String, dynamic> toJson() => _$DeviceMetadataToJson(this);

  /// Creates a copy of this metadata with the given fields replaced.
  DeviceMetadata copyWith({
    String? model,
    String? osVersion,
  }) {
    return DeviceMetadata(
      model: model ?? this.model,
      osVersion: osVersion ?? this.osVersion,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeviceMetadata &&
          runtimeType == other.runtimeType &&
          model == other.model &&
          osVersion == other.osVersion;

  @override
  int get hashCode => model.hashCode ^ osVersion.hashCode;

  @override
  String toString() => 'DeviceMetadata{model: $model, osVersion: $osVersion}';
}

/// Represents a device registered with the DeviceService.
///
/// This model stores device-level information including timezone data,
/// push notification token, and activity tracking. Each device document
/// is stored at `users/{uid}/devices/{deviceId}` in Firestore.
///
/// ## Fields
///
/// - [deviceId]: Unique identifier for this device (UUIDv4, stable per install)
/// - [timezone]: IANA timezone string (e.g., "America/New_York")
/// - [timezoneOffsetMinutes]: Current UTC offset in minutes (updated for DST)
/// - [lastActiveAt]: Last time this device was active (for staleness tracking)
/// - [fcmToken]: Current push notification token (nullable when unavailable)
/// - [fcmTokenUpdatedAt]: When the token was last updated
/// - [createdAt]: When this device was first registered
/// - [updatedAt]: When this device document was last updated
/// - [platform]: Device platform (ios, android, web, macos, windows, linux)
/// - [formFactor]: Physical form factor (phone, tablet, desktop, browser)
/// - [appVersion]: App version installed on this device
/// - [deviceInfo]: Optional additional device metadata
///
/// ## Example
///
/// ```dart
/// final device = DeviceInfo(
///   deviceId: '550e8400-e29b-41d4-a716-446655440000',
///   timezone: 'America/New_York',
///   timezoneOffsetMinutes: -300,
///   platform: DevicePlatform.ios,
///   appVersion: '1.2.3',
/// );
/// ```
@JsonSerializable(explicitToJson: true)
class DeviceInfo extends BaseFirestoreModel {
  /// Unique identifier for this device (UUIDv4).
  ///
  /// Generated once per app install and persisted locally.
  /// Used as the document ID in Firestore: `users/{uid}/devices/{deviceId}`.
  final String deviceId;

  /// IANA timezone identifier (e.g., "America/New_York", "Europe/London").
  ///
  /// This is the semantic timezone that includes DST rules and names.
  /// Used as the authoritative source for local time calculations.
  final String timezone;

  /// Current UTC offset in minutes.
  ///
  /// Positive values are east of UTC, negative values are west.
  /// Examples: -300 (EST), -240 (EDT), 330 (IST), 545 (Nepal).
  ///
  /// This value is denormalized for efficient Firestore queries.
  /// It MUST be refreshed when DST transitions occur, even if [timezone]
  /// remains unchanged.
  final int timezoneOffsetMinutes;

  /// When this device was last active.
  ///
  /// Updated periodically via `touchDevice()` to track device activity.
  /// Used by backend to determine "active devices" for notification delivery
  /// and staleness cleanup.
  @SmartTimestampConverter()
  final DateTime? lastActiveAt;

  /// Current FCM push notification token for this device.
  ///
  /// Nullable when:
  /// - User has not granted notification permission
  /// - Token has been explicitly cleared (logout)
  /// - Token is temporarily unavailable
  ///
  /// When non-null, this device is a "deliverable endpoint" for push
  /// notifications.
  final String? fcmToken;

  /// When [fcmToken] was last updated.
  ///
  /// Used for token freshness tracking and debugging token rotation issues.
  @SmartTimestampConverter()
  final DateTime? fcmTokenUpdatedAt;

  /// When this device was first registered.
  ///
  /// Set once on initial device registration and never updated.
  @SmartTimestampConverter()
  final DateTime? createdAt;

  /// When this device document was last updated.
  ///
  /// Updated on any write to the device document.
  @SmartTimestampConverter()
  final DateTime? updatedAt;

  /// Device platform.
  ///
  /// Identifies whether this is a mobile, desktop, or web device.
  /// Used for platform-specific notification handling and analytics.
  @JsonKey(
    fromJson: DevicePlatformSerialization.deserialize,
    toJson: DevicePlatformSerialization.serialize,
  )
  final DevicePlatform? platform;

  /// Physical form factor of this device.
  ///
  /// Orthogonal to [platform] — an iPad is platform "ios" but
  /// form factor "tablet". Used by server-side delivery strategies
  /// to prioritize notification delivery (e.g., prefer phones over tablets).
  @JsonKey(
    fromJson: DeviceFormFactorSerialization.deserialize,
    toJson: DeviceFormFactorSerialization.serialize,
  )
  final DeviceFormFactor? formFactor;

  /// App version installed on this device.
  ///
  /// Useful for debugging and ensuring notifications are compatible
  /// with the installed app version.
  final String? appVersion;

  /// Additional device metadata.
  ///
  /// Optional field containing non-essential device information like
  /// device model and OS version. Useful for debugging and analytics.
  final DeviceMetadata? deviceInfo;

  DeviceInfo({
    required this.deviceId,
    required this.timezone,
    required this.timezoneOffsetMinutes,
    this.lastActiveAt,
    this.fcmToken,
    this.fcmTokenUpdatedAt,
    this.createdAt,
    this.updatedAt,
    this.platform,
    this.formFactor,
    this.appVersion,
    this.deviceInfo,
  });

  /// Creates a [DeviceInfo] from JSON data.
  ///
  /// Handles multiple timestamp formats from different sources:
  /// - Firestore Timestamp objects
  /// - Cloud Functions Map format ({_seconds, _nanoseconds})
  /// - Milliseconds since epoch
  /// - ISO 8601 strings
  factory DeviceInfo.fromJson(Map<String, dynamic> json) =>
      _$DeviceInfoFromJson(json);

  /// Converts this [DeviceInfo] to JSON data.
  @override
  Map<String, dynamic> toJson() => _$DeviceInfoToJson(this);

  /// Fields that should only be set on document creation.
  @override
  List<String> getCreateTimestampFields() => ['createdAt'];

  /// Fields that should always be updated with server timestamp.
  @override
  List<String> getUpdateTimestampFields() => ['updatedAt'];

  /// Creates a copy of this device info with the given fields replaced.
  DeviceInfo copyWith({
    String? deviceId,
    String? timezone,
    int? timezoneOffsetMinutes,
    DateTime? lastActiveAt,
    String? fcmToken,
    DateTime? fcmTokenUpdatedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    DevicePlatform? platform,
    DeviceFormFactor? formFactor,
    String? appVersion,
    DeviceMetadata? deviceInfo,
  }) {
    return DeviceInfo(
      deviceId: deviceId ?? this.deviceId,
      timezone: timezone ?? this.timezone,
      timezoneOffsetMinutes: timezoneOffsetMinutes ?? this.timezoneOffsetMinutes,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      fcmToken: fcmToken ?? this.fcmToken,
      fcmTokenUpdatedAt: fcmTokenUpdatedAt ?? this.fcmTokenUpdatedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      platform: platform ?? this.platform,
      formFactor: formFactor ?? this.formFactor,
      appVersion: appVersion ?? this.appVersion,
      deviceInfo: deviceInfo ?? this.deviceInfo,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeviceInfo &&
          runtimeType == other.runtimeType &&
          deviceId == other.deviceId &&
          timezone == other.timezone &&
          timezoneOffsetMinutes == other.timezoneOffsetMinutes &&
          lastActiveAt == other.lastActiveAt &&
          fcmToken == other.fcmToken &&
          fcmTokenUpdatedAt == other.fcmTokenUpdatedAt &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt &&
          platform == other.platform &&
          formFactor == other.formFactor &&
          appVersion == other.appVersion &&
          deviceInfo == other.deviceInfo;

  @override
  int get hashCode =>
      deviceId.hashCode ^
      timezone.hashCode ^
      timezoneOffsetMinutes.hashCode ^
      lastActiveAt.hashCode ^
      fcmToken.hashCode ^
      fcmTokenUpdatedAt.hashCode ^
      createdAt.hashCode ^
      updatedAt.hashCode ^
      platform.hashCode ^
      formFactor.hashCode ^
      appVersion.hashCode ^
      deviceInfo.hashCode;

  @override
  String toString() {
    return 'DeviceInfo{'
        'deviceId: $deviceId, '
        'timezone: $timezone, '
        'timezoneOffsetMinutes: $timezoneOffsetMinutes, '
        'platform: $platform, '
        'formFactor: $formFactor, '
        'appVersion: $appVersion, '
        'lastActiveAt: $lastActiveAt, '
        'fcmToken: ${fcmToken != null ? '***' : 'null'}'
        '}';
  }
}
