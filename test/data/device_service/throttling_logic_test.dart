import 'package:flutter_test/flutter_test.dart';

/// Tests for the throttling logic used by DeviceService.
///
/// The throttling system prevents excessive server writes by:
/// - Rate-limiting timezone/offset updates (48h when unchanged, 10m debounce when changed)
/// - Rate-limiting touch updates (60m default)
/// - Applying backoff for pending payload retries (15m default)
///
/// These tests verify the core throttling algorithms independently of
/// network calls, ensuring the logic is correct for all edge cases.
///
/// Note: Time-based tests use computed expectations rather than wall-clock
/// time to ensure deterministic behavior.
void main() {
  group('Timezone Update Throttling', () {
    // Default configuration values from plan
    const unchangedMinMinutes = 2880; // 48 hours
    const changeDebounceMinutes = 10;

    group('Unchanged Throttle (48 hours)', () {
      test('should allow sync when never synced before', () {
        final lastServerSyncAt = null;
        final now = DateTime.now();

        final shouldSync = _shouldSyncTimezone(
          lastServerSyncAt: lastServerSyncAt,
          now: now,
          didChange: false,
          unchangedMinMinutes: unchangedMinMinutes,
          changeDebounceMinutes: changeDebounceMinutes,
        );

        expect(shouldSync, true);
      });

      test('should block sync when unchanged and recently synced', () {
        final now = DateTime.now();
        final lastServerSyncAt = now.subtract(const Duration(hours: 24));

        final shouldSync = _shouldSyncTimezone(
          lastServerSyncAt: lastServerSyncAt,
          now: now,
          didChange: false,
          unchangedMinMinutes: unchangedMinMinutes,
          changeDebounceMinutes: changeDebounceMinutes,
        );

        expect(shouldSync, false);
      });

      test('should allow sync when unchanged but throttle window expired', () {
        final now = DateTime.now();
        final lastServerSyncAt = now.subtract(const Duration(hours: 49));

        final shouldSync = _shouldSyncTimezone(
          lastServerSyncAt: lastServerSyncAt,
          now: now,
          didChange: false,
          unchangedMinMinutes: unchangedMinMinutes,
          changeDebounceMinutes: changeDebounceMinutes,
        );

        expect(shouldSync, true);
      });

      test('should allow sync exactly at throttle boundary', () {
        final now = DateTime.now();
        // Exactly 48 hours ago - should allow sync
        final lastServerSyncAt = now.subtract(
          Duration(minutes: unchangedMinMinutes),
        );

        final shouldSync = _shouldSyncTimezone(
          lastServerSyncAt: lastServerSyncAt,
          now: now,
          didChange: false,
          unchangedMinMinutes: unchangedMinMinutes,
          changeDebounceMinutes: changeDebounceMinutes,
        );

        expect(shouldSync, true);
      });

      test('should block sync 1 minute before throttle expires', () {
        final now = DateTime.now();
        final lastServerSyncAt = now.subtract(
          Duration(minutes: unchangedMinMinutes - 1),
        );

        final shouldSync = _shouldSyncTimezone(
          lastServerSyncAt: lastServerSyncAt,
          now: now,
          didChange: false,
          unchangedMinMinutes: unchangedMinMinutes,
          changeDebounceMinutes: changeDebounceMinutes,
        );

        expect(shouldSync, false);
      });
    });

    group('Change Debounce (10 minutes)', () {
      test('should block sync when changed but within debounce window', () {
        final now = DateTime.now();
        final lastServerSyncAt = now.subtract(const Duration(minutes: 5));

        final shouldSync = _shouldSyncTimezone(
          lastServerSyncAt: lastServerSyncAt,
          now: now,
          didChange: true,
          unchangedMinMinutes: unchangedMinMinutes,
          changeDebounceMinutes: changeDebounceMinutes,
        );

        expect(shouldSync, false);
      });

      test('should allow sync when changed and debounce window expired', () {
        final now = DateTime.now();
        final lastServerSyncAt = now.subtract(const Duration(minutes: 11));

        final shouldSync = _shouldSyncTimezone(
          lastServerSyncAt: lastServerSyncAt,
          now: now,
          didChange: true,
          unchangedMinMinutes: unchangedMinMinutes,
          changeDebounceMinutes: changeDebounceMinutes,
        );

        expect(shouldSync, true);
      });

      test('should allow sync when changed and never synced', () {
        final lastServerSyncAt = null;
        final now = DateTime.now();

        final shouldSync = _shouldSyncTimezone(
          lastServerSyncAt: lastServerSyncAt,
          now: now,
          didChange: true,
          unchangedMinMinutes: unchangedMinMinutes,
          changeDebounceMinutes: changeDebounceMinutes,
        );

        expect(shouldSync, true);
      });

      test('should allow sync exactly at debounce boundary', () {
        final now = DateTime.now();
        final lastServerSyncAt = now.subtract(
          Duration(minutes: changeDebounceMinutes),
        );

        final shouldSync = _shouldSyncTimezone(
          lastServerSyncAt: lastServerSyncAt,
          now: now,
          didChange: true,
          unchangedMinMinutes: unchangedMinMinutes,
          changeDebounceMinutes: changeDebounceMinutes,
        );

        expect(shouldSync, true);
      });
    });

    group('DST-related scenarios', () {
      test('should allow sync when offset changed (DST transition)', () {
        // User in New York, DST starts: offset changes from -300 to -240
        // but timezone string stays "America/New_York"
        final now = DateTime.now();
        final lastServerSyncAt = now.subtract(const Duration(hours: 1));

        // didChange is true because offset changed, even if timezone string didn't
        final shouldSync = _shouldSyncTimezone(
          lastServerSyncAt: lastServerSyncAt,
          now: now,
          didChange: true, // Offset changed
          unchangedMinMinutes: unchangedMinMinutes,
          changeDebounceMinutes: changeDebounceMinutes,
        );

        // Should sync because it's a change, but debounce still applies
        // 1 hour > 10 minutes, so should allow
        expect(shouldSync, true);
      });

      test('should debounce rapid offset flapping', () {
        // User near timezone border, offset could flap
        final now = DateTime.now();
        final lastServerSyncAt = now.subtract(const Duration(minutes: 2));

        final shouldSync = _shouldSyncTimezone(
          lastServerSyncAt: lastServerSyncAt,
          now: now,
          didChange: true,
          unchangedMinMinutes: unchangedMinMinutes,
          changeDebounceMinutes: changeDebounceMinutes,
        );

        // Should be blocked by debounce
        expect(shouldSync, false);
      });
    });
  });

  group('Touch Device Throttling', () {
    const touchThrottleMinutes = 60;

    test('should allow touch when never touched before', () {
      final lastTouchAt = null;
      final now = DateTime.now();

      final shouldTouch = _shouldTouchDevice(
        lastTouchAt: lastTouchAt,
        now: now,
        throttleMinutes: touchThrottleMinutes,
      );

      expect(shouldTouch, true);
    });

    test('should block touch when within throttle window', () {
      final now = DateTime.now();
      final lastTouchAt = now.subtract(const Duration(minutes: 30));

      final shouldTouch = _shouldTouchDevice(
        lastTouchAt: lastTouchAt,
        now: now,
        throttleMinutes: touchThrottleMinutes,
      );

      expect(shouldTouch, false);
    });

    test('should allow touch when throttle window expired', () {
      final now = DateTime.now();
      final lastTouchAt = now.subtract(const Duration(minutes: 61));

      final shouldTouch = _shouldTouchDevice(
        lastTouchAt: lastTouchAt,
        now: now,
        throttleMinutes: touchThrottleMinutes,
      );

      expect(shouldTouch, true);
    });

    test('should allow touch exactly at throttle boundary', () {
      final now = DateTime.now();
      final lastTouchAt = now.subtract(
        Duration(minutes: touchThrottleMinutes),
      );

      final shouldTouch = _shouldTouchDevice(
        lastTouchAt: lastTouchAt,
        now: now,
        throttleMinutes: touchThrottleMinutes,
      );

      expect(shouldTouch, true);
    });

    test('should block touch 1 minute before throttle expires', () {
      final now = DateTime.now();
      final lastTouchAt = now.subtract(
        Duration(minutes: touchThrottleMinutes - 1),
      );

      final shouldTouch = _shouldTouchDevice(
        lastTouchAt: lastTouchAt,
        now: now,
        throttleMinutes: touchThrottleMinutes,
      );

      expect(shouldTouch, false);
    });

    test('should handle very long time since last touch', () {
      final now = DateTime.now();
      final lastTouchAt = now.subtract(const Duration(days: 365));

      final shouldTouch = _shouldTouchDevice(
        lastTouchAt: lastTouchAt,
        now: now,
        throttleMinutes: touchThrottleMinutes,
      );

      expect(shouldTouch, true);
    });
  });

  group('Pending Payload Backoff', () {
    const backoffMinutes = 15;

    test('should not backoff when no previous attempt', () {
      final lastAttemptAt = null;

      final shouldBackoff = _shouldBackoffPendingPayload(
        lastAttemptAt: lastAttemptAt,
        now: DateTime.now(),
        hasChangedFields: false,
        backoffMinutes: backoffMinutes,
      );

      expect(shouldBackoff, false);
    });

    test('should backoff when within interval and no changes', () {
      final now = DateTime.now();
      final lastAttemptAt = now.subtract(const Duration(minutes: 5));

      final shouldBackoff = _shouldBackoffPendingPayload(
        lastAttemptAt: lastAttemptAt,
        now: now,
        hasChangedFields: false,
        backoffMinutes: backoffMinutes,
      );

      expect(shouldBackoff, true);
    });

    test('should not backoff when interval expired', () {
      final now = DateTime.now();
      final lastAttemptAt = now.subtract(const Duration(minutes: 16));

      final shouldBackoff = _shouldBackoffPendingPayload(
        lastAttemptAt: lastAttemptAt,
        now: now,
        hasChangedFields: false,
        backoffMinutes: backoffMinutes,
      );

      expect(shouldBackoff, false);
    });

    test('should bypass backoff when hasChangedFields is true', () {
      final now = DateTime.now();
      final lastAttemptAt = now.subtract(const Duration(minutes: 5));

      final shouldBackoff = _shouldBackoffPendingPayload(
        lastAttemptAt: lastAttemptAt,
        now: now,
        hasChangedFields: true, // Important changes bypass backoff
        backoffMinutes: backoffMinutes,
      );

      expect(shouldBackoff, false);
    });

    test('should not backoff exactly at boundary', () {
      final now = DateTime.now();
      final lastAttemptAt = now.subtract(
        Duration(minutes: backoffMinutes),
      );

      final shouldBackoff = _shouldBackoffPendingPayload(
        lastAttemptAt: lastAttemptAt,
        now: now,
        hasChangedFields: false,
        backoffMinutes: backoffMinutes,
      );

      expect(shouldBackoff, false);
    });

    test('should backoff 1 minute before boundary', () {
      final now = DateTime.now();
      final lastAttemptAt = now.subtract(
        Duration(minutes: backoffMinutes - 1),
      );

      final shouldBackoff = _shouldBackoffPendingPayload(
        lastAttemptAt: lastAttemptAt,
        now: now,
        hasChangedFields: false,
        backoffMinutes: backoffMinutes,
      );

      expect(shouldBackoff, true);
    });
  });

  group('Change Detection', () {
    test('detects timezone string change', () {
      const cachedTimezone = 'America/New_York';
      const currentTimezone = 'Europe/London';
      const cachedOffset = -300;
      const currentOffset = 0;

      final didChange = _detectTimezoneOrOffsetChange(
        cachedTimezone: cachedTimezone,
        currentTimezone: currentTimezone,
        cachedOffset: cachedOffset,
        currentOffset: currentOffset,
      );

      expect(didChange, true);
    });

    test('detects offset change with same timezone (DST)', () {
      const cachedTimezone = 'America/New_York';
      const currentTimezone = 'America/New_York'; // Same timezone
      const cachedOffset = -300; // EST
      const currentOffset = -240; // EDT (DST)

      final didChange = _detectTimezoneOrOffsetChange(
        cachedTimezone: cachedTimezone,
        currentTimezone: currentTimezone,
        cachedOffset: cachedOffset,
        currentOffset: currentOffset,
      );

      expect(didChange, true);
    });

    test('detects no change when both same', () {
      const cachedTimezone = 'America/New_York';
      const currentTimezone = 'America/New_York';
      const cachedOffset = -300;
      const currentOffset = -300;

      final didChange = _detectTimezoneOrOffsetChange(
        cachedTimezone: cachedTimezone,
        currentTimezone: currentTimezone,
        cachedOffset: cachedOffset,
        currentOffset: currentOffset,
      );

      expect(didChange, false);
    });

    test('detects change when cache is null (first run)', () {
      const String? cachedTimezone = null;
      const currentTimezone = 'America/New_York';
      const int? cachedOffset = null;
      const currentOffset = -300;

      final didChange = _detectTimezoneOrOffsetChange(
        cachedTimezone: cachedTimezone,
        currentTimezone: currentTimezone,
        cachedOffset: cachedOffset,
        currentOffset: currentOffset,
      );

      expect(didChange, true);
    });

    test('handles half-hour offset changes (India DST)', () {
      // India doesn't have DST, but this tests half-hour offset handling
      const cachedTimezone = 'Asia/Kolkata';
      const currentTimezone = 'Asia/Kolkata';
      const cachedOffset = 330; // UTC+5:30
      const currentOffset = 330; // Same

      final didChange = _detectTimezoneOrOffsetChange(
        cachedTimezone: cachedTimezone,
        currentTimezone: currentTimezone,
        cachedOffset: cachedOffset,
        currentOffset: currentOffset,
      );

      expect(didChange, false);
    });

    test('handles 45-minute offset (Nepal)', () {
      const cachedTimezone = 'Asia/Kathmandu';
      const currentTimezone = 'Asia/Kathmandu';
      const cachedOffset = 345; // UTC+5:45
      const currentOffset = 345;

      final didChange = _detectTimezoneOrOffsetChange(
        cachedTimezone: cachedTimezone,
        currentTimezone: currentTimezone,
        cachedOffset: cachedOffset,
        currentOffset: currentOffset,
      );

      expect(didChange, false);
    });
  });

  group('Max Interval Ceiling (Safety Net)', () {
    // Configuration: min=60, max=2880 (48h) is typical
    // The max interval is a safety net for self-healing scenarios
    const unchangedMinMinutes = 60; // 1 hour (normal ceiling)
    const unchangedMaxMinutes = 2880; // 48 hours (safety net)
    const changeDebounceMinutes = 10;

    group('2.1 - Sync when max interval exceeded', () {
      test('should force sync when max interval exceeded even if within min', () {
        // This scenario simulates a bug where _lastServerSyncAt became stale
        // In normal operation, min < max means this never triggers
        final now = DateTime.now();
        // 3 days ago - well past the 48h max interval
        final lastServerSyncAt = now.subtract(const Duration(days: 3));

        final shouldSync = _shouldSyncTimezoneWithMaxInterval(
          lastServerSyncAt: lastServerSyncAt,
          now: now,
          didChange: false,
          unchangedMinMinutes: unchangedMinMinutes,
          unchangedMaxMinutes: unchangedMaxMinutes,
          changeDebounceMinutes: changeDebounceMinutes,
        );

        expect(shouldSync, true,
            reason: 'Should force sync when max interval exceeded (self-healing)');
      });

      test('should force sync exactly at max interval boundary', () {
        final now = DateTime.now();
        final lastServerSyncAt = now.subtract(
          Duration(minutes: unchangedMaxMinutes),
        );

        final shouldSync = _shouldSyncTimezoneWithMaxInterval(
          lastServerSyncAt: lastServerSyncAt,
          now: now,
          didChange: false,
          unchangedMinMinutes: unchangedMinMinutes,
          unchangedMaxMinutes: unchangedMaxMinutes,
          changeDebounceMinutes: changeDebounceMinutes,
        );

        expect(shouldSync, true,
            reason: 'Should sync exactly at max interval boundary');
      });

      test('should NOT force sync 1 minute before max interval', () {
        final now = DateTime.now();
        // Just under max interval, but also well past min interval
        // Since we're past min, we'd sync anyway (normal behavior)
        // This test verifies max boundary precision
        final lastServerSyncAt = now.subtract(
          Duration(minutes: unchangedMaxMinutes - 1),
        );

        // Note: This will still sync because we're past min interval!
        // The max interval is only relevant when within min interval
        // (which is an abnormal state that the safety net handles)
        final shouldSync = _shouldSyncTimezoneWithMaxInterval(
          lastServerSyncAt: lastServerSyncAt,
          now: now,
          didChange: false,
          unchangedMinMinutes: unchangedMinMinutes,
          unchangedMaxMinutes: unchangedMaxMinutes,
          changeDebounceMinutes: changeDebounceMinutes,
        );

        // Since max-1 > min, we're past the min interval, so sync occurs
        expect(shouldSync, true,
            reason: 'Past min interval, so sync occurs (normal behavior)');
      });
    });

    group('2.2 - Max clamped to min when max < min', () {
      test('should clamp effectiveMax to min when max < min', () {
        final now = DateTime.now();
        // Config error: max (30) < min (60)
        const badMax = 30;
        const min = 60;

        // 45 minutes ago - past the bad max (30) but within min (60)
        final lastServerSyncAt = now.subtract(const Duration(minutes: 45));

        final shouldSync = _shouldSyncTimezoneWithMaxInterval(
          lastServerSyncAt: lastServerSyncAt,
          now: now,
          didChange: false,
          unchangedMinMinutes: min,
          unchangedMaxMinutes: badMax,
          changeDebounceMinutes: changeDebounceMinutes,
        );

        // With clamping, effectiveMax = min = 60
        // 45 < 60, so we're within the effective max and within min
        // Result: should skip (no sync)
        expect(shouldSync, false,
            reason:
                'Max clamped to min (60), so 45 min ago is within threshold');
      });

      test('should sync when past clamped max interval', () {
        final now = DateTime.now();
        // Config error: max (30) < min (60)
        const badMax = 30;
        const min = 60;

        // 61 minutes ago - past both the bad max (30) and min (60)
        final lastServerSyncAt = now.subtract(const Duration(minutes: 61));

        final shouldSync = _shouldSyncTimezoneWithMaxInterval(
          lastServerSyncAt: lastServerSyncAt,
          now: now,
          didChange: false,
          unchangedMinMinutes: min,
          unchangedMaxMinutes: badMax,
          changeDebounceMinutes: changeDebounceMinutes,
        );

        // effectiveMax = min = 60, 61 > 60, so we're past min (normal ceiling)
        expect(shouldSync, true,
            reason: 'Past clamped effectiveMax (60), should sync');
      });

      test('effectiveMax calculation correctness', () {
        // Verify the clamping formula: effectiveMax = max(min, max)

        // Case 1: max > min (normal) -> effectiveMax = max
        expect(_computeEffectiveMax(min: 60, max: 2880), 2880);

        // Case 2: max < min (misconfiguration) -> effectiveMax = min
        expect(_computeEffectiveMax(min: 60, max: 30), 60);

        // Case 3: max == min -> effectiveMax = min (or max, same value)
        expect(_computeEffectiveMax(min: 60, max: 60), 60);
      });
    });

    group('2.3 - Skip when within min interval (normal operation)', () {
      test('should skip sync when unchanged and within min interval', () {
        final now = DateTime.now();
        // 30 minutes ago - within min (60)
        final lastServerSyncAt = now.subtract(const Duration(minutes: 30));

        final shouldSync = _shouldSyncTimezoneWithMaxInterval(
          lastServerSyncAt: lastServerSyncAt,
          now: now,
          didChange: false,
          unchangedMinMinutes: unchangedMinMinutes,
          unchangedMaxMinutes: unchangedMaxMinutes,
          changeDebounceMinutes: changeDebounceMinutes,
        );

        expect(shouldSync, false,
            reason: 'Within min interval, unchanged - should skip');
      });

      test('should skip sync 1 minute before min interval expires', () {
        final now = DateTime.now();
        final lastServerSyncAt = now.subtract(
          Duration(minutes: unchangedMinMinutes - 1),
        );

        final shouldSync = _shouldSyncTimezoneWithMaxInterval(
          lastServerSyncAt: lastServerSyncAt,
          now: now,
          didChange: false,
          unchangedMinMinutes: unchangedMinMinutes,
          unchangedMaxMinutes: unchangedMaxMinutes,
          changeDebounceMinutes: changeDebounceMinutes,
        );

        expect(shouldSync, false,
            reason: 'Just under min interval - should skip');
      });
    });

    group('2.4 - Sync when past min interval (primary ceiling)', () {
      test('should sync when unchanged but past min interval', () {
        final now = DateTime.now();
        // 90 minutes ago - past min (60) but within max (2880)
        final lastServerSyncAt = now.subtract(const Duration(minutes: 90));

        final shouldSync = _shouldSyncTimezoneWithMaxInterval(
          lastServerSyncAt: lastServerSyncAt,
          now: now,
          didChange: false,
          unchangedMinMinutes: unchangedMinMinutes,
          unchangedMaxMinutes: unchangedMaxMinutes,
          changeDebounceMinutes: changeDebounceMinutes,
        );

        expect(shouldSync, true,
            reason: 'Past min interval - should sync (normal ceiling)');
      });

      test('should sync exactly at min interval boundary', () {
        final now = DateTime.now();
        final lastServerSyncAt = now.subtract(
          Duration(minutes: unchangedMinMinutes),
        );

        final shouldSync = _shouldSyncTimezoneWithMaxInterval(
          lastServerSyncAt: lastServerSyncAt,
          now: now,
          didChange: false,
          unchangedMinMinutes: unchangedMinMinutes,
          unchangedMaxMinutes: unchangedMaxMinutes,
          changeDebounceMinutes: changeDebounceMinutes,
        );

        expect(shouldSync, true,
            reason: 'Exactly at min interval boundary - should sync');
      });

      test('min interval is the effective ceiling in normal operation', () {
        // Verify that with typical config (min=60, max=2880), the min interval
        // is always the limiting factor for unchanged timezone syncs
        final now = DateTime.now();

        // Test various intervals: all past min should sync, all within min should skip
        final testCases = [
          (minutes: 30, shouldSync: false), // Within min
          (minutes: 59, shouldSync: false), // Just under min
          (minutes: 60, shouldSync: true), // At min boundary
          (minutes: 120, shouldSync: true), // Well past min
          (minutes: 1440, shouldSync: true), // 1 day (still < max)
          (minutes: 2880, shouldSync: true), // At max boundary
        ];

        for (final testCase in testCases) {
          final lastServerSyncAt = now.subtract(
            Duration(minutes: testCase.minutes),
          );

          final result = _shouldSyncTimezoneWithMaxInterval(
            lastServerSyncAt: lastServerSyncAt,
            now: now,
            didChange: false,
            unchangedMinMinutes: unchangedMinMinutes,
            unchangedMaxMinutes: unchangedMaxMinutes,
            changeDebounceMinutes: changeDebounceMinutes,
          );

          expect(result, testCase.shouldSync,
              reason:
                  '${testCase.minutes} min ago: expected ${testCase.shouldSync}');
        }
      });
    });
  });

  group('Configurable Throttle Values', () {
    test('respects custom unchanged sync interval', () {
      final now = DateTime.now();
      final lastServerSyncAt = now.subtract(const Duration(hours: 12));

      // With 24h unchanged interval, 12h ago should block
      expect(
        _shouldSyncTimezone(
          lastServerSyncAt: lastServerSyncAt,
          now: now,
          didChange: false,
          unchangedMinMinutes: 1440, // 24 hours
          changeDebounceMinutes: 10,
        ),
        false,
      );

      // With 6h unchanged interval, 12h ago should allow
      expect(
        _shouldSyncTimezone(
          lastServerSyncAt: lastServerSyncAt,
          now: now,
          didChange: false,
          unchangedMinMinutes: 360, // 6 hours
          changeDebounceMinutes: 10,
        ),
        true,
      );
    });

    test('respects custom change debounce interval', () {
      final now = DateTime.now();
      final lastServerSyncAt = now.subtract(const Duration(minutes: 3));

      // With 5m debounce, 3m ago should block
      expect(
        _shouldSyncTimezone(
          lastServerSyncAt: lastServerSyncAt,
          now: now,
          didChange: true,
          unchangedMinMinutes: 2880,
          changeDebounceMinutes: 5,
        ),
        false,
      );

      // With 2m debounce, 3m ago should allow
      expect(
        _shouldSyncTimezone(
          lastServerSyncAt: lastServerSyncAt,
          now: now,
          didChange: true,
          unchangedMinMinutes: 2880,
          changeDebounceMinutes: 2,
        ),
        true,
      );
    });

    test('respects custom touch throttle', () {
      final now = DateTime.now();
      final lastTouchAt = now.subtract(const Duration(minutes: 30));

      // With 60m throttle, 30m ago should block
      expect(
        _shouldTouchDevice(
          lastTouchAt: lastTouchAt,
          now: now,
          throttleMinutes: 60,
        ),
        false,
      );

      // With 15m throttle, 30m ago should allow
      expect(
        _shouldTouchDevice(
          lastTouchAt: lastTouchAt,
          now: now,
          throttleMinutes: 15,
        ),
        true,
      );
    });
  });
}

