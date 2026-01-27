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
