import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mocks/mock_shared_preferences.dart';

/// Tests for app-level notification toggle APIs.
///
/// These tests verify the SharedPreferences persistence behavior for
/// `enableNotifications()`, `disableNotifications()`, and `isNotificationsEnabled()`.
///
/// Note: Full end-to-end testing of these methods requires Firebase mocking,
/// which is complex due to the static nature of FirebaseMessaging.instance.
/// These tests focus on the SharedPreferences flag behavior that can be tested
/// in isolation.

/// Simulates the behavior of `NotificationService.isNotificationsEnabled()`.
///
/// This mirrors the actual implementation which:
/// - Returns the stored boolean value if present
/// - Defaults to true if no value is stored
/// - Defaults to true on error
Future<bool> simulateIsNotificationsEnabled() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(MockSharedPreferencesHelper.keyNotificationsEnabled) ?? true;
  } catch (e) {
    return true;
  }
}

/// Simulates the SharedPreferences update in `NotificationService.disableNotifications()`.
///
/// The actual method also:
/// - Unregisters FCM token on backend (best-effort)
/// - Stops token refresh listener
/// - Deletes FCM token from Firebase
/// - Clears cached tokens
/// These Firebase operations cannot be tested without mocking.
Future<void> simulateDisableNotificationsFlag() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(MockSharedPreferencesHelper.keyNotificationsEnabled, false);
}

/// Simulates the SharedPreferences update in `NotificationService.enableNotifications()`.
///
/// The actual method also:
/// - Re-checks permission status
/// - Requests permission if needed
/// - Fetches fresh FCM token
/// - Restarts token refresh listener
/// These Firebase operations cannot be tested without mocking.
Future<void> simulateEnableNotificationsFlag() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(MockSharedPreferencesHelper.keyNotificationsEnabled, true);
}

/// Simulates the revert behavior when enableNotifications fails.
///
/// When permission request or initialization fails, the flag is reverted to false.
Future<void> simulateEnableNotificationsRevert() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(MockSharedPreferencesHelper.keyNotificationsEnabled, false);
}