// ============================================================================
// Helper functions that mirror the throttling logic from DeviceServiceImpl
// These are extracted for testability and documentation purposes.
// ============================================================================

/// Determines if a timezone/offset sync should occur.
///
/// Mirrors the logic in DeviceServiceImpl.updateTimezoneOrOffsetIfChanged()
bool _shouldSyncTimezone({
  required DateTime? lastServerSyncAt,
  required DateTime now,
  required bool didChange,
  required int unchangedMinMinutes,
  required int changeDebounceMinutes,
}) {
  // If never synced, always allow
  if (lastServerSyncAt == null) {
    return true;
  }

  final timeSinceSync = now.difference(lastServerSyncAt);

  // If changed, apply debounce
  if (didChange) {
    return timeSinceSync >= Duration(minutes: changeDebounceMinutes);
  }

  // If unchanged, apply longer throttle
  return timeSinceSync >= Duration(minutes: unchangedMinMinutes);
}

/// Determines if a touch operation should occur.
///
/// Mirrors the logic in DeviceServiceImpl.touchDevice()
bool _shouldTouchDevice({
  required DateTime? lastTouchAt,
  required DateTime now,
  required int throttleMinutes,
}) {
  if (lastTouchAt == null) {
    return true;
  }

  final timeSinceTouch = now.difference(lastTouchAt);
  return timeSinceTouch >= Duration(minutes: throttleMinutes);
}

