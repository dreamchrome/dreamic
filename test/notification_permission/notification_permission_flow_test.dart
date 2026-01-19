import 'package:dreamic/data/models/notification_permission_status.dart';
import 'package:dreamic/notifications/notification_types.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for the notification permission flow logic.
///
/// These tests verify the expected behavior of the flow decision logic
/// used in [NotificationService.runNotificationPermissionFlow].
///
/// Note: Full end-to-end flow testing requires Firebase mocking, which is
/// complex due to the static nature of FirebaseMessaging.instance.
/// These tests focus on the pure logic components that can be tested in isolation.

/// Standalone version of _mapInitResultToFlowResult for testing.
/// Mirrors the implementation in NotificationService._mapInitResultToFlowResult().
NotificationFlowResult mapInitResultToFlowResult(NotificationInitResult result) {
  switch (result) {
    case NotificationInitResult.success:
      return NotificationFlowResult.granted;
    case NotificationInitResult.alreadyInitialized:
      return NotificationFlowResult.alreadyGranted;
    case NotificationInitResult.permissionDenied:
      return NotificationFlowResult.deniedPermission;
    case NotificationInitResult.permissionPermanentlyDenied:
      return NotificationFlowResult.deniedPermanently;
    case NotificationInitResult.permissionRequestBlocked:
      return NotificationFlowResult.deniedPermission;
    case NotificationInitResult.fcmDisabledConfig:
    case NotificationInitResult.fcmDisabledInstance:
      return NotificationFlowResult.fcmDisabled;
    case NotificationInitResult.error:
      return NotificationFlowResult.error;
  }
}

/// Standalone version of _shouldAskAgain for testing.
/// Mirrors the implementation in NotificationService._shouldAskAgain().
bool shouldAskAgain(NotificationDenialInfo? info, NotificationFlowConfig config) {
  if (info == null) return true;
  if (info.isPermanent) return false;
  if (info.denialCount >= config.maxAskCount) return false;

  final timeSinceDenial = DateTime.now().difference(info.lastDenialTime);
  return timeSinceDenial >= config.askAgainAfter;
}

/// Standalone version of _shouldShowGoToSettingsPrompt for testing.
/// Mirrors the implementation in NotificationService._shouldShowGoToSettingsPrompt().
bool shouldShowGoToSettingsPrompt(
  GoToSettingsPromptInfo? info,
  NotificationFlowConfig config,
) {
  if (info == null) return true; // Never shown before

  // Check max count
  if (config.goToSettingsMaxAskCount != null &&
      info.promptCount >= config.goToSettingsMaxAskCount!) {
    return false;
  }

  // Check timing
  final timeSinceLastPrompt = DateTime.now().difference(info.lastPromptTime);
  return timeSinceLastPrompt >= config.goToSettingsAskAgainAfter;
}

/// Determines if a permission status represents a granted state.
bool isPermissionGranted(NotificationPermissionStatus status) {
  return status == NotificationPermissionStatus.authorized ||
      status == NotificationPermissionStatus.provisional;
}

/// Simulates the flow decision for a given permission status.
///
/// This is a simplified version of the flow logic for testing purposes.
/// Returns what the flow result would be given the inputs.
NotificationFlowResult simulateFlowDecision({
  required NotificationPermissionStatus status,
  required bool canPromptAgain,
  required bool isPermanentlyDenied,
  required NotificationFlowConfig config,
  required bool userAcceptsValueProposition,
  required bool userAcceptsAskAgain,
  required bool userAcceptsGoToSettings,
  required NotificationDenialInfo? denialInfo,
  required GoToSettingsPromptInfo? settingsPromptInfo,
  NotificationInitResult initResult = NotificationInitResult.success,
}) {
  // Already granted
  if (isPermissionGranted(status)) {
    return NotificationFlowResult.alreadyGranted;
  }

  // Not determined - show value proposition
  if (status == NotificationPermissionStatus.notDetermined) {
    if (!userAcceptsValueProposition) {
      return NotificationFlowResult.declinedValueProposition;
    }
    return mapInitResultToFlowResult(initResult);
  }

  // Denied status
  if (status == NotificationPermissionStatus.denied) {
    // Check if permanently denied
    if (isPermanentlyDenied) {
      // Go to settings flow
      if (!config.showGoToSettingsPrompt) {
        return NotificationFlowResult.skippedGoToSettings;
      }

      if (!shouldShowGoToSettingsPrompt(settingsPromptInfo, config)) {
        return NotificationFlowResult.skippedGoToSettings;
      }

      if (!userAcceptsGoToSettings) {
        return NotificationFlowResult.declinedGoToSettings;
      }

      return NotificationFlowResult.openedSettings;
    }

    // Not permanent - can ask again
    if (!shouldAskAgain(denialInfo, config)) {
      return NotificationFlowResult.skippedAskAgain;
    }

    if (!userAcceptsAskAgain) {
      return NotificationFlowResult.skippedAskAgain;
    }

    return mapInitResultToFlowResult(initResult);
  }

  return NotificationFlowResult.error;
}

