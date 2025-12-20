//
// Debug Remote Config for Web - Troubleshooting Utilities
//
// This file contains utilities to debug Remote Config issues specifically on web platforms
//

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:dreamic/app/app_config_base.dart';
import 'package:dreamic/utils/logger.dart';
import 'package:dreamic/data/repos/remote_config_repo_int.dart';
import 'package:get_it/get_it.dart';

/// Debug Remote Config specifically for web platform issues
Future<void> debugRemoteConfigWeb() async {
  if (!kIsWeb) {
    logd('❌ This debug function is only for web platform');
    return;
  }

  logd('🌐 === DEBUG REMOTE CONFIG FOR WEB ===');

  try {
    // 1. Check Firebase instance and project
    final instance = FirebaseRemoteConfig.instance;
    final app = instance.app;
    logd('🔥 Firebase project: ${app.options.projectId}');
    logd('🔥 Firebase app name: ${app.name}');
    logd('🔥 Remote Config instance: ${instance.hashCode}');

    // 2. Check fetch status
    final lastFetchTime = instance.lastFetchTime;
    final lastFetchStatus = instance.lastFetchStatus;
    logd('📅 Last fetch time: $lastFetchTime');
    logd('📊 Last fetch status: $lastFetchStatus');

    // 3. Check defaults are set
    final testDefault = instance.getString('minimumAppVersionRecommendedApple');
    logd('📱 Default value for minimumAppVersionRecommendedApple: "$testDefault"');

    // 4. Check all version-related values
    await _logAllVersionValues();

    // 5. Check value sources
    await _logValueSources();

    // 6. Test manual fetch (web-specific)
    await _testWebFetch();

    // 7. Check dependency injection
    await _testDependencyInjection();

    // 8. Check AppConfigBase values
    await _testAppConfigBaseValues();
  } catch (e) {
    loge('❌ Error during web debug: $e');
  }

  logd('🌐 === END DEBUG REMOTE CONFIG FOR WEB ===');
}

/// Log all version-related values directly from Firebase
Future<void> _logAllVersionValues() async {
  logd('📱 === ALL VERSION VALUES FROM FIREBASE ===');
  final instance = FirebaseRemoteConfig.instance;

  // Required versions
  final requiredApple = instance.getString('minimumAppVersionRequiredApple');
  final requiredGoogle = instance.getString('minimumAppVersionRequiredGoogle');
  final requiredWeb = instance.getString('minimumAppVersionRequiredWeb');

  // Recommended versions
  final recommendedApple = instance.getString('minimumAppVersionRecommendedApple');
  final recommendedGoogle = instance.getString('minimumAppVersionRecommendedGoogle');
  final recommendedWeb = instance.getString('minimumAppVersionRecommendedWeb');

  logd('📱 Required - Apple: "$requiredApple", Google: "$requiredGoogle", Web: "$requiredWeb"');
  logd(
      '📱 Recommended - Apple: "$recommendedApple", Google: "$recommendedGoogle", Web: "$recommendedWeb"');
}

/// Check the value sources (default, remote, or static)
Future<void> _logValueSources() async {
  logd('🔍 === VALUE SOURCES ===');
  final instance = FirebaseRemoteConfig.instance;

  final keys = [
    'minimumAppVersionRequiredApple',
    'minimumAppVersionRequiredGoogle',
    'minimumAppVersionRequiredWeb',
    'minimumAppVersionRecommendedApple',
    'minimumAppVersionRecommendedGoogle',
    'minimumAppVersionRecommendedWeb',
  ];

  for (final key in keys) {
    final value = instance.getValue(key);
    logd('🔍 $key: "${value.asString()}" (source: ${value.source})');
  }
}

/// Test manual fetch specifically for web
Future<void> _testWebFetch() async {
  logd('🔄 === TESTING WEB FETCH ===');
  final instance = FirebaseRemoteConfig.instance;

  try {
    // Log values before fetch
    final beforeValue = instance.getString('minimumAppVersionRecommendedApple');
    logd('📱 BEFORE fetch - minimumAppVersionRecommendedApple: "$beforeValue"');

    // Try to fetch (this should work on web)
    logd('🔄 Attempting fetchAndActivate on web...');
    final result = await instance.fetchAndActivate();
    logd('✅ Web fetch result: $result');

    // Log values after fetch
    final afterValue = instance.getString('minimumAppVersionRecommendedApple');
    logd('📱 AFTER fetch - minimumAppVersionRecommendedApple: "$afterValue"');

    // Check new fetch status
    final newFetchStatus = instance.lastFetchStatus;
    final newFetchTime = instance.lastFetchTime;
    logd('📊 NEW fetch status: $newFetchStatus');
    logd('📅 NEW fetch time: $newFetchTime');

    if (beforeValue != afterValue) {
      logd('🎉 Values changed after fetch!');
    } else {
      logd('ℹ️ Values unchanged after fetch (may be cached or same)');
    }
  } catch (e) {
    loge('❌ Web fetch failed: $e');
  }
}

