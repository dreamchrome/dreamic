import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/models/notification_permission_status.dart';
import 'notification_service.dart';
import '../utils/logger.dart';

/// Helper class for managing notification permission state and logic.
///
/// Provides utilities for:
/// - Checking permission status
/// - Determining optimal permission request timing
/// - Tracking permission request history
/// - Deciding when to show reminders or recovery dialogs
class NotificationPermissionHelper {
  static const String _keyPermissionRequestCount = 'notification_permission_request_count';
  static const String _keyPermissionDenialCount = 'notification_permission_denial_count';
  static const String _keyLastPermissionRequest = 'notification_last_permission_request';
  static const String _keyLastReminderDate = 'notification_last_reminder_date';

  final NotificationService _notificationService;

  NotificationPermissionHelper({NotificationService? notificationService})
      : _notificationService = notificationService ?? NotificationService();

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
      final count = await getPermissionRequestCount();
      return count > 0;
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
      final denialCount = await getPermissionDenialCount();
      return denialCount > 0;
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
  /// On Android 13+, the app can prompt multiple times.
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
      // - Android: Can prompt again
      if (status == NotificationPermissionStatus.denied) {
        if (!kIsWeb && (Platform.isIOS || Platform.isMacOS)) {
          return false; // iOS users must use Settings
        }
        return true; // Android users can be prompted again
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
  Future<bool> shouldShowSettingsPrompt() async {
    try {
      final isDenied = await isPermissionDenied();
      if (!isDenied) {
        return false;
      }

      // On iOS, always show settings prompt if denied
      if (!kIsWeb && (Platform.isIOS || Platform.isMacOS)) {
        return true;
      }

      // On Android, show settings prompt after multiple denials
      final denialCount = await getPermissionDenialCount();
      return denialCount >= 2; // Show settings after 2+ denials
    } catch (e) {
      loge(e, 'Error checking should show settings prompt');
      return false;
    }
  }

  /// Gets the number of times permissions have been denied.
  Future<int> getPermissionDenialCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_keyPermissionDenialCount) ?? 0;
    } catch (e) {
      loge(e, 'Error getting permission denial count');
      return 0;
    }
  }

  /// Gets the number of times permissions have been requested.
  Future<int> getPermissionRequestCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_keyPermissionRequestCount) ?? 0;
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
      final prefs = await SharedPreferences.getInstance();
      final lastReminder = prefs.getInt(_keyLastReminderDate);

      if (lastReminder == null) {
        return true; // Never shown before
      }

      final daysSinceLastReminder =
          DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(lastReminder)).inDays;

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
  Future<bool> shouldRequestPermissions() async {
    try {
      // Don't request if already granted
      if (await isPermissionGranted()) {
        return false;
      }

      // Don't request if denied on iOS (can't prompt again)
      if (await isPermissionDenied() && !await canPromptForPermission()) {
        return false;
      }

      // Don't request too frequently (wait at least 1 day between requests)
      final prefs = await SharedPreferences.getInstance();
      final lastRequest = prefs.getInt(_keyLastPermissionRequest);
      if (lastRequest != null) {
        final daysSinceLastRequest =
            DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(lastRequest)).inDays;

        if (daysSinceLastRequest < 1) {
          return false; // Too soon
        }
      }

      // Don't request too many times
      final requestCount = await getPermissionRequestCount();
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
  Future<void> trackPermissionRequest() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final count = prefs.getInt(_keyPermissionRequestCount) ?? 0;
      await prefs.setInt(_keyPermissionRequestCount, count + 1);
      await prefs.setInt(_keyLastPermissionRequest, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      loge(e, 'Error tracking permission request');
    }
  }

  /// Updates the last reminder date to now.
  Future<void> updateLastReminderDate() async {
    try {
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
      final denialCount = await getPermissionDenialCount();
      final requestCount = await getPermissionRequestCount();

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