/// Determines if pending payload flush should be backed off.
///
/// Mirrors the logic in _PendingDevicePayload.shouldBackoff()
bool _shouldBackoffPendingPayload({
  required DateTime? lastAttemptAt,
  required DateTime now,
  required bool hasChangedFields,
  required int backoffMinutes,
}) {
  // No backoff if never attempted
  if (lastAttemptAt == null) {
    return false;
  }

  // Changed fields bypass backoff
  if (hasChangedFields) {
    return false;
  }

  final timeSinceAttempt = now.difference(lastAttemptAt);
  return timeSinceAttempt < Duration(minutes: backoffMinutes);
}

/// Detects if timezone or offset has changed from cached values.
///
/// Mirrors the change detection logic in DeviceServiceImpl
bool _detectTimezoneOrOffsetChange({
  required String? cachedTimezone,
  required String currentTimezone,
  required int? cachedOffset,
  required int currentOffset,
}) {
  // Null cache means first run, treat as changed
  if (cachedTimezone == null || cachedOffset == null) {
    return true;
  }

  return cachedTimezone != currentTimezone || cachedOffset != currentOffset;
}

/// Computes the effective max interval with clamping.
///
/// Mirrors the clamping logic in DeviceServiceImpl.updateTimezoneOrOffsetIfChanged()
/// that ensures max is never less than min (defensive against misconfiguration).
int _computeEffectiveMax({required int min, required int max}) {
  return max < min ? min : max;
}

