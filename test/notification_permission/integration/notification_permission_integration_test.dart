import 'package:dreamic/notifications/notification_permission_helper.dart';
import 'package:dreamic/notifications/notification_types.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mocks/mock_shared_preferences.dart';

/// Integration tests for the notification permission system.
///
/// These tests verify the integration between components and
/// persistence to SharedPreferences with the correct key names.
void main() {
  late NotificationPermissionHelper helper;

  setUp(() {
    MockSharedPreferencesHelper.setupEmpty();
    helper = NotificationPermissionHelper();
  });

  group('Notification Permission Integration', () {
    group('SharedPreferences persistence', () {
      test('persists denial info with dreamic_ prefix', () async {
        // Record a denial
        await helper.recordDenial(isPermanent: false);

        // Verify persisted with dreamic_ prefix
        final prefs = await SharedPreferences.getInstance();
        final storedJson = prefs.getString('dreamic_notification_denial_info');
        expect(storedJson, isNotNull);

        // Verify data is correct
        final info = await helper.getNotificationDenialInfo();
        expect(info?.denialCount, equals(1));
        expect(info?.isPermanent, isFalse);
      });

      test('persists go-to-settings prompt info with dreamic_ prefix', () async {
        await helper.recordGoToSettingsPrompt(openedSettings: true);

        // Verify persisted with dreamic_ prefix
        final prefs = await SharedPreferences.getInstance();
        final storedJson = prefs.getString('dreamic_notification_settings_prompt_info');
        expect(storedJson, isNotNull);

        // Verify data is correct
        final info = await helper.getGoToSettingsPromptInfo();
        expect(info?.promptCount, equals(1));
        expect(info?.lastActionWasOpenSettings, isTrue);
      });

      test('tracks has-requested-before flag with dreamic_ prefix', () async {
        final prefs = await SharedPreferences.getInstance();

        // Before any request
        expect(prefs.getBool('dreamic_notification_has_requested'), isNull);

        // After recording denial
        await helper.recordDenial(isPermanent: false);

        // Verify flag is set
        expect(prefs.getBool('dreamic_notification_has_requested'), isTrue);
      });

      test('clears denial info correctly', () async {
        // Record and then clear
        await helper.recordDenial(isPermanent: false);
        await helper.clearNotificationDenialInfo();

        // Verify cleared
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('dreamic_notification_denial_info'), isNull);

        final info = await helper.getNotificationDenialInfo();
        expect(info, isNull);
      });

      test('clears settings prompt info correctly', () async {
        // Record and then clear
        await helper.recordGoToSettingsPrompt(openedSettings: false);
        await helper.clearGoToSettingsPromptInfo();

        // Verify cleared
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('dreamic_notification_settings_prompt_info'), isNull);

        final info = await helper.getGoToSettingsPromptInfo();
        expect(info, isNull);
      });
    });

    group('denial tracking accuracy', () {
      test('denial count vs request attempt count tracking', () async {
        // First denial (user saw dialog and denied)
        await helper.recordDenial(isPermanent: false);

        var info = await helper.getNotificationDenialInfo();
        expect(info?.denialCount, equals(1));
        expect(info?.requestAttemptCount, equals(1));

        // Second request was blocked (user didn't see dialog)
        await helper.recordBlockedRequest();

        info = await helper.getNotificationDenialInfo();
        expect(info?.denialCount, equals(1)); // NOT incremented
        expect(info?.requestAttemptCount, equals(2));
        expect(info?.lastRequestWasBlocked, isTrue);

        // Third denial (user saw dialog and denied again)
        await helper.recordDenial(isPermanent: true);

        info = await helper.getNotificationDenialInfo();
        expect(info?.denialCount, equals(2));
        expect(info?.requestAttemptCount, equals(3));
        expect(info?.lastRequestWasBlocked, isFalse);
        expect(info?.isPermanent, isTrue);
      });

      test('blocked request preserves last denial time', () async {
        final denialTime = DateTime.now().subtract(const Duration(days: 7));

        // Set up initial denial
        MockSharedPreferencesHelper.setupWithDreamicData(
          denialInfoJson: MockSharedPreferencesHelper.createDenialInfoJson(
            lastDenialTime: denialTime,
            denialCount: 1,
            isPermanent: false,
            requestAttemptCount: 1,
          ),
          migrationComplete: true,
        );

        // Record blocked request
        await helper.recordBlockedRequest();

        final info = await helper.getNotificationDenialInfo();
        // Compare milliseconds to avoid sub-millisecond precision issues
        expect(info?.lastDenialTime.millisecondsSinceEpoch,
            equals(denialTime.millisecondsSinceEpoch)); // Preserved
        expect(info?.requestAttemptCount, equals(2));
      });
    });

    group('settings prompt tracking', () {
      test('prompt count increments correctly', () async {
        // First prompt
        await helper.recordGoToSettingsPrompt(openedSettings: false);
        var info = await helper.getGoToSettingsPromptInfo();
        expect(info?.promptCount, equals(1));

        // Second prompt
        await helper.recordGoToSettingsPrompt(openedSettings: true);
        info = await helper.getGoToSettingsPromptInfo();
        expect(info?.promptCount, equals(2));

        // Third prompt
        await helper.recordGoToSettingsPrompt(openedSettings: false);
        info = await helper.getGoToSettingsPromptInfo();
        expect(info?.promptCount, equals(3));
      });

      test('lastActionWasOpenSettings tracks most recent action', () async {
        await helper.recordGoToSettingsPrompt(openedSettings: true);
        var info = await helper.getGoToSettingsPromptInfo();
        expect(info?.lastActionWasOpenSettings, isTrue);

        await helper.recordGoToSettingsPrompt(openedSettings: false);
        info = await helper.getGoToSettingsPromptInfo();
        expect(info?.lastActionWasOpenSettings, isFalse);
      });
    });

    group('legacy key migration', () {
      test('migrates all legacy keys and removes them', () async {
        final timestamp = DateTime(2024, 1, 1).millisecondsSinceEpoch;

        // Set up legacy data
        SharedPreferences.setMockInitialValues({
          'notification_permission_request_count': 5,
          'notification_permission_denial_count': 3,
          'notification_last_permission_request': timestamp,
          'notification_last_reminder_date': timestamp,
        });

        // Trigger migration
        await helper.ensureMigrated();

        final prefs = await SharedPreferences.getInstance();

        // Verify legacy keys are gone
        expect(prefs.containsKey('notification_permission_request_count'), isFalse);
        expect(prefs.containsKey('notification_permission_denial_count'), isFalse);
        expect(prefs.containsKey('notification_last_permission_request'), isFalse);
        expect(prefs.containsKey('notification_last_reminder_date'), isFalse);

        // Verify migration flag is set
        expect(prefs.getBool('dreamic_notification_keys_migrated'), isTrue);

        // Verify data was migrated
        final info = await helper.getNotificationDenialInfo();
        expect(info?.denialCount, equals(3));
        expect(info?.requestAttemptCount, equals(5));
      });

      test('migration is idempotent', () async {
        final timestamp = DateTime(2024, 1, 1).millisecondsSinceEpoch;

        // Set up legacy data
        SharedPreferences.setMockInitialValues({
          'notification_permission_denial_count': 2,
          'notification_last_permission_request': timestamp,
        });

        // First migration
        await helper.ensureMigrated();

        final firstInfo = await helper.getNotificationDenialInfo();

        // Clear cache and create new helper instance
        final helper2 = NotificationPermissionHelper();
        await helper2.ensureMigrated();

        final secondInfo = await helper2.getNotificationDenialInfo();

        // Should be identical
        expect(secondInfo?.denialCount, equals(firstInfo?.denialCount));
      });
    });

    group('config-based flow control', () {
      test('denial count tracking respects config maxAskCount', () async {
        // Record denials that should trigger limit
        await helper.recordDenial(isPermanent: false);
        await helper.recordDenial(isPermanent: false);
        await helper.recordDenial(isPermanent: false);

        // Verify denial count matches expected
        final info = await helper.getNotificationDenialInfo();
        expect(info?.denialCount, equals(3));

        // Verify config would limit based on count
        // Note: Full shouldRequestPermissions requires Firebase, so we test
        // the denial count tracking which is the input to that decision
        const config = NotificationFlowConfig(maxAskCount: 3);
        expect(info!.denialCount >= config.maxAskCount, isTrue);
      });
    });

    group('periodic reminder timing', () {
      test('updateLastReminderDate and shouldShowPeriodicReminder work together', () async {
        // Initially should show (never shown)
        expect(await helper.shouldShowPeriodicReminder(), isTrue);

        // Update reminder date
        await helper.updateLastReminderDate();

        // Should not show immediately after
        expect(await helper.shouldShowPeriodicReminder(), isFalse);

        // Verify the date was stored
        final prefs = await SharedPreferences.getInstance();
        final stored = prefs.getInt('dreamic_notification_last_reminder_date');
        expect(stored, isNotNull);
        expect(
          DateTime.fromMillisecondsSinceEpoch(stored!).day,
          equals(DateTime.now().day),
        );
      });
    });

    group('data integrity', () {
      test('NotificationDenialInfo round-trips through persistence', () async {
        // Create specific data
        final originalTime = DateTime(2024, 6, 15, 10, 30, 0);
        MockSharedPreferencesHelper.setupWithDreamicData(
          denialInfoJson: MockSharedPreferencesHelper.createDenialInfoJson(
            lastDenialTime: originalTime,
            denialCount: 5,
            isPermanent: true,
            requestAttemptCount: 7,
            lastRequestAttemptTime: originalTime.add(const Duration(hours: 1)),
            lastRequestWasBlocked: true,
          ),
          migrationComplete: true,
        );

        // Read back
        final info = await helper.getNotificationDenialInfo();

        expect(info?.lastDenialTime, equals(originalTime));
        expect(info?.denialCount, equals(5));
        expect(info?.isPermanent, isTrue);
        expect(info?.requestAttemptCount, equals(7));
        expect(info?.lastRequestAttemptTime, equals(originalTime.add(const Duration(hours: 1))));
        expect(info?.lastRequestWasBlocked, isTrue);
      });

      test('GoToSettingsPromptInfo round-trips through persistence', () async {
        final originalTime = DateTime(2024, 6, 15, 10, 30, 0);
        MockSharedPreferencesHelper.setupWithDreamicData(
          settingsPromptInfoJson: MockSharedPreferencesHelper.createSettingsPromptInfoJson(
            lastPromptTime: originalTime,
            promptCount: 3,
            lastActionWasOpenSettings: true,
          ),
          migrationComplete: true,
        );

        final info = await helper.getGoToSettingsPromptInfo();

        expect(info?.lastPromptTime, equals(originalTime));
        expect(info?.promptCount, equals(3));
        expect(info?.lastActionWasOpenSettings, isTrue);
      });
    });

    group('auto-clear on resume', () {
      // These tests verify the clearing behavior that occurs when permission
      // is detected as granted. The actual permission check calls Firebase,
      // which requires runtime mocking. These tests verify the clearing logic
      // works correctly, which is what autoClearIfGranted() calls internally.

      test('clears denial info when permission is granted', () async {
        // Set up: User previously denied permission
        final denialTime = DateTime.now().subtract(const Duration(days: 3));
        MockSharedPreferencesHelper.setupWithDreamicData(
          denialInfoJson: MockSharedPreferencesHelper.createDenialInfoJson(
            lastDenialTime: denialTime,
            denialCount: 2,
            isPermanent: true,
            requestAttemptCount: 3,
          ),
          migrationComplete: true,
        );

        // Verify denial info exists before
        var denialInfo = await helper.getNotificationDenialInfo();
        expect(denialInfo, isNotNull);
        expect(denialInfo?.denialCount, equals(2));
        expect(denialInfo?.isPermanent, isTrue);

        // Simulate: User enabled notifications in settings, app resumes
        // autoClearIfGranted() calls these methods when permission is granted
        await helper.clearNotificationDenialInfo();

        // Verify: Denial info is cleared
        denialInfo = await helper.getNotificationDenialInfo();
        expect(denialInfo, isNull);

        // Verify in SharedPreferences directly
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('dreamic_notification_denial_info'), isNull);
      });

      test('clears settings prompt info when permission is granted', () async {
        // Set up: User was shown go-to-settings prompt
        final promptTime = DateTime.now().subtract(const Duration(days: 1));
        MockSharedPreferencesHelper.setupWithDreamicData(
          settingsPromptInfoJson: MockSharedPreferencesHelper.createSettingsPromptInfoJson(
            lastPromptTime: promptTime,
            promptCount: 2,
            lastActionWasOpenSettings: true,
          ),
          migrationComplete: true,
        );

        // Verify settings prompt info exists before
        var settingsInfo = await helper.getGoToSettingsPromptInfo();
        expect(settingsInfo, isNotNull);
        expect(settingsInfo?.promptCount, equals(2));

        // Simulate: User enabled notifications in settings, app resumes
        // autoClearIfGranted() calls these methods when permission is granted
        await helper.clearGoToSettingsPromptInfo();

        // Verify: Settings prompt info is cleared
        settingsInfo = await helper.getGoToSettingsPromptInfo();
        expect(settingsInfo, isNull);

        // Verify in SharedPreferences directly
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('dreamic_notification_settings_prompt_info'), isNull);
      });

      test('clears both denial and settings info together on grant', () async {
        // Set up: User has both denial info and settings prompt info
        final denialTime = DateTime.now().subtract(const Duration(days: 7));
        final promptTime = DateTime.now().subtract(const Duration(days: 2));
        MockSharedPreferencesHelper.setupWithDreamicData(
          denialInfoJson: MockSharedPreferencesHelper.createDenialInfoJson(
            lastDenialTime: denialTime,
            denialCount: 3,
            isPermanent: true,
            requestAttemptCount: 5,
          ),
          settingsPromptInfoJson: MockSharedPreferencesHelper.createSettingsPromptInfoJson(
            lastPromptTime: promptTime,
            promptCount: 4,
            lastActionWasOpenSettings: false,
          ),
          migrationComplete: true,
        );

        // Verify both exist before
        expect(await helper.getNotificationDenialInfo(), isNotNull);
        expect(await helper.getGoToSettingsPromptInfo(), isNotNull);

        // Simulate: User enabled notifications in settings, app resumes
        // autoClearIfGranted() clears both when permission is detected as granted
        await helper.clearNotificationDenialInfo();
        await helper.clearGoToSettingsPromptInfo();

        // Verify: Both are cleared
        expect(await helper.getNotificationDenialInfo(), isNull);
        expect(await helper.getGoToSettingsPromptInfo(), isNull);

        // Verify in SharedPreferences directly
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('dreamic_notification_denial_info'), isNull);
        expect(prefs.getString('dreamic_notification_settings_prompt_info'), isNull);
      });

      test('clearing is idempotent (safe to call when no data exists)', () async {
        // Set up: No denial or settings info exists
        MockSharedPreferencesHelper.setupEmpty();

        // Verify nothing exists
        expect(await helper.getNotificationDenialInfo(), isNull);
        expect(await helper.getGoToSettingsPromptInfo(), isNull);

        // Simulate: autoClearIfGranted() is called even when no data exists
        // (this can happen on fresh install where user grants immediately)
        await helper.clearNotificationDenialInfo();
        await helper.clearGoToSettingsPromptInfo();

        // Verify: No errors, still null
        expect(await helper.getNotificationDenialInfo(), isNull);
        expect(await helper.getGoToSettingsPromptInfo(), isNull);
      });

      test('has-requested flag is preserved after auto-clear', () async {
        // Set up: User requested before, then denied
        final denialTime = DateTime.now().subtract(const Duration(days: 1));
        MockSharedPreferencesHelper.setupWithDreamicData(
          denialInfoJson: MockSharedPreferencesHelper.createDenialInfoJson(
            lastDenialTime: denialTime,
            denialCount: 1,
            isPermanent: false,
            requestAttemptCount: 1,
          ),
          hasRequested: true,
          migrationComplete: true,
        );

        // Verify has-requested is true before
        final prefsBefore = await SharedPreferences.getInstance();
        expect(prefsBefore.getBool('dreamic_notification_has_requested'), isTrue);

        // Simulate: User enabled notifications, auto-clear occurs
        await helper.clearNotificationDenialInfo();

        // Verify: has-requested flag is still true (historical record preserved)
        final prefsAfter = await SharedPreferences.getInstance();
        expect(prefsAfter.getBool('dreamic_notification_has_requested'), isTrue);
      });

      test('last reminder date is preserved after auto-clear', () async {
        // Set up: User was shown periodic reminder and denial info exists
        final reminderTimestamp =
            DateTime.now().subtract(const Duration(days: 14)).millisecondsSinceEpoch;
        final denialTime = DateTime.now().subtract(const Duration(days: 20));
        MockSharedPreferencesHelper.setupWithDreamicData(
          denialInfoJson: MockSharedPreferencesHelper.createDenialInfoJson(
            lastDenialTime: denialTime,
            denialCount: 1,
            isPermanent: true,
            requestAttemptCount: 2,
          ),
          lastReminderDate: reminderTimestamp,
          migrationComplete: true,
        );

        // Verify reminder date exists before
        final prefsBefore = await SharedPreferences.getInstance();
        expect(prefsBefore.getInt('dreamic_notification_last_reminder_date'),
            equals(reminderTimestamp));

        // Simulate: User enabled notifications, auto-clear occurs
        await helper.clearNotificationDenialInfo();

        // Verify: Last reminder date is preserved
        // (useful for analytics even after permission is granted)
        final prefsAfter = await SharedPreferences.getInstance();
        expect(prefsAfter.getInt('dreamic_notification_last_reminder_date'),
            equals(reminderTimestamp));
      });
    });
  });
}
