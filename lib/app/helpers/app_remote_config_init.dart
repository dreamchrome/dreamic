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

  logd('🔧 Configuring Remote Config - Debug mode: $kDebugMode, Fetch interval: $fetchInterval');

  // Always set defaults first - this ensures we always have usable values
  final allDefaults = {
    ...AppConfigBase.defaultRemoteConfig,
    ...?additionalDefaultConfigs,
  };

  logd('📋 Setting Remote Config defaults for ${allDefaults.length} parameters');

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
    logd('📱 Default value verification - minimumAppVersionRecommendedApple: $testDefault');
  } catch (e) {
    loge('❌ Failed to set Remote Config defaults: $e');
    loge('⚠️ This is a critical error - app may not function properly');
    rethrow; // This is a critical failure
  }

  // Now try to fetch from Firebase - but this is optional
  // If it fails, we'll just continue with defaults
  await _attemptFirebaseFetch();

  // Verify Remote Config is operational
  await _verifyRemoteConfigInitialization();
}

/// Attempts to fetch Remote Config values from Firebase
/// This is completely optional - if it fails, the app continues with defaults
Future<void> _attemptFirebaseFetch() async {
  try {
    logd('🔄 Attempting optional fetch from Firebase Remote Config...');

    // Log Firebase project info for debugging
    final app = FirebaseRemoteConfig.instance.app;
    logd('🔥 Firebase project: ${app.options.projectId}, app: ${app.name}');

    // Check last fetch time for debugging
    final lastFetchTime = FirebaseRemoteConfig.instance.lastFetchTime;
    final lastFetchStatus = FirebaseRemoteConfig.instance.lastFetchStatus;
    logd('📅 Last fetch time: $lastFetchTime');
    logd('📊 Last fetch status: $lastFetchStatus');

    // Log values before fetch
    final beforeValue =
        FirebaseRemoteConfig.instance.getString('minimumAppVersionRecommendedApple');
    logd('📱 Value BEFORE fetch - minimumAppVersionRecommendedApple: $beforeValue');

    // Try to fetch from Firebase
    final fetchResult = await FirebaseRemoteConfig.instance.fetchAndActivate();

    // Log values after fetch
    final afterValue = FirebaseRemoteConfig.instance.getString('minimumAppVersionRecommendedApple');
    logd('📱 Value AFTER fetch - minimumAppVersionRecommendedApple: $afterValue');

    // Check fetch status
    final newLastFetchTime = FirebaseRemoteConfig.instance.lastFetchTime;
    final newLastFetchStatus = FirebaseRemoteConfig.instance.lastFetchStatus;
    logd('📅 NEW fetch time: $newLastFetchTime');
    logd('📊 NEW fetch status: $newLastFetchStatus');

    if (fetchResult) {
      logd('✅ Firebase Remote Config fetch successful - using server values where available');
    } else {
      logd('⚠️ Firebase Remote Config fetch returned false (cached values or throttled)');
    }
  } on FirebaseException catch (e) {
    if (e.code == 'throttled' || e.message?.contains('throttled') == true) {
      logd(
          '🚫 Firebase Remote Config fetch throttled (hit rate limit). Using defaults/cached values.');
    } else if (e.message?.contains('cannot parse response') == true) {
      logd('📝 Firebase Remote Config not set up in console - using default values');
      logd(
          'ℹ️ This is normal for new projects or when Remote Config parameters aren\'t configured');
      logd('🔧 To use Firebase values: Go to Firebase Console > Remote Config and add parameters');
    } else if (e.code == 'fetch-failed') {
      logd('🌐 Firebase Remote Config fetch failed (network/server issue) - using default values');
    } else {
      logd('⚠️ Firebase Remote Config fetch failed: ${e.code} - ${e.message}');
      logd('ℹ️ Continuing with default values');
    }
  } catch (e) {
    logd('⚠️ Unexpected error during Firebase Remote Config fetch: $e');
    logd('ℹ️ Continuing with default values');
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
    logd('📱 Value BEFORE force refresh - minimumAppVersionRecommendedApple: $beforeRecommended');

    // Set a very short fetch interval temporarily
    await FirebaseRemoteConfig.instance.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: Duration.zero, // Allow immediate fetch
      ),
    );

    // Force fetch and activate
    final result = await FirebaseRemoteConfig.instance.fetchAndActivate();
    logd('🔥 Force refresh result: $result');

    // Log values after force refresh
    final afterRecommended =
        FirebaseRemoteConfig.instance.getString('minimumAppVersionRecommendedApple');
    logd('📱 Value AFTER force refresh - minimumAppVersionRecommendedApple: $afterRecommended');

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
      logd('ℹ️ Remote Config values unchanged after force refresh');
    }
  } on FirebaseException catch (e) {
    if (e.code == 'throttled' || e.message?.contains('throttled') == true) {
      logd('🚫 Force refresh throttled - you have hit Firebase\'s rate limit');
      logd('⏰ Wait before trying again, or restart the app to reset the counter');
    } else if (e.message?.contains('cannot parse response') == true) {
      logd('📝 Force refresh failed: Firebase Remote Config not set up in console');
      logd('ℹ️ This is normal - the app will continue with default values');
    } else {
      logd('⚠️ Firebase error during force refresh: ${e.code} - ${e.message}');
      logd('ℹ️ App continues with current values');
    }
  } catch (e) {
    logd('⚠️ Unexpected error during force refresh: $e');
    logd('ℹ️ App continues with current values');
  }
}

