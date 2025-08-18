//
// Remote Config Initialization - Resilient Implementation
//
// This implementation is designed to work reliably regardless of whether
// Firebase Remote Config parameters are set up in the Firebase Console.
//
// Key Features:
// 1. ✅ Always sets default values first (critical for app functionality)
// 2. ✅ Makes Firebase fetch completely optional (won't break if it fails)
// 3. ✅ Graceful error handling for missing Firebase parameters
// 4. ✅ Uses Firebase values only when they exist and are successfully fetched
// 5. ✅ Comprehensive logging to identify value sources and issues
// 6. ✅ Defensive programming in the repository layer
//
// This means your app will work perfectly even if:
// - Firebase Remote Config console is not set up
// - Firebase project doesn't have Remote Config enabled
// - Network issues prevent fetching from Firebase
// - Rate limits are hit during development
//
// Firebase values will be used automatically when they become available.

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:dreamic/app/app_config_base.dart';
import 'package:dreamic/data/repos/remote_config_repo_mockimpl.dart';
import 'package:dreamic/utils/logger.dart';
import 'package:dreamic/data/repos/remote_config_repo_int.dart';
import 'package:dreamic/data/repos/remote_config_repo_liveimple.dart';
import 'package:dreamic/app/helpers/web_remote_config_refresh_service.dart';
import 'package:get_it/get_it.dart';

Future<void> appInitRemoteConfig({
  Map<String, dynamic>? additionalDefaultConfigs,
}) async {
  // Use fake Remote Config when using backend emulator (unless overridden)
  if (AppConfigBase.doUseBackendEmulator && !AppConfigBase.doOverrideUseLiveRemoteConfig) {
    await _initFakeRemoteConfig(
      additionalDefaultConfigs: additionalDefaultConfigs,
    );
  } else {
    await _initLiveRemoteConfig(
      additionalDefaultConfigs: additionalDefaultConfigs,
    );
  }
}

/// Force a fetch on web platforms for initial startup
/// Web platforms need this explicit fetch since real-time listeners don't work
Future<void> webForceInitialFetch() async {
  if (!kIsWeb) {
    return;
  }

  logv('🌐 Web platform: Forcing initial Remote Config fetch...');

  try {
    // Set minimal fetch interval for immediate fetch
    await FirebaseRemoteConfig.instance.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: Duration.zero,
      ),
    );

    // Force fetch and activate
    final result = await FirebaseRemoteConfig.instance.fetchAndActivate();
    logv('🌐 Web initial fetch result: $result');

    // Check value source
    final testValue = FirebaseRemoteConfig.instance.getValue('minimumAppVersionRecommendedApple');
    logv('🌐 Web fetch value source: ${testValue.source}');
    logv('🌐 Web fetch value: "${testValue.asString()}"');

    // Reset fetch interval
    await FirebaseRemoteConfig.instance.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: kDebugMode ? const Duration(seconds: 10) : const Duration(hours: 1),
      ),
    );

    if (testValue.source == ValueSource.valueRemote) {
      logd('✅ Web platform successfully fetched Remote Config values from server');
    } else {
      logv(
          '⚠️ Web platform using default values - Remote Config may not be set up in Firebase Console');
    }
  } catch (e) {
    logd('⚠️ Web platform initial fetch failed: $e');
    logv('ℹ️ Continuing with default values');
  }
}

