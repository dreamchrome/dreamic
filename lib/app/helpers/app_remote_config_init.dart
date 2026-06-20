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
// 7. ✅ Real-time updates via onConfigUpdated on ALL platforms (iOS, Android, Web)
//
// This means your app will work perfectly even if:
// - Firebase Remote Config console is not set up
// - Firebase project doesn't have Remote Config enabled
// - Network issues prevent fetching from Firebase
// - Rate limits are hit during development
//
// Firebase values will be used automatically when they become available.
// Real-time updates work seamlessly across all platforms (firebase_remote_config 6.1.0+).

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
  // Build + validate the merged defaults ONCE, before any branch or GetIt
  // registration. Validation runs identically on every path (live, mock,
  // emulator), so a bad consumer default fails fast and identically
  // everywhere — surfacing in local development instead of first crashing a
  // live Firebase deploy. Throws an ArgumentError on any non-bool/num/String
  // value (see buildValidatedRemoteConfigDefaults).
  final mergedDefaults = buildValidatedRemoteConfigDefaults(additionalDefaultConfigs);

  // If Firebase is not initialized, always use mock implementation
  if (!AppConfigBase.isFirebaseInitialized) {
    logd('Firebase not initialized - using mock Remote Config');
    await _initFakeRemoteConfig(mergedDefaults);
    return;
  }

  // Use fake Remote Config when using backend emulator (unless overridden)
  if (AppConfigBase.doUseBackendEmulator && !AppConfigBase.doOverrideUseLiveRemoteConfig) {
    await _initFakeRemoteConfig(mergedDefaults);
  } else {
    await _initLiveRemoteConfig(mergedDefaults);
  }
}

/// Merges DreamIC's [AppConfigBase.defaultRemoteConfig] with the
/// consumer-supplied [additionalDefaultConfigs] and validates that every
/// value in the merged map is a `bool`, `num`, or `String` — the only types
/// Firebase Remote Config `setDefaults` accepts.
///
/// Throws an [ArgumentError] (matching Firebase's own `setDefaults` guard,
/// which throws `ArgumentError` on `null`) naming each offending
/// `'key' = RuntimeType` if any value is unsupported. This guard runs on
/// every init path (live, mock, emulator) so a bad consumer default surfaces
/// in local development rather than first crashing app startup on the live
/// Remote Config path.
///
/// Exposed via `@visibleForTesting` (mirroring the `@visibleForTesting`
/// setters in [AppConfigBase]) so validator tests can call it directly
/// without a Firebase-init/GetIt harness.
@visibleForTesting
Map<String, dynamic> buildValidatedRemoteConfigDefaults(
  Map<String, dynamic>? additionalDefaultConfigs,
) {
  final merged = <String, dynamic>{
    ...AppConfigBase.defaultRemoteConfig,
    ...?additionalDefaultConfigs,
  };

  final offenders = <String>[];
  merged.forEach((key, value) {
    if (value is! bool && value is! num && value is! String) {
      offenders.add("'$key' = ${value.runtimeType}");
    }
  });

  if (offenders.isNotEmpty) {
    throw ArgumentError(
      'Invalid Remote Config default value(s): ${offenders.join(', ')}. '
      'Firebase Remote Config defaults must be bool, num, or String. '
      'An unsupported value would otherwise crash app startup on the live '
      'Remote Config path (FirebaseRemoteConfig.setDefaults rejects it).',
    );
  }

  return merged;
}

Future<void> _initLiveRemoteConfig(Map<String, dynamic> allDefaults) async {
  // Remote config — `isRegistered`-guard the registration so a gate-retry
  // re-run does not throw "Object already registered" (Issue 39, live site).
  // The setDefaults/setConfigSettings/fetchAndActivate below are all
  // overwrite/refetch idempotent and safe to re-run.
  if (!GetIt.I.isRegistered<RemoteConfigRepoInt>()) {
    GetIt.I.registerLazySingleton<RemoteConfigRepoInt>(
      () => RemoteConfigRepoLiveImpl(),
    );
  }

  final fetchInterval = kDebugMode
      ? const Duration(seconds: 10) // 10 seconds in debug mode
      : const Duration(hours: 1); // 1 hour in release mode

  logv('🔧 Configuring Remote Config - Debug mode: $kDebugMode, Fetch interval: $fetchInterval');

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

Future<void> _initFakeRemoteConfig(Map<String, dynamic> allDefaults) async {
  // Remote config — store the already-merged, validated defaults.
  // `isRegistered`-guard the registration so a dev/emulator gate-retry re-run
  // does not throw "already registered" (Issue 39, fake/mock site — the path
  // taken when Firebase is not initialized OR the backend emulator is in use).
  if (!GetIt.I.isRegistered<RemoteConfigRepoInt>()) {
    GetIt.I.registerLazySingleton<RemoteConfigRepoInt>(
      () => RemoteConfigRepoMockImpl(allDefaults),
    );
  }
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
    logv('💳 Stripe Key: "${stripeKey.isNotEmpty ? '${stripeKey.substring(0, 20)}...' : 'EMPTY'}"');
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

    logd('✅ Remote Config test completed');
  } catch (e) {
    loge('❌ Error during Remote Config test: $e');
  }
}