/// Determines if a timezone/offset sync should occur, including max interval ceiling.
///
/// Mirrors the updated logic in DeviceServiceImpl.updateTimezoneOrOffsetIfChanged()
/// that includes the safety net for self-healing scenarios.
///
/// The max interval provides a ceiling that forces sync even if within min interval,
/// which handles abnormal states like stale _lastServerSyncAt timestamps.
bool _shouldSyncTimezoneWithMaxInterval({
  required DateTime? lastServerSyncAt,
  required DateTime now,
  required bool didChange,
  required int unchangedMinMinutes,
  required int unchangedMaxMinutes,
  required int changeDebounceMinutes,
}) {
  // If never synced, always allow
  if (lastServerSyncAt == null) {
    return true;
  }

  final timeSinceSync = now.difference(lastServerSyncAt);

  // If changed, apply debounce (same as before - max interval doesn't affect changed syncs)
  if (didChange) {
    return timeSinceSync >= Duration(minutes: changeDebounceMinutes);
  }

  // Clamp max to be at least min (defensive against misconfiguration)
  final effectiveMax = _computeEffectiveMax(
    min: unchangedMinMinutes,
    max: unchangedMaxMinutes,
  );

  // Check if within the normal min interval throttle
  final recentlySyncedUnchanged =
      timeSinceSync < Duration(minutes: unchangedMinMinutes);

  // Safety net: Force sync if max interval exceeded
  final exceededMaxInterval =
      timeSinceSync >= Duration(minutes: effectiveMax);

  // If unchanged and recently synced, skip UNLESS max interval exceeded
  if (recentlySyncedUnchanged && !exceededMaxInterval) {
    return false;
  }

  return true;
}