Future<void> _initLiveRemoteConfig({
  Map<String, dynamic>? additionalDefaultConfigs,
}) async {
  // Remote config
  GetIt.I.registerLazySingleton<RemoteConfigRepoInt>(
    () => RemoteConfigRepoLiveImpl(),
  );

  final fetchInterval = kDebugMode
      ? const Duration(seconds: 10) // 10 seconds in debug mode
      : const Duration(hours: 1); // 1 hour in release mode

  logv('🔧 Configuring Remote Config - Debug mode: $kDebugMode, Fetch interval: $fetchInterval');

  // Always set defaults first - this ensures we always have usable values
  final allDefaults = {
    ...AppConfigBase.defaultRemoteConfig,
    ...?additionalDefaultConfigs,
  };

  logv('📋 Setting Remote Config defaults for ${allDefaults.length} parameters');

  try {
    await FirebaseRemoteConfig.instance.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: fetchInterval,
      ),
    );

    await FirebaseRemoteConfig.instance.setDefaults(allDefaults);
    logd('✅ Remote Config defaults set successfully');

    // Verify defaults are accessible
    final testDefault =
        FirebaseRemoteConfig.instance.getString('minimumAppVersionRecommendedApple');
    logv('📱 Default value verification - minimumAppVersionRecommendedApple: $testDefault');
  } catch (e) {
    loge('❌ Failed to set Remote Config defaults: $e');
    loge('⚠️ This is a critical error - app may not function properly');
    rethrow; // This is a critical failure
  }

  // Now try to fetch from Firebase - but this is optional
  // If it fails, we'll just continue with defaults
  await _attemptFirebaseFetch();

  // For web platforms, force an additional fetch since real-time listeners don't work
  if (kIsWeb) {
    await webForceInitialFetch();

    // Initialize the web refresh service for periodic updates
    await WebRemoteConfigRefreshService.instance.initialize();
  }

  // Verify Remote Config is operational
  await _verifyRemoteConfigInitialization();
}

/// Attempts to fetch Remote Config values from Firebase
/// This is completely optional - if it fails, the app continues with defaults
Future<void> _attemptFirebaseFetch() async {
  try {
    logv('🔄 Attempting optional fetch from Firebase Remote Config...');

    // Log Firebase project info for debugging
    final app = FirebaseRemoteConfig.instance.app;
    logv('🔥 Firebase project: ${app.options.projectId}, app: ${app.name}');

    // Check last fetch time for debugging
    final lastFetchTime = FirebaseRemoteConfig.instance.lastFetchTime;
    final lastFetchStatus = FirebaseRemoteConfig.instance.lastFetchStatus;
    logv('📅 Last fetch time: $lastFetchTime');
    logv('📊 Last fetch status: $lastFetchStatus');

    // Log values before fetch
    final beforeValue =
        FirebaseRemoteConfig.instance.getString('minimumAppVersionRecommendedApple');
    logv('📱 Value BEFORE fetch - minimumAppVersionRecommendedApple: $beforeValue');

    // Check platform-specific behavior
    if (kIsWeb) {
      logv('🌐 Running on web platform - attempting fetch (should work on web)');
    }

    // Try to fetch from Firebase
    final fetchResult = await FirebaseRemoteConfig.instance.fetchAndActivate();

    // Log values after fetch
    final afterValue = FirebaseRemoteConfig.instance.getString('minimumAppVersionRecommendedApple');
    logv('📱 Value AFTER fetch - minimumAppVersionRecommendedApple: $afterValue');

    // Check fetch status
    final newLastFetchTime = FirebaseRemoteConfig.instance.lastFetchTime;
    final newLastFetchStatus = FirebaseRemoteConfig.instance.lastFetchStatus;
    logv('📅 NEW fetch time: $newLastFetchTime');
    logv('📊 NEW fetch status: $newLastFetchStatus');

    if (fetchResult) {
      logd('✅ Firebase Remote Config fetch successful - using server values where available');

      // Log value sources for debugging
      final valueSource =
          FirebaseRemoteConfig.instance.getValue('minimumAppVersionRecommendedApple').source;
      logv('🔍 Value source after fetch: $valueSource');
    } else {
      logv('⚠️ Firebase Remote Config fetch returned false (cached values or throttled)');
    }
  } on FirebaseException catch (e) {
    if (e.code == 'throttled' || e.message?.contains('throttled') == true) {
      logv(
          '🚫 Firebase Remote Config fetch throttled (hit rate limit). Using defaults/cached values.');
    } else if (e.message?.contains('cannot parse response') == true) {
      logv('📝 Firebase Remote Config not set up in console - using default values');
      logv(
          'ℹ️ This is normal for new projects or when Remote Config parameters aren\'t configured');
      logv('🔧 To use Firebase values: Go to Firebase Console > Remote Config and add parameters');
    } else if (e.code == 'fetch-failed') {
      logv('🌐 Firebase Remote Config fetch failed (network/server issue) - using default values');
    } else {
      logd('⚠️ Firebase Remote Config fetch failed: ${e.code} - ${e.message}');
      logv('ℹ️ Continuing with default values');
    }
  } catch (e) {
    logd('⚠️ Unexpected error during Firebase Remote Config fetch: $e');
    logv('ℹ️ Continuing with default values');
  }
}

