import 'dart:async';
import 'dart:io';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:dreamic/app/app_config_base.dart';
import 'package:dreamic/app/helpers/app_version_check.dart';
import 'package:dreamic/data/repos/remote_config_repo_int.dart';
import 'package:dreamic/utils/get_it_utils.dart';
import 'package:dreamic/utils/logger.dart';

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
  bool _isRecoveryInProgress = false;

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
    logv('⏳ Waiting for Remote Config to be initialized...');

    const maxAttempts = 10;
    const delay = Duration(milliseconds: 500);

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        // Try to read a value to verify Remote Config is working through dependency injection
        final testValue = g<RemoteConfigRepoInt>().getString('minimumAppVersionRecommendedApple');

        logv('🔍 Attempt $attempt: Test value from DI: $testValue');

        // If we can read values, Remote Config is initialized
        if (testValue.isNotEmpty) {
          logv('✅ Remote Config verified as initialized on attempt $attempt');
          return;
        }

        if (attempt < maxAttempts) {
          logv('⏳ Remote Config not ready, waiting ${delay.inMilliseconds}ms before retry...');
          await Future.delayed(delay);
        }
      } catch (e) {
        logv('⚠️ Error checking Remote Config on attempt $attempt: $e');
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
      logv('Before - Required: $beforeRequired, Recommended: $beforeRecommended');

      // Note: We don't call fetchAndActivate here anymore because:
      // 1. When using mock Remote Config, there's nothing to fetch
      // 2. When using real Firebase, the fetch was already done during initialization
      // 3. AppConfigBase getters will return the correct values regardless

      // Get values after to verify they're available
      final afterRequired = AppConfigBase.minimumAppVersionRequiredApple;
      final afterRecommended = AppConfigBase.minimumAppVersionRecommendedApple;
      logv('After - Required: $afterRequired, Recommended: $afterRecommended');

      if (beforeRequired != afterRequired || beforeRecommended != afterRecommended) {
        logv('🔄 Remote Config values have different values after check');
      } else {
        logv('ℹ️ Remote Config values consistent');
      }
    } catch (e) {
      // Check if we have valid values
      final currentRequired = AppConfigBase.minimumAppVersionRequiredApple;
      final currentRecommended = AppConfigBase.minimumAppVersionRecommendedApple;

      if (currentRequired != '0.0.0' || currentRecommended != '0.0.0') {
        logv(
            '⚠️ Error ensuring Remote Config values, but valid values available - Required: $currentRequired, Recommended: $currentRecommended');
        logv('Error details: $e');
      } else {
        loge('❌ Error ensuring Remote Config values and no valid values available: $e');
      }
    }
  }

  /// Subscribe to Firebase Remote Config updates
  /// Note: As of firebase_remote_config 6.1.0, onConfigUpdated is now supported on web!
  void _subscribeToRemoteConfigUpdates() {
    // Only set up listener if we're using the live Firebase implementation
    // When using mock/emulator mode, there's no Firebase listener to set up
    if (AppConfigBase.doUseBackendEmulator && !AppConfigBase.doOverrideUseLiveRemoteConfig) {
      logv('🔧 Skipping Remote Config listener setup - using mock implementation');
      return;
    }

    final platform = kIsWeb
        ? 'Web'
        : Platform.isIOS
            ? 'iOS'
            : Platform.isAndroid
                ? 'Android'
                : 'Unknown';
    logv('🔌 Setting up Remote Config listener for version checking on $platform...');

    try {
      // Cancel any existing subscription first
      _remoteConfigSubscription?.cancel();
      _remoteConfigSubscription = null;

      // Verify Remote Config instance is available
      // Note: onConfigUpdated now works on all platforms including web (as of v6.1.0)
      final instance = FirebaseRemoteConfig.instance;
      logv('📡 Remote Config instance for listener: ${instance.hashCode}');

      // Test connectivity by checking current values using AppConfigBase (proper DI)
      final currentValue = AppConfigBase.minimumAppVersionRecommendedApple;
      logv('📱 Current Remote Config value (pre-listener) via AppConfigBase: $currentValue');

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
                logv('✅ Remote config values activated after listener update');
              } else {
                logv('✅ Using mock Remote Config - no activation needed');
              }

              // Log values after activation using AppConfigBase (proper DI)
              final newValue = AppConfigBase.minimumAppVersionRecommendedApple;
              logv('📱 New Remote Config value (post-activation) via AppConfigBase: $newValue');

              // Perform version check with updated values
              logd('🔍 Checking for version updates due to Remote Config change');
              await checkVersionUpdate();
            } catch (e) {
              loge('❌ Error activating Remote Config after listener update: $e');
            }
          } else {
            logv('ℹ️ Updated keys do not include version keys: ${update.updatedKeys}');
            logv('⏭️ Skipping version check since no version-related keys were updated');

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
          // Check if this is the known transient stream error on web platforms
          // This error commonly occurs when:
          // - The browser tab is inactive/backgrounded
          // - Network connectivity changes
          // - Long-running SSE connections are interrupted by the browser
          // It's not a fatal error - the SDK will automatically retry
          final errorStr = error.toString();
          final isTransientStreamError = kIsWeb &&
              (errorStr.contains('stream-error') ||
                  errorStr.contains('Unable to connect to the server') ||
                  errorStr.contains('HTTP status code: undefined'));

          if (isTransientStreamError) {
            // Log as warning since this is expected behavior on web
            logw('⚠️ Remote Config stream connection interrupted (expected on web): $error');
            logw('🔄 The SDK will automatically attempt to reconnect');
          } else {
            loge('❌ Error in Remote Config listener: $error');
          }

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

      logv('✅ Remote Config listener successfully established');

      // Verify the listener is working by checking the subscription
      if (_remoteConfigSubscription != null) {
        logv('🎯 Listener subscription confirmed: ${_remoteConfigSubscription.hashCode}');
      } else {
        loge('❌ Failed to establish listener subscription');
      }
    } catch (e) {
      loge('❌ Failed to set up Remote Config listener: $e');
      // Attempt recovery
      _attemptListenerRecovery();
    }
  }

  /// Attempt to recover from listener failures
  /// Uses a flag to prevent overlapping recovery attempts
  void _attemptListenerRecovery() {
    // Prevent multiple simultaneous recovery attempts
    if (_isRecoveryInProgress) {
      logv('🔄 Recovery already in progress, skipping duplicate attempt');
      return;
    }

    _isRecoveryInProgress = true;
    logv('🔄 Attempting Remote Config listener recovery...');

    // Cancel existing subscription
    _remoteConfigSubscription?.cancel();
    _remoteConfigSubscription = null;

    // Use a longer delay for web platform due to frequent transient errors
    final initialDelay = kIsWeb ? const Duration(seconds: 15) : const Duration(seconds: 5);
    final maxDelay = kIsWeb ? const Duration(minutes: 5) : const Duration(minutes: 2);

    Timer(initialDelay, () {
      if (_isInitialized) {
        logv('🔄 Retrying Remote Config listener setup...');

        try {
          _subscribeToRemoteConfigUpdates();
          _isRecoveryInProgress = false;
        } catch (e) {
          loge('❌ Listener recovery failed: $e');

          // Schedule another retry with longer delay
          Timer(maxDelay, () {
            if (_isInitialized) {
              logv('🔄 Final listener recovery attempt...');
              try {
                _subscribeToRemoteConfigUpdates();
              } catch (e) {
                loge('❌ Final listener recovery failed: $e');
              }
            }
            _isRecoveryInProgress = false;
          });
        }
      } else {
        _isRecoveryInProgress = false;
      }
    });
  }

  /// Check if an app update is available
  Future<VersionUpdateInfo> checkVersionUpdate() async {
    try {
      logv('🔍 Starting version update check...');

      final packageInfo = await AppConfigBase.getAppVersion();
      final currentVersion = packageInfo.version;

      final requiredVersion = _getRequiredVersion();
      final recommendedVersion = _getRecommendedVersion();

      logv('=== Version Check Details ===');
      logv('📱 Current app version: $currentVersion');
      logv('🔒 Required version: $requiredVersion');
      logv('💡 Recommended version: $recommendedVersion');
      logv(
          '🖥️  Platform: ${kIsWeb ? 'Web' : Platform.isIOS ? 'iOS' : Platform.isAndroid ? 'Android' : 'Unknown'}');

      VersionUpdateType updateType = VersionUpdateType.none;

      // Check if current version meets required minimum
      final isRequiredVersionValid = await appIsVersionValid(requiredVersion);
      logv('✅ Is required version valid: $isRequiredVersionValid');

      if (!isRequiredVersionValid) {
        updateType = VersionUpdateType.required;
        logd('🚨 Required version update needed - app is below minimum required version');
      } else {
        // Check if current version meets recommended minimum
        final isRecommendedVersionValid = await appIsVersionValid(recommendedVersion);
        logv('💭 Is recommended version valid: $isRecommendedVersionValid');

        if (!isRecommendedVersionValid) {
          updateType = VersionUpdateType.recommended;
          logd('📢 Recommended version update available - newer version recommended');
        } else {
          logv('✨ No update needed - app is up to date');
        }
      }

      final updateInfo = VersionUpdateInfo(
        updateType: updateType,
        currentVersion: currentVersion,
        requiredVersion: requiredVersion,
        recommendedVersion: recommendedVersion,
        appStoreUrl: AppConfigBase.appStoreUrl,
      );

      logv('📤 Emitting version update info: ${updateInfo.updateType}');

      // Emit the update info
      _updateStreamController.add(updateInfo);

      logv('🔍 Version update check completed');
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
      logv('Required version from Remote Config (Web): $version');
    } else if (Platform.isIOS) {
      version = AppConfigBase.minimumAppVersionRequiredApple;
      logv('Required version from Remote Config (iOS): $version');
    } else if (Platform.isAndroid) {
      version = AppConfigBase.minimumAppVersionRequiredGoogle;
      logv('Required version from Remote Config (Android): $version');
    } else {
      version = '0.0.0';
      logv('Required version defaulted for unknown platform: $version');
    }

    // Also log the raw Remote Config value for debugging
    try {
      if (!kIsWeb && Platform.isIOS) {
        final rawValue = g<RemoteConfigRepoInt>().getString('minimumAppVersionRequiredApple');
        logv('Raw Remote Config value for minimumAppVersionRequiredApple: $rawValue');
      }
    } catch (e) {
      logv('Could not get raw Remote Config value: $e');
    }

    return version;
  }

  /// Get the recommended version for the current platform
  String _getRecommendedVersion() {
    String version;
    if (kIsWeb) {
      version = AppConfigBase.minimumAppVersionRecommendedWeb;
      logv('Recommended version from Remote Config (Web): $version');
    } else if (Platform.isIOS) {
      version = AppConfigBase.minimumAppVersionRecommendedApple;
      logv('Recommended version from Remote Config (iOS): $version');
    } else if (Platform.isAndroid) {
      version = AppConfigBase.minimumAppVersionRecommendedGoogle;
      logv('Recommended version from Remote Config (Android): $version');
    } else {
      version = '0.0.0';
      logv('Recommended version defaulted for unknown platform: $version');
    }

    // Also log the raw Remote Config value for debugging
    try {
      if (!kIsWeb && Platform.isIOS) {
        final rawValue = g<RemoteConfigRepoInt>().getString('minimumAppVersionRecommendedApple');
        logv('Raw Remote Config value for minimumAppVersionRecommendedApple: $rawValue');
      }
    } catch (e) {
      logv('Could not get raw Remote Config value: $e');
    }

    return version;
  }

  /// Force a version check (useful for app resume events)
  /// This uses cached values and listener updates to avoid hitting Firebase fetch limits.
  /// Note: The onConfigUpdated listener (now supported on all platforms including web)
  /// will automatically handle real-time updates when they're published.
  Future<void> forceVersionCheck() async {
    logv('🔄 Force checking version update (using cached values)');

    // Don't fetch from server on app resume to avoid hitting 5 fetches/hour limit
    // The real-time listener will handle updates when they're published
    // and cached values are sufficient for version checking

    logv('ℹ️ Using cached Remote Config values for version check');
    logv('💡 Real-time updates will be handled by the onConfigUpdated listener (all platforms)');

    await checkVersionUpdate();
  }

  /// Force a version check with fresh Remote Config fetch (debug use only)
  /// This should only be used for debugging as it counts toward Firebase's 5 fetches/hour limit.
  /// Note: This is rarely needed now that onConfigUpdated works on all platforms including web.
  Future<void> forceVersionCheckWithFetch() async {
    logv('🔄 Force checking version update WITH Remote Config fetch (debug only)');

    // Try to fetch latest remote config if possible
    try {
      if (!AppConfigBase.doUseBackendEmulator || AppConfigBase.doOverrideUseLiveRemoteConfig) {
        logv(
            '⚠️ Attempting to fetch latest Remote Config for force check (counts toward 5/hour limit)...');

        await FirebaseRemoteConfig.instance.fetchAndActivate();
        logv('✅ Remote Config refreshed for force check');
      } else if (AppConfigBase.doUseBackendEmulator &&
          !AppConfigBase.doOverrideUseLiveRemoteConfig) {
        logv('ℹ️ Using mock Remote Config - no fetch needed');
      }
    } catch (e) {
      logv('⚠️ Could not fetch remote config during force check (using cached values): $e');
      // Continue with cached values - this is not a critical error
    }

    await checkVersionUpdate();
  }

  /// Dispose of the service
  void dispose() {
    logv('Disposing AppVersionUpdateService');
    _remoteConfigSubscription?.cancel();
    _updateStreamController.close();
    _isInitialized = false;
  }

  /// Check if the Remote Config listener is active and working
  bool isListenerActive() {
    final isActive = _remoteConfigSubscription != null && !_remoteConfigSubscription!.isPaused;
    logv('🔍 Remote Config listener status: ${isActive ? "ACTIVE" : "INACTIVE"}');
    if (_remoteConfigSubscription != null) {
      logv(
          '📡 Subscription details: ${_remoteConfigSubscription.hashCode}, isPaused: ${_remoteConfigSubscription!.isPaused}');
    } else {
      logv('❌ No subscription exists');
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
    logv('🧪 Testing Remote Config listener...');

    try {
      if (_remoteConfigSubscription == null) {
        loge('❌ No listener subscription exists');
        return;
      }

      // Check current subscription status
      final isActive = !_remoteConfigSubscription!.isPaused;
      logv('📡 Listener subscription active: $isActive');

      // Test if we can read current values
      final currentValue = AppConfigBase.minimumAppVersionRecommendedApple;
      logv('📱 Current test value via AppConfigBase: $currentValue');

      // Try to trigger a manual fetch to test listener responsiveness
      try {
        if (!AppConfigBase.doUseBackendEmulator || AppConfigBase.doOverrideUseLiveRemoteConfig) {
          final fetchResult = await FirebaseRemoteConfig.instance.fetchAndActivate();
          logv('🔄 Manual fetch result: $fetchResult');
        } else {
          logv('🔄 Using mock Remote Config - no fetch needed');
        }
      } catch (e) {
        logv('⚠️ Manual fetch error (expected if throttled): $e');
      }

      logv('✅ Listener test completed');
    } catch (e) {
      loge('❌ Listener test failed: $e');
    }
  }
}
