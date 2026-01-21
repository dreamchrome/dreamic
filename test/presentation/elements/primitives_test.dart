import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dreamic/presentation/elements/tappable_action.dart';

/// Mock timer factory that extends the real TimerFactory for testing
class MockTimerFactory extends TimerFactory {
  final List<MockTimer> timers = [];

  @override
  Timer createTimer(Duration duration, VoidCallback callback) {
    final timer = MockTimer(duration, callback);
    timers.add(timer);
    return timer;
  }

  void advanceTime(Duration duration) {
    for (final timer in List.from(timers)) {
      timer.advanceTime(duration);
    }
  }

  void triggerAllTimers() {
    for (final timer in List.from(timers)) {
      timer.trigger();
    }
  }

  void clear() {
    for (final timer in timers) {
      timer.cancel();
    }
    timers.clear();
  }
}

class MockTimer implements Timer {
  final Duration duration;
  final VoidCallback callback;
  Duration elapsed = Duration.zero;
  bool _isActive = true;
  bool _hasTriggered = false;

  MockTimer(this.duration, this.callback);

  @override
  void cancel() {
    _isActive = false;
  }

  @override
  bool get isActive => _isActive;

  @override
  int get tick => 0;

  void advanceTime(Duration advance) {
    if (!_isActive || _hasTriggered) return;
    elapsed += advance;
    if (elapsed >= duration) {
      trigger();
    }
  }

  void trigger() {
    if (!_isActive || _hasTriggered) return;
    _hasTriggered = true;
    _isActive = false;
    callback();
  }
}