Future<void> _initFakeRemoteConfig({
  Map<String, dynamic>? additionalDefaultConfigs,
}) async {
  // Remote config
  GetIt.I.registerLazySingleton<RemoteConfigRepoInt>(
    () => RemoteConfigRepoMockImpl({
      ...AppConfigBase.defaultRemoteConfig,
      ...?additionalDefaultConfigs,
    }),
  );
}

/// Force refresh Remote Config values (useful for debugging)
/// This bypasses the minimumFetchInterval by using fetchAndActivate with force
Future<void> forceRefreshRemoteConfig() async {
  try {
    logd('🔥 Force refreshing Remote Config values...');

    // Log values before force refresh
    final beforeRecommended =
        FirebaseRemoteConfig.instance.getString('minimumAppVersionRecommendedApple');
    logv('📱 Value BEFORE force refresh - minimumAppVersionRecommendedApple: $beforeRecommended');

    // Set a very short fetch interval temporarily
    await FirebaseRemoteConfig.instance.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: Duration.zero, // Allow immediate fetch
      ),
    );

    // Force fetch and activate
    final result = await FirebaseRemoteConfig.instance.fetchAndActivate();
    logv('🔥 Force refresh result: $result');

    // Log values after force refresh
    final afterRecommended =
        FirebaseRemoteConfig.instance.getString('minimumAppVersionRecommendedApple');
    logv('📱 Value AFTER force refresh - minimumAppVersionRecommendedApple: $afterRecommended');

    // Reset the fetch interval back to normal
    await FirebaseRemoteConfig.instance.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: kDebugMode ? const Duration(seconds: 10) : const Duration(hours: 1),
      ),
    );

    if (beforeRecommended != afterRecommended) {
      logd('🎉 Remote Config values updated after force refresh!');
    } else {
      logv('ℹ️ Remote Config values unchanged after force refresh');
    }
  } on FirebaseException catch (e) {
    if (e.code == 'throttled' || e.message?.contains('throttled') == true) {
      logd('🚫 Force refresh throttled - you have hit Firebase\'s rate limit');
      logv('⏰ Wait before trying again, or restart the app to reset the counter');
    } else if (e.message?.contains('cannot parse response') == true) {
      logv('📝 Force refresh failed: Firebase Remote Config not set up in console');
      logv('ℹ️ This is normal - the app will continue with default values');
    } else {
      logd('⚠️ Firebase error during force refresh: ${e.code} - ${e.message}');
      logv('ℹ️ App continues with current values');
    }
  } catch (e) {
    logd('⚠️ Unexpected error during force refresh: $e');
    logv('ℹ️ App continues with current values');
  }
}

/// Verify that Remote Config is properly initialized and operational
Future<void> _verifyRemoteConfigInitialization() async {
  try {
    logv('🔍 Verifying Remote Config initialization...');

    // Check if we can read a known default value
    final testValue = FirebaseRemoteConfig.instance.getString('minimumAppVersionRecommendedApple');
    logv('📱 Test value read: $testValue');

    // Check fetch status
    final fetchStatus = FirebaseRemoteConfig.instance.lastFetchStatus;
    final fetchTime = FirebaseRemoteConfig.instance.lastFetchTime;
    logv('📊 Fetch status: $fetchStatus, Last fetch: $fetchTime');

    // Verify the instance is not null
    final instance = FirebaseRemoteConfig.instance;
    logv('✅ Remote Config instance verified: ${instance.hashCode}');

    logd('✅ Remote Config initialization verified successfully');
  } catch (e) {
    loge('❌ Remote Config verification failed: $e');
    rethrow;
  }
}

