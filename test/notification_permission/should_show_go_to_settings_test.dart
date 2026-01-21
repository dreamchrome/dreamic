import 'package:dreamic/notifications/notification_types.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for the "should show go to settings prompt" logic.
///
/// This logic determines whether to show the "go to settings" prompt
/// based on previous prompt history and config limits.
/// The actual implementation is in NotificationService._shouldShowGoToSettingsPrompt().

/// Standalone version of the shouldShowGoToSettingsPrompt logic for testing.
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

void main() {
  group('shouldShowGoToSettingsPrompt', () {
    group('when info is null (never shown)', () {
      test('returns true with default config', () {
        const config = NotificationFlowConfig();
        expect(shouldShowGoToSettingsPrompt(null, config), isTrue);
      });

      test('returns true with custom config', () {
        const config = NotificationFlowConfig(
          goToSettingsMaxAskCount: 1,
          goToSettingsAskAgainAfter: Duration(days: 60),
        );
        expect(shouldShowGoToSettingsPrompt(null, config), isTrue);
      });

      test('returns true even with goToSettingsMaxAskCount of 0', () {
        // Note: The config.showGoToSettingsPrompt check is separate from this logic
        // This function assumes the caller already checked showGoToSettingsPrompt
        const config = NotificationFlowConfig(goToSettingsMaxAskCount: 0);
        expect(shouldShowGoToSettingsPrompt(null, config), isTrue);
      });
    });

    group('when goToSettingsMaxAskCount is set', () {
      test('returns false when promptCount >= goToSettingsMaxAskCount', () {
        final info = GoToSettingsPromptInfo(
          lastPromptTime: DateTime.now().subtract(const Duration(days: 60)),
          promptCount: 2,
          lastActionWasOpenSettings: false,
        );
        const config = NotificationFlowConfig(goToSettingsMaxAskCount: 2);

        expect(shouldShowGoToSettingsPrompt(info, config), isFalse);
      });

      test('returns false when promptCount exceeds goToSettingsMaxAskCount', () {
        final info = GoToSettingsPromptInfo(
          lastPromptTime: DateTime.now().subtract(const Duration(days: 60)),
          promptCount: 5,
          lastActionWasOpenSettings: true,
        );
        const config = NotificationFlowConfig(goToSettingsMaxAskCount: 2);

        expect(shouldShowGoToSettingsPrompt(info, config), isFalse);
      });

      test('returns true when promptCount < goToSettingsMaxAskCount and timing ok', () {
        final info = GoToSettingsPromptInfo(
          lastPromptTime: DateTime.now().subtract(const Duration(days: 45)),
          promptCount: 2,
          lastActionWasOpenSettings: false,
        );
        const config = NotificationFlowConfig(
          goToSettingsAskAgainAfter: Duration(days: 30),
          goToSettingsMaxAskCount: 5,
        );

        expect(shouldShowGoToSettingsPrompt(info, config), isTrue);
      });
    });

    group('when goToSettingsMaxAskCount is null (unlimited)', () {
      test('returns true regardless of promptCount when timing is ok', () {
        final info = GoToSettingsPromptInfo(
          lastPromptTime: DateTime.now().subtract(const Duration(days: 45)),
          promptCount: 100,
          lastActionWasOpenSettings: false,
        );
        const config = NotificationFlowConfig(
          goToSettingsAskAgainAfter: Duration(days: 30),
          goToSettingsMaxAskCount: null, // unlimited
        );

        expect(shouldShowGoToSettingsPrompt(info, config), isTrue);
      });

      test('returns false when timing not met even with unlimited count', () {
        final info = GoToSettingsPromptInfo(
          lastPromptTime: DateTime.now().subtract(const Duration(days: 15)),
          promptCount: 10,
          lastActionWasOpenSettings: false,
        );
        const config = NotificationFlowConfig(
          goToSettingsAskAgainAfter: Duration(days: 30),
          goToSettingsMaxAskCount: null,
        );

        expect(shouldShowGoToSettingsPrompt(info, config), isFalse);
      });
    });

    group('timing constraints', () {
      test('returns false when not enough time has passed', () {
        final info = GoToSettingsPromptInfo(
          lastPromptTime: DateTime.now().subtract(const Duration(days: 15)),
          promptCount: 1,
          lastActionWasOpenSettings: false,
        );
        const config = NotificationFlowConfig(
          goToSettingsAskAgainAfter: Duration(days: 30),
          goToSettingsMaxAskCount: 5,
        );

        expect(shouldShowGoToSettingsPrompt(info, config), isFalse);
      });

      test('returns true when enough time has passed', () {
        final info = GoToSettingsPromptInfo(
          lastPromptTime: DateTime.now().subtract(const Duration(days: 45)),
          promptCount: 1,
          lastActionWasOpenSettings: false,
        );
        const config = NotificationFlowConfig(
          goToSettingsAskAgainAfter: Duration(days: 30),
          goToSettingsMaxAskCount: 5,
        );

        expect(shouldShowGoToSettingsPrompt(info, config), isTrue);
      });

      test('returns true when exactly enough time has passed', () {
        final info = GoToSettingsPromptInfo(
          lastPromptTime: DateTime.now().subtract(const Duration(days: 30)),
          promptCount: 1,
          lastActionWasOpenSettings: false,
        );
        const config = NotificationFlowConfig(
          goToSettingsAskAgainAfter: Duration(days: 30),
          goToSettingsMaxAskCount: 5,
        );

        expect(shouldShowGoToSettingsPrompt(info, config), isTrue);
      });

      test('returns true with Duration.zero goToSettingsAskAgainAfter', () {
        final info = GoToSettingsPromptInfo(
          lastPromptTime: DateTime.now(),
          promptCount: 1,
          lastActionWasOpenSettings: false,
        );
        const config = NotificationFlowConfig(
          goToSettingsAskAgainAfter: Duration.zero,
          goToSettingsMaxAskCount: 5,
        );

        expect(shouldShowGoToSettingsPrompt(info, config), isTrue);
      });
    });

    group('lastActionWasOpenSettings', () {
      test('does not affect the decision (for completeness)', () {
        // lastActionWasOpenSettings is tracked for analytics but doesn't affect
        // whether to show the prompt again
        final infoOpened = GoToSettingsPromptInfo(
          lastPromptTime: DateTime.now().subtract(const Duration(days: 45)),
          promptCount: 1,
          lastActionWasOpenSettings: true,
        );
        final infoDeclined = GoToSettingsPromptInfo(
          lastPromptTime: DateTime.now().subtract(const Duration(days: 45)),
          promptCount: 1,
          lastActionWasOpenSettings: false,
        );
        const config = NotificationFlowConfig(
          goToSettingsAskAgainAfter: Duration(days: 30),
          goToSettingsMaxAskCount: 5,
        );

        expect(shouldShowGoToSettingsPrompt(infoOpened, config), isTrue);
        expect(shouldShowGoToSettingsPrompt(infoDeclined, config), isTrue);
      });
    });

    group('edge cases', () {
      test('handles promptCount of 1 with goToSettingsMaxAskCount of 1', () {
        final info = GoToSettingsPromptInfo(
          lastPromptTime: DateTime.now().subtract(const Duration(days: 60)),
          promptCount: 1,
          lastActionWasOpenSettings: false,
        );
        const config = NotificationFlowConfig(goToSettingsMaxAskCount: 1);

        expect(shouldShowGoToSettingsPrompt(info, config), isFalse);
      });

      test('handles very old prompt with low count', () {
        final info = GoToSettingsPromptInfo(
          lastPromptTime: DateTime.now().subtract(const Duration(days: 365)),
          promptCount: 1,
          lastActionWasOpenSettings: false,
        );
        const config = NotificationFlowConfig(
          goToSettingsAskAgainAfter: Duration(days: 30),
          goToSettingsMaxAskCount: 3,
        );

        expect(shouldShowGoToSettingsPrompt(info, config), isTrue);
      });

      test('uses default 30-day timing with default config', () {
        final info = GoToSettingsPromptInfo(
          lastPromptTime: DateTime.now().subtract(const Duration(days: 25)),
          promptCount: 1,
          lastActionWasOpenSettings: false,
        );
        const config = NotificationFlowConfig(); // default: 30 days

        expect(shouldShowGoToSettingsPrompt(info, config), isFalse);

        final infoOlder = GoToSettingsPromptInfo(
          lastPromptTime: DateTime.now().subtract(const Duration(days: 35)),
          promptCount: 1,
          lastActionWasOpenSettings: false,
        );

        expect(shouldShowGoToSettingsPrompt(infoOlder, config), isTrue);
      });
    });
  });
}
