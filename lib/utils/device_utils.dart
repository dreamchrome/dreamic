import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dreamic/utils/logger.dart';

class DeviceUtils {
  static DeviceInfoPlugin? _deviceInfo;
  static DeviceInfoPlugin get deviceInfo => _deviceInfo ??= DeviceInfoPlugin();

  /// Determines if the app is running on an emulator/simulator
  static Future<bool> isRunningOnEmulator() async {
    if (kIsWeb) {
      return false; // Web is never an emulator
    }

    try {
      if (Platform.isIOS) {
        return await _isIOSSimulator();
      } else if (Platform.isAndroid) {
        return await _isAndroidEmulator();
      }
    } catch (e) {
      logw('Error detecting emulator status: $e');
    }

    return false;
  }

  /// Check if running on iOS Simulator
  static Future<bool> _isIOSSimulator() async {
    try {
      final iosInfo = await deviceInfo.iosInfo;

      // iOS Simulator indicators
      final model = iosInfo.model.toLowerCase();
      final name = iosInfo.name.toLowerCase();
      final utsname = iosInfo.utsname;

      // Check model and machine type for simulator indicators
      return model.contains('simulator') ||
          name.contains('simulator') ||
          utsname.machine.contains('x86_64') ||
          utsname.machine.contains('arm64') && !iosInfo.isPhysicalDevice;
    } catch (e) {
      logw('Error checking iOS simulator status: $e');
      return false;
    }
  }

  /// Check if running on Android Emulator
  static Future<bool> _isAndroidEmulator() async {
    try {
      final androidInfo = await deviceInfo.androidInfo;

      final model = androidInfo.model.toLowerCase();
      final brand = androidInfo.brand.toLowerCase();
      final manufacturer = androidInfo.manufacturer.toLowerCase();
      final product = androidInfo.product.toLowerCase();
      final device = androidInfo.device.toLowerCase();
      final hardware = androidInfo.hardware.toLowerCase();
      final board = androidInfo.board.toLowerCase();
      final fingerprint = androidInfo.fingerprint.toLowerCase();

      // Common emulator indicators
      final emulatorIndicators = [
        'sdk',
        'emulator',
        'android sdk',
        'google_sdk',
        'generic',
        'goldfish',
        'ranchu',
        'vbox',
        'qemu',
        'simulator'
      ];

      for (final indicator in emulatorIndicators) {
        if (model.contains(indicator) ||
            brand.contains(indicator) ||
            manufacturer.contains(indicator) ||
            product.contains(indicator) ||
            device.contains(indicator) ||
            hardware.contains(indicator) ||
            board.contains(indicator) ||
            fingerprint.contains(indicator)) {
          return true;
        }
      }

      // Additional specific checks
      return !androidInfo.isPhysicalDevice ||
          (brand == 'google' && model.startsWith('sdk')) ||
          device.startsWith('generic');
    } catch (e) {
      logw('Error checking Android emulator status: $e');
      return false;
    }
  }
}
