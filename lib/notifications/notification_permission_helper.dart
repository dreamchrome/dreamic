import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/models/notification_permission_status.dart';
import 'notification_service.dart';
import 'notification_types.dart';
import '../utils/logger.dart';

/// Calculates the duration to wait before asking again, based on denial count.
///
/// Uses the formula: askAgainAfter * (askAgainMultiplier ^ (denialCount - 1))
///
/// Examples with askAgainAfter=7 days:
/// - denialCount=1, multiplier=1.5: 7 days
/// - denialCount=2, multiplier=1.5: 10.5 days
/// - denialCount=3, multiplier=1.5: 15.75 days
/// - denialCount=1, multiplier=1.0: 7 days (constant)
/// - denialCount=2, multiplier=1.0: 7 days (constant)
Duration _getAskAgainDuration(NotificationFlowConfig config, int denialCount) {
  if (denialCount <= 1) {
    return config.askAgainAfter;
  }

  // multiplier ^ (denialCount - 1)
  final multiplierFactor = math.pow(config.askAgainMultiplier, denialCount - 1);
  final milliseconds = (config.askAgainAfter.inMilliseconds * multiplierFactor).round();
  return Duration(milliseconds: milliseconds);
}

/// Helper class for managing notification permission state and logic.
///
/// Provides utilities for:
/// - Checking permission status
/// - Determining optimal permission request timing
/// - Tracking permission request history
/// - Deciding when to show reminders or recovery dialogs
///
/// This class owns all permission-related SharedPreferences keys with the
/// `dreamic_` prefix to avoid collisions with consuming apps.
class NotificationPermissionHelper {
  // New dreamic_ prefixed keys (owned by this helper)
  static const String _keyDenialInfo = 'dreamic_notification_denial_info';
  static const String _keySettingsPromptInfo =
      'dreamic_notification_settings_prompt_info';
  static const String _keyHasRequested = 'dreamic_notification_has_requested';
  static const String _keyLastReminderDate =
      'dreamic_notification_last_reminder_date';
  static const String _keyMigrationComplete =
      'dreamic_notification_keys_migrated';

  // Legacy keys (for migration only - do not use for new data)
  static const String _legacyKeyRequestCount =
      'notification_permission_request_count';
  static const String _legacyKeyDenialCount =
      'notification_permission_denial_count';
  static const String _legacyKeyLastRequest =
      'notification_last_permission_request';
  static const String _legacyKeyLastReminder = 'notification_last_reminder_date';

  final NotificationService _notificationService;
  bool _migrationComplete = false;

  NotificationPermissionHelper({NotificationService? notificationService})
      : _notificationService = notificationService ?? NotificationService();

  /// Ensures migration has been performed.
  /// Call this before any SharedPreferences access.
  Future<void> ensureMigrated() async {
    if (_migrationComplete) return;
    await _migrateOldKeys();
    _migrationComplete = true;
  }

  /// Migrates old SharedPreferences keys to new dreamic_ prefixed keys.
  /// Safe to call multiple times - checks if migration is already complete.
  Future<void> _migrateOldKeys() async {
    final prefs = await SharedPreferences.getInstance();

    // Check if migration already done
    if (prefs.getBool(_keyMigrationComplete) == true) {
      logd('Notification permission keys already migrated');
      return;
    }

    // Read old values
    final oldRequestCount = prefs.getInt(_legacyKeyRequestCount);
    final oldDenialCount = prefs.getInt(_legacyKeyDenialCount);
    final oldLastRequest = prefs.getInt(_legacyKeyLastRequest);
    final oldLastReminder = prefs.getInt(_legacyKeyLastReminder);

    // If any old data exists, migrate to new structure
    if (oldDenialCount != null && oldDenialCount > 0) {
      final denialInfo = NotificationDenialInfo(
        lastDenialTime: oldLastRequest != null
            ? DateTime.fromMillisecondsSinceEpoch(oldLastRequest)
            : DateTime.now(),
        denialCount: oldDenialCount,
        isPermanent: false, // Conservative - will be updated on next status check
        requestAttemptCount: oldRequestCount ?? oldDenialCount,
      );
      await prefs.setString(_keyDenialInfo, jsonEncode(denialInfo.toJson()));
    }

    // Migrate has_requested flag based on old request count
    if (oldRequestCount != null && oldRequestCount > 0) {
      await prefs.setBool(_keyHasRequested, true);
    }

    if (oldLastReminder != null) {
      await prefs.setInt(_keyLastReminderDate, oldLastReminder);
    }

    // Clean up old keys
    final oldKeys = [
      _legacyKeyRequestCount,
      _legacyKeyDenialCount,
      _legacyKeyLastRequest,
      _legacyKeyLastReminder,
    ];
    for (final oldKey in oldKeys) {
      await prefs.remove(oldKey);
    }

    // Mark migration complete
    await prefs.setBool(_keyMigrationComplete, true);
    logd('Migrated notification permission keys to dreamic_ prefix');
  }

