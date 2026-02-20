import 'dart:async';

import 'package:dreamic/app/helpers/app_lifecycle_service.dart';
import 'package:dreamic/data/models/notification_permission_status.dart';
import 'package:dreamic/notifications/notification_service.dart';
import 'package:dreamic/notifications/notification_types.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Unit tests for the notification settings deep link handler (Phase 6).
///
/// These tests verify:
/// - Race prevention: synchronous ownership claim, lifecycle polling, early exit
/// - Lifecycle resume handler guard: duplicate entry, finally-block resets
/// - Cold-launch pending intent: pull-based check, MissingPluginException
/// - requestPermissions: providesAppNotificationSettings parameter
/// - Cleanup: nulling out channel handler and callback
///
/// Testing strategy:
/// - Uses [NotificationService.resetForTesting] to get a fresh singleton per test
/// - Uses @visibleForTesting overrides for Firebase-dependent methods
/// - Uses @visibleForTesting setters for internal state
/// - Simulates lifecycle events via [AppLifecycleService.didChangeAppLifecycleState]
/// - Mocks method channels via [TestDefaultBinaryMessengerBinding]
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NotificationService service;

  setUp(() {
    NotificationService.resetForTesting();
    service = NotificationService();
  });

  tearDown(() async {
    service.testGetPermissionStatusOverride = null;
    service.testGetNotificationDenialInfoOverride = null;
    service.testInitializeFcmTokenOverride = null;
    await service.dispose();
    NotificationService.resetForTesting();
  });

  // =========================================================================
  // 6.1  Synchronous ownership claim
  // =========================================================================
  group('Race Prevention — Synchronous Ownership Claim', () {
    test('6.1: _handleSettingsMethodCall clears _waitingForSettingsReturn '
        'synchronously before any async work', () async {
      // Set up: _waitingForSettingsReturn is true (user went to settings)
      service.waitingForSettingsReturnForTesting = true;

      // The first await in _handleSettingsMethodCall is the call to
      // _handleSettingsDeepLink, which calls getNotificationDenialInfo().
      // If _waitingForSettingsReturn is already false when
      // getNotificationDenialInfo() runs, the synchronous claim happened
      // before any await — proving the race prevention mechanism works.
      var wasClearedBeforeFirstAwait = false;
      service.testGetNotificationDenialInfoOverride = () async {
        wasClearedBeforeFirstAwait =
            !service.waitingForSettingsReturnForTesting;
        return null;
      };
      service.testGetPermissionStatusOverride =
          () async => NotificationPermissionStatus.authorized;
      service.onSystemNotificationSettingsOpenedForTesting = (info) async {};

      await service.handleSettingsMethodCallForTesting(
        const MethodCall('openNotificationSettings', 'test_channel'),
      );

      // The flag must have been cleared synchronously before the first await
      // in the async method body. If it was still true when
      // getNotificationDenialInfo ran, the race prevention is broken.
      expect(wasClearedBeforeFirstAwait, isTrue,
          reason: '_waitingForSettingsReturn must be cleared synchronously '
              'before any await in _handleSettingsMethodCall');
      // Also verify the flag is still false after completion
      expect(service.waitingForSettingsReturnForTesting, isFalse);
    });
  });

  // =========================================================================
  // 6.2–6.4  Lifecycle listener polling
  // =========================================================================
  group('Race Prevention — Lifecycle Polling', () {
    test('6.2: lifecycle listener polls and skips _handleResumeAfterSettings '
        'when _waitingForSettingsReturn is cleared during polling window',
        () async {
      // Track whether _handleResumeAfterSettings runs — it calls
      // getPermissionStatus, so a non-zero call count means it ran.
      var getPermissionStatusCallCount = 0;
      service.testGetPermissionStatusOverride = () async {
        getPermissionStatusCallCount++;
        return NotificationPermissionStatus.denied;
      };

      // Deep link callback registered → lifecycle listener will poll.
      service.onSystemNotificationSettingsOpenedForTesting = (info) async {};
      service.waitingForSettingsReturnForTesting = true;
      service.setupLifecycleListenerForTesting();

      // Schedule clearing the flag after 30ms — simulates the method channel
      // handler claiming ownership during the polling window (10ms intervals,
      // up to 100ms).
      Future<void>.delayed(const Duration(milliseconds: 30), () {
        service.waitingForSettingsReturnForTesting = false;
      });

      // Simulate lifecycle resume — starts the polling loop.
      AppLifecycleService().didChangeAppLifecycleState(
        AppLifecycleState.resumed,
      );

      // Wait long enough for all polling to complete (100ms max + margin).
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // _handleResumeAfterSettings should NOT have run — the deep link
      // handler claimed ownership during the polling window.
      expect(getPermissionStatusCallCount, 0,
          reason: '_handleResumeAfterSettings should be skipped when '
              '_waitingForSettingsReturn is cleared during polling');
      // Guard should be reset by the finally block.
      expect(service.lifecycleResumeHandlerActiveForTesting, isFalse);
    });

    test('6.3: lifecycle listener exits polling loop early when '
        '_waitingForSettingsReturn is cleared (does not wait full 100ms)',
        () async {
      var getPermissionStatusCallCount = 0;
      service.testGetPermissionStatusOverride = () async {
        getPermissionStatusCallCount++;
        return NotificationPermissionStatus.denied;
      };

      service.onSystemNotificationSettingsOpenedForTesting = (info) async {};
      service.waitingForSettingsReturnForTesting = true;
      service.setupLifecycleListenerForTesting();

      // Simulate resume — starts polling.
      AppLifecycleService().didChangeAppLifecycleState(
        AppLifecycleState.resumed,
      );

      // The listener's first action after entering the try block is the while
      // loop, which does await Future.delayed(10ms). Clear the flag
      // synchronously after the listener starts — it will be visible on the
      // listener's first loop check (~10ms later).
      service.waitingForSettingsReturnForTesting = false;

      // At 50ms, the listener should have already exited. If it waited the
      // full 100ms, the guard would still be active at this point.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Guard reset proves the listener completed (exited early).
      expect(service.lifecycleResumeHandlerActiveForTesting, isFalse,
          reason: 'Lifecycle listener should exit early (at ~10ms), not wait '
              'the full 100ms polling window');
      // Handler should NOT have run.
      expect(getPermissionStatusCallCount, 0);
    });

    test('6.4: lifecycle listener runs _handleResumeAfterSettings immediately '
        '(no polling) when _onSystemNotificationSettingsOpened is null',
        () async {
      var getPermissionStatusCallCount = 0;
      service.testGetPermissionStatusOverride = () async {
        getPermissionStatusCallCount++;
        return NotificationPermissionStatus.denied;
      };

      // Do NOT set onSystemNotificationSettingsOpened — it's null.
      // The lifecycle listener should skip polling entirely.
      service.waitingForSettingsReturnForTesting = true;
      service.setupLifecycleListenerForTesting();

      // Simulate resume.
      AppLifecycleService().didChangeAppLifecycleState(
        AppLifecycleState.resumed,
      );

      // With no deep link callback, the listener should run immediately
      // (no 100ms polling delay). A brief yield is needed for the async
      // listener body to execute after the synchronous stream dispatch.
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // _handleResumeAfterSettings should have run — it calls
      // getPermissionStatus().
      expect(getPermissionStatusCallCount, 1,
          reason: '_handleResumeAfterSettings should run immediately when '
              '_onSystemNotificationSettingsOpened is null');
      expect(service.waitingForSettingsReturnForTesting, isFalse);
      expect(service.lifecycleResumeHandlerActiveForTesting, isFalse);
    });
  });

  // =========================================================================
  // 6.5–6.8  Lifecycle resume handler guard
  // =========================================================================
  group('Lifecycle Resume Handler Guard', () {
    test('6.5: _lifecycleResumeHandlerActive prevents duplicate entry '
        'during polling', () async {
      var getPermissionStatusCallCount = 0;
      service.testGetPermissionStatusOverride = () async {
        getPermissionStatusCallCount++;
        return NotificationPermissionStatus.denied;
      };

      // Deep link callback registered → enables polling.
      service.onSystemNotificationSettingsOpenedForTesting = (info) async {};
      service.waitingForSettingsReturnForTesting = true;
      service.setupLifecycleListenerForTesting();

      // Fire first resume — enters polling loop, sets guard.
      AppLifecycleService().didChangeAppLifecycleState(
        AppLifecycleState.resumed,
      );

      // The listener is now suspended in await Future.delayed(10ms).
      // _lifecycleResumeHandlerActive is true.
      // A brief yield allows the listener to reach the polling loop.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(service.lifecycleResumeHandlerActiveForTesting, isTrue);

      // Fire second resume — should be dropped by the guard.
      AppLifecycleService().didChangeAppLifecycleState(
        AppLifecycleState.resumed,
      );

      // Let the polling complete naturally (100ms max + margin).
      // Clear the flag so the first listener proceeds to
      // _handleResumeAfterSettings.
      await Future<void>.delayed(const Duration(milliseconds: 150));

      // Only one invocation of _handleResumeAfterSettings should have
      // occurred (from the first listener, after the polling window expired).
      expect(getPermissionStatusCallCount, 1,
          reason: 'Only the first lifecycle listener should proceed; '
              'the second should be dropped by the guard');
    });

    test('6.6: _lifecycleResumeHandlerActive reset to false after normal '
        'completion (finally block)', () async {
      service.testGetPermissionStatusOverride =
          () async => NotificationPermissionStatus.denied;

      // No deep link callback → no polling, immediate execution.
      service.waitingForSettingsReturnForTesting = true;
      service.setupLifecycleListenerForTesting();

      AppLifecycleService().didChangeAppLifecycleState(
        AppLifecycleState.resumed,
      );

      // Wait for the listener to complete.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(service.lifecycleResumeHandlerActiveForTesting, isFalse,
          reason: 'Guard should be reset by finally block after normal '
              'completion');
    });

    test('6.7: _lifecycleResumeHandlerActive reset to false after handler '
        'throws (finally block)', () async {
      service.testGetPermissionStatusOverride = () async {
        throw Exception('Firebase error in _handleResumeAfterSettings');
      };

      // No deep link callback → no polling, immediate execution.
      // _handleResumeAfterSettings will throw because getPermissionStatus
      // throws. Since _handleResumeAfterSettings() is called without await
      // in the lifecycle listener, its exception becomes an unhandled Zone
      // error. The finally block still resets the guard because it runs
      // immediately after the fire-and-forget invocation.
      //
      // We set up the listener inside runZonedGuarded so that the unhandled
      // async error is captured by the zone error handler rather than
      // propagating to the test framework (which would fail the test).
      service.waitingForSettingsReturnForTesting = true;

      final caughtErrors = <Object>[];
      await runZonedGuarded(() async {
        service.setupLifecycleListenerForTesting();

        AppLifecycleService().didChangeAppLifecycleState(
          AppLifecycleState.resumed,
        );

        // Wait for the listener to complete (including the error path).
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }, (error, stack) {
        caughtErrors.add(error);
      });

      expect(service.lifecycleResumeHandlerActiveForTesting, isFalse,
          reason: 'Guard should be reset by finally block even when the '
              'handler throws');
      // Confirm the error was actually raised (not silently swallowed).
      expect(caughtErrors, isNotEmpty,
          reason: 'The _handleResumeAfterSettings error should have been '
              'caught by the zone error handler');
    });

    test('6.8: _lifecycleResumeHandlerActive reset to false by '
        'cleanup/dispose', () async {
      // Manually set the guard to true (simulating mid-handling state).
      service.lifecycleResumeHandlerActiveForTesting = true;
      expect(service.lifecycleResumeHandlerActiveForTesting, isTrue);

      await service.dispose();

      expect(service.lifecycleResumeHandlerActiveForTesting, isFalse);
    });
  });

  // =========================================================================
  // 6.9–6.10  Cold launch pending intent
  // =========================================================================
  group('Cold Launch Pending Intent', () {
    test('6.9: getPendingSettingsIntent called during initialize(), callback '
        'invoked if pending', () async {
      // Set up the deep link callback to capture the info.
      NotificationSettingsDeepLinkInfo? receivedInfo;
      service.onSystemNotificationSettingsOpenedForTesting = (info) async {
        receivedInfo = info;
      };

      // Set up the method channel with a mock that returns a pending intent.
      const channel =
          MethodChannel(NotificationService.notificationSettingsChannelName);
      service.settingsChannelForTesting = channel;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getPendingSettingsIntent') {
          return <String, dynamic>{'channelId': 'test_pending_channel'};
        }
        return null;
      });

      // Override Firebase-dependent methods so _handleSettingsDeepLink works.
      service.testGetNotificationDenialInfoOverride = () async => null;
      service.testGetPermissionStatusOverride =
          () async => NotificationPermissionStatus.authorized;

      // Call the pending intent check (mirrors initialize() logic).
      await service.checkPendingSettingsIntentForTesting();

      // The deep link callback should have been invoked with the pending data.
      expect(receivedInfo, isNotNull);
      expect(receivedInfo!.channelId, 'test_pending_channel');
      expect(receivedInfo!.permissionStatus,
          NotificationPermissionStatus.authorized);

      // Clean up mock.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('6.10: MissingPluginException from getPendingSettingsIntent caught '
        'gracefully (native setup not configured)', () async {
      // Set up the deep link callback.
      var callbackInvoked = false;
      service.onSystemNotificationSettingsOpenedForTesting = (info) async {
        callbackInvoked = true;
      };

      // Set up the method channel WITHOUT a mock handler — invokeMethod will
      // throw MissingPluginException because no platform handler exists.
      const channel =
          MethodChannel(NotificationService.notificationSettingsChannelName);
      service.settingsChannelForTesting = channel;

      // Should not throw — MissingPluginException is caught internally.
      await service.checkPendingSettingsIntentForTesting();

      // Callback should NOT have been invoked — there was no pending intent.
      expect(callbackInvoked, isFalse);
    });

    test('6.9 (no pending): getPendingSettingsIntent returns null — no '
        'callback invocation', () async {
      var callbackInvoked = false;
      service.onSystemNotificationSettingsOpenedForTesting = (info) async {
        callbackInvoked = true;
      };

      const channel =
          MethodChannel(NotificationService.notificationSettingsChannelName);
      service.settingsChannelForTesting = channel;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getPendingSettingsIntent') {
          return null; // No pending intent.
        }
        return null;
      });

      await service.checkPendingSettingsIntentForTesting();

      expect(callbackInvoked, isFalse,
          reason: 'No pending intent means no callback invocation');

      // Clean up mock.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
  });

  // =========================================================================
  // 6.11–6.12  providesAppNotificationSettings
  // =========================================================================
  group('requestPermissions — providesAppNotificationSettings', () {
    test('6.11: providesAppNotificationSettings is true when callback is '
        'registered', () {
      service.onSystemNotificationSettingsOpenedForTesting = (info) async {};

      expect(service.providesAppNotificationSettingsForTesting, isTrue,
          reason: 'providesAppNotificationSettings should be true when '
              'onSystemNotificationSettingsOpened is registered');
    });

    test('6.12: providesAppNotificationSettings is false when callback is '
        'not registered', () {
      // onSystemNotificationSettingsOpened is null by default.
      expect(service.providesAppNotificationSettingsForTesting, isFalse,
          reason: 'providesAppNotificationSettings should be false when '
              'onSystemNotificationSettingsOpened is not registered');
    });
  });

  // =========================================================================
  // 6.13  Cleanup
  // =========================================================================
  group('Cleanup', () {
    test('6.13: cleanup nulls out channel handler and callback', () async {
      // Set up state that should be cleaned.
      service.onSystemNotificationSettingsOpenedForTesting = (info) async {};
      service.settingsChannelForTesting =
          const MethodChannel(NotificationService.notificationSettingsChannelName);
      service.handlingDeepLinkForTesting = true;
      service.lifecycleResumeHandlerActiveForTesting = true;
      service.waitingForSettingsReturnForTesting = true;

      // Verify state is set.
      expect(
          service.onSystemNotificationSettingsOpenedGetterForTesting, isNotNull);
      expect(service.settingsChannelForTesting, isNotNull);
      expect(service.handlingDeepLinkForTesting, isTrue);
      expect(service.lifecycleResumeHandlerActiveForTesting, isTrue);
      expect(service.waitingForSettingsReturnForTesting, isTrue);

      // Dispose cleans up everything.
      await service.dispose();

      expect(service.onSystemNotificationSettingsOpenedGetterForTesting, isNull,
          reason: 'Callback should be nulled out by dispose');
      expect(service.settingsChannelForTesting, isNull,
          reason: 'Channel should be nulled out by dispose');
      expect(service.handlingDeepLinkForTesting, isFalse,
          reason: '_handlingDeepLink should be reset by dispose');
      expect(service.lifecycleResumeHandlerActiveForTesting, isFalse,
          reason: '_lifecycleResumeHandlerActive should be reset by dispose');
      expect(service.waitingForSettingsReturnForTesting, isFalse,
          reason: '_waitingForSettingsReturn should be reset by dispose');
    });
  });
}