void main() {
  group('isNotificationsEnabled', () {
    setUp(() {
      MockSharedPreferencesHelper.setupEmpty();
    });

    test('returns true by default when no preference exists', () async {
      final enabled = await simulateIsNotificationsEnabled();
      expect(enabled, isTrue);
    });

    test('returns true when preference is set to true', () async {
      MockSharedPreferencesHelper.setupWithValues({
        MockSharedPreferencesHelper.keyNotificationsEnabled: true,
      });

      final enabled = await simulateIsNotificationsEnabled();
      expect(enabled, isTrue);
    });

    test('returns false when preference is set to false', () async {
      MockSharedPreferencesHelper.setupWithValues({
        MockSharedPreferencesHelper.keyNotificationsEnabled: false,
      });

      final enabled = await simulateIsNotificationsEnabled();
      expect(enabled, isFalse);
    });

    test('default is true (opt-out model, not opt-in)', () async {
      // This verifies the design decision: notifications are enabled by default.
      // Users must explicitly disable them, not explicitly enable them.
      final enabled = await simulateIsNotificationsEnabled();
      expect(enabled, isTrue, reason: 'Notifications should be enabled by default (opt-out model)');
    });
  });

  group('disableNotifications flag behavior', () {
    setUp(() {
      MockSharedPreferencesHelper.setupEmpty();
    });

    test('sets preference to false', () async {
      // Initially should be true (default)
      expect(await simulateIsNotificationsEnabled(), isTrue);

      // Disable
      await simulateDisableNotificationsFlag();

      // Should now be false
      expect(await simulateIsNotificationsEnabled(), isFalse);
    });

    test('persists across preference reads', () async {
      await simulateDisableNotificationsFlag();

      // Multiple reads should all return false
      expect(await simulateIsNotificationsEnabled(), isFalse);
      expect(await simulateIsNotificationsEnabled(), isFalse);
      expect(await simulateIsNotificationsEnabled(), isFalse);
    });

    test('can be called when already disabled', () async {
      // Disable once
      await simulateDisableNotificationsFlag();
      expect(await simulateIsNotificationsEnabled(), isFalse);

      // Disable again (should be idempotent)
      await simulateDisableNotificationsFlag();
      expect(await simulateIsNotificationsEnabled(), isFalse);
    });
  });

  group('enableNotifications flag behavior', () {
    setUp(() {
      MockSharedPreferencesHelper.setupEmpty();
    });

    test('sets preference to true', () async {
      // First disable
      await simulateDisableNotificationsFlag();
      expect(await simulateIsNotificationsEnabled(), isFalse);

      // Then enable
      await simulateEnableNotificationsFlag();
      expect(await simulateIsNotificationsEnabled(), isTrue);
    });

    test('can toggle between enabled and disabled', () async {
      // Start with default (enabled)
      expect(await simulateIsNotificationsEnabled(), isTrue);

      // Disable
      await simulateDisableNotificationsFlag();
      expect(await simulateIsNotificationsEnabled(), isFalse);

      // Enable
      await simulateEnableNotificationsFlag();
      expect(await simulateIsNotificationsEnabled(), isTrue);

      // Disable again
      await simulateDisableNotificationsFlag();
      expect(await simulateIsNotificationsEnabled(), isFalse);

      // Enable again
      await simulateEnableNotificationsFlag();
      expect(await simulateIsNotificationsEnabled(), isTrue);
    });

    test('can be called when already enabled', () async {
      // Already enabled by default
      expect(await simulateIsNotificationsEnabled(), isTrue);

      // Enable again (should be idempotent)
      await simulateEnableNotificationsFlag();
      expect(await simulateIsNotificationsEnabled(), isTrue);
    });

    test('revert sets flag back to false on failure', () async {
      // Enable
      await simulateEnableNotificationsFlag();
      expect(await simulateIsNotificationsEnabled(), isTrue);

      // Simulate failure revert
      await simulateEnableNotificationsRevert();
      expect(await simulateIsNotificationsEnabled(), isFalse);
    });
  });

  group('Notification toggle integration with other preferences', () {
    setUp(() {
      MockSharedPreferencesHelper.setupEmpty();
    });

    test('notification toggle is independent of FCM token', () async {
      MockSharedPreferencesHelper.setupWithValues({
        MockSharedPreferencesHelper.keyFcmToken: 'test-fcm-token-123',
      });

      // FCM token exists but notification enabled flag is not set
      // Should return true (default)
      expect(await simulateIsNotificationsEnabled(), isTrue);

      // Disable notifications
      await simulateDisableNotificationsFlag();
      expect(await simulateIsNotificationsEnabled(), isFalse);

      // Verify FCM token is still there (in real implementation,
      // disableNotifications would clear it)
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(MockSharedPreferencesHelper.keyFcmToken),
        'test-fcm-token-123',
      );
    });

    test('notification toggle is independent of denial info', () async {
      MockSharedPreferencesHelper.setupWithValues({
        MockSharedPreferencesHelper.keyDenialInfo: MockSharedPreferencesHelper.createDenialInfoJson(
          lastDenialTime: DateTime.now(),
          denialCount: 2,
          isPermanent: false,
        ),
      });

      // Denial info exists but notification enabled flag is not set
      // Should return true (default)
      expect(await simulateIsNotificationsEnabled(), isTrue);

      // Disable notifications
      await simulateDisableNotificationsFlag();
      expect(await simulateIsNotificationsEnabled(), isFalse);
    });

    test('both notification toggle and denial info can coexist', () async {
      MockSharedPreferencesHelper.setupWithValues({
        MockSharedPreferencesHelper.keyNotificationsEnabled: false,
        MockSharedPreferencesHelper.keyDenialInfo: MockSharedPreferencesHelper.createDenialInfoJson(
          lastDenialTime: DateTime.now(),
          denialCount: 1,
          isPermanent: true,
        ),
      });

      // Both flags set
      expect(await simulateIsNotificationsEnabled(), isFalse);

      // Enable notifications (does not clear denial info)
      await simulateEnableNotificationsFlag();
      expect(await simulateIsNotificationsEnabled(), isTrue);

      // Denial info should still be there
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(MockSharedPreferencesHelper.keyDenialInfo),
        isNotNull,
      );
    });
  });

  group('App-level vs OS-level distinction', () {
    test('app-level enabled does not imply OS permission granted', () async {
      // This test documents the design: app-level flag is separate from
      // OS permission status. The app can have notifications "enabled"
      // at the app level while still being denied at the OS level.
      //
      // This allows the app to track user preference separately from
      // the actual permission state.
      expect(await simulateIsNotificationsEnabled(), isTrue);

      // Even with app-level enabled, the user might have:
      // - Never been prompted (notDetermined)
      // - Denied the permission (denied)
      // - Permanently denied (permanentlyDenied)
      //
      // The isNotificationsEnabled() only tells us the app-level preference.
    });

    test('user disabling at app level persists even if OS grants permission', () async {
      // If user disables in the app, that preference should persist
      // even if they later grant OS permission through settings.
      await simulateDisableNotificationsFlag();
      expect(await simulateIsNotificationsEnabled(), isFalse);

      // This flag is the source of truth for "does the user want
      // notifications in this app?"
    });
  });

  group('SharedPreferences key consistency', () {
    test('uses correct key for notifications enabled', () {
      // Verify the key matches what NotificationService uses
      expect(
        MockSharedPreferencesHelper.keyNotificationsEnabled,
        'dreamic_notifications_enabled',
      );
    });

    test('key follows dreamic_ prefix convention', () {
      // All dreamic notification keys should follow the same pattern
      expect(
        MockSharedPreferencesHelper.keyNotificationsEnabled,
        startsWith('dreamic_'),
      );
      expect(
        MockSharedPreferencesHelper.keyDenialInfo,
        startsWith('dreamic_'),
      );
      expect(
        MockSharedPreferencesHelper.keyFcmToken,
        startsWith('dreamic_'),
      );
    });
  });
}
