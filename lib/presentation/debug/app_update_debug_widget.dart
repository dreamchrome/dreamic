import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dreamic/app/app_config_base.dart';
import 'package:dreamic/app/helpers/app_version_update_service.dart';
import 'package:dreamic/app/helpers/app_lifecycle_service.dart';
import 'package:dreamic/app/helpers/app_remote_config_init.dart';
import 'package:dreamic/data/repos/remote_config_repo_int.dart';
import 'package:dreamic/utils/get_it_utils.dart';
import 'package:dreamic/utils/logger.dart';

/// A debug widget that provides manual controls for testing the app update system
/// This should only be used in development builds
class AppUpdateDebugWidget extends StatelessWidget {
  const AppUpdateDebugWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'App Update Debug Controls',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            Text(
              'Use these controls to test the app update notification system:',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _forceVersionCheck(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Check for Updates'),
                ),
                ElevatedButton.icon(
                  onPressed: () => _forceRefreshRemoteConfig(),
                  icon: const Icon(Icons.cloud_download),
                  label: const Text('Force Refresh Config'),
                ),
                ElevatedButton.icon(
                  onPressed: () => _testRemoteConfigListener(),
                  icon: const Icon(Icons.sensors),
                  label: const Text('Test RC Listener'),
                ),
                ElevatedButton.icon(
                  onPressed: () => _checkListenerStatus(),
                  icon: const Icon(Icons.health_and_safety),
                  label: const Text('Check Listener Health'),
                ),
                ElevatedButton.icon(
                  onPressed: () => _simulateLifecycleResume(),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Simulate App Resume'),
                ),
                ElevatedButton.icon(
                  onPressed: () => _showCurrentVersionInfo(context),
                  icon: const Icon(Icons.info),
                  label: const Text('Version Info'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Testing Notes:',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '• To test required updates, set a higher version in Firebase Remote Config with updateType: "required"',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '• To test recommended updates, set a higher version with updateType: "recommended"',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '• Version checks happen automatically on app resume after 5+ minutes',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '• Use "Test RC Listener" to verify Real-time Remote Config updates are working',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _forceVersionCheck() {
    logd('Debug: Forcing version check WITH fetch (counts toward Firebase limits)');
    AppVersionUpdateService().forceVersionCheckWithFetch().catchError((error) {
      loge('Debug: Error during forced version check: $error');
    });
  }

  void _forceRefreshRemoteConfig() async {
    logd('Debug: Force refreshing Remote Config values');
    try {
      await forceRefreshRemoteConfig();
      logd('Debug: Remote Config force refresh completed - check logs for details');
    } catch (error) {
      loge('Debug: Error during Remote Config force refresh: $error');
    }
  }

  void _testRemoteConfigListener() async {
    logd('🧪 === Testing Remote Config Listener ===');

    final updateService = AppVersionUpdateService();

    // Check listener status first
    _checkListenerStatus();

    if (!updateService.isInitialized) {
      loge('❌ AppVersionUpdateService is not initialized - listener may not be set up');
      return;
    }

    // Get current values for comparison
    final currentVersion = await AppConfigBase.getAppVersionString();

    logd('📱 Current values before test:');
    logd('   App version: $currentVersion');

    if (!kIsWeb && Platform.isIOS) {
      final requiredApple = AppConfigBase.minimumAppVersionRequiredApple;
      final recommendedApple = AppConfigBase.minimumAppVersionRecommendedApple;
      logd('   iOS Required: $requiredApple');
      logd('   iOS Recommended: $recommendedApple');
    } else if (!kIsWeb && Platform.isAndroid) {
      final requiredGoogle = AppConfigBase.minimumAppVersionRequiredGoogle;
      final recommendedGoogle = AppConfigBase.minimumAppVersionRecommendedGoogle;
      logd('   Android Required: $requiredGoogle');
      logd('   Android Recommended: $recommendedGoogle');
    } else if (kIsWeb) {
      final requiredWeb = AppConfigBase.minimumAppVersionRequiredWeb;
      final recommendedWeb = AppConfigBase.minimumAppVersionRecommendedWeb;
      logd('   Web Required: $requiredWeb');
      logd('   Web Recommended: $recommendedWeb');
    }

    logd('');
    logd('📋 TESTING STEPS:');
    logd('1. Go to Firebase Console > Remote Config');
    logd('2. Find the appropriate version key for your platform');
    logd('3. Change the value to something higher than current app version');
    logd('4. Click "Publish changes" (not just save)');
    logd('5. Wait 10-30 seconds for the listener to trigger');
    logd('6. Watch console for: "🔄 Remote config updated from listener!"');
    logd('');
    logd('📱 VERSION KEYS TO TEST:');
    logd('- minimumAppVersionRequiredApple (iOS required)');
    logd('- minimumAppVersionRecommendedApple (iOS recommended)');
    logd('- minimumAppVersionRequiredGoogle (Android required)');
    logd('- minimumAppVersionRecommendedGoogle (Android recommended)');
    logd('- minimumAppVersionRequiredWeb (Web required)');
    logd('- minimumAppVersionRecommendedWeb (Web recommended)');
    logd('');
    logd('⏰ Now watching for Remote Config listener updates...');
    logd(
        '🎯 The system will automatically check for version updates when version keys are updated');
    logd('🧪 === End Remote Config Listener Test Setup ===');
  }

  void _simulateLifecycleResume() {
    logd('Debug: Simulating app lifecycle resume');
    AppLifecycleService().checkForUpdates().catchError((error) {
      loge('Debug: Error during simulated lifecycle resume: $error');
    });
  }

  void _showCurrentVersionInfo(BuildContext context) {
    final updateService = AppVersionUpdateService();
    final lifecycleService = AppLifecycleService();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Current Version Info'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Update Service Initialized: ${updateService.isInitialized}'),
            Text('Lifecycle Service Initialized: ${lifecycleService.isInitialized}'),
            const SizedBox(height: 16),
            Text(
              'Current version info will be logged to console.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    // Log current version info
    logd('Debug: Version service initialized: ${updateService.isInitialized}');
    logd('Debug: Lifecycle service initialized: ${lifecycleService.isInitialized}');
  }

  void _checkListenerStatus() {
    final updateService = AppVersionUpdateService();
    final status = updateService.getListenerStatus();

    logd('🔍 === Remote Config Listener Health Check ===');
    logd('📊 Service initialized: ${status['isInitialized']}');
    logd('📡 Has subscription: ${status['hasSubscription']}');
    logd('⏸️ Is paused: ${status['isPaused']}');
    logd('🔢 Subscription hash: ${status['subscriptionHashCode']}');
    logd('✅ Listener active: ${status['isListenerActive']}');

    // Test if we can read Remote Config values
    try {
      final testValue = AppConfigBase.minimumAppVersionRecommendedApple;
      final remoteConfigRepo = g<RemoteConfigRepoInt>();
      final rawValue = remoteConfigRepo.getString('minimumAppVersionRecommendedApple');

      logd('📱 Current test value (AppConfigBase): $testValue');
      logd('📱 Current raw value (Remote Config): $rawValue');

      // Only show fetch status if using real Firebase (not in emulator mode)
      if (!AppConfigBase.doUseBackendEmulator || AppConfigBase.doOverrideUseLiveRemoteConfig) {
        // When using real Firebase, we can access fetch status
        logd('📊 Using real Firebase Remote Config');
      } else {
        logd('📊 Using mock Remote Config (emulator mode)');
      }
    } catch (e) {
      loge('❌ Error reading Remote Config values: $e');
    }

    logd('🔍 === End Listener Health Check ===');
  }
}

/// Extension to add debug functionality to any widget tree
extension AppUpdateDebugExtension on Widget {
  /// Wraps this widget with debug controls if in debug mode
  Widget withUpdateDebugControls() {
    // Only show in debug mode
    bool isDebug = false;
    assert(isDebug = true); // This assignment only happens in debug mode

    if (!isDebug) return this;

    return Column(
      children: [
        const AppUpdateDebugWidget(),
        Expanded(child: this),
      ],
    );
  }
}
