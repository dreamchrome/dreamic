import 'package:dreamic/notifications/notification_types.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for the "should ask again" logic used in notification permission flows.
///
/// This logic determines whether to prompt the user again after a previous denial.
/// The actual implementation is in NotificationService._shouldAskAgain().
/// These tests verify the expected behavior based on denial info and config.

/// Standalone version of the shouldAskAgain logic for testing.
/// Mirrors the implementation in NotificationService._shouldAskAgain().
bool shouldAskAgain(NotificationDenialInfo? info, NotificationFlowConfig config) {
  if (info == null) return true;
  if (info.isPermanent) return false;
  if (info.denialCount >= config.maxAskCount) return false;

  final timeSinceDenial = DateTime.now().difference(info.lastDenialTime);
  return timeSinceDenial >= config.askAgainAfter;
}

void main() {
  group('shouldAskAgain', () {
    group('when info is null (never asked)', () {
      test('returns true with default config', () {
        const config = NotificationFlowConfig();
        expect(shouldAskAgain(null, config), isTrue);
      });

      test('returns true with custom config', () {
        const config = NotificationFlowConfig(
          maxAskCount: 1,
          askAgainAfter: Duration(days: 30),
        );
        expect(shouldAskAgain(null, config), isTrue);
      });
    });

    group('when isPermanent is true', () {
      test('returns false regardless of other factors', () {
        final info = NotificationDenialInfo(
          lastDenialTime: DateTime.now().subtract(const Duration(days: 365)),
          denialCount: 1,
          isPermanent: true,
        );
        const config = NotificationFlowConfig(
          maxAskCount: 100,
          askAgainAfter: Duration.zero,
        );

        expect(shouldAskAgain(info, config), isFalse);
      });
    });

    group('when denialCount >= maxAskCount', () {
      test('returns false when denial count equals max ask count', () {
        final info = NotificationDenialInfo(
          lastDenialTime: DateTime.now().subtract(const Duration(days: 30)),
          denialCount: 3,
          isPermanent: false,
        );
        const config = NotificationFlowConfig(maxAskCount: 3);

        expect(shouldAskAgain(info, config), isFalse);
      });

      test('returns false when denial count exceeds max ask count', () {
        final info = NotificationDenialInfo(
          lastDenialTime: DateTime.now().subtract(const Duration(days: 30)),
          denialCount: 5,
          isPermanent: false,
        );
        const config = NotificationFlowConfig(maxAskCount: 3);

        expect(shouldAskAgain(info, config), isFalse);
      });

      test('returns false with maxAskCount of 0 (never ask again)', () {
        final info = NotificationDenialInfo(
          lastDenialTime: DateTime.now().subtract(const Duration(days: 30)),
          denialCount: 1,
          isPermanent: false,
        );
        const config = NotificationFlowConfig(maxAskCount: 0);

        expect(shouldAskAgain(info, config), isFalse);
      });
    });

    group('timing constraints', () {
      test('returns false when not enough time has passed', () {
        final info = NotificationDenialInfo(
          lastDenialTime: DateTime.now().subtract(const Duration(days: 3)),
          denialCount: 1,
          isPermanent: false,
        );
        const config = NotificationFlowConfig(
          askAgainAfter: Duration(days: 7),
          maxAskCount: 5,
        );

        expect(shouldAskAgain(info, config), isFalse);
      });

      test('returns true when enough time has passed', () {
        final info = NotificationDenialInfo(
          lastDenialTime: DateTime.now().subtract(const Duration(days: 10)),
          denialCount: 2,
          isPermanent: false,
        );
        const config = NotificationFlowConfig(
          askAgainAfter: Duration(days: 7),
          maxAskCount: 5,
        );

        expect(shouldAskAgain(info, config), isTrue);
      });

      test('returns true when exactly enough time has passed', () {
        final info = NotificationDenialInfo(
          lastDenialTime: DateTime.now().subtract(const Duration(days: 7)),
          denialCount: 1,
          isPermanent: false,
        );
        const config = NotificationFlowConfig(
          askAgainAfter: Duration(days: 7),
          maxAskCount: 5,
        );

        expect(shouldAskAgain(info, config), isTrue);
      });

      test('returns true with Duration.zero askAgainAfter', () {
        final info = NotificationDenialInfo(
          lastDenialTime: DateTime.now(),
          denialCount: 1,
          isPermanent: false,
        );
        const config = NotificationFlowConfig(
          askAgainAfter: Duration.zero,
          maxAskCount: 5,
        );

        expect(shouldAskAgain(info, config), isTrue);
      });
    });

    group('combined conditions', () {
      test('returns true when all conditions are met', () {
        final info = NotificationDenialInfo(
          lastDenialTime: DateTime.now().subtract(const Duration(days: 14)),
          denialCount: 1,
          isPermanent: false,
        );
        const config = NotificationFlowConfig(
          askAgainAfter: Duration(days: 7),
          maxAskCount: 3,
        );

        expect(shouldAskAgain(info, config), isTrue);
      });

      test('returns false when under count but not enough time', () {
        final info = NotificationDenialInfo(
          lastDenialTime: DateTime.now().subtract(const Duration(days: 3)),
          denialCount: 1,
          isPermanent: false,
        );
        const config = NotificationFlowConfig(
          askAgainAfter: Duration(days: 7),
          maxAskCount: 3,
        );

        expect(shouldAskAgain(info, config), isFalse);
      });

      test('returns false when enough time but at count limit', () {
        final info = NotificationDenialInfo(
          lastDenialTime: DateTime.now().subtract(const Duration(days: 30)),
          denialCount: 3,
          isPermanent: false,
        );
        const config = NotificationFlowConfig(
          askAgainAfter: Duration(days: 7),
          maxAskCount: 3,
        );

        expect(shouldAskAgain(info, config), isFalse);
      });
    });

    group('edge cases', () {
      test('handles denial count of 1 with maxAskCount of 1', () {
        final info = NotificationDenialInfo(
          lastDenialTime: DateTime.now().subtract(const Duration(days: 30)),
          denialCount: 1,
          isPermanent: false,
        );
        const config = NotificationFlowConfig(
          askAgainAfter: Duration(days: 7),
          maxAskCount: 1,
        );

        expect(shouldAskAgain(info, config), isFalse);
      });

      test('handles very old denial with low count', () {
        final info = NotificationDenialInfo(
          lastDenialTime: DateTime.now().subtract(const Duration(days: 365)),
          denialCount: 1,
          isPermanent: false,
        );
        const config = NotificationFlowConfig(
          askAgainAfter: Duration(days: 7),
          maxAskCount: 3,
        );

        expect(shouldAskAgain(info, config), isTrue);
      });
    });
  });
}
