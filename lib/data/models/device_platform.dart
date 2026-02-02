import 'package:dreamic/data/helpers/enum_converters.dart';
import 'package:json_annotation/json_annotation.dart';

/// Supported device platforms for device tracking.
///
/// This enum represents the platforms where the app can run and be tracked
/// by the DeviceService. It includes mobile, desktop, and web platforms.
enum DevicePlatform {
  /// iOS devices (iPhone, iPad)
  @JsonValue('ios')
  ios,

  /// Android devices
  @JsonValue('android')
  android,

  /// Web browsers
  @JsonValue('web')
  web,

  /// macOS desktop
  @JsonValue('macos')
  macos,

  /// Windows desktop
  @JsonValue('windows')
  windows,

  /// Linux desktop
  @JsonValue('linux')
  linux,
}

/// Extension providing static serialization methods for [DevicePlatform].
///
/// Uses the pattern from enum_converters.dart for safe serialization
/// that handles unknown values gracefully.
extension DevicePlatformSerialization on DevicePlatform {
  /// Deserializes a [DevicePlatform] from JSON, returning null for unknown values.
  ///
  /// This is a safe deserializer that will not throw on unknown values,
  /// making the app resilient to new platform values from the backend.
  static DevicePlatform? deserialize(String? value) {
    return safeEnumFromJson<DevicePlatform>(
      value,
      DevicePlatform.values,
    );
  }

  /// Serializes a [DevicePlatform] to JSON (lowercase string).
  static String? serialize(DevicePlatform? value) {
    return safeEnumToJson<DevicePlatform>(value);
  }
}

/// Extension to provide a displayable name for each platform.
extension DevicePlatformExtension on DevicePlatform {
  /// Returns a human-readable display name for this platform.
  String get displayName {
    switch (this) {
      case DevicePlatform.ios:
        return 'iOS';
      case DevicePlatform.android:
        return 'Android';
      case DevicePlatform.web:
        return 'Web';
      case DevicePlatform.macos:
        return 'macOS';
      case DevicePlatform.windows:
        return 'Windows';
      case DevicePlatform.linux:
        return 'Linux';
    }
  }

  /// Returns true if this is a mobile platform (iOS or Android).
  bool get isMobile => this == DevicePlatform.ios || this == DevicePlatform.android;

  /// Returns true if this is a desktop platform (macOS, Windows, or Linux).
  bool get isDesktop =>
      this == DevicePlatform.macos ||
      this == DevicePlatform.windows ||
      this == DevicePlatform.linux;

  /// Returns true if this is the web platform.
  bool get isWeb => this == DevicePlatform.web;
}
