import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:dreamic/data/repos/remote_config_repo_int.dart';

class RemoteConfigRepoLiveImpl implements RemoteConfigRepoInt {
  final remoteConfig = FirebaseRemoteConfig.instance;

  /// Private logging method that avoids circular dependency with AppConfigBase.logLevel
  /// Uses hardcoded LogLevel.info to prevent stack overflow when accessing Remote Config
  void _logForRemoteConfig(String message) {
    // Use direct debug print to avoid Logger which depends on AppConfigBase.logLevel
    // This prevents circular dependency: Remote Config -> Logger -> AppConfigBase.logLevel -> Remote Config
    //TODO: include crashlytics logging if needed
    debugPrint('[RemoteConfig] $message');
  }

  // @override
  // Future<RemoteConfigModel> getRemoteConfig() async {
  //   await remoteConfig.fetchAndActivate();
  //   return RemoteConfigModel(
  //     isFeatureEnabled: remoteConfig.getBool('is_feature_enabled'),
  //     featureTitle: remoteConfig.getString('feature_title'),
  //     featureDescription: remoteConfig.getString('feature_description'),
  //   );
  // }

  // @override
  // Future<bool> isFeatureEnabled(String featureName) async {
  //   await remoteConfig.fetchAndActivate();
  //   return remoteConfig.getBool(featureName);
  // }

  @override
  String getString(String key) {
    try {
      final value = remoteConfig.getString(key);
      // Firebase Remote Config returns empty string for non-existent keys
      // If we get an empty string and the key seems like it should have a default,
      // log it for debugging but return the value anyway (it might be intentionally empty)
      // if (value.isEmpty && _isLikelyNonEmptyParameter(key)) {
      //   // _logForRemoteConfig('🔍 Remote Config getString("$key") returned empty string - AppConfigBase will use default');
      // } else if (value.isNotEmpty) {
      //   // _logForRemoteConfig('✅ Remote Config getString("$key") = "$value"');
      // }
      return value;
    } catch (e) {
      _logForRemoteConfig('❌ Error getting Remote Config string for "$key": $e');
      // Return empty string as fallback (Firebase default behavior)
      return '';
    }
  }

  @override
  bool getBool(String key) {
    try {
      return remoteConfig.getBool(key);
    } catch (e) {
      _logForRemoteConfig('❌ Error getting Remote Config bool for "$key": $e');
      // Return false as fallback (Firebase default behavior)
      return false;
    }
  }

  @override
  int getInt(String key) {
    try {
      return remoteConfig.getInt(key);
    } catch (e) {
      _logForRemoteConfig('❌ Error getting Remote Config int for "$key": $e');
      // Return 0 as fallback (Firebase default behavior)
      return 0;
    }
  }

  @override
  double getDouble(String key) {
    try {
      return remoteConfig.getDouble(key);
    } catch (e) {
      _logForRemoteConfig('❌ Error getting Remote Config double for "$key": $e');
      // Return 0.0 as fallback (Firebase default behavior)
      return 0.0;
    }
  }

  /// Helper method to identify parameters that are likely supposed to be non-empty
  // bool _isLikelyNonEmptyParameter(String key) {
  //   final nonEmptyParams = [
  //     'minimumAppVersionRequiredApple',
  //     'minimumAppVersionRequiredGoogle',
  //     'minimumAppVersionRequiredWeb',
  //     'minimumAppVersionRecommendedApple',
  //     'minimumAppVersionRecommendedGoogle',
  //     'minimumAppVersionRecommendedWeb',
  //     'logLevel',
  //     'subscribeVideoVimeoId',
  //     'stripePublishableKey',
  //     'shareLifeTileSubtext',
  //     'sharePurposeStatementSubtext',
  //     'termsOfUseUrl',
  //     'privacyPolicyUrl',
  //   ];
  //   return nonEmptyParams.contains(key);
  // }
}