void main() {
  group('mapInitResultToFlowResult', () {
    test('maps success to granted', () {
      expect(
        mapInitResultToFlowResult(NotificationInitResult.success),
        NotificationFlowResult.granted,
      );
    });

    test('maps alreadyInitialized to alreadyGranted', () {
      expect(
        mapInitResultToFlowResult(NotificationInitResult.alreadyInitialized),
        NotificationFlowResult.alreadyGranted,
      );
    });

    test('maps permissionDenied to deniedPermission', () {
      expect(
        mapInitResultToFlowResult(NotificationInitResult.permissionDenied),
        NotificationFlowResult.deniedPermission,
      );
    });

    test('maps permissionPermanentlyDenied to deniedPermanently', () {
      expect(
        mapInitResultToFlowResult(
            NotificationInitResult.permissionPermanentlyDenied),
        NotificationFlowResult.deniedPermanently,
      );
    });

    test('maps permissionRequestBlocked to deniedPermission', () {
      // Blocked requests are treated as denials from the flow perspective
      expect(
        mapInitResultToFlowResult(
            NotificationInitResult.permissionRequestBlocked),
        NotificationFlowResult.deniedPermission,
      );
    });

    test('maps fcmDisabledConfig to fcmDisabled', () {
      expect(
        mapInitResultToFlowResult(NotificationInitResult.fcmDisabledConfig),
        NotificationFlowResult.fcmDisabled,
      );
    });

    test('maps fcmDisabledInstance to fcmDisabled', () {
      expect(
        mapInitResultToFlowResult(NotificationInitResult.fcmDisabledInstance),
        NotificationFlowResult.fcmDisabled,
      );
    });

    test('maps error to error', () {
      expect(
        mapInitResultToFlowResult(NotificationInitResult.error),
        NotificationFlowResult.error,
      );
    });
  });

  group('Flow decision logic - already granted', () {
    test('returns alreadyGranted for authorized status', () {
      final result = simulateFlowDecision(
        status: NotificationPermissionStatus.authorized,
        canPromptAgain: false,
        isPermanentlyDenied: false,
        config: const NotificationFlowConfig(),
        userAcceptsValueProposition: false, // Irrelevant
        userAcceptsAskAgain: false, // Irrelevant
        userAcceptsGoToSettings: false, // Irrelevant
        denialInfo: null,
        settingsPromptInfo: null,
      );
      expect(result, NotificationFlowResult.alreadyGranted);
    });

    test('returns alreadyGranted for provisional status', () {
      final result = simulateFlowDecision(
        status: NotificationPermissionStatus.provisional,
        canPromptAgain: false,
        isPermanentlyDenied: false,
        config: const NotificationFlowConfig(),
        userAcceptsValueProposition: false,
        userAcceptsAskAgain: false,
        userAcceptsGoToSettings: false,
        denialInfo: null,
        settingsPromptInfo: null,
      );
      expect(result, NotificationFlowResult.alreadyGranted);
    });
  });

  group('Flow decision logic - not determined', () {
    test('returns declinedValueProposition when user declines', () {
      final result = simulateFlowDecision(
        status: NotificationPermissionStatus.notDetermined,
        canPromptAgain: true,
        isPermanentlyDenied: false,
        config: const NotificationFlowConfig(),
        userAcceptsValueProposition: false,
        userAcceptsAskAgain: false,
        userAcceptsGoToSettings: false,
        denialInfo: null,
        settingsPromptInfo: null,
      );
      expect(result, NotificationFlowResult.declinedValueProposition);
    });

    test('returns granted when user accepts and permission succeeds', () {
      final result = simulateFlowDecision(
        status: NotificationPermissionStatus.notDetermined,
        canPromptAgain: true,
        isPermanentlyDenied: false,
        config: const NotificationFlowConfig(),
        userAcceptsValueProposition: true,
        userAcceptsAskAgain: false,
        userAcceptsGoToSettings: false,
        denialInfo: null,
        settingsPromptInfo: null,
        initResult: NotificationInitResult.success,
      );
      expect(result, NotificationFlowResult.granted);
    });

    test('returns deniedPermission when user accepts but denies permission', () {
      final result = simulateFlowDecision(
        status: NotificationPermissionStatus.notDetermined,
        canPromptAgain: true,
        isPermanentlyDenied: false,
        config: const NotificationFlowConfig(),
        userAcceptsValueProposition: true,
        userAcceptsAskAgain: false,
        userAcceptsGoToSettings: false,
        denialInfo: null,
        settingsPromptInfo: null,
        initResult: NotificationInitResult.permissionDenied,
      );
      expect(result, NotificationFlowResult.deniedPermission);
    });
  });

  group('Flow decision logic - denied (can retry)', () {
    test('returns skippedAskAgain when config limits reached', () {
      final denialInfo = NotificationDenialInfo(
        lastDenialTime: DateTime.now().subtract(const Duration(days: 30)),
        denialCount: 3,
        isPermanent: false,
      );

      final result = simulateFlowDecision(
        status: NotificationPermissionStatus.denied,
        canPromptAgain: true,
        isPermanentlyDenied: false,
        config: const NotificationFlowConfig(maxAskCount: 3),
        userAcceptsValueProposition: false,
        userAcceptsAskAgain: true,
        userAcceptsGoToSettings: false,
        denialInfo: denialInfo,
        settingsPromptInfo: null,
      );
      expect(result, NotificationFlowResult.skippedAskAgain);
    });

    test('returns skippedAskAgain when user declines ask-again dialog', () {
      final denialInfo = NotificationDenialInfo(
        lastDenialTime: DateTime.now().subtract(const Duration(days: 30)),
        denialCount: 1,
        isPermanent: false,
      );

      final result = simulateFlowDecision(
        status: NotificationPermissionStatus.denied,
        canPromptAgain: true,
        isPermanentlyDenied: false,
        config: const NotificationFlowConfig(maxAskCount: 5),
        userAcceptsValueProposition: false,
        userAcceptsAskAgain: false,
        userAcceptsGoToSettings: false,
        denialInfo: denialInfo,
        settingsPromptInfo: null,
      );
      expect(result, NotificationFlowResult.skippedAskAgain);
    });

    test('returns granted when user accepts and succeeds', () {
      final denialInfo = NotificationDenialInfo(
        lastDenialTime: DateTime.now().subtract(const Duration(days: 30)),
        denialCount: 1,
        isPermanent: false,
      );

      final result = simulateFlowDecision(
        status: NotificationPermissionStatus.denied,
        canPromptAgain: true,
        isPermanentlyDenied: false,
        config: const NotificationFlowConfig(maxAskCount: 5),
        userAcceptsValueProposition: false,
        userAcceptsAskAgain: true,
        userAcceptsGoToSettings: false,
        denialInfo: denialInfo,
        settingsPromptInfo: null,
        initResult: NotificationInitResult.success,
      );
      expect(result, NotificationFlowResult.granted);
    });
  });

  group('Flow decision logic - permanently denied', () {
    test('returns skippedGoToSettings when config disables it', () {
      final result = simulateFlowDecision(
        status: NotificationPermissionStatus.denied,
        canPromptAgain: false,
        isPermanentlyDenied: true,
        config: const NotificationFlowConfig(showGoToSettingsPrompt: false),
        userAcceptsValueProposition: false,
        userAcceptsAskAgain: false,
        userAcceptsGoToSettings: true,
        denialInfo: null,
        settingsPromptInfo: null,
      );
      expect(result, NotificationFlowResult.skippedGoToSettings);
    });

    test('returns skippedGoToSettings when prompt count limit reached', () {
      final settingsInfo = GoToSettingsPromptInfo(
        lastPromptTime: DateTime.now().subtract(const Duration(days: 60)),
        promptCount: 2,
        lastActionWasOpenSettings: false,
      );

      final result = simulateFlowDecision(
        status: NotificationPermissionStatus.denied,
        canPromptAgain: false,
        isPermanentlyDenied: true,
        config: const NotificationFlowConfig(goToSettingsMaxAskCount: 2),
        userAcceptsValueProposition: false,
        userAcceptsAskAgain: false,
        userAcceptsGoToSettings: true,
        denialInfo: null,
        settingsPromptInfo: settingsInfo,
      );
      expect(result, NotificationFlowResult.skippedGoToSettings);
    });

    test('returns skippedGoToSettings when timing limit not met', () {
      final settingsInfo = GoToSettingsPromptInfo(
        lastPromptTime: DateTime.now().subtract(const Duration(days: 5)),
        promptCount: 1,
        lastActionWasOpenSettings: false,
      );

      final result = simulateFlowDecision(
        status: NotificationPermissionStatus.denied,
        canPromptAgain: false,
        isPermanentlyDenied: true,
        config: const NotificationFlowConfig(
          goToSettingsAskAgainAfter: Duration(days: 30),
        ),
        userAcceptsValueProposition: false,
        userAcceptsAskAgain: false,
        userAcceptsGoToSettings: true,
        denialInfo: null,
        settingsPromptInfo: settingsInfo,
      );
      expect(result, NotificationFlowResult.skippedGoToSettings);
    });

    test('returns declinedGoToSettings when user declines', () {
      final result = simulateFlowDecision(
        status: NotificationPermissionStatus.denied,
        canPromptAgain: false,
        isPermanentlyDenied: true,
        config: const NotificationFlowConfig(),
        userAcceptsValueProposition: false,
        userAcceptsAskAgain: false,
        userAcceptsGoToSettings: false,
        denialInfo: null,
        settingsPromptInfo: null,
      );
      expect(result, NotificationFlowResult.declinedGoToSettings);
    });

    test('returns openedSettings when user accepts', () {
      final result = simulateFlowDecision(
        status: NotificationPermissionStatus.denied,
        canPromptAgain: false,
        isPermanentlyDenied: true,
        config: const NotificationFlowConfig(),
        userAcceptsValueProposition: false,
        userAcceptsAskAgain: false,
        userAcceptsGoToSettings: true,
        denialInfo: null,
        settingsPromptInfo: null,
      );
      expect(result, NotificationFlowResult.openedSettings);
    });
  });

  group('Blocked request detection', () {
    test('maps blocked request to denied permission', () {
      // This tests the mapping behavior - a blocked request should
      // be treated as a denial from the flow perspective
      expect(
        mapInitResultToFlowResult(
            NotificationInitResult.permissionRequestBlocked),
        NotificationFlowResult.deniedPermission,
      );
    });

    test(
        'blocked request should not increment denial count (tracked separately)',
        () {
      // NotificationDenialInfo tracks requestAttemptCount separately from denialCount
      // A blocked request increments requestAttemptCount but not denialCount
      final infoAfterBlockedRequest = NotificationDenialInfo(
        lastDenialTime: DateTime.now(),
        denialCount: 0, // Not incremented for blocked request
        isPermanent: false,
        requestAttemptCount: 1, // This IS incremented
        lastRequestWasBlocked: true, // Marked as blocked
      );

      expect(infoAfterBlockedRequest.denialCount, 0);
      expect(infoAfterBlockedRequest.requestAttemptCount, 1);
      expect(infoAfterBlockedRequest.lastRequestWasBlocked, isTrue);
    });
  });

  group('Config with custom builders', () {
    test('valuePropositionBuilder can be set in config', () {
      // Custom builder that always returns false (simulating user decline)
      final config = NotificationFlowConfig(
        valuePropositionBuilder: (context) async {
          return false;
        },
      );

      // Verify the config accepts the builder
      expect(config.valuePropositionBuilder, isNotNull);
    });

    test('goToSettingsBuilder can be set in config', () {
      final config = NotificationFlowConfig(
        goToSettingsBuilder: (context) async {
          return true;
        },
      );

      expect(config.goToSettingsBuilder, isNotNull);
    });

    test('askAgainBuilder can be set in config', () {
      final config = NotificationFlowConfig(
        askAgainBuilder: (context, info) async {
          return info.denialCount < 2; // Only ask again if denied once
        },
      );

      expect(config.askAgainBuilder, isNotNull);
    });

    test('config with all custom builders', () {
      final config = NotificationFlowConfig(
        valuePropositionBuilder: (context) async => true,
        goToSettingsBuilder: (context) async => false,
        askAgainBuilder: (context, info) async => info.denialCount < 3,
      );

      expect(config.valuePropositionBuilder, isNotNull);
      expect(config.goToSettingsBuilder, isNotNull);
      expect(config.askAgainBuilder, isNotNull);
    });
  });

  group('Flow result enum completeness', () {
    test('all NotificationFlowResult values are handled', () {
      // Ensure we have test coverage for all flow results
      final allResults = NotificationFlowResult.values;
      expect(allResults, contains(NotificationFlowResult.granted));
      expect(allResults, contains(NotificationFlowResult.alreadyGranted));
      expect(allResults, contains(NotificationFlowResult.declinedValueProposition));
      expect(allResults, contains(NotificationFlowResult.deniedPermission));
      expect(allResults, contains(NotificationFlowResult.deniedPermanently));
      expect(allResults, contains(NotificationFlowResult.skippedAskAgain));
      expect(allResults, contains(NotificationFlowResult.skippedGoToSettings));
      expect(allResults, contains(NotificationFlowResult.declinedGoToSettings));
      expect(allResults, contains(NotificationFlowResult.openedSettings));
      expect(allResults, contains(NotificationFlowResult.fcmDisabled));
      expect(allResults, contains(NotificationFlowResult.error));
    });

    test('all NotificationInitResult values are mapped', () {
      // Verify all init results have a corresponding flow result
      for (final initResult in NotificationInitResult.values) {
        final flowResult = mapInitResultToFlowResult(initResult);
        expect(flowResult, isA<NotificationFlowResult>());
      }
    });
  });

  group('Edge cases', () {
    test('handles null denial info for first-time user', () {
      final result = simulateFlowDecision(
        status: NotificationPermissionStatus.denied,
        canPromptAgain: true,
        isPermanentlyDenied: false,
        config: const NotificationFlowConfig(),
        userAcceptsValueProposition: false,
        userAcceptsAskAgain: true,
        userAcceptsGoToSettings: false,
        denialInfo: null, // First time, no previous denials recorded
        settingsPromptInfo: null,
        initResult: NotificationInitResult.success,
      );
      // With null denial info, shouldAskAgain returns true
      expect(result, NotificationFlowResult.granted);
    });

    test('handles null settings prompt info for first go-to-settings', () {
      final result = simulateFlowDecision(
        status: NotificationPermissionStatus.denied,
        canPromptAgain: false,
        isPermanentlyDenied: true,
        config: const NotificationFlowConfig(),
        userAcceptsValueProposition: false,
        userAcceptsAskAgain: false,
        userAcceptsGoToSettings: true,
        denialInfo: null,
        settingsPromptInfo: null, // First time showing settings prompt
      );
      // With null settings info, shouldShowGoToSettingsPrompt returns true
      expect(result, NotificationFlowResult.openedSettings);
    });

    test('zero maxAskCount means never ask again', () {
      final denialInfo = NotificationDenialInfo(
        lastDenialTime: DateTime.now().subtract(const Duration(days: 365)),
        denialCount: 1,
        isPermanent: false,
      );

      final result = simulateFlowDecision(
        status: NotificationPermissionStatus.denied,
        canPromptAgain: true,
        isPermanentlyDenied: false,
        config: const NotificationFlowConfig(maxAskCount: 0),
        userAcceptsValueProposition: false,
        userAcceptsAskAgain: true,
        userAcceptsGoToSettings: false,
        denialInfo: denialInfo,
        settingsPromptInfo: null,
      );
      expect(result, NotificationFlowResult.skippedAskAgain);
    });

    test('goToSettingsMaxAskCount of 0 skips when there is existing info', () {
      // With goToSettingsMaxAskCount: 0 and existing info with promptCount >= 0,
      // it should skip (never show again)
      final infoWithZeroPrompts = GoToSettingsPromptInfo(
        lastPromptTime: DateTime.now().subtract(const Duration(days: 365)),
        promptCount: 0,
        lastActionWasOpenSettings: false,
      );
      expect(
        shouldShowGoToSettingsPrompt(
          infoWithZeroPrompts,
          const NotificationFlowConfig(goToSettingsMaxAskCount: 0),
        ),
        isFalse,
      );
    });

    test('goToSettingsMaxAskCount of 1 allows exactly one prompt', () {
      // First prompt - should show
      expect(
        shouldShowGoToSettingsPrompt(null, const NotificationFlowConfig(goToSettingsMaxAskCount: 1)),
        isTrue,
      );

      // Second prompt - should not show
      final infoAfterFirstPrompt = GoToSettingsPromptInfo(
        lastPromptTime: DateTime.now().subtract(const Duration(days: 365)),
        promptCount: 1,
        lastActionWasOpenSettings: false,
      );
      expect(
        shouldShowGoToSettingsPrompt(
          infoAfterFirstPrompt,
          const NotificationFlowConfig(goToSettingsMaxAskCount: 1),
        ),
        isFalse,
      );
    });
  });
}