/// Test Remote Config functionality and log the results
/// This is useful for debugging Remote Config issues
Future<void> testRemoteConfigValues() async {
  try {
    logd('🧪 Testing Remote Config values...');

    // Test version parameters
    final requiredApple = FirebaseRemoteConfig.instance.getString('minimumAppVersionRequiredApple');
    final recommendedApple =
        FirebaseRemoteConfig.instance.getString('minimumAppVersionRecommendedApple');
    logv('📱 Version Required Apple: "$requiredApple"');
    logv('📱 Version Recommended Apple: "$recommendedApple"');

    // Test web-specific values
    if (kIsWeb) {
      final requiredWeb = FirebaseRemoteConfig.instance.getString('minimumAppVersionRequiredWeb');
      final recommendedWeb =
          FirebaseRemoteConfig.instance.getString('minimumAppVersionRecommendedWeb');
      logv('🌐 Version Required Web: "$requiredWeb"');
      logv('🌐 Version Recommended Web: "$recommendedWeb"');

      // Check value sources on web
      final webRequiredSource =
          FirebaseRemoteConfig.instance.getValue('minimumAppVersionRequiredWeb').source;
      final webRecommendedSource =
          FirebaseRemoteConfig.instance.getValue('minimumAppVersionRecommendedWeb').source;
      logv('🔍 Web Required source: $webRequiredSource');
      logv('🔍 Web Recommended source: $webRecommendedSource');
    }

    // Test feature flags
    final calsyncGoogle = FirebaseRemoteConfig.instance.getBool('calsyncEnableGoogle');
    final communityTutorial = FirebaseRemoteConfig.instance.getBool('communityTutorialEnabled');
    logv('🔧 Calsync Google Enabled: $calsyncGoogle');
    logv('🔧 Community Tutorial Enabled: $communityTutorial');

    // Test string parameters
    final stripeKey = FirebaseRemoteConfig.instance.getString('stripePublishableKey');
    final vimeoId = FirebaseRemoteConfig.instance.getString('subscribeVideoVimeoId');
    logv('💳 Stripe Key: "${stripeKey.isNotEmpty ? stripeKey.substring(0, 20) + '...' : 'EMPTY'}"');
    logv('🎥 Vimeo ID: "$vimeoId"');

    // Test numeric parameters
    final maxSelections = FirebaseRemoteConfig.instance.getInt('psmChoiceSelectionsMax');
    final refreshInterval =
        FirebaseRemoteConfig.instance.getInt('userPrivateRefreshIntervalSeconds');
    logv('🔢 PSM Max Selections: $maxSelections');
    logv('🔢 Refresh Interval: $refreshInterval');

    // Check fetch status
    final fetchStatus = FirebaseRemoteConfig.instance.lastFetchStatus;
    final fetchTime = FirebaseRemoteConfig.instance.lastFetchTime;
    logv('📊 Last fetch status: $fetchStatus');
    logv('📅 Last fetch time: $fetchTime');

    // Check value source (will help identify if values come from defaults, cache, or remote)
    final valueSource =
        FirebaseRemoteConfig.instance.getValue('minimumAppVersionRecommendedApple').source;
    logd('🔍 Value source for minimumAppVersionRecommendedApple: $valueSource');

    // Web-specific status
    if (kIsWeb) {
      final refreshServiceStatus = WebRemoteConfigRefreshService.instance.getStatus();
      logv('🌐 Web refresh service status: $refreshServiceStatus');
    }

    logd('✅ Remote Config test completed');
  } catch (e) {
    loge('❌ Error during Remote Config test: $e');
  }
}