  /// Returns true if notification permissions are granted.
  Future<bool> isPermissionGranted() async {
    try {
      final status = await _notificationService.getPermissionStatus();
      return status == NotificationPermissionStatus.authorized;
    } catch (e) {
      loge(e, 'Error checking if permission granted');
      return false;
    }
  }

  /// Returns true if notification permissions are denied.
  Future<bool> isPermissionDenied() async {
    try {
      final status = await _notificationService.getPermissionStatus();
      return status == NotificationPermissionStatus.denied;
    } catch (e) {
      loge(e, 'Error checking if permission denied');
      return false;
    }
  }

  /// Returns true if notification permissions have not been determined yet.
  Future<bool> isPermissionNotDetermined() async {
    try {
      final status = await _notificationService.getPermissionStatus();
      return status == NotificationPermissionStatus.notDetermined;
    } catch (e) {
      loge(e, 'Error checking if permission not determined');
      return true; // Default to not determined on error
    }
  }

  /// Returns true if permissions have been requested at least once.
  Future<bool> hasRequestedPermissionBefore() async {
    try {
      await ensureMigrated();
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_keyHasRequested) ?? false;
    } catch (e) {
      loge(e, 'Error checking if requested permission before');
      return false;
    }
  }

  /// Returns true if the app should show a rationale before requesting permissions.
  ///
  /// On Android, this helps determine if the user has previously denied permissions
  /// and should see an explanation before being prompted again.
  ///
  /// On iOS, this always returns false since iOS doesn't provide this information.
  Future<bool> shouldShowPermissionRationale() async {
    // iOS doesn't provide a way to check this
    if (!kIsWeb && (Platform.isIOS || Platform.isMacOS)) {
      return false;
    }

    // On Android, show rationale if user has denied before
    try {
      final denialInfo = await getNotificationDenialInfo();
      return denialInfo != null && denialInfo.denialCount > 0;
    } catch (e) {
      loge(e, 'Error checking should show rationale');
      return false;
    }
  }

  /// Returns true if the app can prompt for permissions.
  ///
  /// On iOS, once permissions are denied, the app cannot prompt again
  /// and must direct users to Settings.
  ///
  /// On Android 13+, the app can prompt again after first denial,
  /// but not after second denial (permanently denied).
  Future<bool> canPromptForPermission() async {
    try {
      final status = await _notificationService.getPermissionStatus();

      // If already granted, no need to prompt
      if (status == NotificationPermissionStatus.authorized) {
        return false;
      }

      // If not determined, can always prompt
      if (status == NotificationPermissionStatus.notDetermined) {
        return true;
      }

      // If denied:
      // - iOS: Cannot prompt again, must use Settings
      // - Android: Can prompt again until permanently denied
      if (status == NotificationPermissionStatus.denied) {
        if (!kIsWeb && (Platform.isIOS || Platform.isMacOS)) {
          return false; // iOS users must use Settings
        }

        // On Android, check if permanently denied (denied + has requested before)
        // After two denials on Android 13+, the system won't show the dialog
        final denialInfo = await getNotificationDenialInfo();
        if (denialInfo != null && denialInfo.isPermanent) {
          return false;
        }

        // Check denial count - Android 13+ allows one re-request after first denial
        if (denialInfo != null && denialInfo.denialCount >= 2) {
          return false; // Permanently denied after 2 denials
        }

        return true; // Android users can be prompted again (first denial)
      }

      return false;
    } catch (e) {
      loge(e, 'Error checking can prompt for permission');
      return false;
    }
  }

  /// Returns true if the app should show a settings prompt.
  ///
  /// This is true when:
  /// - Permissions are denied
  /// - AND on iOS (can't prompt again) OR user has denied multiple times on Android
  ///
  /// Optionally respects [config] limits for timing and count.
  Future<bool> shouldShowSettingsPrompt({
    NotificationFlowConfig? config,
  }) async {
    try {
      final isDenied = await isPermissionDenied();
      if (!isDenied) {
        return false;
      }

      // On iOS, always show settings prompt if denied
      if (!kIsWeb && (Platform.isIOS || Platform.isMacOS)) {
        return _shouldShowSettingsPromptWithConfig(config);
      }

      // On Android, show settings prompt after multiple denials
      final denialInfo = await getNotificationDenialInfo();
      final shouldShow =
          denialInfo != null && (denialInfo.denialCount >= 2 || denialInfo.isPermanent);

      if (!shouldShow) {
        return false;
      }

      return _shouldShowSettingsPromptWithConfig(config);
    } catch (e) {
      loge(e, 'Error checking should show settings prompt');
      return false;
    }
  }

  /// Checks config limits for settings prompt.
  Future<bool> _shouldShowSettingsPromptWithConfig(
    NotificationFlowConfig? config,
  ) async {
    if (config == null) return true;

    if (!config.showGoToSettingsPrompt) {
      return false;
    }

    final settingsInfo = await getGoToSettingsPromptInfo();
    if (settingsInfo == null) return true; // Never shown before

    // Check max count
    if (config.goToSettingsMaxAskCount != null &&
        settingsInfo.promptCount >= config.goToSettingsMaxAskCount!) {
      return false;
    }

    // Check timing
    final timeSinceLastPrompt =
        DateTime.now().difference(settingsInfo.lastPromptTime);
    return timeSinceLastPrompt >= config.goToSettingsAskAgainAfter;
  }

  /// Gets structured information about notification permission denials.
  Future<NotificationDenialInfo?> getNotificationDenialInfo() async {
    try {
      await ensureMigrated();
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_keyDenialInfo);
      if (jsonStr == null) return null;

      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      return NotificationDenialInfo.fromJson(json);
    } catch (e) {
      loge(e, 'Error getting notification denial info');
      return null;
    }
  }

  /// Clears stored denial info (e.g., after user grants permission via settings).
  Future<void> clearNotificationDenialInfo() async {
    try {
      await ensureMigrated();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyDenialInfo);
      logd('Cleared notification denial info');
    } catch (e) {
      loge(e, 'Error clearing notification denial info');
    }
  }

  /// Gets structured information about "go to settings" prompts.
  Future<GoToSettingsPromptInfo?> getGoToSettingsPromptInfo() async {
    try {
      await ensureMigrated();
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_keySettingsPromptInfo);
      if (jsonStr == null) return null;

      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      return GoToSettingsPromptInfo.fromJson(json);
    } catch (e) {
      loge(e, 'Error getting go to settings prompt info');
      return null;
    }
  }

  /// Clears stored "go to settings" prompt info.
  Future<void> clearGoToSettingsPromptInfo() async {
    try {
      await ensureMigrated();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keySettingsPromptInfo);
      logd('Cleared go to settings prompt info');
    } catch (e) {
      loge(e, 'Error clearing go to settings prompt info');
    }
  }

  /// Records a permission denial.
  ///
  /// [isPermanent] should be true for iOS (always permanent after first denial)
  /// or Android after second denial.
  Future<void> recordDenial({required bool isPermanent}) async {
    try {
      await ensureMigrated();
      final prefs = await SharedPreferences.getInstance();

      final existingInfo = await getNotificationDenialInfo();
      final now = DateTime.now();

      final newInfo = NotificationDenialInfo(
        lastDenialTime: now,
        denialCount: (existingInfo?.denialCount ?? 0) + 1,
        isPermanent: isPermanent,
        requestAttemptCount: (existingInfo?.requestAttemptCount ?? 0) + 1,
        lastRequestAttemptTime: now,
        lastRequestWasBlocked: false,
      );

      await prefs.setString(_keyDenialInfo, jsonEncode(newInfo.toJson()));
      await prefs.setBool(_keyHasRequested, true);

      logd('Recorded permission denial: $newInfo');
    } catch (e) {
      loge(e, 'Error recording denial');
    }
  }

  /// Records when a permission request was blocked by the system.
  ///
  /// This is distinct from a denial - the user never saw the dialog.
  /// Used for OEM restrictions or other system-level blocking.
  Future<void> recordBlockedRequest() async {
    try {
      await ensureMigrated();
      final prefs = await SharedPreferences.getInstance();

      final existingInfo = await getNotificationDenialInfo();
      final now = DateTime.now();

      final newInfo = NotificationDenialInfo(
        lastDenialTime: existingInfo?.lastDenialTime ?? now,
        denialCount: existingInfo?.denialCount ?? 0, // Don't increment
        isPermanent: existingInfo?.isPermanent ?? false,
        requestAttemptCount: (existingInfo?.requestAttemptCount ?? 0) + 1,
        lastRequestAttemptTime: now,
        lastRequestWasBlocked: true,
      );

      await prefs.setString(_keyDenialInfo, jsonEncode(newInfo.toJson()));
      await prefs.setBool(_keyHasRequested, true);

      logd('Recorded blocked request: $newInfo');
    } catch (e) {
      loge(e, 'Error recording blocked request');
    }
  }

  /// Records that a "go to settings" prompt was shown.
  ///
  /// [openedSettings] should be true if the user chose to open settings,
  /// false if they declined.
  Future<void> recordGoToSettingsPrompt({required bool openedSettings}) async {
    try {
      await ensureMigrated();
      final prefs = await SharedPreferences.getInstance();

      final existingInfo = await getGoToSettingsPromptInfo();
      final now = DateTime.now();

      final newInfo = GoToSettingsPromptInfo(
        lastPromptTime: now,
        promptCount: (existingInfo?.promptCount ?? 0) + 1,
        lastActionWasOpenSettings: openedSettings,
      );

      await prefs.setString(_keySettingsPromptInfo, jsonEncode(newInfo.toJson()));

      logd('Recorded go to settings prompt: $newInfo');
    } catch (e) {
      loge(e, 'Error recording go to settings prompt');
    }
  }

  /// Checks permission status and clears tracking data if granted.
  ///
  /// Call this when the app resumes or at strategic points to detect
  /// when the user has enabled notifications via settings.
  ///
  /// Returns true if permission is now granted and tracking data was cleared.
  Future<bool> autoClearIfGranted() async {
    try {
      final isGranted = await isPermissionGranted();
      if (isGranted) {
        final denialInfo = await getNotificationDenialInfo();
        final settingsInfo = await getGoToSettingsPromptInfo();

        if (denialInfo != null || settingsInfo != null) {
          await clearNotificationDenialInfo();
          await clearGoToSettingsPromptInfo();
          logd('Permission now granted - cleared stored tracking info');
          return true;
        }
      }
      return false;
    } catch (e) {
      loge(e, 'Error in autoClearIfGranted');
      return false;
    }
  }

  /// Gets the number of times permissions have been denied.
  ///
  /// Prefer using [getNotificationDenialInfo] for more detailed information.
  Future<int> getPermissionDenialCount() async {
    try {
      final info = await getNotificationDenialInfo();
      return info?.denialCount ?? 0;
    } catch (e) {
      loge(e, 'Error getting permission denial count');
      return 0;
    }
  }

  /// Gets the number of times permissions have been requested.
  ///
  /// Prefer using [getNotificationDenialInfo] for more detailed information.
  Future<int> getPermissionRequestCount() async {
    try {
      final info = await getNotificationDenialInfo();
      return info?.requestAttemptCount ?? 0;
    } catch (e) {
      loge(e, 'Error getting permission request count');
      return 0;
    }
  }

  /// Returns true if enough time has passed to show a periodic reminder.
  ///
  /// Uses the interval configured in NotificationService (default 30 days).
  Future<bool> shouldShowPeriodicReminder({int? intervalDays}) async {
    try {
      await ensureMigrated();
      final prefs = await SharedPreferences.getInstance();
      final lastReminder = prefs.getInt(_keyLastReminderDate);

      if (lastReminder == null) {
        return true; // Never shown before
      }

      final daysSinceLastReminder = DateTime.now()
          .difference(DateTime.fromMillisecondsSinceEpoch(lastReminder))
          .inDays;

      final interval = intervalDays ?? 30;
      return daysSinceLastReminder >= interval;
    } catch (e) {
      loge(e, 'Error checking should show periodic reminder');
      return false;
    }
  }

  /// Returns true if the app should request permissions now.
  ///
  /// Considers:
  /// - Current permission status
  /// - Previous request history
  /// - Platform capabilities
  /// - Time since last request
  /// - Optional flow configuration
  Future<bool> shouldRequestPermissions({
    NotificationFlowConfig? config,
  }) async {
    try {
      // Don't request if already granted
      if (await isPermissionGranted()) {
        return false;
      }

      // Don't request if denied on iOS (can't prompt again)
      if (await isPermissionDenied() && !await canPromptForPermission()) {
        return false;
      }

      final denialInfo = await getNotificationDenialInfo();

      // If using config, respect its limits
      if (config != null && denialInfo != null) {
        // Check denial count against maxAskCount
        if (denialInfo.denialCount >= config.maxAskCount) {
          return false;
        }

        // Check timing with multiplier based on denial count
        // The delay increases with each denial when multiplier > 1
        final requiredDelay = _getAskAgainDuration(config, denialInfo.denialCount);
        final timeSinceDenial =
            DateTime.now().difference(denialInfo.lastDenialTime);
        if (timeSinceDenial < requiredDelay) {
          return false;
        }

        return true;
      }

      // Legacy behavior without config
      // Don't request too frequently (wait at least 1 day between requests)
      if (denialInfo?.lastRequestAttemptTime != null) {
        final daysSinceLastRequest = DateTime.now()
            .difference(denialInfo!.lastRequestAttemptTime!)
            .inDays;

        if (daysSinceLastRequest < 1) {
          return false; // Too soon
        }
      }

      // Don't request too many times
      final requestCount = denialInfo?.requestAttemptCount ?? 0;
      if (requestCount >= 5) {
        return false; // Stop after 5 attempts
      }

      return true;
    } catch (e) {
      loge(e, 'Error checking should request permissions');
      return false;
    }
  }

  /// Tracks a permission request attempt.
  ///
  /// Prefer using [recordDenial] or [recordBlockedRequest] for more accurate tracking.
  Future<void> trackPermissionRequest() async {
    try {
      await ensureMigrated();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyHasRequested, true);

      // Also update denial info if it exists (to track attempt time)
      final existingInfo = await getNotificationDenialInfo();
      if (existingInfo != null) {
        final updatedInfo = existingInfo.copyWith(
          requestAttemptCount: existingInfo.requestAttemptCount + 1,
          lastRequestAttemptTime: DateTime.now(),
        );
        await prefs.setString(_keyDenialInfo, jsonEncode(updatedInfo.toJson()));
      }
    } catch (e) {
      loge(e, 'Error tracking permission request');
    }
  }

  /// Updates the last reminder date to now.
  Future<void> updateLastReminderDate() async {
    try {
      await ensureMigrated();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyLastReminderDate, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      loge(e, 'Error updating last reminder date');
    }
  }

  /// Suggests the optimal context for requesting permissions.
  ///
  /// Returns suggestions based on:
  /// - User's previous behavior
  /// - Platform best practices
  /// - App usage patterns
  ///
  /// Returns a string with suggestions like:
  /// - "Show after first value moment"
  /// - "Show during onboarding"
  /// - "Show when user enables a feature that needs notifications"
  Future<String> getOptimalContext() async {
    try {
      final denialInfo = await getNotificationDenialInfo();
      final requestCount = denialInfo?.requestAttemptCount ?? 0;
      final denialCount = denialInfo?.denialCount ?? 0;

      if (requestCount == 0) {
        return 'Show after first value moment (user has experienced app benefits)';
      }

      if (denialCount > 0) {
        return 'Show when user explicitly enables a feature that needs notifications';
      }

      if (requestCount >= 2) {
        return 'Show with strong rationale explaining specific benefits user will miss';
      }

      return 'Show in context of a feature the user is actively using';
    } catch (e) {
      loge(e, 'Error getting optimal context');
      return 'Show when contextually appropriate';
    }
  }
}
