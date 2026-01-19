import 'package:dreamic/notifications/notification_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NotificationFlowConfig', () {
    group('default values', () {
      test('has correct default values', () {
        const config = NotificationFlowConfig();

        // Re-ask defaults
        expect(config.askAgainAfter, equals(const Duration(days: 7)));
        expect(config.maxAskCount, equals(3));

        // Go-to-settings defaults
        expect(config.showGoToSettingsPrompt, isTrue);
        expect(config.goToSettingsAskAgainAfter, equals(const Duration(days: 30)));
        expect(config.goToSettingsMaxAskCount, isNull);

        // Strings and builders
        expect(config.strings, isA<NotificationFlowStrings>());
        expect(config.valuePropositionBuilder, isNull);
        expect(config.goToSettingsBuilder, isNull);
        expect(config.askAgainBuilder, isNull);
      });
    });

    group('custom values', () {
      test('accepts custom askAgainAfter duration', () {
        const config = NotificationFlowConfig(
          askAgainAfter: Duration(days: 14),
        );

        expect(config.askAgainAfter, equals(const Duration(days: 14)));
      });

      test('accepts custom maxAskCount', () {
        const config = NotificationFlowConfig(
          maxAskCount: 5,
        );

        expect(config.maxAskCount, equals(5));
      });

      test('accepts zero maxAskCount (never ask again)', () {
        const config = NotificationFlowConfig(
          maxAskCount: 0,
        );

        expect(config.maxAskCount, equals(0));
      });

      test('accepts showGoToSettingsPrompt false', () {
        const config = NotificationFlowConfig(
          showGoToSettingsPrompt: false,
        );

        expect(config.showGoToSettingsPrompt, isFalse);
      });

      test('accepts custom goToSettingsAskAgainAfter', () {
        const config = NotificationFlowConfig(
          goToSettingsAskAgainAfter: Duration(days: 60),
        );

        expect(config.goToSettingsAskAgainAfter, equals(const Duration(days: 60)));
      });

      test('accepts Duration.zero for goToSettingsAskAgainAfter', () {
        const config = NotificationFlowConfig(
          goToSettingsAskAgainAfter: Duration.zero,
        );

        expect(config.goToSettingsAskAgainAfter, equals(Duration.zero));
      });

      test('accepts custom goToSettingsMaxAskCount', () {
        const config = NotificationFlowConfig(
          goToSettingsMaxAskCount: 2,
        );

        expect(config.goToSettingsMaxAskCount, equals(2));
      });

      test('accepts zero goToSettingsMaxAskCount (never show)', () {
        const config = NotificationFlowConfig(
          goToSettingsMaxAskCount: 0,
        );

        expect(config.goToSettingsMaxAskCount, equals(0));
      });

      test('accepts custom strings', () {
        const customStrings = NotificationFlowStrings(
          valuePropositionTitle: 'Custom Title',
        );

        const config = NotificationFlowConfig(
          strings: customStrings,
        );

        expect(config.strings.valuePropositionTitle, equals('Custom Title'));
      });
    });

    group('copyWith', () {
      test('creates copy with replaced fields', () {
        const original = NotificationFlowConfig(
          askAgainAfter: Duration(days: 7),
          maxAskCount: 3,
        );

        final copy = original.copyWith(
          askAgainAfter: const Duration(days: 14),
        );

        expect(copy.askAgainAfter, equals(const Duration(days: 14)));
        expect(copy.maxAskCount, equals(3)); // Unchanged
      });

      test('creates copy with replaced go-to-settings config', () {
        const original = NotificationFlowConfig(
          showGoToSettingsPrompt: true,
          goToSettingsMaxAskCount: null,
        );

        final copy = original.copyWith(
          showGoToSettingsPrompt: false,
          goToSettingsMaxAskCount: 2,
        );

        expect(copy.showGoToSettingsPrompt, isFalse);
        expect(copy.goToSettingsMaxAskCount, equals(2));
      });

      test('creates identical copy when no fields specified', () {
        const original = NotificationFlowConfig(
          askAgainAfter: Duration(days: 14),
          maxAskCount: 5,
          showGoToSettingsPrompt: false,
          goToSettingsMaxAskCount: 2,
        );

        final copy = original.copyWith();

        expect(copy.askAgainAfter, equals(original.askAgainAfter));
        expect(copy.maxAskCount, equals(original.maxAskCount));
        expect(copy.showGoToSettingsPrompt, equals(original.showGoToSettingsPrompt));
        expect(copy.goToSettingsMaxAskCount, equals(original.goToSettingsMaxAskCount));
      });

      test('can replace strings via copyWith', () {
        const original = NotificationFlowConfig();

        final copy = original.copyWith(
          strings: const NotificationFlowStrings(
            valuePropositionTitle: 'New Title',
          ),
        );

        expect(copy.strings.valuePropositionTitle, equals('New Title'));
      });
    });
  });

  group('NotificationFlowStrings', () {
    group('default values', () {
      test('has correct default values', () {
        const strings = NotificationFlowStrings();

        // Value proposition
        expect(strings.valuePropositionTitle, equals('Enable Notifications'));
        expect(strings.valuePropositionMessage,
            equals('Stay updated with important alerts and messages.'));
        expect(strings.valuePropositionAcceptButton, equals('Enable'));
        expect(strings.valuePropositionDeclineButton, equals('Not Now'));

        // Go to settings
        expect(strings.goToSettingsTitle, equals('Notifications Disabled'));
        expect(strings.goToSettingsMessage,
            contains('please enable them in your device settings'));
        expect(strings.goToSettingsButton, equals('Open Settings'));
        expect(strings.goToSettingsCancelButton, equals('Cancel'));

        // Ask again
        expect(strings.askAgainTitle, equals('Enable Notifications?'));
        expect(strings.askAgainMessage, contains('previously declined'));
        expect(strings.askAgainAcceptButton, equals('Yes, Enable'));
        expect(strings.askAgainDeclineButton, equals('No Thanks'));

        // Web settings instructions
        expect(strings.webSettingsInstructionsTitle, equals('Enable Notifications'));
        expect(strings.webSettingsInstructionsMessage, contains('lock/info icon'));
        expect(strings.webSettingsInstructionsButton, equals('Got It'));
      });
    });

    group('custom values', () {
      test('accepts custom value proposition strings', () {
        const strings = NotificationFlowStrings(
          valuePropositionTitle: 'Get Notified',
          valuePropositionMessage: 'Never miss an update!',
          valuePropositionAcceptButton: 'Yes',
          valuePropositionDeclineButton: 'Later',
        );

        expect(strings.valuePropositionTitle, equals('Get Notified'));
        expect(strings.valuePropositionMessage, equals('Never miss an update!'));
        expect(strings.valuePropositionAcceptButton, equals('Yes'));
        expect(strings.valuePropositionDeclineButton, equals('Later'));
      });

      test('accepts custom go-to-settings strings', () {
        const strings = NotificationFlowStrings(
          goToSettingsTitle: 'Notifications Off',
          goToSettingsMessage: 'Turn on in Settings',
          goToSettingsButton: 'Go to Settings',
          goToSettingsCancelButton: 'No Thanks',
        );

        expect(strings.goToSettingsTitle, equals('Notifications Off'));
        expect(strings.goToSettingsMessage, equals('Turn on in Settings'));
        expect(strings.goToSettingsButton, equals('Go to Settings'));
        expect(strings.goToSettingsCancelButton, equals('No Thanks'));
      });

      test('accepts custom web instructions', () {
        const strings = NotificationFlowStrings(
          webSettingsInstructionsTitle: 'Browser Notifications',
          webSettingsInstructionsMessage: 'Click the padlock icon',
          webSettingsInstructionsButton: 'OK',
        );

        expect(strings.webSettingsInstructionsTitle, equals('Browser Notifications'));
        expect(strings.webSettingsInstructionsMessage, equals('Click the padlock icon'));
        expect(strings.webSettingsInstructionsButton, equals('OK'));
      });
    });

    group('copyWith', () {
      test('creates copy with replaced fields', () {
        const original = NotificationFlowStrings(
          valuePropositionTitle: 'Original',
          askAgainTitle: 'Original Ask Again',
        );

        final copy = original.copyWith(
          valuePropositionTitle: 'New Title',
        );

        expect(copy.valuePropositionTitle, equals('New Title'));
        expect(copy.askAgainTitle, equals('Original Ask Again')); // Unchanged
      });

      test('creates identical copy when no fields specified', () {
        const original = NotificationFlowStrings(
          valuePropositionTitle: 'Custom Title',
          valuePropositionMessage: 'Custom Message',
        );

        final copy = original.copyWith();

        expect(copy.valuePropositionTitle, equals(original.valuePropositionTitle));
        expect(copy.valuePropositionMessage, equals(original.valuePropositionMessage));
      });
    });
  });
}
