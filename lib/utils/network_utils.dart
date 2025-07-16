import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dreamic/utils/logger.dart';

class NetworkUtils {
  static const String _cachedEmulatorAddressKey = 'dreamic_firebase_emulator_host_address';

  /// Discovers the host machine's IP address for Firebase emulator
  static Future<String?> discoverFirebaseEmulatorHost({int port = 5001}) async {
    if (kIsWeb) {
      return '127.0.0.1'; // Web always uses localhost
    }

    logd('Starting Firebase emulator host discovery on port $port...');

    // Try cached address first (if available)
    final cachedAddress = await _getCachedEmulatorAddress();
    if (cachedAddress != null) {
      logd('Testing cached emulator address: $cachedAddress');
      if (await _testConnection(cachedAddress, port)) {
        logd('Cached Firebase emulator address still valid: $cachedAddress');
        return cachedAddress;
      } else {
        logd('Cached address no longer valid, clearing cache');
        await _clearCachedEmulatorAddress();
      }
    }

    // Test localhost first (might work for some setups)
    if (await _testConnection('127.0.0.1', port)) {
      logd('Firebase emulator found at localhost');
      await _saveCachedEmulatorAddress('127.0.0.1');
      return '127.0.0.1';
    }

    // Get device IP addresses to determine which subnets to scan
    final deviceIps = await getDeviceIpAddresses();
    final subnetsToScan = <String>{};

    // Extract subnets from device IPs
    for (final deviceIp in deviceIps) {
      final subnet = _getSubnetFromIp(deviceIp);
      if (subnet.isNotEmpty) {
        subnetsToScan.add(subnet);
        logd('Will scan subnet $subnet (from device IP: $deviceIp)');
      }
    }

    // If no device IPs found, fall back to common ranges
    if (subnetsToScan.isEmpty) {
      logd('No device IPs found, using common network ranges');
      subnetsToScan.addAll([
        '192.168.1.', // Common home networks
        '172.20.10.', // iOS hotspot range
        '192.168.0.', // Common router default
        '10.0.0.', // Some corporate networks
        '10.0.1.', // Alternative corporate setup
        '172.16.0.', // Docker/VPN networks
        '192.168.43.', // Android hotspot range
      ]);
    }

    // Test each subnet with priority IPs first
    for (final range in subnetsToScan) {
      // Test common host IPs first (router gateway, common static IPs)
      final priorityIPs = [1, 100, 101, 102, 2, 10, 20, 50];

      for (final ip in priorityIPs) {
        final address = '$range$ip';
        if (await _testConnection(address, port)) {
          logd('Firebase emulator found at: $address');
          await _saveCachedEmulatorAddress(address);
          return address;
        }
      }

      // If priority IPs don't work, scan the full range (but limit it for performance)
      for (int i = 2; i <= 254; i++) {
        if (priorityIPs.contains(i)) continue; // Skip already tested IPs

        final address = '$range$i';
        if (await _testConnection(address, port)) {
          logd('Firebase emulator found at: $address');
          await _saveCachedEmulatorAddress(address);
          return address;
        }

        // Add small delay every 20 IPs to avoid overwhelming the network
        if (i % 20 == 0) {
          await Future.delayed(const Duration(milliseconds: 10));
        }
      }
    }

    logw('Firebase emulator host not found');
    return null;
  }

  /// Get the cached emulator address from SharedPreferences
  static Future<String?> _getCachedEmulatorAddress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_cachedEmulatorAddressKey);
    } catch (e) {
      logw('Error reading cached emulator address: $e');
      return null;
    }
  }

  /// Save the discovered emulator address to SharedPreferences
  static Future<void> _saveCachedEmulatorAddress(String address) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cachedEmulatorAddressKey, address);
      logd('Cached emulator address: $address');
    } catch (e) {
      logw('Error saving cached emulator address: $e');
    }
  }

  /// Clear the cached emulator address from SharedPreferences
  static Future<void> _clearCachedEmulatorAddress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cachedEmulatorAddressKey);
      logd('Cleared cached emulator address');
    } catch (e) {
      logw('Error clearing cached emulator address: $e');
    }
  }

  /// Manually clear the cached emulator address (for testing or troubleshooting)
  static Future<void> clearCachedEmulatorAddress() async {
    await _clearCachedEmulatorAddress();
  }

  /// Test if Firebase emulator is accessible at the given address
  static Future<bool> _testConnection(String address, int port) async {
    try {
      logd('Testing connection to $address:$port...');
      final socket =
          await Socket.connect(address, port, timeout: const Duration(milliseconds: 350));

      socket.destroy();
      return true;
    } catch (e) {
      // Connection failed
      return false;
    }
  }

  /// Get all device IP addresses (for debugging and network discovery)
  static Future<List<String>> getDeviceIpAddresses() async {
    final addresses = <String>[];

    try {
      final interfaces = await NetworkInterface.list();

      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (address.type == InternetAddressType.IPv4 &&
              !address.isLoopback &&
              !address.address.startsWith('169.254')) {
            // Exclude link-local
            addresses.add(address.address);
          }
        }
      }
    } catch (e) {
      logw('Error getting device IPs: $e');
    }

    return addresses;
  }

  /// Get the device's current IP address (for debugging) - returns first valid IP
  static Future<String?> getDeviceIpAddress() async {
    final addresses = await getDeviceIpAddresses();
    return addresses.isNotEmpty ? addresses.first : null;
  }

  /// Extract subnet from IP address (e.g., "192.168.1.100" -> "192.168.1.")
  static String _getSubnetFromIp(String ipAddress) {
    final parts = ipAddress.split('.');
    if (parts.length >= 3) {
      return '${parts[0]}.${parts[1]}.${parts[2]}.';
    }
    return '';
  }
}
