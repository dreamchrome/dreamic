//
// Web Remote Config Refresh Service
//
// Since web platforms don't support onConfigUpdated listeners,
// this service provides periodic refresh functionality for web builds
//

import 'dart:async';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:dreamic/app/app_config_base.dart';
import 'package:dreamic/utils/logger.dart';

class WebRemoteConfigRefreshService {
  static WebRemoteConfigRefreshService? _instance;
  static WebRemoteConfigRefreshService get instance =>
      _instance ??= WebRemoteConfigRefreshService._();

  WebRemoteConfigRefreshService._();

  Timer? _refreshTimer;
  bool _isInitialized = false;

  /// Initialize the web refresh service
  /// This should be called after Remote Config initialization on web platforms only
  Future<void> initialize() async {
    if (!kIsWeb) {
      logd('🚫 WebRemoteConfigRefreshService: Not a web platform, skipping initialization');
      return;
    }

    if (_isInitialized) {
      logd('✅ WebRemoteConfigRefreshService: Already initialized');
      return;
    }

    logd('🌐 WebRemoteConfigRefreshService: Initializing for web platform...');

    // Start periodic refresh (every 5 minutes)
    _startPeriodicRefresh();
    _isInitialized = true;

    logd('✅ WebRemoteConfigRefreshService: Initialized successfully');
  }

  /// Start periodic refresh of Remote Config for web
  void _startPeriodicRefresh() {
    // Refresh every 5 minutes (300 seconds)
    const refreshInterval = Duration(minutes: 5);

    logd('🌐 Starting periodic Remote Config refresh every ${refreshInterval.inMinutes} minutes');

    _refreshTimer = Timer.periodic(refreshInterval, (timer) async {
      await _performRefresh();
    });
  }

  /// Perform a single refresh attempt
  Future<void> _performRefresh() async {
    if (!kIsWeb) return;

    try {
      logd('🔄 WebRemoteConfigRefreshService: Performing periodic refresh...');

      // Skip if using emulator mode
      if (AppConfigBase.doUseBackendEmulator && !AppConfigBase.doOverrideUseLiveRemoteConfig) {
        logd('🔧 Skipping refresh - using mock Remote Config');
        return;
      }

      final instance = FirebaseRemoteConfig.instance;

      // Log values before refresh
      final beforeValue = instance.getString('minimumAppVersionRecommendedApple');
      final beforeSource = instance.getValue('minimumAppVersionRecommendedApple').source;

      // Attempt fetch with current settings (respects minimumFetchInterval)
      final result = await instance.fetchAndActivate();

      // Log values after refresh
      final afterValue = instance.getString('minimumAppVersionRecommendedApple');
      final afterSource = instance.getValue('minimumAppVersionRecommendedApple').source;

      if (result && beforeValue != afterValue) {
        logd(
            '🎉 WebRemoteConfigRefreshService: Values updated! Before: "$beforeValue" -> After: "$afterValue"');

        // Notify that values have changed (if needed by other systems)
        _notifyConfigUpdated();
      } else if (result) {
        logd('✅ WebRemoteConfigRefreshService: Refresh successful, values unchanged');
      } else {
        logd('ℹ️ WebRemoteConfigRefreshService: Refresh skipped (throttled or cached)');
      }

      logd('🔍 Value source before: $beforeSource, after: $afterSource');
    } catch (e) {
      // Don't log as error since this is expected to fail sometimes due to rate limits
      logd('⚠️ WebRemoteConfigRefreshService: Refresh failed (expected with rate limits): $e');
    }
  }

  /// Force an immediate refresh (bypassing rate limits)
  /// Use sparingly due to Firebase's 5 fetches/hour limit
  Future<void> forceRefresh() async {
    if (!kIsWeb) {
      logd('🚫 WebRemoteConfigRefreshService: Force refresh only available on web');
      return;
    }

    try {
      logd('🔥 WebRemoteConfigRefreshService: Force refresh requested...');

      final instance = FirebaseRemoteConfig.instance;

      // Temporarily set zero fetch interval
      await instance.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 10),
          minimumFetchInterval: Duration.zero,
        ),
      );

      // Log before
      final beforeValue = instance.getString('minimumAppVersionRecommendedApple');

      // Force fetch
      final result = await instance.fetchAndActivate();

      // Log after
      final afterValue = instance.getString('minimumAppVersionRecommendedApple');

      // Reset fetch interval
      await instance.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 10),
          minimumFetchInterval: kDebugMode ? const Duration(seconds: 10) : const Duration(hours: 1),
        ),
      );

      if (result) {
        logd('✅ WebRemoteConfigRefreshService: Force refresh successful');
        if (beforeValue != afterValue) {
          logd('🎉 Values updated! Before: "$beforeValue" -> After: "$afterValue"');
          _notifyConfigUpdated();
        }
      } else {
        logd('⚠️ WebRemoteConfigRefreshService: Force refresh returned false');
      }
    } catch (e) {
      loge('❌ WebRemoteConfigRefreshService: Force refresh failed: $e');
    }
  }

  /// Notify other systems that config has been updated
  void _notifyConfigUpdated() {
    // This could trigger version checks or other config-dependent operations
    logd('📢 WebRemoteConfigRefreshService: Config updated, notifying systems...');

    // You could add callbacks here or use a stream to notify other parts of the app
    // For now, just log that an update occurred
  }

  /// Stop the refresh service
  void dispose() {
    logd('🛑 WebRemoteConfigRefreshService: Disposing...');
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _isInitialized = false;
  }

  /// Get current status of the service
  Map<String, dynamic> getStatus() {
    return {
      'isInitialized': _isInitialized,
      'hasActiveTimer': _refreshTimer?.isActive ?? false,
      'isWebPlatform': kIsWeb,
    };
  }
}
