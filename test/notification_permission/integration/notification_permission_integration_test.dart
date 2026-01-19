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
        final storedJson =
            prefs.getString('dreamic_notification_settings_prompt_info');
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
        expect(
            prefs.getString('dreamic_notification_settings_prompt_info'), isNull);

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
      test('updateLastReminderDate and shouldShowPeriodicReminder work together',
          () async {
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
        expect(info?.lastRequestAttemptTime,
            equals(originalTime.add(const Duration(hours: 1))));
        expect(info?.lastRequestWasBlocked, isTrue);
      });

      test('GoToSettingsPromptInfo round-trips through persistence', () async {
        final originalTime = DateTime(2024, 6, 15, 10, 30, 0);
        MockSharedPreferencesHelper.setupWithDreamicData(
          settingsPromptInfoJson:
              MockSharedPreferencesHelper.createSettingsPromptInfoJson(
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
  });
}
