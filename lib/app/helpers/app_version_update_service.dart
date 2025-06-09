import 'dart:async';
import 'dart:io';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:dreamic/app/app_config_base.dart';
import 'package:dreamic/app/helpers/app_version_check.dart';
import 'package:dreamic/data/repos/remote_config_repo_int.dart';
import 'package:dreamic/utils/get_it_utils.dart';
import 'package:dreamic/utils/logger.dart';
import 'package:package_info_plus/package_info_plus.dart';

enum VersionUpdateType {
  none,
  recommended,
  required,
}

class VersionUpdateInfo {
  final VersionUpdateType updateType;
  final String currentVersion;
  final String requiredVersion;
  final String recommendedVersion;
  final String appStoreUrl;

  const VersionUpdateInfo({
    required this.updateType,
    required this.currentVersion,
    required this.requiredVersion,
    required this.recommendedVersion,
    required this.appStoreUrl,
  });

  bool get hasUpdate => updateType != VersionUpdateType.none;
  bool get isRequired => updateType == VersionUpdateType.required;
  bool get isRecommended => updateType == VersionUpdateType.recommended;

  String get targetVersion => isRequired ? requiredVersion : recommendedVersion;
}

class AppVersionUpdateService {
  static final AppVersionUpdateService _instance = AppVersionUpdateService._internal();
  factory AppVersionUpdateService() => _instance;
  AppVersionUpdateService._internal();

  StreamSubscription<RemoteConfigUpdate>? _remoteConfigSubscription;
  final StreamController<VersionUpdateInfo> _updateStreamController =
      StreamController<VersionUpdateInfo>.broadcast();
  bool _isInitialized = false;

  Stream<VersionUpdateInfo> get updateStream => _updateStreamController.stream;
  bool get isInitialized => _isInitialized;

  /// Initialize the version update service and start listening for remote config updates
  Future<void> initialize() async {
    if (_isInitialized) return;

    logd('🔧 Initializing AppVersionUpdateService...');
    _isInitialized = true;

    // Wait for Remote Config to be fully initialized
    await _waitForRemoteConfigInitialization();

    // On first initialization, ensure we have the latest values
    // Remote Config should already be initialized in main.dart, but let's ensure we have fresh values
    await _ensureLatestRemoteConfigValues();

    // Subscribe to remote config updates FIRST (works on all platforms including web)
    // This ensures we catch any updates that happen during or after initialization
    _subscribeToRemoteConfigUpdates();

    // Add a small delay to ensure listener is established
    await Future.delayed(const Duration(milliseconds: 500));

    // Check current version status
    await checkVersionUpdate();

    logd('✅ AppVersionUpdateService initialization completed');
  }