/// Test dependency injection system
Future<void> _testDependencyInjection() async {
  logd('🔧 === TESTING DEPENDENCY INJECTION ===');

  try {
    final repo = GetIt.I.get<RemoteConfigRepoInt>();
    logd('✅ Remote Config repo retrieved: ${repo.runtimeType}');

    // Test values through DI
    final testValue = repo.getString('minimumAppVersionRecommendedApple');
    logd('📱 Value through DI: "$testValue"');

    // Check emulator settings
    logd('🔧 doUseBackendEmulator: ${AppConfigBase.doUseBackendEmulator}');
    logd('🔧 doOverrideUseLiveRemoteConfig: ${AppConfigBase.doOverrideUseLiveRemoteConfig}');
  } catch (e) {
    loge('❌ Dependency injection test failed: $e');
  }
}

/// Test AppConfigBase values
Future<void> _testAppConfigBaseValues() async {
  logd('⚙️ === TESTING APPCONFIG BASE VALUES ===');

  try {
    // Test all web-related values
    final requiredWeb = AppConfigBase.minimumAppVersionRequiredWeb;
    final recommendedWeb = AppConfigBase.minimumAppVersionRecommendedWeb;
    final logLevel = AppConfigBase.logLevel;

    logd('📱 AppConfigBase.minimumAppVersionRequiredWeb: "$requiredWeb"');
    logd('📱 AppConfigBase.minimumAppVersionRecommendedWeb: "$recommendedWeb"');
    logd('📱 AppConfigBase.logLevel: $logLevel');

    // Test a few Apple values for comparison
    final requiredApple = AppConfigBase.minimumAppVersionRequiredApple;
    final recommendedApple = AppConfigBase.minimumAppVersionRecommendedApple;
    logd('📱 AppConfigBase.minimumAppVersionRequiredApple: "$requiredApple"');
    logd('📱 AppConfigBase.minimumAppVersionRecommendedApple: "$recommendedApple"');
  } catch (e) {
    loge('❌ AppConfigBase test failed: $e');
  }
}

/// Force refresh Remote Config for web with detailed logging
Future<void> forceRefreshRemoteConfigWeb() async {
  if (!kIsWeb) {
    logd('❌ This function is only for web platform');
    return;
  }

  logd('🔥 === FORCE REFRESH FOR WEB ===');

  try {
    final instance = FirebaseRemoteConfig.instance;

    // Log current state
    logd('📊 Current fetch status: ${instance.lastFetchStatus}');
    logd('📅 Current fetch time: ${instance.lastFetchTime}');

    // Log values before
    final beforeValue = instance.getString('minimumAppVersionRecommendedApple');
    logd('📱 BEFORE force refresh: "$beforeValue"');

    // Set minimal fetch interval for immediate fetch
    await instance.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: Duration.zero, // Allow immediate fetch
      ),
    );

    // Force fetch
    logd('🔄 Executing force fetchAndActivate...');
    final result = await instance.fetchAndActivate();
    logd('✅ Force fetch result: $result');

    // Log values after
    final afterValue = instance.getString('minimumAppVersionRecommendedApple');
    logd('📱 AFTER force refresh: "$afterValue"');

    // Reset fetch interval
    await instance.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: kDebugMode ? const Duration(seconds: 10) : const Duration(hours: 1),
      ),
    );

    // Log final state
    logd('📊 Final fetch status: ${instance.lastFetchStatus}');
    logd('📅 Final fetch time: ${instance.lastFetchTime}');

    if (beforeValue != afterValue) {
      logd('🎉 SUCCESS: Remote Config values updated!');
    } else {
      logd('ℹ️ Values unchanged (may be up to date or no server values set)');
    }
  } catch (e) {
    loge('❌ Force refresh failed: $e');
  }
}

/// Test if Remote Config parameters are set up in Firebase Console
Future<void> testFirebaseConsoleSetup() async {
  logd('🔍 === TESTING FIREBASE CONSOLE SETUP ===');

  try {
    final instance = FirebaseRemoteConfig.instance;

    // Try a minimal fetch to see if parameters exist
    await instance.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 5),
        minimumFetchInterval: Duration.zero,
      ),
    );

    final result = await instance.fetchAndActivate();
    logd('🔄 Test fetch result: $result');

    // Check if we got any non-default values
    final testValue = instance.getValue('minimumAppVersionRecommendedApple');
    logd('🔍 Test value source: ${testValue.source}');
    logd('🔍 Test value: "${testValue.asString()}"');

    if (testValue.source == ValueSource.valueRemote) {
      logd('✅ SUCCESS: Firebase Console has Remote Config parameters set up!');
    } else if (testValue.source == ValueSource.valueDefault) {
      logd(
          '⚠️ WARNING: Using default values - Remote Config may not be set up in Firebase Console');
      logd('ℹ️ Go to Firebase Console > Remote Config and add parameters');
    } else {
      logd('ℹ️ Value source: ${testValue.source}');
    }
  } catch (e) {
    loge('❌ Firebase Console setup test failed: $e');
    if (e.toString().contains('cannot parse response')) {
      logd('📝 This error suggests Remote Config is not set up in Firebase Console');
    }
  }
}
