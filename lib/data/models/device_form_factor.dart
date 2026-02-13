import 'package:dreamic/data/helpers/enum_converters.dart';
import 'package:json_annotation/json_annotation.dart';

/// Physical form factor of the device.
///
/// This represents the physical device type, which is orthogonal to
/// [DevicePlatform]. An iPad is platform "ios" but form factor "tablet".
/// Used by the server-side delivery strategy system to prioritize
/// which devices receive notifications.
enum DeviceFormFactor {
  /// Phone (iPhone, Android phone)
  @JsonValue('phone')
  phone,

  /// Tablet (iPad, Android tablet)
  @JsonValue('tablet')
  tablet,

  /// Desktop native app (macOS, Windows, Linux)
  @JsonValue('desktop')
  desktop,

  /// Web browser (any OS)
  @JsonValue('browser')
  browser,
}

/// Extension providing static serialization methods for [DeviceFormFactor].
///
/// Uses the same pattern as [DevicePlatformSerialization] for safe
/// serialization that handles unknown values gracefully.
extension DeviceFormFactorSerialization on DeviceFormFactor {
  /// Deserializes a [DeviceFormFactor] from JSON, returning null for unknown values.
  ///
  /// This is a safe deserializer that will not throw on unknown values,
  /// making the app resilient to new form factor values from the backend.
  static DeviceFormFactor? deserialize(String? value) {
    return safeEnumFromJson<DeviceFormFactor>(
      value,
      DeviceFormFactor.values,
    );
  }

  /// Serializes a [DeviceFormFactor] to JSON (lowercase string).
  static String? serialize(DeviceFormFactor? value) {
    return safeEnumToJson<DeviceFormFactor>(value);
  }
}

/// Extension to provide a displayable name for each form factor.
extension DeviceFormFactorExtension on DeviceFormFactor {
  /// Returns a human-readable display name for this form factor.
  String get displayName {
    switch (this) {
      case DeviceFormFactor.phone:
        return 'Phone';
      case DeviceFormFactor.tablet:
        return 'Tablet';
      case DeviceFormFactor.desktop:
        return 'Desktop';
      case DeviceFormFactor.browser:
        return 'Browser';
    }
  }
}
