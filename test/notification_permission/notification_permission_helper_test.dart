import 'package:dreamic/notifications/notification_permission_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mocks/mock_shared_preferences.dart';

void main() {
  late NotificationPermissionHelper helper;

  setUp(() {
    MockSharedPreferencesHelper.setupEmpty();
    // Create helper without notification service (uses default instance)
    // For tests that need the helper, we create it without service dependency
    helper = NotificationPermissionHelper();
  });

  group('NotificationPermissionHelper', () {
    group('key migration', () {
      test('migrates legacy keys to dreamic_ prefixed keys', () async {
        // Set up legacy data
        final legacyTimestamp = DateTime(2024, 1, 1).millisecondsSinceEpoch;
        SharedPreferences.setMockInitialValues({
          'notification_permission_request_count': 3,
          'notification_permission_denial_count': 2,
          'notification_last_permission_request': legacyTimestamp,
          'notification_last_reminder_date': legacyTimestamp,
        });

        await helper.ensureMigrated();

        final prefs = await SharedPreferences.getInstance();

        // Verify legacy keys are removed
        expect(prefs.getInt('notification_permission_request_count'), isNull);
        expect(prefs.getInt('notification_permission_denial_count'), isNull);
        expect(prefs.getInt('notification_last_permission_request'), isNull);
        expect(prefs.getInt('notification_last_reminder_date'), isNull);

        // Verify dreamic_ keys are set
        expect(prefs.getBool(MockSharedPreferencesHelper.keyMigrationComplete), isTrue);
        expect(prefs.getString(MockSharedPreferencesHelper.keyDenialInfo), isNotNull);
        expect(prefs.getInt(MockSharedPreferencesHelper.keyLastReminderDate), equals(legacyTimestamp));
      });

      test('sets has_requested flag when migrating non-zero request count', () async {
        SharedPreferences.setMockInitialValues({
          'notification_permission_request_count': 2,
        });

        await helper.ensureMigrated();

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool(MockSharedPreferencesHelper.keyHasRequested), isTrue);
      });

      test('does not re-migrate if already complete', () async {
        // Set migration complete flag without any data
        SharedPreferences.setMockInitialValues({
          'dreamic_notification_keys_migrated': true,
          // Legacy keys that should NOT be read (already migrated)
          'notification_permission_request_count': 100,
        });

        await helper.ensureMigrated();

        // Verify denial info is still null (migration skipped)
        final info = await helper.getNotificationDenialInfo();
        expect(info, isNull);
      });

      test('handles missing legacy data gracefully', () async {
        MockSharedPreferencesHelper.setupEmpty();

        await helper.ensureMigrated();

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool(MockSharedPreferencesHelper.keyMigrationComplete), isTrue);

        final info = await helper.getNotificationDenialInfo();
        expect(info, isNull);
      });
    });

    group('getNotificationDenialInfo', () {
      test('returns null when no denial info stored', () async {
        MockSharedPreferencesHelper.setupEmpty();

        final info = await helper.getNotificationDenialInfo();
        expect(info, isNull);
      });

      test('returns deserialized denial info when stored', () async {
        final denialTime = DateTime(2024, 6, 15);
        final jsonStr = MockSharedPreferencesHelper.createDenialInfoJson(
          lastDenialTime: denialTime,
          denialCount: 2,
          isPermanent: true,
          requestAttemptCount: 3,
        );
        MockSharedPreferencesHelper.setupWithDreamicData(
          denialInfoJson: jsonStr,
          migrationComplete: true,
        );

        final info = await helper.getNotificationDenialInfo();

        expect(info, isNotNull);
        expect(info!.lastDenialTime, equals(denialTime));
        expect(info.denialCount, equals(2));
        expect(info.isPermanent, isTrue);
        expect(info.requestAttemptCount, equals(3));
      });

      test('handles corrupted JSON gracefully', () async {
        SharedPreferences.setMockInitialValues({
          'dreamic_notification_keys_migrated': true,
          'dreamic_notification_denial_info': 'not valid json',
        });

        final info = await helper.getNotificationDenialInfo();
        expect(info, isNull);
      });
    });

    group('clearNotificationDenialInfo', () {
      test('removes denial info from storage', () async {
        MockSharedPreferencesHelper.setupWithDreamicData(
          denialInfoJson: MockSharedPreferencesHelper.createDenialInfoJson(
            lastDenialTime: DateTime.now(),
            denialCount: 2,
            isPermanent: false,
          ),
          migrationComplete: true,
        );

        await helper.clearNotificationDenialInfo();

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(MockSharedPreferencesHelper.keyDenialInfo), isNull);
      });
    });

    group('getGoToSettingsPromptInfo', () {
      test('returns null when no prompt info stored', () async {
        MockSharedPreferencesHelper.setupEmpty();

        final info = await helper.getGoToSettingsPromptInfo();
        expect(info, isNull);
      });

      test('returns deserialized prompt info when stored', () async {
        final promptTime = DateTime(2024, 6, 15);
        final jsonStr = MockSharedPreferencesHelper.createSettingsPromptInfoJson(
          lastPromptTime: promptTime,
          promptCount: 3,
          lastActionWasOpenSettings: true,
        );
        MockSharedPreferencesHelper.setupWithDreamicData(
          settingsPromptInfoJson: jsonStr,
          migrationComplete: true,
        );

        final info = await helper.getGoToSettingsPromptInfo();

        expect(info, isNotNull);
        expect(info!.lastPromptTime, equals(promptTime));
        expect(info.promptCount, equals(3));
        expect(info.lastActionWasOpenSettings, isTrue);
      });
    });

    group('clearGoToSettingsPromptInfo', () {
      test('removes prompt info from storage', () async {
        MockSharedPreferencesHelper.setupWithDreamicData(
          settingsPromptInfoJson: MockSharedPreferencesHelper.createSettingsPromptInfoJson(
            lastPromptTime: DateTime.now(),
            promptCount: 2,
            lastActionWasOpenSettings: false,
          ),
          migrationComplete: true,
        );

        await helper.clearGoToSettingsPromptInfo();

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(MockSharedPreferencesHelper.keySettingsPromptInfo), isNull);
      });
    });

    group('recordDenial', () {
      test('creates new denial info when none exists', () async {
        MockSharedPreferencesHelper.setupWithDreamicData(migrationComplete: true);

        await helper.recordDenial(isPermanent: false);

        final info = await helper.getNotificationDenialInfo();
        expect(info, isNotNull);
        expect(info!.denialCount, equals(1));
        expect(info.isPermanent, isFalse);
        expect(info.requestAttemptCount, equals(1));
        expect(info.lastRequestWasBlocked, isFalse);
      });

      test('increments denial count when info exists', () async {
        MockSharedPreferencesHelper.setupWithDreamicData(
          denialInfoJson: MockSharedPreferencesHelper.createDenialInfoJson(
            lastDenialTime: DateTime.now().subtract(const Duration(days: 7)),
            denialCount: 1,
            isPermanent: false,
            requestAttemptCount: 1,
          ),
          migrationComplete: true,
        );

        await helper.recordDenial(isPermanent: false);

        final info = await helper.getNotificationDenialInfo();
        expect(info!.denialCount, equals(2));
        expect(info.requestAttemptCount, equals(2));
      });

      test('sets isPermanent correctly', () async {
        MockSharedPreferencesHelper.setupWithDreamicData(migrationComplete: true);

        await helper.recordDenial(isPermanent: true);

        final info = await helper.getNotificationDenialInfo();
        expect(info!.isPermanent, isTrue);
      });

      test('sets has_requested flag', () async {
        MockSharedPreferencesHelper.setupWithDreamicData(migrationComplete: true);

        await helper.recordDenial(isPermanent: false);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool(MockSharedPreferencesHelper.keyHasRequested), isTrue);
      });
    });

    group('recordBlockedRequest', () {
      test('creates new info without incrementing denial count', () async {
        MockSharedPreferencesHelper.setupWithDreamicData(migrationComplete: true);

        await helper.recordBlockedRequest();

        final info = await helper.getNotificationDenialInfo();
        expect(info, isNotNull);
        expect(info!.denialCount, equals(0)); // NOT incremented
        expect(info.requestAttemptCount, equals(1));
        expect(info.lastRequestWasBlocked, isTrue);
      });

      test('increments request attempt count without denial count', () async {
        MockSharedPreferencesHelper.setupWithDreamicData(
          denialInfoJson: MockSharedPreferencesHelper.createDenialInfoJson(
            lastDenialTime: DateTime.now(),
            denialCount: 1,
            isPermanent: false,
            requestAttemptCount: 2,
          ),
          migrationComplete: true,
        );

        await helper.recordBlockedRequest();

        final info = await helper.getNotificationDenialInfo();
        expect(info!.denialCount, equals(1)); // NOT incremented
        expect(info.requestAttemptCount, equals(3));
        expect(info.lastRequestWasBlocked, isTrue);
      });

      test('sets has_requested flag', () async {
        MockSharedPreferencesHelper.setupWithDreamicData(migrationComplete: true);

        await helper.recordBlockedRequest();

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool(MockSharedPreferencesHelper.keyHasRequested), isTrue);
      });
    });

    group('recordGoToSettingsPrompt', () {
      test('creates new prompt info when none exists', () async {
        MockSharedPreferencesHelper.setupWithDreamicData(migrationComplete: true);

        await helper.recordGoToSettingsPrompt(openedSettings: true);

        final info = await helper.getGoToSettingsPromptInfo();
        expect(info, isNotNull);
        expect(info!.promptCount, equals(1));
        expect(info.lastActionWasOpenSettings, isTrue);
      });

      test('increments prompt count when info exists', () async {
        MockSharedPreferencesHelper.setupWithDreamicData(
          settingsPromptInfoJson: MockSharedPreferencesHelper.createSettingsPromptInfoJson(
            lastPromptTime: DateTime.now().subtract(const Duration(days: 30)),
            promptCount: 2,
            lastActionWasOpenSettings: false,
          ),
          migrationComplete: true,
        );

        await helper.recordGoToSettingsPrompt(openedSettings: true);

        final info = await helper.getGoToSettingsPromptInfo();
        expect(info!.promptCount, equals(3));
        expect(info.lastActionWasOpenSettings, isTrue);
      });

      test('records openedSettings = false correctly', () async {
        MockSharedPreferencesHelper.setupWithDreamicData(migrationComplete: true);

        await helper.recordGoToSettingsPrompt(openedSettings: false);

        final info = await helper.getGoToSettingsPromptInfo();
        expect(info!.lastActionWasOpenSettings, isFalse);
      });
    });

    group('hasRequestedPermissionBefore', () {
      test('returns false when never requested', () async {
        MockSharedPreferencesHelper.setupWithDreamicData(migrationComplete: true);

        final hasRequested = await helper.hasRequestedPermissionBefore();
        expect(hasRequested, isFalse);
      });

      test('returns true when has requested', () async {
        MockSharedPreferencesHelper.setupWithDreamicData(
          hasRequested: true,
          migrationComplete: true,
        );

        final hasRequested = await helper.hasRequestedPermissionBefore();
        expect(hasRequested, isTrue);
      });
    });

    group('getPermissionDenialCount', () {
      test('returns 0 when no denial info', () async {
        MockSharedPreferencesHelper.setupWithDreamicData(migrationComplete: true);

        final count = await helper.getPermissionDenialCount();
        expect(count, equals(0));
      });

      test('returns denial count from stored info', () async {
        MockSharedPreferencesHelper.setupWithDreamicData(
          denialInfoJson: MockSharedPreferencesHelper.createDenialInfoJson(
            lastDenialTime: DateTime.now(),
            denialCount: 3,
            isPermanent: false,
          ),
          migrationComplete: true,
        );

        final count = await helper.getPermissionDenialCount();
        expect(count, equals(3));
      });
    });

    group('getPermissionRequestCount', () {
      test('returns 0 when no denial info', () async {
        MockSharedPreferencesHelper.setupWithDreamicData(migrationComplete: true);

        final count = await helper.getPermissionRequestCount();
        expect(count, equals(0));
      });

      test('returns request attempt count from stored info', () async {
        MockSharedPreferencesHelper.setupWithDreamicData(
          denialInfoJson: MockSharedPreferencesHelper.createDenialInfoJson(
            lastDenialTime: DateTime.now(),
            denialCount: 2,
            isPermanent: false,
            requestAttemptCount: 5,
          ),
          migrationComplete: true,
        );

        final count = await helper.getPermissionRequestCount();
        expect(count, equals(5));
      });
    });

    group('shouldShowPeriodicReminder', () {
      test('returns true when never shown', () async {
        MockSharedPreferencesHelper.setupWithDreamicData(migrationComplete: true);

        final shouldShow = await helper.shouldShowPeriodicReminder();
        expect(shouldShow, isTrue);
      });

      test('returns false when recently shown (within default 30 days)', () async {
        final recentTime = DateTime.now().subtract(const Duration(days: 15));
        MockSharedPreferencesHelper.setupWithDreamicData(
          lastReminderDate: recentTime.millisecondsSinceEpoch,
          migrationComplete: true,
        );

        final shouldShow = await helper.shouldShowPeriodicReminder();
        expect(shouldShow, isFalse);
      });

      test('returns true when shown long ago (over 30 days)', () async {
        final oldTime = DateTime.now().subtract(const Duration(days: 45));
        MockSharedPreferencesHelper.setupWithDreamicData(
          lastReminderDate: oldTime.millisecondsSinceEpoch,
          migrationComplete: true,
        );

        final shouldShow = await helper.shouldShowPeriodicReminder();
        expect(shouldShow, isTrue);
      });

      test('respects custom interval', () async {
        final time = DateTime.now().subtract(const Duration(days: 8));
        MockSharedPreferencesHelper.setupWithDreamicData(
          lastReminderDate: time.millisecondsSinceEpoch,
          migrationComplete: true,
        );

        // With 7 day interval, 8 days ago should be true
        final shouldShow = await helper.shouldShowPeriodicReminder(intervalDays: 7);
        expect(shouldShow, isTrue);

        // With 14 day interval, 8 days ago should be false
        final shouldNotShow = await helper.shouldShowPeriodicReminder(intervalDays: 14);
        expect(shouldNotShow, isFalse);
      });
    });

    group('updateLastReminderDate', () {
      test('sets last reminder date to now', () async {
        MockSharedPreferencesHelper.setupWithDreamicData(migrationComplete: true);

        final before = DateTime.now().millisecondsSinceEpoch;
        await helper.updateLastReminderDate();
        final after = DateTime.now().millisecondsSinceEpoch;

        final prefs = await SharedPreferences.getInstance();
        final stored = prefs.getInt(MockSharedPreferencesHelper.keyLastReminderDate);

        expect(stored, isNotNull);
        expect(stored, greaterThanOrEqualTo(before));
        expect(stored, lessThanOrEqualTo(after));
      });
    });

    group('trackPermissionRequest', () {
      test('sets has_requested flag', () async {
        MockSharedPreferencesHelper.setupWithDreamicData(migrationComplete: true);

        await helper.trackPermissionRequest();

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool(MockSharedPreferencesHelper.keyHasRequested), isTrue);
      });

      test('updates existing denial info with new attempt time', () async {
        final oldAttemptTime = DateTime.now().subtract(const Duration(days: 7));
        MockSharedPreferencesHelper.setupWithDreamicData(
          denialInfoJson: MockSharedPreferencesHelper.createDenialInfoJson(
            lastDenialTime: oldAttemptTime,
            denialCount: 1,
            isPermanent: false,
            requestAttemptCount: 1,
            lastRequestAttemptTime: oldAttemptTime,
          ),
          migrationComplete: true,
        );

        await helper.trackPermissionRequest();

        final info = await helper.getNotificationDenialInfo();
        expect(info!.requestAttemptCount, equals(2));
        expect(info.lastRequestAttemptTime!.isAfter(oldAttemptTime), isTrue);
      });
    });

    group('getOptimalContext', () {
      test('suggests value moment for first-time users', () async {
        MockSharedPreferencesHelper.setupWithDreamicData(migrationComplete: true);

        final suggestion = await helper.getOptimalContext();
        expect(suggestion, contains('value moment'));
      });

      test('suggests feature context for previously denied users', () async {
        MockSharedPreferencesHelper.setupWithDreamicData(
          denialInfoJson: MockSharedPreferencesHelper.createDenialInfoJson(
            lastDenialTime: DateTime.now(),
            denialCount: 1,
            isPermanent: false,
            requestAttemptCount: 1, // Must be > 0 to pass requestCount check
          ),
          migrationComplete: true,
        );

        final suggestion = await helper.getOptimalContext();
        expect(suggestion, contains('feature'));
      });

      test('suggests rationale for multiple request attempts', () async {
        MockSharedPreferencesHelper.setupWithDreamicData(
          denialInfoJson: MockSharedPreferencesHelper.createDenialInfoJson(
            lastDenialTime: DateTime.now(),
            denialCount: 0,
            isPermanent: false,
            requestAttemptCount: 3,
          ),
          migrationComplete: true,
        );

        final suggestion = await helper.getOptimalContext();
        expect(suggestion, contains('rationale'));
      });
    });
  });
}