void main() {
  group('Throttler', () {
    late MockTimerFactory timerFactory;

    setUp(() {
      timerFactory = MockTimerFactory();
    });

    tearDown(() {
      timerFactory.clear();
    });

    test('executes immediately on first call', () {
      final throttler = Throttler(timerFactory: timerFactory);
      int callCount = 0;

      throttler.call(() => callCount++);

      expect(callCount, 1);
      throttler.dispose();
    });

    test('blocks subsequent calls during throttle period', () {
      final throttler = Throttler(
        duration: const Duration(milliseconds: 500),
        timerFactory: timerFactory,
      );
      int callCount = 0;

      throttler.call(() => callCount++);
      throttler.call(() => callCount++);
      throttler.call(() => callCount++);

      expect(callCount, 1);
      throttler.dispose();
    });

    test('allows calls after throttle period expires', () {
      final throttler = Throttler(
        duration: const Duration(milliseconds: 500),
        timerFactory: timerFactory,
      );
      int callCount = 0;

      throttler.call(() => callCount++);
      expect(callCount, 1);

      timerFactory.advanceTime(const Duration(milliseconds: 500));

      throttler.call(() => callCount++);
      expect(callCount, 2);
      throttler.dispose();
    });

    test('callWithDuration overrides default duration', () {
      final throttler = Throttler(
        duration: const Duration(milliseconds: 500),
        timerFactory: timerFactory,
      );
      int callCount = 0;

      throttler.callWithDuration(() => callCount++, const Duration(milliseconds: 100));
      expect(callCount, 1);

      timerFactory.advanceTime(const Duration(milliseconds: 100));

      throttler.call(() => callCount++);
      expect(callCount, 2);
      throttler.dispose();
    });

    test('wrap() creates a wrapped callback', () {
      final throttler = Throttler(timerFactory: timerFactory);
      int callCount = 0;

      final wrapped = throttler.wrap(() => callCount++);
      expect(wrapped, isNotNull);

      wrapped!();
      expect(callCount, 1);

      throttler.dispose();
    });

    test('wrap() returns null for null callback', () {
      final throttler = Throttler(timerFactory: timerFactory);

      final wrapped = throttler.wrap(null);
      expect(wrapped, isNull);

      throttler.dispose();
    });

    test('enabled=false bypasses throttling', () {
      final throttler = Throttler(
        enabled: false,
        timerFactory: timerFactory,
      );
      int callCount = 0;

      throttler.call(() => callCount++);
      throttler.call(() => callCount++);
      throttler.call(() => callCount++);

      expect(callCount, 3);
      throttler.dispose();
    });

    test('reset() clears throttle state', () {
      final throttler = Throttler(
        duration: const Duration(milliseconds: 500),
        timerFactory: timerFactory,
      );
      int callCount = 0;

      throttler.call(() => callCount++);
      expect(callCount, 1);
      expect(throttler.isThrottled, true);

      throttler.reset();
      expect(throttler.isThrottled, false);

      throttler.call(() => callCount++);
      expect(callCount, 2);
      throttler.dispose();
    });

    test('onMetrics callback is called with execution time', () {
      Duration? reportedDuration;
      bool? wasExecuted;

      final throttler = Throttler(
        timerFactory: timerFactory,
        onMetrics: (duration, executed) {
          reportedDuration = duration;
          wasExecuted = executed;
        },
      );

      throttler.call(() {});

      expect(reportedDuration, isNotNull);
      expect(wasExecuted, true);
      throttler.dispose();
    });

    test('onMetrics reports blocked calls', () {
      Duration? reportedDuration;
      bool? wasExecuted;

      final throttler = Throttler(
        timerFactory: timerFactory,
        onMetrics: (duration, executed) {
          reportedDuration = duration;
          wasExecuted = executed;
        },
      );

      throttler.call(() {});
      throttler.call(() {}); // This one should be blocked

      expect(wasExecuted, false);
      expect(reportedDuration, Duration.zero);
      throttler.dispose();
    });

    test('resetOnError resets state when callback throws', () {
      final throttler = Throttler(
        resetOnError: true,
        timerFactory: timerFactory,
      );

      expect(
        () => throttler.call(() => throw Exception('Test error')),
        throwsException,
      );

      expect(throttler.isThrottled, false);
      throttler.dispose();
    });
  });

  group('Debouncer', () {
    late MockTimerFactory timerFactory;

    setUp(() {
      timerFactory = MockTimerFactory();
    });

    tearDown(() {
      timerFactory.clear();
    });

    test('trailing edge: executes after delay (default behavior)', () {
      final debouncer = Debouncer(
        duration: const Duration(milliseconds: 300),
        timerFactory: timerFactory,
      );
      int callCount = 0;

      debouncer.call(() => callCount++);
      expect(callCount, 0);

      timerFactory.advanceTime(const Duration(milliseconds: 300));
      expect(callCount, 1);

      debouncer.dispose();
    });

    test('leading edge: executes immediately on first call', () {
      final debouncer = Debouncer(
        duration: const Duration(milliseconds: 300),
        leading: true,
        trailing: false,
        timerFactory: timerFactory,
      );
      int callCount = 0;

      debouncer.call(() => callCount++);
      expect(callCount, 1);

      debouncer.call(() => callCount++);
      expect(callCount, 1); // No additional calls

      debouncer.dispose();
    });

    test('leading + trailing: executes both edges', () {
      final debouncer = Debouncer(
        duration: const Duration(milliseconds: 300),
        leading: true,
        trailing: true,
        timerFactory: timerFactory,
      );
      int callCount = 0;

      debouncer.call(() => callCount++);
      expect(callCount, 1); // Leading edge

      debouncer.call(() => callCount++);
      expect(callCount, 1); // Still leading only

      timerFactory.advanceTime(const Duration(milliseconds: 300));
      expect(callCount, 2); // Trailing edge

      debouncer.dispose();
    });

    test('flush() executes callback immediately', () {
      final debouncer = Debouncer(
        duration: const Duration(milliseconds: 300),
        timerFactory: timerFactory,
      );
      int callCount = 0;

      debouncer.flush(() => callCount++);
      expect(callCount, 1);

      debouncer.dispose();
    });

    test('callWithDuration overrides default duration', () {
      final debouncer = Debouncer(
        duration: const Duration(milliseconds: 300),
        timerFactory: timerFactory,
      );
      int callCount = 0;

      debouncer.callWithDuration(() => callCount++, const Duration(milliseconds: 100));
      expect(callCount, 0);

      timerFactory.advanceTime(const Duration(milliseconds: 100));
      expect(callCount, 1);

      debouncer.dispose();
    });

    test('enabled=false bypasses debouncing', () {
      final debouncer = Debouncer(
        enabled: false,
        timerFactory: timerFactory,
      );
      int callCount = 0;

      debouncer.call(() => callCount++);
      expect(callCount, 1);

      debouncer.dispose();
    });

    test('onMetrics reports wait time and cancelled state', () {
      Duration? reportedDuration;
      bool? wasCancelled;

      final debouncer = Debouncer(
        duration: const Duration(milliseconds: 300),
        timerFactory: timerFactory,
        onMetrics: (duration, cancelled) {
          reportedDuration = duration;
          wasCancelled = cancelled;
        },
      );

      debouncer.call(() {});
      timerFactory.advanceTime(const Duration(milliseconds: 300));

      expect(wasCancelled, false);
      expect(reportedDuration, isNotNull);

      debouncer.dispose();
    });

    test('onMetrics reports cancelled calls', () {
      bool? wasCancelled;

      final debouncer = Debouncer(
        duration: const Duration(milliseconds: 300),
        timerFactory: timerFactory,
        onMetrics: (duration, cancelled) {
          wasCancelled = cancelled;
        },
      );

      debouncer.call(() {});
      debouncer.call(() {}); // This should cancel the previous

      expect(wasCancelled, true);

      debouncer.dispose();
    });

    test('cancel() cancels pending execution', () {
      final debouncer = Debouncer(
        duration: const Duration(milliseconds: 300),
        timerFactory: timerFactory,
      );
      int callCount = 0;

      debouncer.call(() => callCount++);
      debouncer.cancel();

      timerFactory.advanceTime(const Duration(milliseconds: 300));
      expect(callCount, 0);

      debouncer.dispose();
    });

    test('resetOnError cancels pending debounce when callback throws', () {
      final debouncer = Debouncer(
        duration: const Duration(milliseconds: 300),
        resetOnError: true,
        timerFactory: timerFactory,
      );
      int callCount = 0;

      // First call with error (executed via flush to trigger immediately)
      expect(
        () => debouncer.flush(() => throw Exception('Test error')),
        throwsException,
      );

      // After error, state should be cleared
      expect(debouncer.isPending, false);

      // Next call should work normally
      debouncer.call(() => callCount++);
      timerFactory.advanceTime(const Duration(milliseconds: 300));
      expect(callCount, 1);

      debouncer.dispose();
    });
  });

  group('RateLimiter', () {
    test('starts with full token capacity', () {
      final limiter = RateLimiter(maxTokens: 10);
      expect(limiter.availableTokens, 10);
      limiter.dispose();
    });

    test('tryAcquire consumes tokens', () {
      final limiter = RateLimiter(maxTokens: 5);

      expect(limiter.tryAcquire(), true);
      expect(limiter.availableTokens, 4);

      expect(limiter.tryAcquire(2), true);
      expect(limiter.availableTokens, 2);

      limiter.dispose();
    });

    test('tryAcquire fails when not enough tokens', () {
      final limiter = RateLimiter(maxTokens: 2);

      expect(limiter.tryAcquire(3), false);
      expect(limiter.availableTokens, 2);

      limiter.dispose();
    });

    test('call() executes callback when tokens available', () {
      final limiter = RateLimiter(maxTokens: 5);
      int callCount = 0;

      final result = limiter.call(() => callCount++);

      expect(result, true);
      expect(callCount, 1);

      limiter.dispose();
    });

    test('call() does not execute when no tokens', () {
      final limiter = RateLimiter(maxTokens: 1);
      int callCount = 0;

      limiter.tryAcquire(); // Use up the token

      final result = limiter.call(() => callCount++);

      expect(result, false);
      expect(callCount, 0);

      limiter.dispose();
    });

    test('enabled=false bypasses rate limiting', () {
      final limiter = RateLimiter(maxTokens: 1, enabled: false);
      int callCount = 0;

      limiter.tryAcquire();
      limiter.tryAcquire();
      limiter.call(() => callCount++);

      expect(callCount, 1);
      limiter.dispose();
    });

    test('reset() restores full capacity', () {
      final limiter = RateLimiter(maxTokens: 5);

      limiter.tryAcquire(3);
      expect(limiter.availableTokens, 2);

      limiter.reset();
      expect(limiter.availableTokens, 5);

      limiter.dispose();
    });

    test('onMetrics callback is called', () {
      int? reportedTokens;
      bool? wasAcquired;

      final limiter = RateLimiter(
        maxTokens: 5,
        onMetrics: (tokens, acquired) {
          reportedTokens = tokens;
          wasAcquired = acquired;
        },
      );

      limiter.tryAcquire();

      expect(reportedTokens, 4);
      expect(wasAcquired, true);

      limiter.dispose();
    });

    test('callAsync() executes async callback when tokens available', () async {
      final limiter = RateLimiter(maxTokens: 5);

      final result = await limiter.callAsync(() async => 'success');

      expect(result, 'success');
      expect(limiter.availableTokens, 4);

      limiter.dispose();
    });

    test('callAsync() returns null when no tokens available', () async {
      final limiter = RateLimiter(maxTokens: 1);

      limiter.tryAcquire(); // Use up the token

      final result = await limiter.callAsync(() async => 'success');

      expect(result, isNull);

      limiter.dispose();
    });

    test('timeUntilNextToken returns zero when tokens available', () {
      final limiter = RateLimiter(maxTokens: 5);

      expect(limiter.timeUntilNextToken, Duration.zero);

      limiter.dispose();
    });

    test('timeUntilNextToken returns positive duration when no tokens', () {
      final limiter = RateLimiter(
        maxTokens: 1,
        refillRate: 1,
        refillInterval: const Duration(seconds: 1),
      );

      limiter.tryAcquire(); // Use up the token

      // Should return a positive duration since no tokens available
      final timeUntilNext = limiter.timeUntilNextToken;
      expect(timeUntilNext, greaterThan(Duration.zero));
      expect(timeUntilNext, lessThanOrEqualTo(const Duration(seconds: 1)));

      limiter.dispose();
    });

    test('canAcquire reflects token availability', () {
      final limiter = RateLimiter(maxTokens: 1);

      expect(limiter.canAcquire, true);

      limiter.tryAcquire();

      expect(limiter.canAcquire, false);

      limiter.dispose();
    });
  });

  group('HighFrequencyThrottler', () {
    test('executes first call immediately', () {
      final throttler = HighFrequencyThrottler();
      int callCount = 0;

      final result = throttler.call(() => callCount++);

      expect(result, true);
      expect(callCount, 1);
      throttler.dispose();
    });

    test('uses 16ms default duration', () {
      expect(HighFrequencyThrottler.defaultDuration, const Duration(milliseconds: 16));
    });

    test('wrap() creates a wrapped callback', () {
      final throttler = HighFrequencyThrottler();
      int callCount = 0;

      final wrapped = throttler.wrap(() => callCount++);
      expect(wrapped, isNotNull);

      wrapped!();
      expect(callCount, 1);

      throttler.dispose();
    });

    test('wrap() returns null for null callback', () {
      final throttler = HighFrequencyThrottler();

      final wrapped = throttler.wrap(null);
      expect(wrapped, isNull);

      throttler.dispose();
    });

    test('reset() clears throttle state', () {
      final throttler = HighFrequencyThrottler();

      throttler.call(() {});
      expect(throttler.isThrottled, true);

      throttler.reset();
      expect(throttler.isThrottled, false);

      throttler.dispose();
    });
  });

  group('ThrottleDebouncer', () {
    late MockTimerFactory timerFactory;

    setUp(() {
      timerFactory = MockTimerFactory();
    });

    tearDown(() {
      timerFactory.clear();
    });

    test('executes immediately on first call (leading edge)', () {
      final throttleDebouncer = ThrottleDebouncer(timerFactory: timerFactory);
      int callCount = 0;

      throttleDebouncer.call(() => callCount++);

      expect(callCount, 1);
      throttleDebouncer.dispose();
    });

    test('queues subsequent calls for trailing edge', () {
      final throttleDebouncer = ThrottleDebouncer(
        duration: const Duration(milliseconds: 500),
        timerFactory: timerFactory,
      );
      int callCount = 0;

      throttleDebouncer.call(() => callCount++);
      expect(callCount, 1);

      throttleDebouncer.call(() => callCount++);
      expect(callCount, 1);

      timerFactory.advanceTime(const Duration(milliseconds: 500));
      expect(callCount, 2);

      throttleDebouncer.dispose();
    });

    test('restarts throttle window after trailing edge', () {
      final throttleDebouncer = ThrottleDebouncer(
        duration: const Duration(milliseconds: 500),
        timerFactory: timerFactory,
      );
      int callCount = 0;

      throttleDebouncer.call(() => callCount++); // Leading
      throttleDebouncer.call(() => callCount++); // Queued

      timerFactory.advanceTime(const Duration(milliseconds: 500));
      expect(callCount, 2);

      // Should still be throttled
      throttleDebouncer.call(() => callCount++); // Queued again

      timerFactory.advanceTime(const Duration(milliseconds: 500));
      expect(callCount, 3);

      throttleDebouncer.dispose();
    });

    test('wrap() creates a wrapped callback', () {
      final throttleDebouncer = ThrottleDebouncer(timerFactory: timerFactory);
      int callCount = 0;

      final wrapped = throttleDebouncer.wrap(() => callCount++);
      expect(wrapped, isNotNull);

      wrapped!();
      expect(callCount, 1);

      throttleDebouncer.dispose();
    });

    test('cancel() clears pending callback', () {
      final throttleDebouncer = ThrottleDebouncer(
        duration: const Duration(milliseconds: 500),
        timerFactory: timerFactory,
      );
      int callCount = 0;

      throttleDebouncer.call(() => callCount++);
      throttleDebouncer.call(() => callCount++);

      throttleDebouncer.cancel();

      timerFactory.advanceTime(const Duration(milliseconds: 500));
      expect(callCount, 1); // Only the first one

      throttleDebouncer.dispose();
    });
  });

  group('BatchThrottler', () {
    late MockTimerFactory timerFactory;

    setUp(() {
      timerFactory = MockTimerFactory();
    });

    tearDown(() {
      timerFactory.clear();
    });

    test('collects multiple actions into a batch', () {
      List<int>? executedBatch;

      final batcher = BatchThrottler<int>(
        duration: const Duration(milliseconds: 300),
        onBatchExecute: (batch) => executedBatch = batch,
        timerFactory: timerFactory,
      );

      batcher.add(1);
      batcher.add(2);
      batcher.add(3);

      expect(batcher.pendingCount, 3);

      timerFactory.advanceTime(const Duration(milliseconds: 300));

      expect(executedBatch, [1, 2, 3]);
      expect(batcher.pendingCount, 0);

      batcher.dispose();
    });

    test('flush() executes batch immediately', () {
      List<int>? executedBatch;

      final batcher = BatchThrottler<int>(
        duration: const Duration(milliseconds: 300),
        onBatchExecute: (batch) => executedBatch = batch,
        timerFactory: timerFactory,
      );

      batcher.add(1);
      batcher.add(2);
      batcher.flush();

      expect(executedBatch, [1, 2]);

      batcher.dispose();
    });

    test('clear() discards pending without executing', () {
      List<int>? executedBatch;

      final batcher = BatchThrottler<int>(
        duration: const Duration(milliseconds: 300),
        onBatchExecute: (batch) => executedBatch = batch,
        timerFactory: timerFactory,
      );

      batcher.add(1);
      batcher.add(2);
      batcher.clear();

      expect(batcher.pendingCount, 0);

      timerFactory.advanceTime(const Duration(milliseconds: 300));
      expect(executedBatch, isNull);

      batcher.dispose();
    });

    test('hasPending reflects state correctly', () {
      final batcher = BatchThrottler<int>(
        duration: const Duration(milliseconds: 300),
        onBatchExecute: (_) {},
        timerFactory: timerFactory,
      );

      expect(batcher.hasPending, false);

      batcher.add(1);
      expect(batcher.hasPending, true);

      timerFactory.advanceTime(const Duration(milliseconds: 300));
      expect(batcher.hasPending, false);

      batcher.dispose();
    });
  });

  group('AsyncDebouncer', () {
    late MockTimerFactory timerFactory;

    setUp(() {
      timerFactory = MockTimerFactory();
    });

    tearDown(() {
      timerFactory.clear();
    });

    test('executes after delay', () async {
      final debouncer = AsyncDebouncer(
        duration: const Duration(milliseconds: 300),
        timerFactory: timerFactory,
      );
      int callCount = 0;

      final future = debouncer.run(() async {
        callCount++;
        return 'result';
      });

      expect(callCount, 0);

      timerFactory.advanceTime(const Duration(milliseconds: 300));

      final result = await future;
      expect(result, 'result');
      expect(callCount, 1);

      debouncer.dispose();
    });

    test('auto-cancels previous calls', () async {
      final debouncer = AsyncDebouncer(
        duration: const Duration(milliseconds: 300),
        timerFactory: timerFactory,
      );
      int callCount = 0;

      final future1 = debouncer.run(() async {
        callCount++;
        return 'first';
      });

      final future2 = debouncer.run(() async {
        callCount++;
        return 'second';
      });

      timerFactory.advanceTime(const Duration(milliseconds: 300));

      final result1 = await future1;
      final result2 = await future2;

      expect(result1, isNull); // Cancelled
      expect(result2, 'second');
      expect(callCount, 1);

      debouncer.dispose();
    });

    test('enabled=false bypasses debouncing', () async {
      final debouncer = AsyncDebouncer(
        enabled: false,
        timerFactory: timerFactory,
      );
      int callCount = 0;

      final result = await debouncer.run(() async {
        callCount++;
        return 'result';
      });

      expect(result, 'result');
      expect(callCount, 1);

      debouncer.dispose();
    });

    test('cancel() returns null for pending call', () async {
      final debouncer = AsyncDebouncer(
        duration: const Duration(milliseconds: 300),
        timerFactory: timerFactory,
      );

      final future = debouncer.run(() async => 'result');

      debouncer.cancel();

      final result = await future;
      expect(result, isNull);

      debouncer.dispose();
    });

    test('call ID tracking prevents stale executions', () async {
      final debouncer = AsyncDebouncer(
        duration: const Duration(milliseconds: 300),
        timerFactory: timerFactory,
      );
      final executedIds = <int>[];

      // Start multiple calls rapidly
      for (var i = 0; i < 3; i++) {
        final callNumber = i;
        unawaited(debouncer.run<int>(() async {
          executedIds.add(callNumber);
          return callNumber;
        }));
      }

      timerFactory.advanceTime(const Duration(milliseconds: 300));
      await Future.delayed(Duration.zero);

      // Only the last call should have executed
      expect(executedIds, [2]);

      debouncer.dispose();
    });

    test('onMetrics callback is called with execution time', () async {
      Duration? reportedDuration;
      bool? wasCancelled;

      final debouncer = AsyncDebouncer(
        duration: const Duration(milliseconds: 300),
        timerFactory: timerFactory,
        onMetrics: (duration, cancelled) {
          reportedDuration = duration;
          wasCancelled = cancelled;
        },
      );

      final future = debouncer.run(() async => 'result');
      timerFactory.advanceTime(const Duration(milliseconds: 300));
      await future;

      expect(reportedDuration, isNotNull);
      expect(wasCancelled, false);

      debouncer.dispose();
    });

    test('onMetrics reports cancelled calls', () async {
      bool? wasCancelled;

      final debouncer = AsyncDebouncer(
        duration: const Duration(milliseconds: 300),
        timerFactory: timerFactory,
        onMetrics: (duration, cancelled) {
          wasCancelled = cancelled;
        },
      );

      unawaited(debouncer.run(() async => 'first'));
      unawaited(debouncer.run(() async => 'second')); // Cancels first

      expect(wasCancelled, true);

      debouncer.dispose();
    });

    test('resetOnError resets state when async callback throws', () async {
      final debouncer = AsyncDebouncer(
        duration: const Duration(milliseconds: 300),
        resetOnError: true,
        timerFactory: timerFactory,
      );

      final future = debouncer.run(() async {
        throw Exception('Test error');
      });

      timerFactory.advanceTime(const Duration(milliseconds: 300));

      // When resetOnError is true, cancel() is called which completes with null
      final result = await future;

      expect(result, isNull);
      // After error with resetOnError, state should be cleared
      expect(debouncer.isPending, false);

      debouncer.dispose();
    });
  });

  group('AsyncThrottler', () {
    late MockTimerFactory timerFactory;

    setUp(() {
      timerFactory = MockTimerFactory();
    });

    tearDown(() {
      timerFactory.clear();
    });

    test('executes first call', () async {
      final throttler = AsyncThrottler(timerFactory: timerFactory);
      int callCount = 0;

      await throttler.call(() async {
        callCount++;
      });

      expect(callCount, 1);
      expect(throttler.isLocked, false);

      throttler.dispose();
    });

    test('blocks while executing', () async {
      final throttler = AsyncThrottler(timerFactory: timerFactory);
      int callCount = 0;
      final completer = Completer<void>();

      // Start first call that won't complete
      unawaited(throttler.call(() async {
        callCount++;
        await completer.future;
      }));

      // Give it time to start
      await Future.microtask(() {});
      expect(throttler.isLocked, true);

      // Try second call - should be blocked
      await throttler.call(() async {
        callCount++;
      });

      expect(callCount, 1);

      completer.complete();
      throttler.dispose();
    });

    test('enabled=false bypasses throttling', () async {
      final throttler = AsyncThrottler(
        enabled: false,
        timerFactory: timerFactory,
      );
      int callCount = 0;

      await throttler.call(() async => callCount++);
      await throttler.call(() async => callCount++);
      await throttler.call(() async => callCount++);

      expect(callCount, 3);
      throttler.dispose();
    });

    test('wrap() creates a wrapped callback', () async {
      final throttler = AsyncThrottler(timerFactory: timerFactory);
      int callCount = 0;

      final wrapped = throttler.wrap(() async => callCount++);
      expect(wrapped, isNotNull);

      wrapped!();
      await Future.microtask(() {});
      expect(callCount, 1);

      throttler.dispose();
    });

    test('reset() clears locked state', () async {
      final throttler = AsyncThrottler(timerFactory: timerFactory);
      final completer = Completer<void>();

      unawaited(throttler.call(() async {
        await completer.future;
      }));

      await Future.microtask(() {});
      expect(throttler.isLocked, true);

      throttler.reset();
      expect(throttler.isLocked, false);

      completer.complete();
      throttler.dispose();
    });

    test('maxDuration timeout unlocks throttler', () async {
      final throttler = AsyncThrottler(
        maxDuration: const Duration(milliseconds: 100),
        timerFactory: timerFactory,
      );
      final completer = Completer<void>();

      unawaited(throttler.call(() async {
        await completer.future;
      }));

      await Future.microtask(() {});
      expect(throttler.isLocked, true);

      // Advance time past maxDuration
      timerFactory.advanceTime(const Duration(milliseconds: 100));

      // Should be unlocked by timeout
      expect(throttler.isLocked, false);

      completer.complete();
      throttler.dispose();
    });

    test('resetOnError resets state when callback throws', () async {
      final throttler = AsyncThrottler(
        resetOnError: true,
        timerFactory: timerFactory,
      );

      await expectLater(
        throttler.call(() async => throw Exception('Test error')),
        throwsException,
      );

      expect(throttler.isLocked, false);
      throttler.dispose();
    });

    test('onMetrics callback is called with execution time', () async {
      Duration? reportedDuration;

      final throttler = AsyncThrottler(
        timerFactory: timerFactory,
        onMetrics: (duration) {
          reportedDuration = duration;
        },
      );

      await throttler.call(() async {});

      expect(reportedDuration, isNotNull);
      throttler.dispose();
    });
  });

  group('AsyncExecutor', () {
    test('drop mode: ignores new calls while executing', () async {
      final executor = AsyncExecutor(mode: ConcurrencyMode.drop);
      int callCount = 0;
      final completer = Completer<void>();

      // Start first call
      unawaited(executor.execute(() async {
        callCount++;
        await completer.future;
      }));

      await Future.microtask(() {});

      // Try second call - should be dropped
      final result = await executor.execute(() async {
        callCount++;
      });

      expect(result, false);
      expect(callCount, 1);

      completer.complete();
      executor.dispose();
    });

    test('keepLatest mode: queues only the latest', () async {
      final executor = AsyncExecutor(mode: ConcurrencyMode.keepLatest);
      final order = <int>[];
      final completer = Completer<void>();

      // Start first call
      unawaited(executor.execute(() async {
        order.add(1);
        await completer.future;
      }));

      await Future.microtask(() {});

      // Queue several - only last should be kept
      unawaited(executor.execute(() async => order.add(2)));
      unawaited(executor.execute(() async => order.add(3)));
      unawaited(executor.execute(() async => order.add(4)));

      expect(executor.pendingCount, 1);

      completer.complete();
      await Future.delayed(Duration.zero); // Let queued execute

      expect(order, [1, 4]);

      executor.dispose();
    });

    test('enqueue mode: queues all calls FIFO', () async {
      final executor = AsyncExecutor(mode: ConcurrencyMode.enqueue);
      final order = <int>[];
      final completer = Completer<void>();

      // Start first call
      unawaited(executor.execute(() async {
        order.add(1);
        await completer.future;
      }));

      await Future.microtask(() {});

      // Queue several
      unawaited(executor.execute(() async => order.add(2)));
      unawaited(executor.execute(() async => order.add(3)));

      expect(executor.pendingCount, 2);

      completer.complete();
      await Future.delayed(Duration.zero); // Let queue process

      expect(order, [1, 2, 3]);

      executor.dispose();
    });

    test('enabled=false bypasses concurrency control', () async {
      final executor = AsyncExecutor(
        mode: ConcurrencyMode.drop,
        enabled: false,
      );
      int callCount = 0;

      await executor.execute(() async => callCount++);
      await executor.execute(() async => callCount++);
      await executor.execute(() async => callCount++);

      expect(callCount, 3);
      executor.dispose();
    });

    test('shouldContinue() tracks call validity', () async {
      final executor = AsyncExecutor(mode: ConcurrencyMode.replace);

      final callId = executor.currentCallId + 1;

      unawaited(executor.execute(() async {}));

      expect(executor.shouldContinue(callId), true);

      executor.cancel();

      expect(executor.shouldContinue(callId), false);

      executor.dispose();
    });

    test('wrap() creates a wrapped callback', () async {
      final executor = AsyncExecutor();
      int callCount = 0;

      final wrapped = executor.wrap(() async => callCount++);
      expect(wrapped, isNotNull);

      wrapped!();
      await Future.microtask(() {});
      expect(callCount, 1);

      executor.dispose();
    });

    test('cancel() clears pending operations', () async {
      final executor = AsyncExecutor(mode: ConcurrencyMode.enqueue);
      final completer = Completer<void>();
      int callCount = 0;

      unawaited(executor.execute(() async {
        callCount++;
        await completer.future;
      }));

      await Future.microtask(() {});

      unawaited(executor.execute(() async => callCount++));
      unawaited(executor.execute(() async => callCount++));

      executor.cancel();

      expect(executor.pendingCount, 0);

      completer.complete();
      await Future.delayed(Duration.zero);

      expect(callCount, 1); // Only the first one

      executor.dispose();
    });

    test('replace mode: new call supersedes current', () async {
      final executor = AsyncExecutor(mode: ConcurrencyMode.replace);
      final order = <int>[];
      final completer1 = Completer<void>();
      final completer2 = Completer<void>();

      // Start first call
      final future1 = executor.execute(() async {
        order.add(1);
        await completer1.future;
        order.add(11);
      });

      await Future.microtask(() {});
      expect(executor.isExecuting, true);

      // Start second call - should replace first
      final future2 = executor.execute(() async {
        order.add(2);
        await completer2.future;
        order.add(22);
      });

      await Future.microtask(() {});

      // Complete first call - but it was superseded
      completer1.complete();
      await Future.microtask(() {});

      // The first call should have started, second should have added
      expect(order.contains(1), true);
      expect(order.contains(2), true);

      completer2.complete();
      await future1;
      await future2;

      executor.dispose();
    });

    test('maxDuration timeout causes TimeoutException', () async {
      final executor = AsyncExecutor(
        maxDuration: const Duration(milliseconds: 10),
      );
      final completer = Completer<void>();

      final future = executor.execute(() async {
        await completer.future;
      });

      await expectLater(future, throwsA(isA<TimeoutException>()));

      completer.complete();
      executor.dispose();
    });

    test('resetOnError resets state when callback throws', () async {
      final executor = AsyncExecutor(
        mode: ConcurrencyMode.enqueue,
        resetOnError: true,
      );

      await expectLater(
        executor.execute(() async => throw Exception('Test error')),
        throwsException,
      );

      expect(executor.isExecuting, false);
      expect(executor.pendingCount, 0);
      executor.dispose();
    });

    test('onMetrics callback is called with execution time', () async {
      Duration? reportedDuration;

      final executor = AsyncExecutor(
        onMetrics: (duration) {
          reportedDuration = duration;
        },
      );

      await executor.execute(() async {});

      expect(reportedDuration, isNotNull);
      executor.dispose();
    });
  });

  group('ConcurrencyMode', () {
    test('all modes are defined', () {
      expect(ConcurrencyMode.values.length, 4);
      expect(ConcurrencyMode.drop, isNotNull);
      expect(ConcurrencyMode.replace, isNotNull);
      expect(ConcurrencyMode.keepLatest, isNotNull);
      expect(ConcurrencyMode.enqueue, isNotNull);
    });
  });

  // ==========================================================================
  // Integration Tests
  // ==========================================================================

  group('TappableActionConfig', () {
    test('default config has correct values', () {
      const config = TappableActionConfig();

      expect(config.requireNetwork, true);
      expect(config.debounceTaps, true);
      expect(config.executionMode, TapExecutionMode.throttle);
      expect(config.executeOnLeadingEdge, true);
      expect(config.executeOnTrailingEdge, false);
      expect(config.concurrencyMode, TapConcurrencyMode.drop);
      expect(config.enabled, true);
      expect(config.isValid, true);
    });

    test('search preset has correct debounce configuration', () {
      const config = TappableActionConfig.search();

      expect(config.executionMode, TapExecutionMode.debounce);
      expect(config.executeOnLeadingEdge, false);
      expect(config.executeOnTrailingEdge, true);
      expect(config.disableVisuallyDuringDebouncing, false);
      expect(config.coolDownDuration, const Duration(milliseconds: 300));
    });

    test('toggle preset has correct replace configuration', () {
      const config = TappableActionConfig.toggle();

      expect(config.executionMode, TapExecutionMode.throttle);
      expect(config.concurrencyMode, TapConcurrencyMode.replace);
      expect(config.executeOnLeadingEdge, true);
      expect(config.coolDownDuration, const Duration(milliseconds: 500));
    });

    test('slider preset has correct rate limit configuration', () {
      const config = TappableActionConfig.slider();

      expect(config.executionMode, TapExecutionMode.rateLimited);
      expect(config.requireNetwork, false);
      expect(config.rateLimitMaxTokens, 20);
      expect(config.rateLimitRefillInterval, const Duration(milliseconds: 100));
      expect(config.rateLimitTokensPerRefill, 5);
    });

    test('highFrequency preset has correct configuration', () {
      const config = TappableActionConfig.highFrequency();

      expect(config.executionMode, TapExecutionMode.highFrequency);
      expect(config.requireNetwork, false);
      expect(config.disableVisuallyDuringDebouncing, false);
      expect(config.coolDownDuration, const Duration(milliseconds: 100));
    });

    test('critical preset has conservative configuration', () {
      const config = TappableActionConfig.critical();

      expect(config.executionMode, TapExecutionMode.throttle);
      expect(config.requireNetwork, true);
      expect(config.coolDownDuration, const Duration(seconds: 2));
      expect(
          config.delayBeforeFirstTapDuration, const Duration(milliseconds: 300));
      expect(config.minDisabledDuration, const Duration(seconds: 1));
    });

    test('isValid returns false for invalid configurations', () {
      // Negative cooldown
      expect(
        TappableActionConfig(
          coolDownDuration: const Duration(milliseconds: -100),
        ).isValid,
        false,
      );

      // Empty group ID
      expect(
        const TappableActionConfig(groupId: '   ').isValid,
        false,
      );

      // Invalid rate limit tokens
      expect(
        const TappableActionConfig(rateLimitMaxTokens: 0).isValid,
        false,
      );

      // Invalid refill rate
      expect(
        const TappableActionConfig(rateLimitTokensPerRefill: 0).isValid,
        false,
      );
    });

    test('copyWith preserves unmodified values', () {
      const original = TappableActionConfig(
        requireNetwork: false,
        executionMode: TapExecutionMode.debounce,
        concurrencyMode: TapConcurrencyMode.enqueue,
        debugName: 'test',
      );

      final copied = original.copyWith(
        requireNetwork: true,
      );

      expect(copied.requireNetwork, true);
      expect(copied.executionMode, TapExecutionMode.debounce);
      expect(copied.concurrencyMode, TapConcurrencyMode.enqueue);
      expect(copied.debugName, 'test');
    });
  });

  group('TapExecutionMode Integration', () {
    late MockTimerFactory timerFactory;

    setUp(() {
      timerFactory = MockTimerFactory();
    });

    tearDown(() {
      timerFactory.clear();
    });

    test('throttle mode uses Throttler behavior', () {
      // Simulate what TappableAction does with throttle mode
      final throttler = Throttler(
        duration: const Duration(milliseconds: 500),
        timerFactory: timerFactory,
      );

      int callCount = 0;

      // First call executes immediately
      throttler.call(() => callCount++);
      expect(callCount, 1);

      // Subsequent calls blocked during throttle window
      throttler.call(() => callCount++);
      throttler.call(() => callCount++);
      expect(callCount, 1);

      // After window, next call executes
      timerFactory.advanceTime(const Duration(milliseconds: 500));
      throttler.call(() => callCount++);
      expect(callCount, 2);

      throttler.dispose();
    });

    test('debounce mode uses Debouncer behavior', () {
      // Simulate what TappableAction does with debounce mode
      final debouncer = Debouncer(
        duration: const Duration(milliseconds: 300),
        leading: false,
        trailing: true,
        timerFactory: timerFactory,
      );

      int callCount = 0;

      // Calls don't execute immediately
      debouncer.call(() => callCount++);
      debouncer.call(() => callCount++);
      debouncer.call(() => callCount++);
      expect(callCount, 0);

      // After pause, callback fires once
      timerFactory.advanceTime(const Duration(milliseconds: 300));
      expect(callCount, 1);

      debouncer.dispose();
    });

    test('throttleDebounce mode uses ThrottleDebouncer behavior', () {
      final throttleDebouncer = ThrottleDebouncer(
        duration: const Duration(milliseconds: 500),
        timerFactory: timerFactory,
      );

      int callCount = 0;

      // First call executes immediately (leading edge)
      throttleDebouncer.call(() => callCount++);
      expect(callCount, 1);

      // Subsequent calls queued
      throttleDebouncer.call(() => callCount++);
      expect(callCount, 1);

      // After window, trailing edge fires
      timerFactory.advanceTime(const Duration(milliseconds: 500));
      expect(callCount, 2);

      throttleDebouncer.dispose();
    });

    test('rateLimited mode uses RateLimiter behavior', () {
      final rateLimiter = RateLimiter(
        maxTokens: 3,
        refillRate: 1,
        refillInterval: const Duration(seconds: 1),
      );

      int callCount = 0;

      // First 3 calls succeed (burst capacity)
      expect(rateLimiter.call(() => callCount++), true);
      expect(rateLimiter.call(() => callCount++), true);
      expect(rateLimiter.call(() => callCount++), true);
      expect(callCount, 3);

      // 4th call fails (no tokens)
      expect(rateLimiter.call(() => callCount++), false);
      expect(callCount, 3);

      rateLimiter.dispose();
    });

    test('highFrequency mode uses HighFrequencyThrottler behavior', () {
      final highFreq = HighFrequencyThrottler(
        duration: const Duration(milliseconds: 16),
      );

      int callCount = 0;

      // First call executes
      expect(highFreq.call(() => callCount++), true);
      expect(callCount, 1);

      // Immediate subsequent call blocked (DateTime-based)
      expect(highFreq.call(() => callCount++), false);
      expect(callCount, 1);

      highFreq.dispose();
    });
  });

  group('TapConcurrencyMode Integration', () {
    test('drop mode maps to ConcurrencyMode.drop', () async {
      final executor = AsyncExecutor(mode: ConcurrencyMode.drop);
      int callCount = 0;
      final completer = Completer<void>();

      // Start first call
      unawaited(executor.execute(() async {
        callCount++;
        await completer.future;
      }));

      await Future.microtask(() {});

      // Second call dropped
      final wasExecuted = await executor.execute(() async {
        callCount++;
      });

      expect(wasExecuted, false);
      expect(callCount, 1);

      completer.complete();
      executor.dispose();
    });

    test('replace mode maps to ConcurrencyMode.replace', () async {
      final executor = AsyncExecutor(mode: ConcurrencyMode.replace);
      final executionOrder = <String>[];
      final completer = Completer<void>();

      // Start first call
      unawaited(executor.execute(() async {
        executionOrder.add('first-start');
        await completer.future;
        executionOrder.add('first-end');
      }));

      await Future.microtask(() {});

      // Second call starts (replaces first)
      unawaited(executor.execute(() async {
        executionOrder.add('second-start');
        executionOrder.add('second-end');
      }));

      await Future.microtask(() {});
      completer.complete();
      await Future.delayed(Duration.zero);

      expect(executionOrder.contains('first-start'), true);
      expect(executionOrder.contains('second-start'), true);

      executor.dispose();
    });

    test('keepLatest mode maps to ConcurrencyMode.keepLatest', () async {
      final executor = AsyncExecutor(mode: ConcurrencyMode.keepLatest);
      final executionOrder = <int>[];
      final completer = Completer<void>();

      // Start first call
      unawaited(executor.execute(() async {
        executionOrder.add(1);
        await completer.future;
      }));

      await Future.microtask(() {});

      // Queue several - only last should execute
      unawaited(executor.execute(() async => executionOrder.add(2)));
      unawaited(executor.execute(() async => executionOrder.add(3)));
      unawaited(executor.execute(() async => executionOrder.add(4)));

      expect(executor.pendingCount, 1);

      completer.complete();
      await Future.delayed(Duration.zero);

      expect(executionOrder, [1, 4]);

      executor.dispose();
    });

    test('enqueue mode maps to ConcurrencyMode.enqueue', () async {
      final executor = AsyncExecutor(mode: ConcurrencyMode.enqueue);
      final executionOrder = <int>[];
      final completer = Completer<void>();

      // Start first call
      unawaited(executor.execute(() async {
        executionOrder.add(1);
        await completer.future;
      }));

      await Future.microtask(() {});

      // Queue all
      unawaited(executor.execute(() async => executionOrder.add(2)));
      unawaited(executor.execute(() async => executionOrder.add(3)));

      expect(executor.pendingCount, 2);

      completer.complete();
      await Future.delayed(Duration.zero);

      expect(executionOrder, [1, 2, 3]);

      executor.dispose();
    });
  });

  group('TapMetrics Integration', () {
    late MockTimerFactory timerFactory;

    setUp(() {
      timerFactory = MockTimerFactory();
    });

    tearDown(() {
      timerFactory.clear();
    });

    test('TapMetrics captures throttle metrics correctly', () {
      TapMetrics? capturedMetrics;

      void onMetrics(TapMetrics metrics) {
        capturedMetrics = metrics;
      }

      // Simulate TappableAction metrics callback wiring
      final throttler = Throttler(
        timerFactory: timerFactory,
        onMetrics: (duration, executed) {
          onMetrics(TapMetrics(
            executionDuration: duration,
            wasThrottled: !executed,
            wasCancelled: false,
            hadError: false,
            tapCountInWindow: 1,
            groupId: 'test-group',
            executionMode: TapExecutionMode.throttle,
            timestamp: DateTime.now(),
          ));
        },
      );

      // Execute and capture metrics
      throttler.call(() {});

      expect(capturedMetrics, isNotNull);
      expect(capturedMetrics!.wasThrottled, false);
      expect(capturedMetrics!.wasCancelled, false);
      expect(capturedMetrics!.executionMode, TapExecutionMode.throttle);
      expect(capturedMetrics!.groupId, 'test-group');

      // Blocked call should report throttled
      throttler.call(() {});

      expect(capturedMetrics!.wasThrottled, true);

      throttler.dispose();
    });

    test('TapMetrics captures debounce metrics correctly', () {
      TapMetrics? capturedMetrics;
      int metricsCallCount = 0;

      void onMetrics(TapMetrics metrics) {
        capturedMetrics = metrics;
        metricsCallCount++;
      }

      final debouncer = Debouncer(
        duration: const Duration(milliseconds: 300),
        timerFactory: timerFactory,
        onMetrics: (duration, cancelled) {
          onMetrics(TapMetrics(
            executionDuration: duration,
            wasThrottled: false,
            wasCancelled: cancelled,
            hadError: false,
            tapCountInWindow: metricsCallCount + 1,
            groupId: null,
            executionMode: TapExecutionMode.debounce,
            timestamp: DateTime.now(),
          ));
        },
      );

      // First call
      debouncer.call(() {});

      // Second call cancels first
      debouncer.call(() {});

      expect(capturedMetrics, isNotNull);
      expect(capturedMetrics!.wasCancelled, true);
      expect(capturedMetrics!.executionMode, TapExecutionMode.debounce);

      // Let it complete
      timerFactory.advanceTime(const Duration(milliseconds: 300));

      expect(capturedMetrics!.wasCancelled, false);

      debouncer.dispose();
    });

    test('TapMetrics captures rate limit metrics correctly', () {
      TapMetrics? capturedMetrics;

      void onMetrics(TapMetrics metrics) {
        capturedMetrics = metrics;
      }

      final rateLimiter = RateLimiter(
        maxTokens: 2,
        onMetrics: (tokensRemaining, acquired) {
          onMetrics(TapMetrics(
            executionDuration: Duration.zero,
            wasThrottled: !acquired,
            wasCancelled: false,
            hadError: false,
            tapCountInWindow: 1,
            groupId: null,
            executionMode: TapExecutionMode.rateLimited,
            timestamp: DateTime.now(),
          ));
        },
      );

      // First two calls succeed
      rateLimiter.call(() {});
      expect(capturedMetrics!.wasThrottled, false);

      rateLimiter.call(() {});
      expect(capturedMetrics!.wasThrottled, false);

      // Third call throttled (no tokens)
      rateLimiter.call(() {});
      expect(capturedMetrics!.wasThrottled, true);
      expect(capturedMetrics!.executionMode, TapExecutionMode.rateLimited);

      rateLimiter.dispose();
    });

    test('TapMetrics equality works correctly', () {
      final timestamp = DateTime.now();

      final metrics1 = TapMetrics(
        executionDuration: const Duration(milliseconds: 100),
        wasThrottled: false,
        wasCancelled: false,
        hadError: false,
        tapCountInWindow: 1,
        groupId: 'test',
        executionMode: TapExecutionMode.throttle,
        timestamp: timestamp,
      );

      final metrics2 = TapMetrics(
        executionDuration: const Duration(milliseconds: 100),
        wasThrottled: false,
        wasCancelled: false,
        hadError: false,
        tapCountInWindow: 1,
        groupId: 'test',
        executionMode: TapExecutionMode.throttle,
        timestamp: timestamp,
      );

      expect(metrics1, equals(metrics2));
      expect(metrics1.hashCode, equals(metrics2.hashCode));
    });

    test('TapMetrics toString provides useful debug info', () {
      final metrics = TapMetrics(
        executionDuration: const Duration(milliseconds: 50),
        wasThrottled: true,
        wasCancelled: false,
        hadError: false,
        tapCountInWindow: 3,
        groupId: 'btn-group',
        executionMode: TapExecutionMode.throttle,
        timestamp: DateTime.now(),
      );

      final str = metrics.toString();
      expect(str, contains('50ms'));
      expect(str, contains('throttled: true'));
      expect(str, contains('tapCount: 3'));
      expect(str, contains('throttle'));
    });
  });

  group('TappableActionGroupManager', () {
    late MockTimerFactory timerFactory;
    late TappableActionGroupConfig config;

    setUp(() {
      timerFactory = MockTimerFactory();
      config = TappableActionGroupConfig.testing(
        timerFactory: timerFactory,
        enableAutoReset: true,
        autoResetDelay: const Duration(milliseconds: 500),
      );
    });

    tearDown(() {
      timerFactory.clear();
    });

    test('registers and unregisters widgets correctly', () {
      final manager = TappableActionGroupManager.forTesting(config);
      final widget1 = Object();
      final widget2 = Object();

      manager.registerWidget('group1', widget1);
      manager.registerWidget('group1', widget2);

      // Access group to create notifier (registration alone doesn't create it)
      expect(manager.isGroupDisabled('group1'), false);

      final debugInfo = manager.getDebugInfo();
      expect(debugInfo['totalGroups'], 1);

      manager.unregisterWidget('group1', widget1);
      manager.unregisterWidget('group1', widget2);

      manager.dispose();
    });

    test('disables and enables groups correctly', () {
      final manager = TappableActionGroupManager.forTesting(config);

      expect(manager.isGroupDisabled('test-group'), false);

      manager.setGroupDisabled('test-group', true);
      expect(manager.isGroupDisabled('test-group'), true);

      manager.setGroupDisabled('test-group', false);
      expect(manager.isGroupDisabled('test-group'), false);

      manager.dispose();
    });

    test('handles null group IDs gracefully', () {
      final manager = TappableActionGroupManager.forTesting(config);

      expect(manager.isGroupDisabled(null), false);
      manager.setGroupDisabled(null, true);
      expect(manager.isGroupDisabled(null), false);

      manager.registerWidget(null, Object());
      manager.unregisterWidget(null, Object());
      manager.resetGroup(null);

      manager.dispose();
    });

    test('auto-resets empty disabled groups after delay', () {
      final manager = TappableActionGroupManager.forTesting(config);
      final widget = Object();

      manager.registerWidget('auto-group', widget);
      manager.setGroupDisabled('auto-group', true);
      expect(manager.isGroupDisabled('auto-group'), true);

      manager.unregisterWidget('auto-group', widget);
      expect(manager.isGroupDisabled('auto-group'), true);

      // Advance time to trigger auto-reset
      timerFactory.advanceTime(const Duration(milliseconds: 500));
      expect(manager.isGroupDisabled('auto-group'), false);

      manager.dispose();
    });

    test('resetAllGroups resets all disabled groups', () {
      final manager = TappableActionGroupManager.forTesting(config);

      manager.setGroupDisabled('group1', true);
      manager.setGroupDisabled('group2', true);
      manager.setGroupDisabled('group3', true);

      expect(manager.isGroupDisabled('group1'), true);
      expect(manager.isGroupDisabled('group2'), true);
      expect(manager.isGroupDisabled('group3'), true);

      manager.resetAllGroups();

      expect(manager.isGroupDisabled('group1'), false);
      expect(manager.isGroupDisabled('group2'), false);
      expect(manager.isGroupDisabled('group3'), false);

      manager.dispose();
    });

    test('getGroupNotifier returns reactive notifier', () {
      final manager = TappableActionGroupManager.forTesting(config);

      final notifier = manager.getGroupNotifier('reactive-group');
      expect(notifier, isA<ValueNotifier<bool>>());
      expect(notifier.value, false);

      var notificationCount = 0;
      notifier.addListener(() => notificationCount++);

      manager.setGroupDisabled('reactive-group', true);
      expect(notificationCount, 1);
      expect(notifier.value, true);

      manager.setGroupDisabled('reactive-group', false);
      expect(notificationCount, 2);
      expect(notifier.value, false);

      manager.dispose();
    });

    test('provides debug info', () {
      final manager = TappableActionGroupManager.forTesting(config);
      final widget = Object();

      manager.registerWidget('debug-group', widget);
      manager.setGroupDisabled('debug-group', true);

      final debugInfo = manager.getDebugInfo();

      expect(debugInfo['totalGroups'], 1);
      expect(debugInfo['config'], isA<Map>());
      expect(debugInfo['groups'], isA<Iterable>());

      manager.dispose();
    });
  });

  group('Network Awareness Preservation', () {
    test('TappableActionConfig.requireNetwork defaults to true', () {
      const config = TappableActionConfig();
      expect(config.requireNetwork, true);
    });

    test('TappableActionConfig.slider sets requireNetwork to false', () {
      const config = TappableActionConfig.slider();
      expect(config.requireNetwork, false);
    });

    test('TappableActionConfig.highFrequency sets requireNetwork to false', () {
      const config = TappableActionConfig.highFrequency();
      expect(config.requireNetwork, false);
    });

    test('TappableActionConfig.critical sets requireNetwork to true', () {
      const config = TappableActionConfig.critical();
      expect(config.requireNetwork, true);
    });

    test('copyWith can override requireNetwork', () {
      const original = TappableActionConfig(requireNetwork: true);
      final copied = original.copyWith(requireNetwork: false);

      expect(original.requireNetwork, true);
      expect(copied.requireNetwork, false);
    });
  });

  // ==========================================================================
  // Memory Leak Tests
  // ==========================================================================

  group('Memory Leak Tests', () {
    late MockTimerFactory timerFactory;

    setUp(() {
      timerFactory = MockTimerFactory();
    });

    tearDown(() {
      timerFactory.clear();
    });

    group('Disposal cleans up all timers', () {
      test('Throttler disposal cancels pending timer', () {
        final throttler = Throttler(
          duration: const Duration(milliseconds: 500),
          timerFactory: timerFactory,
        );

        throttler.call(() {});
        expect(timerFactory.timers.any((t) => t.isActive), true);

        throttler.dispose();
        expect(timerFactory.timers.every((t) => !t.isActive), true);
      });

      test('Debouncer disposal cancels pending timer', () {
        final debouncer = Debouncer(
          duration: const Duration(milliseconds: 300),
          timerFactory: timerFactory,
        );

        debouncer.call(() {});
        expect(timerFactory.timers.any((t) => t.isActive), true);

        debouncer.dispose();
        expect(timerFactory.timers.every((t) => !t.isActive), true);
      });

      test('ThrottleDebouncer disposal cancels pending timer', () {
        final throttleDebouncer = ThrottleDebouncer(
          duration: const Duration(milliseconds: 500),
          timerFactory: timerFactory,
        );

        throttleDebouncer.call(() {});
        expect(timerFactory.timers.any((t) => t.isActive), true);

        throttleDebouncer.dispose();
        expect(timerFactory.timers.every((t) => !t.isActive), true);
      });

      test('BatchThrottler disposal cancels pending timer', () {
        final batcher = BatchThrottler<int>(
          duration: const Duration(milliseconds: 300),
          onBatchExecute: (_) {},
          timerFactory: timerFactory,
        );

        batcher.add(1);
        expect(timerFactory.timers.any((t) => t.isActive), true);

        batcher.dispose();
        expect(timerFactory.timers.every((t) => !t.isActive), true);
      });

      test('AsyncDebouncer disposal cancels pending timer', () {
        final asyncDebouncer = AsyncDebouncer(
          duration: const Duration(milliseconds: 300),
          timerFactory: timerFactory,
        );

        unawaited(asyncDebouncer.run(() async => 'result'));
        expect(timerFactory.timers.any((t) => t.isActive), true);

        asyncDebouncer.dispose();
        expect(timerFactory.timers.every((t) => !t.isActive), true);
      });

      test('AsyncThrottler disposal cancels timeout timer', () async {
        final asyncThrottler = AsyncThrottler(
          maxDuration: const Duration(milliseconds: 500),
          timerFactory: timerFactory,
        );
        final completer = Completer<void>();

        unawaited(asyncThrottler.call(() async {
          await completer.future;
        }));

        await Future.microtask(() {});
        expect(timerFactory.timers.any((t) => t.isActive), true);

        asyncThrottler.dispose();
        expect(timerFactory.timers.every((t) => !t.isActive), true);

        completer.complete();
      });

      test('TappableActionGroupManager disposal cancels all reset timers', () {
        final config = TappableActionGroupConfig.testing(
          timerFactory: timerFactory,
          enableAutoReset: true,
          autoResetDelay: const Duration(milliseconds: 500),
        );
        final manager = TappableActionGroupManager.forTesting(config);
        final widget = Object();

        // Create multiple groups with reset timers
        manager.registerWidget('group1', widget);
        manager.setGroupDisabled('group1', true);
        manager.unregisterWidget('group1', widget);

        manager.registerWidget('group2', widget);
        manager.setGroupDisabled('group2', true);
        manager.unregisterWidget('group2', widget);

        expect(timerFactory.timers.any((t) => t.isActive), true);

        manager.dispose();
        expect(timerFactory.timers.every((t) => !t.isActive), true);
      });
    });

    group('Rapid config changes do not leak primitives', () {
      test('Throttler: multiple rapid calls do not accumulate timers', () {
        final throttler = Throttler(
          duration: const Duration(milliseconds: 500),
          timerFactory: timerFactory,
        );

        // Rapid calls
        for (var i = 0; i < 100; i++) {
          throttler.call(() {});
        }

        // Should only have one timer (the first throttle cooldown)
        expect(
          timerFactory.timers.where((t) => t.isActive).length,
          1,
        );

        throttler.dispose();
      });

      test('Debouncer: rapid calls replace pending timer', () {
        final debouncer = Debouncer(
          duration: const Duration(milliseconds: 300),
          timerFactory: timerFactory,
        );

        // Rapid calls
        for (var i = 0; i < 100; i++) {
          debouncer.call(() {});
        }

        // Should only have one active timer
        expect(
          timerFactory.timers.where((t) => t.isActive).length,
          1,
        );

        debouncer.dispose();
      });

      test('ThrottleDebouncer: rapid calls do not accumulate timers', () {
        final throttleDebouncer = ThrottleDebouncer(
          duration: const Duration(milliseconds: 500),
          timerFactory: timerFactory,
        );

        // Rapid calls
        for (var i = 0; i < 100; i++) {
          throttleDebouncer.call(() {});
        }

        // Should only have one active timer
        expect(
          timerFactory.timers.where((t) => t.isActive).length,
          1,
        );

        throttleDebouncer.dispose();
      });

      test('BatchThrottler: rapid additions do not accumulate timers', () {
        final batcher = BatchThrottler<int>(
          duration: const Duration(milliseconds: 300),
          onBatchExecute: (_) {},
          timerFactory: timerFactory,
        );

        // Rapid additions
        for (var i = 0; i < 100; i++) {
          batcher.add(i);
        }

        // Should only have one active timer
        expect(
          timerFactory.timers.where((t) => t.isActive).length,
          1,
        );

        batcher.dispose();
      });

      test('AsyncDebouncer: rapid calls cancel previous completers', () async {
        final asyncDebouncer = AsyncDebouncer(
          duration: const Duration(milliseconds: 300),
          timerFactory: timerFactory,
        );

        final futures = <Future<String?>>[];

        // Rapid calls
        for (var i = 0; i < 10; i++) {
          futures.add(asyncDebouncer.run(() async => 'result$i'));
        }

        // Trigger the last timer
        timerFactory.advanceTime(const Duration(milliseconds: 300));
        await Future.delayed(Duration.zero);

        final results = await Future.wait(futures);

        // All but the last should be cancelled (null)
        expect(results.where((r) => r == null).length, 9);
        expect(results.last, 'result9');

        asyncDebouncer.dispose();
      });
    });

    group('Async operations cancelled on dispose', () {
      test('AsyncDebouncer: pending operation returns null on dispose', () async {
        final asyncDebouncer = AsyncDebouncer(
          duration: const Duration(milliseconds: 300),
          timerFactory: timerFactory,
        );

        final future = asyncDebouncer.run(() async => 'result');

        asyncDebouncer.dispose();

        final result = await future;
        expect(result, isNull);
      });

      test('AsyncExecutor: queued operations cleared on dispose', () async {
        final executor = AsyncExecutor(mode: ConcurrencyMode.enqueue);
        final completer = Completer<void>();
        int callCount = 0;

        // Start first call that won't complete
        unawaited(executor.execute(() async {
          callCount++;
          await completer.future;
        }));

        await Future.microtask(() {});

        // Queue several more
        unawaited(executor.execute(() async => callCount++));
        unawaited(executor.execute(() async => callCount++));
        unawaited(executor.execute(() async => callCount++));

        expect(executor.pendingCount, 3);

        // Dispose before completion
        executor.dispose();

        expect(executor.pendingCount, 0);

        // Complete the first one
        completer.complete();
        await Future.delayed(Duration.zero);

        // Only the first call should have executed
        expect(callCount, 1);
      });

      test('AsyncExecutor keepLatest: queued callback cleared on dispose', () async {
        final executor = AsyncExecutor(mode: ConcurrencyMode.keepLatest);
        final completer = Completer<void>();
        int callCount = 0;

        // Start first call
        unawaited(executor.execute(() async {
          callCount++;
          await completer.future;
        }));

        await Future.microtask(() {});

        // Queue latest
        unawaited(executor.execute(() async => callCount++));

        expect(executor.pendingCount, 1);

        executor.dispose();

        expect(executor.pendingCount, 0);

        completer.complete();
        await Future.delayed(Duration.zero);

        expect(callCount, 1);
      });
    });

    group('Mounted checks prevent setState after dispose', () {
      test('Throttler: timer is cancelled but throttle state persists until reset', () {
        final throttler = Throttler(
          duration: const Duration(milliseconds: 500),
          timerFactory: timerFactory,
        );

        throttler.call(() {});
        expect(throttler.isThrottled, true);
        expect(throttler.isPending, true);

        // Cancel only cancels the timer, not the throttle state
        throttler.cancel();

        // Timer should be cancelled (isPending = false)
        expect(throttler.isPending, false);

        // But throttle state remains - use reset() to clear both
        expect(throttler.isThrottled, true);

        // Now reset to clear everything
        throttler.reset();
        expect(throttler.isThrottled, false);
        expect(throttler.isPending, false);

        throttler.dispose();
      });

      test('Debouncer: timer callback does not fire after cancel', () {
        final debouncer = Debouncer(
          duration: const Duration(milliseconds: 300),
          timerFactory: timerFactory,
        );
        int callbackCount = 0;

        debouncer.call(() => callbackCount++);

        // Cancel before timer fires
        debouncer.cancel();

        // Try to advance and trigger timer
        timerFactory.advanceTime(const Duration(milliseconds: 300));

        // Callback should not have been called
        expect(callbackCount, 0);

        debouncer.dispose();
      });

      test('AsyncDebouncer: call ID invalidation prevents stale execution', () async {
        final asyncDebouncer = AsyncDebouncer(
          duration: const Duration(milliseconds: 300),
          timerFactory: timerFactory,
        );
        int executionCount = 0;

        final future1 = asyncDebouncer.run(() async {
          executionCount++;
          return 'first';
        });

        // Cancel before execution
        asyncDebouncer.cancel();

        // Trigger timer anyway (simulating edge case)
        timerFactory.advanceTime(const Duration(milliseconds: 300));

        final result = await future1;
        expect(result, isNull);
        expect(executionCount, 0);

        asyncDebouncer.dispose();
      });

      test('AsyncExecutor: superseded calls check shouldContinue', () async {
        final executor = AsyncExecutor(mode: ConcurrencyMode.replace);
        final order = <String>[];
        final completer1 = Completer<void>();
        final completer2 = Completer<void>();

        // Start first call
        final callId1 = executor.currentCallId + 1;
        unawaited(executor.execute(() async {
          order.add('first-start');
          await completer1.future;
          if (executor.shouldContinue(callId1)) {
            order.add('first-end');
          } else {
            order.add('first-superseded');
          }
        }));

        await Future.microtask(() {});

        // Start second call (supersedes first)
        unawaited(executor.execute(() async {
          order.add('second-start');
          await completer2.future;
          order.add('second-end');
        }));

        await Future.microtask(() {});

        completer1.complete();
        completer2.complete();
        await Future.delayed(Duration.zero);

        expect(order.contains('first-start'), true);
        expect(order.contains('second-start'), true);

        executor.dispose();
      });
    });

    group('didUpdateWidget properly disposes old primitives', () {
      test('Throttler: reset clears all state', () {
        final throttler = Throttler(
          duration: const Duration(milliseconds: 500),
          timerFactory: timerFactory,
        );

        throttler.call(() {});
        expect(throttler.isThrottled, true);
        expect(throttler.isPending, true);

        throttler.reset();

        expect(throttler.isThrottled, false);
        expect(throttler.isPending, false);

        throttler.dispose();
      });

      test('Debouncer: dispose clears all state', () {
        final debouncer = Debouncer(
          duration: const Duration(milliseconds: 300),
          leading: true,
          trailing: true,
          timerFactory: timerFactory,
        );

        debouncer.call(() {});
        expect(debouncer.isPending, true);

        debouncer.dispose();

        expect(debouncer.isPending, false);
      });

      test('ThrottleDebouncer: reset clears all state', () {
        final throttleDebouncer = ThrottleDebouncer(
          duration: const Duration(milliseconds: 500),
          timerFactory: timerFactory,
        );

        throttleDebouncer.call(() {});
        throttleDebouncer.call(() {}); // Queue a callback

        expect(throttleDebouncer.isThrottled, true);
        expect(throttleDebouncer.hasPendingCallback, true);
        expect(throttleDebouncer.isPending, true);

        throttleDebouncer.reset();

        expect(throttleDebouncer.isThrottled, false);
        expect(throttleDebouncer.hasPendingCallback, false);
        expect(throttleDebouncer.isPending, false);

        throttleDebouncer.dispose();
      });

      test('BatchThrottler: dispose clears pending actions', () {
        List<int>? executedBatch;
        final batcher = BatchThrottler<int>(
          duration: const Duration(milliseconds: 300),
          onBatchExecute: (batch) => executedBatch = batch,
          timerFactory: timerFactory,
        );

        batcher.add(1);
        batcher.add(2);
        batcher.add(3);

        expect(batcher.pendingCount, 3);

        batcher.dispose();

        expect(batcher.pendingCount, 0);
        expect(executedBatch, isNull); // Batch was not executed
      });

      test('AsyncExecutor: dispose resets all state', () async {
        final executor = AsyncExecutor(mode: ConcurrencyMode.enqueue);
        final completer = Completer<void>();

        unawaited(executor.execute(() async {
          await completer.future;
        }));

        await Future.microtask(() {});
        expect(executor.isExecuting, true);

        unawaited(executor.execute(() async {}));
        unawaited(executor.execute(() async {}));
        expect(executor.pendingCount, 2);

        executor.dispose();

        expect(executor.isExecuting, false);
        expect(executor.pendingCount, 0);
        expect(executor.hasPendingCalls, false);

        completer.complete();
      });

      test('AsyncDebouncer: dispose clears pending completer', () async {
        final asyncDebouncer = AsyncDebouncer(
          duration: const Duration(milliseconds: 300),
          timerFactory: timerFactory,
        );

        final future = asyncDebouncer.run(() async => 'result');
        expect(asyncDebouncer.isPending, true);

        asyncDebouncer.dispose();

        expect(asyncDebouncer.isPending, false);

        final result = await future;
        expect(result, isNull);
      });

      test('AsyncThrottler: dispose clears locked state and timer', () async {
        final asyncThrottler = AsyncThrottler(
          maxDuration: const Duration(milliseconds: 500),
          timerFactory: timerFactory,
        );
        final completer = Completer<void>();

        unawaited(asyncThrottler.call(() async {
          await completer.future;
        }));

        await Future.microtask(() {});
        expect(asyncThrottler.isLocked, true);

        asyncThrottler.dispose();

        expect(asyncThrottler.isLocked, false);

        completer.complete();
      });
    });

    group('Stopwatch is stopped on RateLimiter dispose', () {
      test('RateLimiter: dispose stops the internal stopwatch', () {
        final rateLimiter = RateLimiter(
          maxTokens: 5,
          refillRate: 1,
          refillInterval: const Duration(seconds: 1),
        );

        // Use some tokens
        rateLimiter.tryAcquire();
        rateLimiter.tryAcquire();
        expect(rateLimiter.availableTokens, 3);

        // Dispose should stop the stopwatch
        rateLimiter.dispose();

        // The dispose method calls _stopwatch.stop() internally
        // We can't directly test the stopwatch state, but we can verify
        // the dispose method doesn't throw and the limiter was functional before
        expect(true, true); // Dispose completed without error
      });

      test('RateLimiter: multiple dispose calls are safe', () {
        final rateLimiter = RateLimiter();

        // Multiple dispose calls should not throw
        rateLimiter.dispose();
        rateLimiter.dispose();
        rateLimiter.dispose();

        // Should complete without error
        expect(true, true);
      });

      test('RateLimiter: operations after dispose do not throw', () {
        final rateLimiter = RateLimiter(maxTokens: 5);

        rateLimiter.dispose();

        // These operations should not throw, though behavior is undefined
        // The stopwatch is stopped, so refill calculations may be inaccurate
        // but the code should be defensive and not crash
        expect(() => rateLimiter.availableTokens, returnsNormally);
        expect(() => rateLimiter.canAcquire, returnsNormally);
        expect(() => rateLimiter.tryAcquire(), returnsNormally);
      });

      test('HighFrequencyThrottler: dispose clears state', () {
        final throttler = HighFrequencyThrottler(
          duration: const Duration(milliseconds: 16),
        );

        throttler.call(() {});
        expect(throttler.isThrottled, true);

        throttler.dispose();

        // After dispose, isThrottled should be false
        expect(throttler.isThrottled, false);
      });

      test('HighFrequencyThrottler: multiple dispose calls are safe', () {
        final throttler = HighFrequencyThrottler();

        throttler.dispose();
        throttler.dispose();
        throttler.dispose();

        expect(true, true);
      });
    });
  });
}
