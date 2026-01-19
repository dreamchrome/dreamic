import 'package:shared_preferences/shared_preferences.dart';

/// Utility for managing SharedPreferences in tests.
///
/// SharedPreferences provides a built-in mock via [SharedPreferences.setMockInitialValues].
/// This class provides convenience methods for setting up test data with the correct
/// keys used by the notification permission system.
class MockSharedPreferencesHelper {
  /// Keys used by the notification permission system.
  static const String keyDenialInfo = 'dreamic_notification_denial_info';
  static const String keySettingsPromptInfo =
      'dreamic_notification_settings_prompt_info';
  static const String keyHasRequested = 'dreamic_notification_has_requested';
  static const String keyLastReminderDate =
      'dreamic_notification_last_reminder_date';
  static const String keyMigrationComplete =
      'dreamic_notification_keys_migrated';
  static const String keyFcmToken = 'dreamic_fcm_token';

  /// Legacy keys (for migration testing).
  static const String legacyKeyRequestCount =
      'notification_permission_request_count';
  static const String legacyKeyDenialCount =
      'notification_permission_denial_count';
  static const String legacyKeyLastRequest =
      'notification_last_permission_request';
  static const String legacyKeyLastReminder = 'notification_last_reminder_date';
  static const String legacyKeyFcmToken = 'commonSharedKeyFcmToken';

  /// Sets up SharedPreferences with empty initial values.
  ///
  /// Call this in setUp() to ensure a clean state for each test.
  static void setupEmpty() {
    SharedPreferences.setMockInitialValues({});
  }

  /// Sets up SharedPreferences with the given initial values.
  static void setupWithValues(Map<String, Object> values) {
    SharedPreferences.setMockInitialValues(values);
  }

  /// Sets up SharedPreferences with legacy keys for migration testing.
  static void setupWithLegacyData({
    int? requestCount,
    int? denialCount,
    int? lastRequest,
    int? lastReminder,
    String? fcmToken,
  }) {
    final values = <String, Object>{};

    if (requestCount != null) {
      values[legacyKeyRequestCount] = requestCount;
    }
    if (denialCount != null) {
      values[legacyKeyDenialCount] = denialCount;
    }
    if (lastRequest != null) {
      values[legacyKeyLastRequest] = lastRequest;
    }
    if (lastReminder != null) {
      values[legacyKeyLastReminder] = lastReminder;
    }
    if (fcmToken != null) {
      values[legacyKeyFcmToken] = fcmToken;
    }

    SharedPreferences.setMockInitialValues(values);
  }

  /// Sets up SharedPreferences with dreamic_ prefixed keys.
  static void setupWithDreamicData({
    String? denialInfoJson,
    String? settingsPromptInfoJson,
    bool? hasRequested,
    int? lastReminderDate,
    bool? migrationComplete,
    String? fcmToken,
  }) {
    final values = <String, Object>{};

    if (denialInfoJson != null) {
      values[keyDenialInfo] = denialInfoJson;
    }
    if (settingsPromptInfoJson != null) {
      values[keySettingsPromptInfo] = settingsPromptInfoJson;
    }
    if (hasRequested != null) {
      values[keyHasRequested] = hasRequested;
    }
    if (lastReminderDate != null) {
      values[keyLastReminderDate] = lastReminderDate;
    }
    if (migrationComplete != null) {
      values[keyMigrationComplete] = migrationComplete;
    }
    if (fcmToken != null) {
      values[keyFcmToken] = fcmToken;
    }

    SharedPreferences.setMockInitialValues(values);
  }

  /// Creates a JSON string for NotificationDenialInfo.
  static String createDenialInfoJson({
    required DateTime lastDenialTime,
    required int denialCount,
    required bool isPermanent,
    int requestAttemptCount = 0,
    DateTime? lastRequestAttemptTime,
    bool lastRequestWasBlocked = false,
  }) {
    final buffer = StringBuffer('{');
    buffer.write('"lastDenialTime":${lastDenialTime.millisecondsSinceEpoch}');
    buffer.write(',"denialCount":$denialCount');
    buffer.write(',"isPermanent":$isPermanent');
    buffer.write(',"requestAttemptCount":$requestAttemptCount');
    if (lastRequestAttemptTime != null) {
      buffer.write(
          ',"lastRequestAttemptTime":${lastRequestAttemptTime.millisecondsSinceEpoch}');
    } else {
      buffer.write(',"lastRequestAttemptTime":null');
    }
    buffer.write(',"lastRequestWasBlocked":$lastRequestWasBlocked');
    buffer.write('}');
    return buffer.toString();
  }

  /// Creates a JSON string for GoToSettingsPromptInfo.
  static String createSettingsPromptInfoJson({
    required DateTime lastPromptTime,
    required int promptCount,
    required bool lastActionWasOpenSettings,
  }) {
    return '{'
        '"lastPromptTime":${lastPromptTime.millisecondsSinceEpoch},'
        '"promptCount":$promptCount,'
        '"lastActionWasOpenSettings":$lastActionWasOpenSettings'
        '}';
  }
}