  /// Wait for Remote Config to be properly initialized before setting up listener
  Future<void> _waitForRemoteConfigInitialization() async {
    logd('⏳ Waiting for Remote Config to be initialized...');

    const maxAttempts = 10;
    const delay = Duration(milliseconds: 500);

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        // Try to read a value to verify Remote Config is working through dependency injection
        final testValue = g<RemoteConfigRepoInt>().getString('minimumAppVersionRecommendedApple');

        logd('🔍 Attempt $attempt: Test value from DI: $testValue');

        // If we can read values, Remote Config is initialized
        if (testValue.isNotEmpty) {
          logd('✅ Remote Config verified as initialized on attempt $attempt');
          return;
        }

        if (attempt < maxAttempts) {
          logd('⏳ Remote Config not ready, waiting ${delay.inMilliseconds}ms before retry...');
          await Future.delayed(delay);
        }
      } catch (e) {
        logd('⚠️ Error checking Remote Config on attempt $attempt: $e');
        if (attempt < maxAttempts) {
          await Future.delayed(delay);
        }
      }
    }

    logw('⚠️ Remote Config initialization wait timed out after $maxAttempts attempts');
    logw('⚠️ Proceeding with listener setup, but it may not work properly');
  }

  /// Ensure we have the latest Remote Config values
  Future<void> _ensureLatestRemoteConfigValues() async {
    try {
      // Get current values before any operations for comparison
      final beforeRequired = AppConfigBase.minimumAppVersionRequiredApple;
      final beforeRecommended = AppConfigBase.minimumAppVersionRecommendedApple;
      logd('Before - Required: $beforeRequired, Recommended: $beforeRecommended');

      // Note: We don't call fetchAndActivate here anymore because:
      // 1. When using mock Remote Config, there's nothing to fetch
      // 2. When using real Firebase, the fetch was already done during initialization
      // 3. AppConfigBase getters will return the correct values regardless

      // Get values after to verify they're available
      final afterRequired = AppConfigBase.minimumAppVersionRequiredApple;
      final afterRecommended = AppConfigBase.minimumAppVersionRecommendedApple;
      logd('After - Required: $afterRequired, Recommended: $afterRecommended');

      if (beforeRequired != afterRequired || beforeRecommended != afterRecommended) {
        logd('🔄 Remote Config values have different values after check');
      } else {
        logd('ℹ️ Remote Config values consistent');
      }
    } catch (e) {
      // Check if we have valid values
      final currentRequired = AppConfigBase.minimumAppVersionRequiredApple;
      final currentRecommended = AppConfigBase.minimumAppVersionRecommendedApple;

      if (currentRequired != '0.0.0' || currentRecommended != '0.0.0') {
        logd(
            '⚠️ Error ensuring Remote Config values, but valid values available - Required: $currentRequired, Recommended: $currentRecommended');
        logd('Error details: $e');
      } else {
        loge('❌ Error ensuring Remote Config values and no valid values available: $e');
      }
    }
  }

  /// Subscribe to Firebase Remote Config updates
  void _subscribeToRemoteConfigUpdates() {
    if (kIsWeb) {
      logd(
          '🌐 Skipping Remote Config listener setup on web platform (onConfigUpdated not supported)');
      return;
    }

    // Only set up listener if we're using the live Firebase implementation
    // When using mock/emulator mode, there's no Firebase listener to set up
    if (AppConfigBase.doUseBackendEmulator && !AppConfigBase.doOverrideUseLiveRemoteConfig) {
      logd('🔧 Skipping Remote Config listener setup - using mock implementation');
      return;
    }

    logd('🔌 Setting up Remote Config listener for version checking...');

    try {
      // Cancel any existing subscription first
      _remoteConfigSubscription?.cancel();
      _remoteConfigSubscription = null;

      // Skip listener setup when using mock implementation (emulator mode)
      if (AppConfigBase.doUseBackendEmulator && !AppConfigBase.doOverrideUseLiveRemoteConfig) {
        logd('🚫 Skipping Remote Config listener setup - using mock implementation');
        return;
      }

      // Verify Remote Config instance is available
      // Note: This still uses Firebase directly for listener setup, but only when needed
      final instance = FirebaseRemoteConfig.instance;
      logd('📡 Remote Config instance for listener: ${instance.hashCode}');

      // Test connectivity by checking current values using AppConfigBase (proper DI)
      final currentValue = AppConfigBase.minimumAppVersionRecommendedApple;
      logd('📱 Current Remote Config value (pre-listener) via AppConfigBase: $currentValue');

      _remoteConfigSubscription = instance.onConfigUpdated.listen(
        (RemoteConfigUpdate update) async {
          logd('🔄 Remote config updated from listener! Updated keys: ${update.updatedKeys}');

          // Check if any version-related keys were updated
          final versionKeys = [
            'minimumAppVersionRequiredApple',
            'minimumAppVersionRequiredGoogle',
            'minimumAppVersionRequiredWeb',
            'minimumAppVersionRecommendedApple',
            'minimumAppVersionRecommendedGoogle',
            'minimumAppVersionRecommendedWeb'
          ];

          final updatedVersionKeys =
              update.updatedKeys.where((key) => versionKeys.contains(key)).toList();

          if (updatedVersionKeys.isNotEmpty) {
            logd('📱 Version-related keys updated: $updatedVersionKeys');

            try {
              // Only activate if using real Firebase (not mock)
              if (!AppConfigBase.doUseBackendEmulator ||
                  AppConfigBase.doOverrideUseLiveRemoteConfig) {
                await FirebaseRemoteConfig.instance.activate();
                logd('✅ Remote config values activated after listener update');
              } else {
                logd('✅ Using mock Remote Config - no activation needed');
              }

              // Log values after activation using AppConfigBase (proper DI)
              final newValue = AppConfigBase.minimumAppVersionRecommendedApple;
              logd('📱 New Remote Config value (post-activation) via AppConfigBase: $newValue');

              // Perform version check with updated values
              logd('🔍 Checking for version updates due to Remote Config change');
              await checkVersionUpdate();
            } catch (e) {
              loge('❌ Error activating Remote Config after listener update: $e');
            }
          } else {
            logd('ℹ️ Updated keys do not include version keys: ${update.updatedKeys}');
            logd('⏭️ Skipping version check since no version-related keys were updated');

            // Still activate to ensure other systems get the updates
            try {
              if (!AppConfigBase.doUseBackendEmulator ||
                  AppConfigBase.doOverrideUseLiveRemoteConfig) {
                await FirebaseRemoteConfig.instance.activate();
              }
            } catch (e) {
              loge('❌ Error activating Remote Config for non-version update: $e');
            }
          }
        },
        onError: (error) {
          loge('❌ Error in Remote Config listener: $error');
          // Attempt to re-establish the listener after a delay
          _attemptListenerRecovery();
        },
        onDone: () {
          logd('🔌 Remote Config listener stream closed');
          // Attempt to re-establish the listener
          _attemptListenerRecovery();
        },
        cancelOnError: false, // Keep listening even if individual updates fail
      );

      logd('✅ Remote Config listener successfully established');

      // Verify the listener is working by checking the subscription
      if (_remoteConfigSubscription != null) {
        logd('🎯 Listener subscription confirmed: ${_remoteConfigSubscription.hashCode}');
        logd('🔊 Listener is paused: ${_remoteConfigSubscription!.isPaused}');
      } else {
        loge('❌ Failed to establish listener subscription');
      }

      // Set up a periodic health check for the listener
      _scheduleListenerHealthCheck();
    } catch (e) {
      loge('❌ Failed to set up Remote Config listener: $e');
      // Attempt recovery
      _attemptListenerRecovery();
    }
  }

  /// Schedule periodic health checks for the Remote Config listener
  void _scheduleListenerHealthCheck() {
    Timer.periodic(const Duration(minutes: 5), (timer) {
      if (!_isInitialized) {
        timer.cancel();
        return;
      }

      final isActive = _remoteConfigSubscription != null && !_remoteConfigSubscription!.isPaused;
      if (isActive) {
        logd('💚 Remote Config listener health check: HEALTHY');
      } else {
        logw('⚠️ Remote Config listener health check: UNHEALTHY - attempting recovery');
        _attemptListenerRecovery();
      }
    });
  }

  /// Attempt to recover from listener failures
  void _attemptListenerRecovery() {
    logd('🔄 Attempting Remote Config listener recovery...');

    // Cancel existing subscription
    _remoteConfigSubscription?.cancel();
    _remoteConfigSubscription = null;

    // Retry after a delay with exponential backoff
    const initialDelay = Duration(seconds: 5);
    const maxDelay = Duration(minutes: 2);

    Timer(initialDelay, () {
      if (_isInitialized) {
        logd('🔄 Retrying Remote Config listener setup...');

        try {
          _subscribeToRemoteConfigUpdates();
        } catch (e) {
          loge('❌ Listener recovery failed: $e');

          // Schedule another retry with longer delay
          Timer(maxDelay, () {
            if (_isInitialized) {
              logd('🔄 Final listener recovery attempt...');
              try {
                _subscribeToRemoteConfigUpdates();
              } catch (e) {
                loge('❌ Final listener recovery failed: $e');
              }
            }
          });
        }
      }
    });
  }

  /// Check if an app update is available
  Future<VersionUpdateInfo> checkVersionUpdate() async {
    try {
      logd('🔍 Starting version update check...');

      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final requiredVersion = _getRequiredVersion();
      final recommendedVersion = _getRecommendedVersion();

      logd('=== Version Check Details ===');
      logd('📱 Current app version: $currentVersion');
      logd('🔒 Required version: $requiredVersion');
      logd('💡 Recommended version: $recommendedVersion');
      logd(
          '🖥️  Platform: ${kIsWeb ? 'Web' : Platform.isIOS ? 'iOS' : Platform.isAndroid ? 'Android' : 'Unknown'}');

      VersionUpdateType updateType = VersionUpdateType.none;

      // Check if current version meets required minimum
      final isRequiredVersionValid = await appIsVersionValid(requiredVersion);
      logd('✅ Is required version valid: $isRequiredVersionValid');

      if (!isRequiredVersionValid) {
        updateType = VersionUpdateType.required;
        logd('🚨 Required version update needed - app is below minimum required version');
      } else {
        // Check if current version meets recommended minimum
        final isRecommendedVersionValid = await appIsVersionValid(recommendedVersion);
        logd('💭 Is recommended version valid: $isRecommendedVersionValid');

        if (!isRecommendedVersionValid) {
          updateType = VersionUpdateType.recommended;
          logd('📢 Recommended version update available - newer version recommended');
        } else {
          logd('✨ No update needed - app is up to date');
        }
      }

      final updateInfo = VersionUpdateInfo(
        updateType: updateType,
        currentVersion: currentVersion,
        requiredVersion: requiredVersion,
        recommendedVersion: recommendedVersion,
        appStoreUrl: AppConfigBase.appStoreUrl,
      );

      logd('📤 Emitting version update info: ${updateInfo.updateType}');

      // Emit the update info
      _updateStreamController.add(updateInfo);

      logd('🔍 Version update check completed');
      return updateInfo;
    } catch (e) {
      loge('❌ Error checking version update: $e');
      return const VersionUpdateInfo(
        updateType: VersionUpdateType.none,
        currentVersion: '',
        requiredVersion: '',
        recommendedVersion: '',
        appStoreUrl: '',
      );
    }
  }

  /// Get the required version for the current platform
  String _getRequiredVersion() {
    String version;
    if (kIsWeb) {
      version = AppConfigBase.minimumAppVersionRequiredWeb;
      logd('Required version from Remote Config (Web): $version');
    } else if (Platform.isIOS) {
      version = AppConfigBase.minimumAppVersionRequiredApple;
      logd('Required version from Remote Config (iOS): $version');
    } else if (Platform.isAndroid) {
      version = AppConfigBase.minimumAppVersionRequiredGoogle;
      logd('Required version from Remote Config (Android): $version');
    } else {
      version = '0.0.0';
      logd('Required version defaulted for unknown platform: $version');
    }

    // Also log the raw Remote Config value for debugging
    try {
      if (!kIsWeb && Platform.isIOS) {
        final rawValue = g<RemoteConfigRepoInt>().getString('minimumAppVersionRequiredApple');
        logd('Raw Remote Config value for minimumAppVersionRequiredApple: $rawValue');
      }
    } catch (e) {
      logd('Could not get raw Remote Config value: $e');
    }

    return version;
  }

  /// Get the recommended version for the current platform
  String _getRecommendedVersion() {
    String version;
    if (kIsWeb) {
      version = AppConfigBase.minimumAppVersionRecommendedWeb;
      logd('Recommended version from Remote Config (Web): $version');
    } else if (Platform.isIOS) {
      version = AppConfigBase.minimumAppVersionRecommendedApple;
      logd('Recommended version from Remote Config (iOS): $version');
    } else if (Platform.isAndroid) {
      version = AppConfigBase.minimumAppVersionRecommendedGoogle;
      logd('Recommended version from Remote Config (Android): $version');
    } else {
      version = '0.0.0';
      logd('Recommended version defaulted for unknown platform: $version');
    }

    // Also log the raw Remote Config value for debugging
    try {
      if (!kIsWeb && Platform.isIOS) {
        final rawValue = g<RemoteConfigRepoInt>().getString('minimumAppVersionRecommendedApple');
        logd('Raw Remote Config value for minimumAppVersionRecommendedApple: $rawValue');
      }
    } catch (e) {
      logd('Could not get raw Remote Config value: $e');
    }

    return version;
  }

  /// Force a version check (useful for app resume events)
  /// This uses cached values and listener updates to avoid hitting Firebase fetch limits
  Future<void> forceVersionCheck() async {
    logd('🔄 Force checking version update (using cached values)');

    // Don't fetch from server on app resume to avoid hitting 5 fetches/hour limit
    // The real-time listener will handle updates when they're published
    // and cached values are sufficient for version checking

    logd('ℹ️ Using cached Remote Config values for version check');
    logd('💡 Real-time updates will be handled by the onConfigUpdated listener');

    await checkVersionUpdate();
  }

  /// Force a version check with fresh Remote Config fetch (debug use only)
  /// This should only be used for debugging as it counts toward Firebase's 5 fetches/hour limit
  Future<void> forceVersionCheckWithFetch() async {
    logd('🔄 Force checking version update WITH Remote Config fetch (debug only)');

    // Try to fetch latest remote config if possible
    try {
      // Updated condition to allow web platform force fetch
      if (!AppConfigBase.doUseBackendEmulator || AppConfigBase.doOverrideUseLiveRemoteConfig) {
        logd(
            '⚠️ Attempting to fetch latest Remote Config for force check (counts toward 5/hour limit)...');

        // Web platform can fetch, but with additional logging
        if (kIsWeb) {
          logd('🌐 Force fetching on web platform...');
        }

        await FirebaseRemoteConfig.instance.fetchAndActivate();
        logd('✅ Remote Config refreshed for force check');
      } else if (AppConfigBase.doUseBackendEmulator &&
          !AppConfigBase.doOverrideUseLiveRemoteConfig) {
        logd('ℹ️ Using mock Remote Config - no fetch needed');
      }
    } catch (e) {
      logd('⚠️ Could not fetch remote config during force check (using cached values): $e');
      // Continue with cached values - this is not a critical error
    }

    await checkVersionUpdate();
  }

  /// Dispose of the service
  void dispose() {
    logd('Disposing AppVersionUpdateService');
    _remoteConfigSubscription?.cancel();
    _updateStreamController.close();
    _isInitialized = false;
  }

  /// Check if the Remote Config listener is active and working
  bool isListenerActive() {
    final isActive = _remoteConfigSubscription != null && !_remoteConfigSubscription!.isPaused;
    logd('🔍 Remote Config listener status: ${isActive ? "ACTIVE" : "INACTIVE"}');
    if (_remoteConfigSubscription != null) {
      logd(
          '📡 Subscription details: ${_remoteConfigSubscription.hashCode}, isPaused: ${_remoteConfigSubscription!.isPaused}');
    } else {
      logd('❌ No subscription exists');
    }
    return isActive;
  }

  /// Get detailed listener status for debugging
  Map<String, dynamic> getListenerStatus() {
    return {
      'isInitialized': _isInitialized,
      'hasSubscription': _remoteConfigSubscription != null,
      'isPaused': _remoteConfigSubscription?.isPaused ?? false,
      'subscriptionHashCode': _remoteConfigSubscription?.hashCode,
      'isListenerActive': isListenerActive(),
    };
  }

  /// Test the Remote Config listener by forcing a manual value check
  Future<void> testListener() async {
    logd('🧪 Testing Remote Config listener...');

    try {
      if (_remoteConfigSubscription == null) {
        loge('❌ No listener subscription exists');
        return;
      }

      // Check current subscription status
      final isActive = !_remoteConfigSubscription!.isPaused;
      logd('📡 Listener subscription active: $isActive');

      // Test if we can read current values
      final currentValue = AppConfigBase.minimumAppVersionRecommendedApple;
      logd('📱 Current test value via AppConfigBase: $currentValue');

      // Try to trigger a manual fetch to test listener responsiveness
      try {
        if (!AppConfigBase.doUseBackendEmulator || AppConfigBase.doOverrideUseLiveRemoteConfig) {
          final fetchResult = await FirebaseRemoteConfig.instance.fetchAndActivate();
          logd('🔄 Manual fetch result: $fetchResult');
        } else {
          logd('🔄 Using mock Remote Config - no fetch needed');
        }
      } catch (e) {
        logd('⚠️ Manual fetch error (expected if throttled): $e');
      }

      logd('✅ Listener test completed');
    } catch (e) {
      loge('❌ Listener test failed: $e');
    }
  }
}