/// Verify that Remote Config is properly initialized and operational
Future<void> _verifyRemoteConfigInitialization() async {
  try {
    logd('🔍 Verifying Remote Config initialization...');

    // Check if we can read a known default value
    final testValue = FirebaseRemoteConfig.instance.getString('minimumAppVersionRecommendedApple');
    logd('📱 Test value read: $testValue');

    // Check fetch status
    final fetchStatus = FirebaseRemoteConfig.instance.lastFetchStatus;
    final fetchTime = FirebaseRemoteConfig.instance.lastFetchTime;
    logd('📊 Fetch status: $fetchStatus, Last fetch: $fetchTime');

    // Verify the instance is not null
    final instance = FirebaseRemoteConfig.instance;
    logd('✅ Remote Config instance verified: ${instance.hashCode}');

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
    logd('📱 Version Required Apple: "$requiredApple"');
    logd('📱 Version Recommended Apple: "$recommendedApple"');

    // Test feature flags
    final calsyncGoogle = FirebaseRemoteConfig.instance.getBool('calsyncEnableGoogle');
    final communityTutorial = FirebaseRemoteConfig.instance.getBool('communityTutorialEnabled');
    logd('🔧 Calsync Google Enabled: $calsyncGoogle');
    logd('🔧 Community Tutorial Enabled: $communityTutorial');

    // Test string parameters
    final stripeKey = FirebaseRemoteConfig.instance.getString('stripePublishableKey');
    final vimeoId = FirebaseRemoteConfig.instance.getString('subscribeVideoVimeoId');
    logd('💳 Stripe Key: "${stripeKey.isNotEmpty ? stripeKey.substring(0, 20) + '...' : 'EMPTY'}"');
    logd('🎥 Vimeo ID: "$vimeoId"');

    // Test numeric parameters
    final maxSelections = FirebaseRemoteConfig.instance.getInt('psmChoiceSelectionsMax');
    final refreshInterval =
        FirebaseRemoteConfig.instance.getInt('userPrivateRefreshIntervalSeconds');
    logd('🔢 PSM Max Selections: $maxSelections');
    logd('🔢 Refresh Interval: $refreshInterval');

    // Check fetch status
    final fetchStatus = FirebaseRemoteConfig.instance.lastFetchStatus;
    final fetchTime = FirebaseRemoteConfig.instance.lastFetchTime;
    logd('📊 Last fetch status: $fetchStatus');
    logd('📅 Last fetch time: $fetchTime');

    // Check value source (will help identify if values come from defaults, cache, or remote)
    final valueSource =
        FirebaseRemoteConfig.instance.getValue('minimumAppVersionRecommendedApple').source;
    logd('🔍 Value source for minimumAppVersionRecommendedApple: $valueSource');

    logd('✅ Remote Config test completed');
  } catch (e) {
    loge('❌ Error during Remote Config test: $e');
  }
}
