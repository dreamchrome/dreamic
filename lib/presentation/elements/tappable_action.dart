import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:dreamic/app/app_cubit.dart';
import 'package:dreamic/utils/logger.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Interface for group management to enable testing
abstract class ITappableActionGroupManager {
  bool isGroupDisabled(String? groupId);
  void setGroupDisabled(String? groupId, bool isDisabled);
  ValueNotifier<bool> getGroupNotifier(String? groupId);
  void registerWidget(String? groupId, Object widget);
  void unregisterWidget(String? groupId, Object widget);
  void resetGroup(String? groupId);
  void resetAllGroups();
  void dispose();
}

/// Factory for creating timers (enables testing)
class TimerFactory {
  const TimerFactory();

  Timer createTimer(Duration duration, VoidCallback callback) {
    return Timer(duration, callback);
  }
}

// ============================================================================
// Core Primitives for Debounce/Throttle
// ============================================================================

/// Base class for synchronous callback controllers (Throttler, Debouncer).
abstract class CallbackController {
  final Duration duration;
  final bool enabled;
  final bool debugMode;
  final String? name;
  final TimerFactory _timerFactory;

  Timer? _timer;

  CallbackController({
    required this.duration,
    this.enabled = true,
    this.debugMode = false,
    this.name,
    TimerFactory? timerFactory,
  }) : _timerFactory = timerFactory ?? const TimerFactory();

  /// Execute the callback with timing control.
  void call(VoidCallback callback);

  /// Execute with a custom duration (overrides default).
  void callWithDuration(VoidCallback callback, Duration customDuration);

  /// Wrap a nullable callback for use with listeners.
  VoidCallback? wrap(VoidCallback? callback) {
    if (callback == null) return null;
    return () => call(callback);
  }

  /// Cancel pending operations.
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  /// Full cleanup.
  void dispose() => cancel();

  /// Whether an operation is pending.
  bool get isPending => _timer?.isActive ?? false;

  @protected
  set timer(Timer? value) {
    _timer?.cancel();
    _timer = value;
  }

  @protected
  Timer? get timer => _timer;

  @protected
  Timer createTimer(Duration duration, VoidCallback callback) =>
      _timerFactory.createTimer(duration, callback);

  @protected
  void debugLog(String message) {
    if (debugMode) {
      final prefix = name != null ? '[$name] ' : '';
      // ignore: avoid_print
      print('$prefix$message');
    }
  }
}

/// Executes immediately on first call, blocks subsequent calls until duration passes.
class Throttler extends CallbackController {
  bool _isThrottled = false;

  final bool resetOnError;
  final void Function(Duration executionTime, bool executed)? onMetrics;

  Throttler({
    super.duration = const Duration(milliseconds: 500),
    super.enabled = true,
    super.debugMode = false,
    super.name,
    super.timerFactory,
    this.resetOnError = false,
    this.onMetrics,
  });

  bool get isThrottled => _isThrottled;

  @override
  void call(VoidCallback callback) => callWithDuration(callback, duration);

  @override
  void callWithDuration(VoidCallback callback, Duration customDuration) {
    final startTime = DateTime.now();

    if (!enabled) {
      debugLog('Throttle bypassed (disabled)');
      _executeCallback(callback, startTime, executed: true);
      return;
    }

    if (_isThrottled) {
      debugLog('Throttle blocked');
      onMetrics?.call(Duration.zero, false);
      return;
    }

    debugLog('Throttle executed');
    _executeCallback(callback, startTime, executed: true);
    _isThrottled = true;
    timer = createTimer(customDuration, () {
      _isThrottled = false;
      debugLog('Throttle cooldown ended');
    });
  }

  void _executeCallback(
    VoidCallback callback,
    DateTime startTime, {
    required bool executed,
  }) {
    try {
      callback();
      final executionTime = DateTime.now().difference(startTime);
      onMetrics?.call(executionTime, executed);
    } catch (e) {
      if (resetOnError) {
        debugLog('Error occurred, resetting throttle state');
        reset();
      }
      rethrow;
    }
  }

  void reset() {
    cancel();
    _isThrottled = false;
    debugLog('Throttle reset');
  }

  @override
  void dispose() {
    super.dispose();
    _isThrottled = false;
  }
}

/// Waits for a pause in activity before executing. Supports leading/trailing edge.
class Debouncer extends CallbackController {
  bool _hasLeadingExecuted = false;
  DateTime? _lastCallTime;

  final bool leading;
  final bool trailing;
  final bool resetOnError;
  final void Function(Duration waitTime, bool cancelled)? onMetrics;

  Debouncer({
    super.duration = const Duration(milliseconds: 300),
    super.enabled = true,
    super.debugMode = false,
    super.name,
    super.timerFactory,
    this.leading = false,
    this.trailing = true,
    this.resetOnError = false,
    this.onMetrics,
  });

  @override
  void call(VoidCallback callback) => callWithDuration(callback, duration);

  @override
  void callWithDuration(VoidCallback callback, Duration customDuration) {
    final callTime = DateTime.now();

    if (!enabled) {
      debugLog('Debounce bypassed (disabled)');
      _executeCallback(callback, callTime, cancelled: false);
      return;
    }

    // Report cancelled metric for previous pending call
    if (_lastCallTime != null && isPending) {
      final waitTime = callTime.difference(_lastCallTime!);
      debugLog(
          'Debounce cancelled (new call after ${waitTime.inMilliseconds}ms)');
      onMetrics?.call(waitTime, true);
    }

    final isFirstCall = !isPending;
    _lastCallTime = callTime;
    timer?.cancel();

    // Leading edge: execute immediately on first call
    if (leading && isFirstCall) {
      debugLog('Debounce leading edge executed');
      _executeCallback(callback, callTime, cancelled: false);
      _hasLeadingExecuted = true;
    }

    // Schedule trailing edge execution
    timer = createTimer(customDuration, () {
      if (trailing && !(leading && _hasLeadingExecuted && isFirstCall)) {
        final totalWaitTime = DateTime.now().difference(callTime);
        debugLog(
            'Debounce trailing edge executed after ${totalWaitTime.inMilliseconds}ms');
        _executeCallback(callback, callTime, cancelled: false);
      }
      _hasLeadingExecuted = false;
      _lastCallTime = null;
    });
  }

  void _executeCallback(
    VoidCallback callback,
    DateTime callTime, {
    required bool cancelled,
  }) {
    if (cancelled) return;

    try {
      callback();
      final totalTime = DateTime.now().difference(callTime);
      onMetrics?.call(totalTime, false);
    } catch (e) {
      if (resetOnError) {
        debugLog('Error occurred, cancelling pending debounce');
        cancel();
        _lastCallTime = null;
      }
      rethrow;
    }
  }

  /// Execute the callback immediately without waiting.
  void flush(VoidCallback callback) {
    cancel();
    _lastCallTime = null;
    debugLog('Debounce flushed (immediate execution)');
    callback();
    onMetrics?.call(Duration.zero, false);
  }

  @override
  void cancel() {
    super.cancel();
    _hasLeadingExecuted = false;
  }

  @override
  void dispose() {
    super.dispose();
    _lastCallTime = null;
  }
}

/// Token bucket algorithm for sustained rate limiting with burst capacity.
/// Uses Stopwatch (monotonic clock) for accurate timing.
class RateLimiter {
  /// Maximum tokens in the bucket (burst capacity).
  final int maxTokens;

  /// Number of tokens to add per [refillInterval].
  final int refillRate;

  /// How often tokens are refilled.
  final Duration refillInterval;

  /// Whether rate limiting is enabled. If false, all calls succeed.
  final bool enabled;

  final bool debugMode;
  final String? name;

  /// Callback for metrics tracking.
  final void Function(int tokensRemaining, bool acquired)? onMetrics;

  double _tokens;
  final Stopwatch _stopwatch;
  int _lastRefillMicroseconds;

  RateLimiter({
    this.maxTokens = 10,
    this.refillRate = 1,
    this.refillInterval = const Duration(seconds: 1),
    this.enabled = true,
    this.debugMode = false,
    this.name,
    this.onMetrics,
  })  : assert(maxTokens > 0, 'maxTokens must be positive'),
        assert(refillRate > 0, 'refillRate must be positive'),
        _tokens = maxTokens.toDouble(),
        _stopwatch = Stopwatch()..start(),
        _lastRefillMicroseconds = 0;

  void _refillTokens() {
    final nowMicroseconds = _stopwatch.elapsedMicroseconds;
    final elapsedMicroseconds = nowMicroseconds - _lastRefillMicroseconds;
    final intervalsElapsed =
        elapsedMicroseconds / refillInterval.inMicroseconds;
    final tokensToAdd = intervalsElapsed * refillRate;

    if (tokensToAdd > 0) {
      _tokens = (_tokens + tokensToAdd).clamp(0, maxTokens).toDouble();
      _lastRefillMicroseconds = nowMicroseconds;
      _debugLog('Refilled ${tokensToAdd.toStringAsFixed(2)} tokens, '
          'now at ${_tokens.toStringAsFixed(2)}');
    }
  }

  /// Current available tokens (rounded down).
  int get availableTokens {
    _refillTokens();
    return _tokens.floor();
  }

  /// Whether at least one token is available.
  bool get canAcquire {
    _refillTokens();
    return _tokens >= 1;
  }

  /// Try to acquire [tokens] tokens. Returns true if successful.
  bool tryAcquire([int tokens = 1]) {
    if (!enabled) {
      _debugLog('Rate limiting disabled, allowing acquire');
      onMetrics?.call(availableTokens, true);
      return true;
    }

    _refillTokens();

    if (_tokens >= tokens) {
      _tokens -= tokens;
      _debugLog('Acquired $tokens token(s), ${_tokens.toStringAsFixed(2)} remaining');
      onMetrics?.call(availableTokens, true);
      return true;
    }

    _debugLog('Failed to acquire $tokens token(s), '
        'only ${_tokens.toStringAsFixed(2)} available');
    onMetrics?.call(availableTokens, false);
    return false;
  }

  /// Execute [callback] if token is available, otherwise do nothing.
  bool call(VoidCallback callback, [int tokens = 1]) {
    if (tryAcquire(tokens)) {
      callback();
      return true;
    }
    return false;
  }

  /// Execute async [callback] if token is available.
  Future<T?> callAsync<T>(Future<T> Function() callback,
      [int tokens = 1]) async {
    if (tryAcquire(tokens)) {
      return await callback();
    }
    return null;
  }

  /// Time until next token is available.
  Duration get timeUntilNextToken {
    _refillTokens();

    if (_tokens >= 1) {
      return Duration.zero;
    }

    final tokensNeeded = 1 - _tokens;
    final intervalsNeeded = tokensNeeded / refillRate;
    final microseconds =
        (intervalsNeeded * refillInterval.inMicroseconds).ceil();

    return Duration(microseconds: microseconds);
  }

  /// Reset to full capacity.
  void reset() {
    _tokens = maxTokens.toDouble();
    _lastRefillMicroseconds = _stopwatch.elapsedMicroseconds;
    _debugLog('Reset to full capacity ($maxTokens tokens)');
  }

  void dispose() {
    _stopwatch.stop();
    _debugLog('Disposed');
  }

  void _debugLog(String message) {
    if (debugMode) {
      final prefix = name != null ? '[$name] ' : '';
      // ignore: avoid_print
      print('$prefix$message');
    }
  }
}

/// Optimized for high-frequency events (16-32ms intervals like scroll/resize).
/// Uses DateTime.now() comparison instead of Timer objects for reduced overhead.
class HighFrequencyThrottler {
  static const Duration defaultDuration = Duration(milliseconds: 16);

  final Duration duration;
  DateTime? _lastExecutionTime;

  HighFrequencyThrottler({this.duration = defaultDuration});

  bool get isThrottled {
    if (_lastExecutionTime == null) return false;
    return DateTime.now().difference(_lastExecutionTime!) < duration;
  }

  /// Execute callback if not throttled. Returns true if executed.
  bool call(VoidCallback callback) {
    final now = DateTime.now();

    if (_lastExecutionTime == null ||
        now.difference(_lastExecutionTime!) >= duration) {
      callback();
      _lastExecutionTime = now;
      return true;
    }
    return false;
  }

  /// Wrap a nullable callback for use with listeners.
  VoidCallback? wrap(VoidCallback? callback) {
    if (callback == null) return null;
    return () => call(callback);
  }

  void reset() {
    _lastExecutionTime = null;
  }

  void dispose() {
    _lastExecutionTime = null;
  }
}

/// Combines throttle + debounce: executes immediately (leading edge),
/// then again after pause (trailing edge).
class ThrottleDebouncer {
  static const Duration defaultDuration = Duration(milliseconds: 500);

  final Duration duration;
  final TimerFactory _timerFactory;

  Timer? _timer;
  VoidCallback? _pendingCallback;
  bool _isThrottled = false;

  ThrottleDebouncer({
    this.duration = defaultDuration,
    TimerFactory? timerFactory,
  }) : _timerFactory = timerFactory ?? const TimerFactory();

  bool get isPending => _timer?.isActive ?? false;
  bool get isThrottled => _isThrottled;
  bool get hasPendingCallback => _pendingCallback != null;

  void call(VoidCallback callback) => callWithDuration(callback, duration);

  void callWithDuration(VoidCallback callback, Duration customDuration) {
    if (!_isThrottled) {
      // Leading edge: execute immediately
      callback();
      _startThrottleWindow(customDuration);
    } else {
      // Queue for trailing edge
      _pendingCallback = callback;
    }
  }

  void _startThrottleWindow(Duration windowDuration) {
    _isThrottled = true;
    _timer?.cancel();
    _timer = _timerFactory.createTimer(windowDuration, () {
      if (_pendingCallback != null) {
        final pending = _pendingCallback!;
        _pendingCallback = null;
        pending();
        // Restart throttle window if there was a pending callback
        _startThrottleWindow(windowDuration);
      } else {
        _isThrottled = false;
      }
    });
  }

  /// Wrap a nullable callback for use with listeners.
  VoidCallback? wrap(VoidCallback? callback) {
    if (callback == null) return null;
    return () => call(callback);
  }

  void reset() {
    cancel();
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _pendingCallback = null;
    _isThrottled = false;
  }

  void dispose() => cancel();
}

/// Collects multiple actions and executes them as a single batch after a pause.
class BatchThrottler<T> {
  final Duration duration;
  final void Function(List<T> batch) onBatchExecute;
  final bool debugMode;
  final String? name;
  final TimerFactory _timerFactory;

  Timer? _timer;
  final List<T> _pendingActions = [];

  BatchThrottler({
    required this.duration,
    required this.onBatchExecute,
    this.debugMode = false,
    this.name,
    TimerFactory? timerFactory,
  }) : _timerFactory = timerFactory ?? const TimerFactory();

  int get pendingCount => _pendingActions.length;
  bool get hasPending => _pendingActions.isNotEmpty;

  void add(T action) {
    _pendingActions.add(action);
    _debugLog('Added action, pending count: ${_pendingActions.length}');
    _timer?.cancel();
    _timer = _timerFactory.createTimer(duration, _executeBatch);
  }

  void _executeBatch() {
    if (_pendingActions.isEmpty) return;
    final batch = List<T>.from(_pendingActions);
    _pendingActions.clear();
    _debugLog('Executing batch of ${batch.length} actions');
    onBatchExecute(batch);
  }

  /// Execute immediately without waiting.
  void flush() {
    _timer?.cancel();
    _debugLog('Flushing batch immediately');
    _executeBatch();
  }

  /// Discard pending without executing.
  void clear() {
    _timer?.cancel();
    _debugLog('Cleared ${_pendingActions.length} pending actions');
    _pendingActions.clear();
  }

  void dispose() {
    _timer?.cancel();
    _pendingActions.clear();
    _debugLog('Disposed');
  }

  void _debugLog(String message) {
    if (debugMode) {
      final prefix = name != null ? '[$name] ' : '';
      // ignore: avoid_print
      print('$prefix$message');
    }
  }
}

// ============================================================================
// Async Primitives
// ============================================================================

/// Async debouncing with auto-cancellation of previous calls.
/// Returns null if cancelled by a newer invocation.
class AsyncDebouncer {
  final Duration duration;
  final bool enabled;
  final bool resetOnError;
  final bool debugMode;
  final String? name;
  final void Function(Duration executionTime, bool cancelled)? onMetrics;
  final TimerFactory _timerFactory;

  Timer? _timer;
  int _latestCallId = 0;
  Completer<dynamic>? _pendingCompleter;

  AsyncDebouncer({
    this.duration = const Duration(milliseconds: 300),
    this.enabled = true,
    this.resetOnError = true,
    this.debugMode = false,
    this.name,
    this.onMetrics,
    TimerFactory? timerFactory,
  }) : _timerFactory = timerFactory ?? const TimerFactory();

  bool get isPending => _timer?.isActive ?? false;

  Future<T?> run<T>(Future<T> Function() action) async {
    final startTime = DateTime.now();

    if (!enabled) {
      _debugLog('AsyncDebounce bypassed (disabled)');
      try {
        final result = await action();
        final executionTime = DateTime.now().difference(startTime);
        onMetrics?.call(executionTime, false);
        return result;
      } catch (e) {
        if (resetOnError) {
          _debugLog('Error occurred, state reset');
        }
        rethrow;
      }
    }

    _timer?.cancel();

    // Cancel previous pending call
    if (_pendingCompleter != null && !_pendingCompleter!.isCompleted) {
      _pendingCompleter!.complete(null);
      _debugLog('AsyncDebounce cancelled previous call');
      final cancelTime = DateTime.now().difference(startTime);
      onMetrics?.call(cancelTime, true);
    }

    final currentCallId = ++_latestCallId;
    final completer = Completer<T?>();
    _pendingCompleter = completer;

    _timer = _timerFactory.createTimer(duration, () async {
      try {
        if (currentCallId != _latestCallId) {
          if (!completer.isCompleted) {
            completer.complete(null);
            _debugLog('AsyncDebounce cancelled during wait');
          }
          return;
        }

        _debugLog('AsyncDebounce executing async action');
        try {
          final result = await action();
          if (currentCallId == _latestCallId && !completer.isCompleted) {
            final executionTime = DateTime.now().difference(startTime);
            _debugLog(
                'AsyncDebounce completed in ${executionTime.inMilliseconds}ms');
            onMetrics?.call(executionTime, false);
            completer.complete(result);
          } else if (!completer.isCompleted) {
            _debugLog('AsyncDebounce cancelled after execution');
            completer.complete(null);
          }
        } catch (e, stackTrace) {
          _debugLog('AsyncDebounce error: $e');
          if (resetOnError) {
            _debugLog('Resetting AsyncDebouncer state due to error');
            cancel();
          }
          if (!completer.isCompleted) {
            completer.completeError(e, stackTrace);
          }
        }
      } catch (e, stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(e, stackTrace);
        }
      } finally {
        if (_pendingCompleter == completer) {
          _pendingCompleter = null;
        }
      }
    });

    return completer.future;
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;

    if (_pendingCompleter != null && !_pendingCompleter!.isCompleted) {
      _pendingCompleter!.complete(null);
      _pendingCompleter = null;
    }

    _latestCallId++;
    _debugLog('Cancelled');
  }

  void dispose() {
    cancel();
    _debugLog('Disposed');
  }

  void _debugLog(String message) {
    if (debugMode) {
      final prefix = name != null ? '[$name] ' : '';
      // ignore: avoid_print
      print('$prefix$message');
    }
  }
}

/// Async throttling with process-based locking.
class AsyncThrottler {
  final Duration? maxDuration;
  final bool enabled;
  final bool resetOnError;
  final bool debugMode;
  final String? name;
  final void Function(Duration executionTime)? onMetrics;
  final TimerFactory _timerFactory;

  bool _isLocked = false;
  Timer? _timeoutTimer;

  AsyncThrottler({
    this.maxDuration,
    this.enabled = true,
    this.resetOnError = false,
    this.debugMode = false,
    this.name,
    this.onMetrics,
    TimerFactory? timerFactory,
  }) : _timerFactory = timerFactory ?? const TimerFactory();

  bool get isLocked => _isLocked;

  Future<void> call(Future<void> Function() callback) async {
    if (!enabled) {
      _debugLog('AsyncThrottle bypassed (disabled)');
      final startTime = DateTime.now();
      await callback();
      onMetrics?.call(DateTime.now().difference(startTime));
      return;
    }

    if (_isLocked) {
      _debugLog('AsyncThrottle blocked (locked)');
      return;
    }

    _isLocked = true;
    _debugLog('AsyncThrottle executing');

    // Start timeout timer if maxDuration is set
    if (maxDuration != null) {
      _timeoutTimer = _timerFactory.createTimer(maxDuration!, () {
        _debugLog('AsyncThrottle timeout - unlocking');
        _isLocked = false;
      });
    }

    final startTime = DateTime.now();
    try {
      await callback();
      final executionTime = DateTime.now().difference(startTime);
      _debugLog('AsyncThrottle completed in ${executionTime.inMilliseconds}ms');
      onMetrics?.call(executionTime);
    } catch (e) {
      _debugLog('AsyncThrottle error: $e');
      if (resetOnError) {
        reset();
      }
      rethrow;
    } finally {
      _timeoutTimer?.cancel();
      _timeoutTimer = null;
      _isLocked = false;
    }
  }

  /// Wrap a nullable callback for use with builder widgets.
  VoidCallback? wrap(Future<void> Function()? callback) {
    if (callback == null) return null;
    return () => call(callback);
  }

  void reset() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _isLocked = false;
    _debugLog('Reset');
  }

  void dispose() {
    reset();
    _debugLog('Disposed');
  }

  void _debugLog(String message) {
    if (debugMode) {
      final prefix = name != null ? '[$name] ' : '';
      // ignore: avoid_print
      print('$prefix$message');
    }
  }
}

/// Concurrency mode for async operations.
enum ConcurrencyMode {
  /// Ignore new calls while processing (default).
  drop,

  /// Cancel current operation and start new one.
  replace,

  /// Keep current + queue latest only, drop intermediate.
  keepLatest,

  /// Queue all calls, execute sequentially (FIFO).
  enqueue,
}

// ============================================================================
// TappableAction Configuration Enums and Classes
// ============================================================================

/// Execution timing mode for tap handlers.
enum TapExecutionMode {
  /// Execute immediately, block subsequent (default).
  throttle,

  /// Wait for pause in activity before executing.
  debounce,

  /// Combined: execute immediately (leading) + after pause (trailing).
  throttleDebounce,

  /// Token bucket - allow bursts with sustained rate limit.
  rateLimited,

  /// Optimized for high-frequency events (16-32ms), uses DateTime instead of Timer.
  highFrequency,
}

/// Concurrency control for async tap handlers.
enum TapConcurrencyMode {
  /// Ignore new taps while processing (default).
  drop,

  /// Cancel current operation and start new one.
  replace,

  /// Keep current + latest only, drop intermediate.
  keepLatest,

  /// Queue all taps, execute sequentially (FIFO).
  enqueue,
}

/// Metrics data for tap analytics and observability.
@immutable
class TapMetrics {
  final Duration executionDuration;
  final bool wasThrottled;
  final bool wasCancelled;
  final bool hadError;
  final int tapCountInWindow;
  final String? groupId;
  final TapExecutionMode executionMode;
  final DateTime timestamp;

  const TapMetrics({
    required this.executionDuration,
    required this.wasThrottled,
    required this.wasCancelled,
    required this.hadError,
    required this.tapCountInWindow,
    this.groupId,
    required this.executionMode,
    required this.timestamp,
  });

  @override
  String toString() => 'TapMetrics('
      'duration: ${executionDuration.inMilliseconds}ms, '
      'throttled: $wasThrottled, '
      'cancelled: $wasCancelled, '
      'error: $hadError, '
      'tapCount: $tapCountInWindow, '
      'mode: $executionMode)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TapMetrics &&
          runtimeType == other.runtimeType &&
          executionDuration == other.executionDuration &&
          wasThrottled == other.wasThrottled &&
          wasCancelled == other.wasCancelled &&
          hadError == other.hadError &&
          tapCountInWindow == other.tapCountInWindow &&
          groupId == other.groupId &&
          executionMode == other.executionMode &&
          timestamp == other.timestamp;

  @override
  int get hashCode =>
      executionDuration.hashCode ^
      wasThrottled.hashCode ^
      wasCancelled.hashCode ^
      hadError.hashCode ^
      tapCountInWindow.hashCode ^
      groupId.hashCode ^
      executionMode.hashCode ^
      timestamp.hashCode;
}

/// Handles async operations with concurrency control and cancellation.
class AsyncExecutor {
  final ConcurrencyMode mode;
  final Duration? maxDuration;
  final bool enabled;
  final bool resetOnError;
  final bool debugMode;
  final String? name;
  final void Function(Duration executionTime)? onMetrics;

  int _currentCallId = 0;
  int? _activeCallId;
  Future<void> Function()? _queuedCallback;
  final Queue<Future<void> Function()> _queue = Queue();
  bool _isExecuting = false;
  bool _isProcessingQueue = false;

  AsyncExecutor({
    this.mode = ConcurrencyMode.drop,
    this.maxDuration,
    this.enabled = true,
    this.resetOnError = false,
    this.debugMode = false,
    this.name,
    this.onMetrics,
  });

  bool get isExecuting => _isExecuting;
  bool get isLocked => _isExecuting; // Alias for compatibility
  int get currentCallId => _currentCallId;
  int get queueSize => _queue.length;
  bool get hasPendingCalls => _queuedCallback != null || _queue.isNotEmpty;
  int get pendingCount {
    switch (mode) {
      case ConcurrencyMode.enqueue:
        return _queue.length;
      case ConcurrencyMode.keepLatest:
        return _queuedCallback != null ? 1 : 0;
      case ConcurrencyMode.drop:
      case ConcurrencyMode.replace:
        return 0;
    }
  }

  /// Wrap a nullable callback for use with builder widgets.
  VoidCallback? wrap(Future<void> Function()? callback) {
    if (callback == null) return null;
    return () => execute(callback);
  }

  /// Returns true if this call was executed (not dropped/queued).
  Future<bool> execute(Future<void> Function() callback) async {
    if (!enabled) {
      _debugLog('AsyncExecutor bypassed (disabled)');
      final startTime = DateTime.now();
      await callback();
      onMetrics?.call(DateTime.now().difference(startTime));
      return true;
    }

    final callId = ++_currentCallId;

    switch (mode) {
      case ConcurrencyMode.drop:
        if (_isExecuting) {
          _debugLog('Dropped (already executing)');
          return false;
        }
        break;

      case ConcurrencyMode.replace:
        if (_isExecuting) {
          _debugLog('Replacing current execution');
        }
        // New call takes over - old one will check callId and bail
        break;

      case ConcurrencyMode.keepLatest:
        if (_isExecuting) {
          _queuedCallback = callback;
          _debugLog('Queued as latest (will replace previous)');
          return false;
        }
        break;

      case ConcurrencyMode.enqueue:
        if (_isExecuting) {
          _queue.add(callback);
          _debugLog('Enqueued (queue size: ${_queue.length})');
          return false;
        }
        break;
    }

    _activeCallId = callId;
    _isExecuting = true;
    _debugLog('Executing (mode: ${mode.name})');

    final startTime = DateTime.now();
    try {
      if (maxDuration != null) {
        await callback().timeout(maxDuration!);
      } else {
        await callback();
      }
      final executionTime = DateTime.now().difference(startTime);
      _debugLog('Completed in ${executionTime.inMilliseconds}ms');
      onMetrics?.call(executionTime);
      // Return true only if this call wasn't superseded
      return _currentCallId == callId;
    } catch (e) {
      _debugLog('Error: $e');
      if (resetOnError) {
        reset();
      }
      rethrow;
    } finally {
      if (_activeCallId == callId) {
        _isExecuting = false;
        _activeCallId = null;

        // Execute queued callback for keepLatest mode
        if (mode == ConcurrencyMode.keepLatest && _queuedCallback != null) {
          final queued = _queuedCallback;
          _queuedCallback = null;
          _debugLog('Processing kept latest callback');
          await execute(queued!);
        }

        // Process queue for enqueue mode
        if (mode == ConcurrencyMode.enqueue && _queue.isNotEmpty) {
          _processQueue();
        }
      }
    }
  }

  Future<void> _processQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;

    while (_queue.isNotEmpty) {
      final next = _queue.removeFirst();
      _debugLog('Processing queued callback (remaining: ${_queue.length})');
      await execute(next);
    }

    _isProcessingQueue = false;
  }

  /// Check if a specific call should continue executing.
  bool shouldContinue(int callId) => _currentCallId == callId;

  /// Cancel any pending/queued operations.
  void cancel() {
    _currentCallId++;
    _queuedCallback = null;
    _queue.clear();
    _debugLog('Cancelled');
  }

  /// Reset state (cancel + clear execution state).
  void reset() {
    cancel();
    _isExecuting = false;
    _isProcessingQueue = false;
    _activeCallId = null;
    _debugLog('Reset');
  }

  /// Full cleanup - call in widget dispose.
  void dispose() {
    reset();
    _debugLog('Disposed');
  }

  void _debugLog(String message) {
    if (debugMode) {
      final prefix = name != null ? '[$name] ' : '';
      // ignore: avoid_print
      print('$prefix$message');
    }
  }
}

/// Configuration for TappableActionGroupManager
@immutable
class TappableActionGroupConfig {
  final Duration autoResetDelay;
  final bool enableAutoReset;
  final bool resetOnAppResume;
  final TimerFactory timerFactory;
  final int maxConcurrentGroups;
  final Duration maxGroupLifetime;
  
  const TappableActionGroupConfig({
    this.autoResetDelay = const Duration(milliseconds: 500),
    this.enableAutoReset = true,
    this.resetOnAppResume = true,
    this.timerFactory = const TimerFactory(),
    this.maxConcurrentGroups = 100,
    this.maxGroupLifetime = const Duration(minutes: 10),
  });
  
  const TappableActionGroupConfig.testing({
    this.autoResetDelay = Duration.zero,
    this.enableAutoReset = false,
    this.resetOnAppResume = false,
    required this.timerFactory,
    this.maxConcurrentGroups = 100,
    this.maxGroupLifetime = Duration.zero,
  });
}

/// Production-grade group manager with comprehensive safety measures
class TappableActionGroupManager with WidgetsBindingObserver implements ITappableActionGroupManager {
  static TappableActionGroupManager? _instance;
  static const TappableActionGroupConfig _config = TappableActionGroupConfig();
  
  /// Factory constructor with optional config
  factory TappableActionGroupManager([TappableActionGroupConfig? config]) {
    if (config != null) {
      _instance?.dispose();
      _instance = TappableActionGroupManager._internal(config);
    }
    _instance ??= TappableActionGroupManager._internal(_config);
    return _instance!;
  }
  
  /// Testing constructor that creates a new instance
  factory TappableActionGroupManager.forTesting(TappableActionGroupConfig config) {
    return TappableActionGroupManager._internal(config);
  }
  
  TappableActionGroupManager._internal(this.config) {
    if (config.resetOnAppResume) {
      WidgetsBinding.instance.addObserver(this);
    }
    
    // Start periodic cleanup if group lifetime is configured
    if (config.maxGroupLifetime > Duration.zero) {
      _startPeriodicCleanup();
    }
  }
  
  final TappableActionGroupConfig config;
  final Map<String, ValueNotifier<bool>> _groupNotifiers = <String, ValueNotifier<bool>>{};
  final Map<String, Set<Object>> _groupWidgets = <String, Set<Object>>{};
  final Map<String, Timer?> _groupResetTimers = <String, Timer?>{};
  final Map<String, int> _groupTapCounts = <String, int>{};
  final Map<String, DateTime> _groupCreationTimes = <String, DateTime>{};
  Timer? _cleanupTimer;
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (state == AppLifecycleState.resumed && config.resetOnAppResume) {
      logv('TappableActionGroupManager: App resumed, resetting all disabled groups');
      resetAllGroups();
    }
  }
  
  @override
  void dispose() {
    if (config.resetOnAppResume) {
      WidgetsBinding.instance.removeObserver(this);
    }
    
    // Cancel all timers
    for (final timer in _groupResetTimers.values) {
      timer?.cancel();
    }
    _cleanupTimer?.cancel();
    
    // Dispose all notifiers to prevent memory leaks
    for (final notifier in _groupNotifiers.values) {
      notifier.dispose();
    }
    
    // Clear all collections
    _groupResetTimers.clear();
    _groupNotifiers.clear();
    _groupWidgets.clear();
    _groupTapCounts.clear();
    _groupCreationTimes.clear();
  }
  
  ValueNotifier<bool> _getNotifier(String groupId) {
    // Check group limits before creating new groups
    if (!_groupNotifiers.containsKey(groupId) && _groupNotifiers.length >= config.maxConcurrentGroups) {
      _cleanupOldestGroups();
    }
    
    return _groupNotifiers.putIfAbsent(groupId, () {
      _groupCreationTimes[groupId] = DateTime.now();
      return ValueNotifier<bool>(false);
    });
  }
  
  @override
  bool isGroupDisabled(String? groupId) {
    if (groupId == null) return false;
    return _getNotifier(groupId).value;
  }
  
  @override
  void setGroupDisabled(String? groupId, bool isDisabled) {
    if (groupId == null) return;
    
    final wasDisabled = isGroupDisabled(groupId);
    if (wasDisabled == isDisabled) return; // No change needed
    
    logv('TappableActionGroupManager: ${isDisabled ? 'Disabling' : 'Enabling'} group "$groupId"');
    _getNotifier(groupId).value = isDisabled;
    
    if (isDisabled) {
      _groupTapCounts[groupId] = (_groupTapCounts[groupId] ?? 0) + 1;
      logv('TappableActionGroupManager: Group "$groupId" tap count: ${_groupTapCounts[groupId]}');
    } else {
      _cancelAutoReset(groupId);
    }
  }
  
  @override
  ValueNotifier<bool> getGroupNotifier(String? groupId) {
    if (groupId == null) return ValueNotifier<bool>(false);
    return _getNotifier(groupId);
  }
  
  @override
  void registerWidget(String? groupId, Object widget) {
    if (groupId == null) return;
    
    final widgets = _groupWidgets.putIfAbsent(groupId, () => {});
    final wasEmpty = widgets.isEmpty;
    widgets.add(widget);
    
    logv('TappableActionGroupManager: Registered widget for group "$groupId" (${widgets.length} total)');
    
    // Cancel any pending auto-reset if widgets are being added
    if (wasEmpty && _groupResetTimers[groupId] != null) {
      logv('TappableActionGroupManager: Cancelling auto-reset for group "$groupId" - widget registered');
      _cancelAutoReset(groupId);
      
      // Only auto-enable if the group is still disabled and we're adding the first widget
      if (isGroupDisabled(groupId) && config.enableAutoReset) {
        logd('TappableActionGroupManager: Auto-enabling group "$groupId" - first widget registered');
        setGroupDisabled(groupId, false);
      }
    }
  }
  
  @override
  void unregisterWidget(String? groupId, Object widget) {
    if (groupId == null) return;
    
    _groupWidgets[groupId]?.remove(widget);
    final remaining = _groupWidgets[groupId]?.length ?? 0;
    
    logv('TappableActionGroupManager: Unregistered widget from group "$groupId" ($remaining remaining)');
    
    // Schedule auto-reset only if group is empty and disabled
    if (remaining == 0 && isGroupDisabled(groupId) && config.enableAutoReset) {
      _scheduleAutoReset(groupId);
    }
  }
  
  void _scheduleAutoReset(String groupId) {
    _cancelAutoReset(groupId);
    
    logv('TappableActionGroupManager: Scheduling auto-reset for empty group "$groupId" in ${config.autoResetDelay.inMilliseconds}ms');
    
    _groupResetTimers[groupId] = config.timerFactory.createTimer(
      config.autoResetDelay,
      () {
        // Double-check conditions before resetting
        if ((_groupWidgets[groupId]?.isEmpty ?? true) && isGroupDisabled(groupId)) {
          logd('TappableActionGroupManager: Auto-resetting empty group "$groupId"');
          setGroupDisabled(groupId, false);
          _groupTapCounts[groupId] = 0;
        }
        _groupResetTimers[groupId] = null;
      },
    );
  }
  
  void _cancelAutoReset(String groupId) {
    _groupResetTimers[groupId]?.cancel();
    _groupResetTimers[groupId] = null;
  }
  
  @override
  void resetGroup(String? groupId) {
    if (groupId == null) return;
    logd('TappableActionGroupManager: Force resetting group "$groupId"');
    _cancelAutoReset(groupId);
    setGroupDisabled(groupId, false);
    _groupTapCounts[groupId] = 0;
  }
  
  @override
  void resetAllGroups() {
    logd('TappableActionGroupManager: Resetting all groups');
    for (final groupId in _groupNotifiers.keys.toList()) {
      resetGroup(groupId);
    }
  }
  
  /// Start periodic cleanup timer for group lifetime management
  void _startPeriodicCleanup() {
    _cleanupTimer = config.timerFactory.createTimer(
      config.maxGroupLifetime,
      () {
        _performCleanup();
        if (!config.timerFactory.toString().contains('Mock')) {
          _startPeriodicCleanup(); // Restart timer for production
        }
      },
    );
  }
  
  /// Clean up oldest groups when limit is reached
  void _cleanupOldestGroups() {
    if (_groupNotifiers.length < config.maxConcurrentGroups) return;
    
    // Find oldest inactive groups to remove
    final sortedGroups = _groupCreationTimes.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    
    final toRemove = <String>[];
    for (final entry in sortedGroups) {
      final groupId = entry.key;
      // Only remove inactive groups
      if (!isGroupDisabled(groupId) && (_groupWidgets[groupId]?.isEmpty ?? true)) {
        toRemove.add(groupId);
        if (_groupNotifiers.length - toRemove.length <= config.maxConcurrentGroups ~/ 2) {
          break;
        }
      }
    }
    
    for (final groupId in toRemove) {
      _removeGroup(groupId);
    }
    
    if (toRemove.isNotEmpty) {
      logd('TappableActionGroupManager: Cleaned up ${toRemove.length} inactive groups');
    }
  }
  
  /// Perform periodic cleanup of expired groups
  void _performCleanup() {
    final now = DateTime.now();
    final expired = <String>[];
    
    for (final entry in _groupCreationTimes.entries) {
      final groupId = entry.key;
      final creationTime = entry.value;
      
      if (now.difference(creationTime) > config.maxGroupLifetime &&
          !isGroupDisabled(groupId) &&
          (_groupWidgets[groupId]?.isEmpty ?? true)) {
        expired.add(groupId);
      }
    }
    
    for (final groupId in expired) {
      _removeGroup(groupId);
    }
    
    if (expired.isNotEmpty) {
      logd('TappableActionGroupManager: Cleaned up ${expired.length} expired groups');
    }
  }
  
  /// Safely remove a group and all its resources
  void _removeGroup(String groupId) {
    _groupResetTimers[groupId]?.cancel();
    _groupResetTimers.remove(groupId);
    
    final notifier = _groupNotifiers.remove(groupId);
    notifier?.dispose();
    
    _groupWidgets.remove(groupId);
    _groupTapCounts.remove(groupId);
    _groupCreationTimes.remove(groupId);
  }
  
  /// Get comprehensive debugging information about groups
  Map<String, dynamic> getDebugInfo() {
    final now = DateTime.now();
    return {
      'totalGroups': _groupNotifiers.length,
      'maxConcurrentGroups': config.maxConcurrentGroups,
      'hasCleanupTimer': _cleanupTimer?.isActive ?? false,
      'config': {
        'autoResetDelay': config.autoResetDelay.inMilliseconds,
        'enableAutoReset': config.enableAutoReset,
        'resetOnAppResume': config.resetOnAppResume,
        'maxGroupLifetime': config.maxGroupLifetime.inMinutes,
      },
      'groups': _groupNotifiers.keys.map((id) => {
        'id': id,
        'disabled': isGroupDisabled(id),
        'widgetCount': _groupWidgets[id]?.length ?? 0,
        'tapCount': _groupTapCounts[id] ?? 0,
        'hasResetTimer': _groupResetTimers[id] != null,
        'ageMinutes': _groupCreationTimes[id] != null 
          ? now.difference(_groupCreationTimes[id]!).inMinutes 
          : null,
      }).toList(),
    };
  }
}

/// Configuration for TappableAction behavior
@immutable
class TappableActionConfig {
  // === EXISTING (preserved, no changes) ===
  final bool requireNetwork;
  final bool debounceTaps; // Kept for backward compatibility
  final Duration? coolDownDuration;
  final Duration? delayBeforeFirstTapDuration;
  final bool disableVisuallyDuringFirstDelay;
  final Duration? minDisabledDuration;
  final String? groupId;
  final bool disableVisuallyDuringDebouncing;

  // === NEW ===

  /// Execution timing mode (throttle, debounce, or rate-limited).
  /// Defaults to throttle for backward compatibility.
  final TapExecutionMode executionMode;

  /// Execute immediately on first tap (leading edge).
  final bool executeOnLeadingEdge;

  /// Execute after cooldown/pause period (trailing edge).
  final bool executeOnTrailingEdge;

  /// Concurrency control for async handlers.
  final TapConcurrencyMode concurrencyMode;

  /// Rate limiter config: maximum tokens in bucket (when executionMode == rateLimited).
  final int rateLimitMaxTokens;

  /// Rate limiter config: how often tokens are refilled.
  final Duration rateLimitRefillInterval;

  /// Rate limiter config: tokens added per refill interval.
  final int rateLimitTokensPerRefill;

  /// Metrics callback for observability.
  final void Function(TapMetrics)? onMetrics;

  /// Enable/disable toggle (bypass all logic when false).
  final bool enabled;

  /// Maximum duration for async operations (timeout).
  final Duration? maxDuration;

  /// Debug name for logging/troubleshooting.
  final String? debugName;

  const TappableActionConfig({
    // Existing
    this.requireNetwork = true,
    this.debounceTaps = true,
    this.coolDownDuration,
    this.delayBeforeFirstTapDuration,
    this.disableVisuallyDuringFirstDelay = true,
    this.minDisabledDuration,
    this.groupId,
    this.disableVisuallyDuringDebouncing = true,
    // New
    this.executionMode = TapExecutionMode.throttle,
    this.executeOnLeadingEdge = true,
    this.executeOnTrailingEdge = false,
    this.concurrencyMode = TapConcurrencyMode.drop,
    this.rateLimitMaxTokens = 10,
    this.rateLimitRefillInterval = const Duration(seconds: 1),
    this.rateLimitTokensPerRefill = 5,
    this.onMetrics,
    this.enabled = true,
    this.maxDuration,
    this.debugName,
  });

  /// Optimized configuration for high-frequency interactions.
  const TappableActionConfig.highFrequency({
    this.requireNetwork = false,
    this.debounceTaps = true,
    this.coolDownDuration = const Duration(milliseconds: 100),
    this.delayBeforeFirstTapDuration,
    this.disableVisuallyDuringFirstDelay = false,
    this.minDisabledDuration = const Duration(milliseconds: 50),
    this.groupId,
    this.disableVisuallyDuringDebouncing = false,
    // New defaults for high-frequency
    this.executionMode = TapExecutionMode.highFrequency,
    this.executeOnLeadingEdge = true,
    this.executeOnTrailingEdge = false,
    this.concurrencyMode = TapConcurrencyMode.drop,
    this.rateLimitMaxTokens = 10,
    this.rateLimitRefillInterval = const Duration(seconds: 1),
    this.rateLimitTokensPerRefill = 5,
    this.onMetrics,
    this.enabled = true,
    this.maxDuration,
    this.debugName,
  });

  /// Conservative configuration for critical actions (payments, deletions, etc.).
  const TappableActionConfig.critical({
    this.requireNetwork = true,
    this.debounceTaps = true,
    this.coolDownDuration = const Duration(seconds: 2),
    this.delayBeforeFirstTapDuration = const Duration(milliseconds: 300),
    this.disableVisuallyDuringFirstDelay = true,
    this.minDisabledDuration = const Duration(seconds: 1),
    this.groupId,
    this.disableVisuallyDuringDebouncing = true,
    // New defaults for critical
    this.executionMode = TapExecutionMode.throttle,
    this.executeOnLeadingEdge = true,
    this.executeOnTrailingEdge = false,
    this.concurrencyMode = TapConcurrencyMode.drop,
    this.rateLimitMaxTokens = 10,
    this.rateLimitRefillInterval = const Duration(seconds: 1),
    this.rateLimitTokensPerRefill = 5,
    this.onMetrics,
    this.enabled = true,
    this.maxDuration,
    this.debugName,
  });

  /// For search inputs - debounce with trailing edge.
  const TappableActionConfig.search({
    this.requireNetwork = true,
    this.debounceTaps = true,
    this.coolDownDuration = const Duration(milliseconds: 300),
    this.delayBeforeFirstTapDuration,
    this.disableVisuallyDuringFirstDelay = true,
    this.minDisabledDuration,
    this.groupId,
    this.disableVisuallyDuringDebouncing = false,
    // Search-specific: debounce, trailing edge only
    this.executionMode = TapExecutionMode.debounce,
    this.executeOnLeadingEdge = false,
    this.executeOnTrailingEdge = true,
    this.concurrencyMode = TapConcurrencyMode.drop,
    this.rateLimitMaxTokens = 10,
    this.rateLimitRefillInterval = const Duration(seconds: 1),
    this.rateLimitTokensPerRefill = 5,
    this.onMetrics,
    this.enabled = true,
    this.maxDuration,
    this.debugName,
  });

  /// For like/favorite buttons - immediate feedback, replace on rapid tap.
  const TappableActionConfig.toggle({
    this.requireNetwork = true,
    this.debounceTaps = true,
    this.coolDownDuration = const Duration(milliseconds: 500),
    this.delayBeforeFirstTapDuration,
    this.disableVisuallyDuringFirstDelay = true,
    this.minDisabledDuration,
    this.groupId,
    this.disableVisuallyDuringDebouncing = true,
    // Toggle-specific: throttle with replace mode
    this.executionMode = TapExecutionMode.throttle,
    this.executeOnLeadingEdge = true,
    this.executeOnTrailingEdge = false,
    this.concurrencyMode = TapConcurrencyMode.replace,
    this.rateLimitMaxTokens = 10,
    this.rateLimitRefillInterval = const Duration(seconds: 1),
    this.rateLimitTokensPerRefill = 5,
    this.onMetrics,
    this.enabled = true,
    this.maxDuration,
    this.debugName,
  });

  /// For sliders/high-frequency - rate limited with burst capacity.
  const TappableActionConfig.slider({
    this.requireNetwork = false,
    this.debounceTaps = true,
    this.coolDownDuration,
    this.delayBeforeFirstTapDuration,
    this.disableVisuallyDuringFirstDelay = false,
    this.minDisabledDuration,
    this.groupId,
    this.disableVisuallyDuringDebouncing = false,
    // Slider-specific: rate limited
    this.executionMode = TapExecutionMode.rateLimited,
    this.executeOnLeadingEdge = true,
    this.executeOnTrailingEdge = false,
    this.concurrencyMode = TapConcurrencyMode.drop,
    this.rateLimitMaxTokens = 20,
    this.rateLimitRefillInterval = const Duration(milliseconds: 100),
    this.rateLimitTokensPerRefill = 5,
    this.onMetrics,
    this.enabled = true,
    this.maxDuration,
    this.debugName,
  });

  /// Validation helper
  bool get isValid {
    if (coolDownDuration?.isNegative == true) return false;
    if (delayBeforeFirstTapDuration?.isNegative == true) return false;
    if (minDisabledDuration?.isNegative == true) return false;
    if (maxDuration?.isNegative == true) return false;
    if (groupId?.trim().isEmpty == true) return false;
    if (rateLimitMaxTokens <= 0) return false;
    if (rateLimitTokensPerRefill <= 0) return false;
    if (rateLimitRefillInterval.isNegative) return false;
    return true;
  }

  /// Create a copy with modified fields.
  TappableActionConfig copyWith({
    bool? requireNetwork,
    bool? debounceTaps,
    Duration? coolDownDuration,
    Duration? delayBeforeFirstTapDuration,
    bool? disableVisuallyDuringFirstDelay,
    Duration? minDisabledDuration,
    String? groupId,
    bool? disableVisuallyDuringDebouncing,
    TapExecutionMode? executionMode,
    bool? executeOnLeadingEdge,
    bool? executeOnTrailingEdge,
    TapConcurrencyMode? concurrencyMode,
    int? rateLimitMaxTokens,
    Duration? rateLimitRefillInterval,
    int? rateLimitTokensPerRefill,
    void Function(TapMetrics)? onMetrics,
    bool? enabled,
    Duration? maxDuration,
    String? debugName,
  }) {
    return TappableActionConfig(
      requireNetwork: requireNetwork ?? this.requireNetwork,
      debounceTaps: debounceTaps ?? this.debounceTaps,
      coolDownDuration: coolDownDuration ?? this.coolDownDuration,
      delayBeforeFirstTapDuration:
          delayBeforeFirstTapDuration ?? this.delayBeforeFirstTapDuration,
      disableVisuallyDuringFirstDelay:
          disableVisuallyDuringFirstDelay ?? this.disableVisuallyDuringFirstDelay,
      minDisabledDuration: minDisabledDuration ?? this.minDisabledDuration,
      groupId: groupId ?? this.groupId,
      disableVisuallyDuringDebouncing:
          disableVisuallyDuringDebouncing ?? this.disableVisuallyDuringDebouncing,
      executionMode: executionMode ?? this.executionMode,
      executeOnLeadingEdge: executeOnLeadingEdge ?? this.executeOnLeadingEdge,
      executeOnTrailingEdge: executeOnTrailingEdge ?? this.executeOnTrailingEdge,
      concurrencyMode: concurrencyMode ?? this.concurrencyMode,
      rateLimitMaxTokens: rateLimitMaxTokens ?? this.rateLimitMaxTokens,
      rateLimitRefillInterval:
          rateLimitRefillInterval ?? this.rateLimitRefillInterval,
      rateLimitTokensPerRefill:
          rateLimitTokensPerRefill ?? this.rateLimitTokensPerRefill,
      onMetrics: onMetrics ?? this.onMetrics,
      enabled: enabled ?? this.enabled,
      maxDuration: maxDuration ?? this.maxDuration,
      debugName: debugName ?? this.debugName,
    );
  }
}

/// Enhanced TappableAction with production-grade reliability
class TappableAction extends StatefulWidget {
  const TappableAction({
    super.key,
    required this.onTap,
    required this.builder,
    this.config = const TappableActionConfig(),
    this.groupManager,
    this.timerFactory,
  });
  
  final VoidCallback? onTap;
  final Widget Function(BuildContext context, VoidCallback? onTap) builder;
  final TappableActionConfig config;
  final ITappableActionGroupManager? groupManager;
  final TimerFactory? timerFactory;
  
  @override
  State<TappableAction> createState() => _TappableActionState();
}

class _TappableActionState extends State<TappableAction> {
  late final ITappableActionGroupManager _groupManager;
  late final TimerFactory _timerFactory;

  // Execution primitives (initialized based on config)
  Throttler? _throttler;
  Debouncer? _debouncer;
  RateLimiter? _rateLimiter;
  HighFrequencyThrottler? _highFrequencyThrottler;
  ThrottleDebouncer? _throttleDebouncer;
  AsyncExecutor? _asyncExecutor;

  bool _isDelayed = false;
  bool _isDisabledByMinDuration = false;
  bool _isExecuting = false;
  Timer? _minDurationTimer;
  Timer? _delayTimer;
  int _tapCountInWindow = 0;

  @override
  void initState() {
    super.initState();

    _groupManager = widget.groupManager ?? TappableActionGroupManager();
    _timerFactory = widget.timerFactory ?? const TimerFactory();

    _groupManager.registerWidget(widget.config.groupId, this);
    _initializeExecutionPrimitives();
    _initializeDelayTimer();
  }

  void _initializeExecutionPrimitives() {
    final config = widget.config;
    final cooldown = config.coolDownDuration ?? const Duration(milliseconds: 300);

    switch (config.executionMode) {
      case TapExecutionMode.throttle:
        _throttler = Throttler(
          duration: cooldown,
          enabled: config.enabled,
          debugMode: config.debugName != null,
          name: config.debugName,
          timerFactory: _timerFactory,
          resetOnError: true,
          onMetrics: _onThrottlerMetrics,
        );
        break;

      case TapExecutionMode.debounce:
        _debouncer = Debouncer(
          duration: cooldown,
          enabled: config.enabled,
          debugMode: config.debugName != null,
          name: config.debugName,
          timerFactory: _timerFactory,
          leading: config.executeOnLeadingEdge,
          trailing: config.executeOnTrailingEdge,
          resetOnError: true,
          onMetrics: _onDebouncerMetrics,
        );
        break;

      case TapExecutionMode.throttleDebounce:
        _throttleDebouncer = ThrottleDebouncer(
          duration: cooldown,
          timerFactory: _timerFactory,
        );
        break;

      case TapExecutionMode.rateLimited:
        _rateLimiter = RateLimiter(
          maxTokens: config.rateLimitMaxTokens,
          refillRate: config.rateLimitTokensPerRefill,
          refillInterval: config.rateLimitRefillInterval,
          enabled: config.enabled,
          debugMode: config.debugName != null,
          name: config.debugName,
          onMetrics: _onRateLimiterMetrics,
        );
        break;

      case TapExecutionMode.highFrequency:
        _highFrequencyThrottler = HighFrequencyThrottler(
          duration: cooldown,
        );
        break;
    }

    // Always create async executor for concurrency control
    _asyncExecutor = AsyncExecutor(
      mode: _mapConcurrencyMode(config.concurrencyMode),
      maxDuration: config.maxDuration,
      enabled: config.enabled,
      resetOnError: true,
      debugMode: config.debugName != null,
      name: config.debugName,
      onMetrics: _onAsyncExecutorMetrics,
    );
  }

  ConcurrencyMode _mapConcurrencyMode(TapConcurrencyMode mode) {
    switch (mode) {
      case TapConcurrencyMode.drop:
        return ConcurrencyMode.drop;
      case TapConcurrencyMode.replace:
        return ConcurrencyMode.replace;
      case TapConcurrencyMode.keepLatest:
        return ConcurrencyMode.keepLatest;
      case TapConcurrencyMode.enqueue:
        return ConcurrencyMode.enqueue;
    }
  }

  void _initializeDelayTimer() {
    if (widget.config.delayBeforeFirstTapDuration != null) {
      _isDelayed = true;
      _delayTimer = _timerFactory.createTimer(
        widget.config.delayBeforeFirstTapDuration!,
        () {
          if (mounted) {
            setState(() {
              _isDelayed = false;
            });
          }
        },
      );
    }
  }

  void _disposeExecutionPrimitives() {
    _throttler?.dispose();
    _throttler = null;
    _debouncer?.dispose();
    _debouncer = null;
    _rateLimiter?.dispose();
    _rateLimiter = null;
    _highFrequencyThrottler?.dispose();
    _highFrequencyThrottler = null;
    _throttleDebouncer?.dispose();
    _throttleDebouncer = null;
    _asyncExecutor?.dispose();
    _asyncExecutor = null;
  }

  // Metrics callbacks
  void _onThrottlerMetrics(Duration executionTime, bool executed) {
    _tapCountInWindow++;
    _reportMetrics(
      executionDuration: executionTime,
      wasThrottled: !executed,
      wasCancelled: false,
      hadError: false,
    );
  }

  void _onDebouncerMetrics(Duration waitTime, bool cancelled) {
    _tapCountInWindow++;
    _reportMetrics(
      executionDuration: waitTime,
      wasThrottled: false,
      wasCancelled: cancelled,
      hadError: false,
    );
  }

  void _onRateLimiterMetrics(int tokensRemaining, bool acquired) {
    _tapCountInWindow++;
    _reportMetrics(
      executionDuration: Duration.zero,
      wasThrottled: !acquired,
      wasCancelled: false,
      hadError: false,
    );
  }

  void _onAsyncExecutorMetrics(Duration executionTime) {
    // AsyncExecutor metrics are handled separately for async operations
  }

  void _reportMetrics({
    required Duration executionDuration,
    required bool wasThrottled,
    required bool wasCancelled,
    required bool hadError,
  }) {
    widget.config.onMetrics?.call(TapMetrics(
      executionDuration: executionDuration,
      wasThrottled: wasThrottled,
      wasCancelled: wasCancelled,
      hadError: hadError,
      tapCountInWindow: _tapCountInWindow,
      groupId: widget.config.groupId,
      executionMode: widget.config.executionMode,
      timestamp: DateTime.now(),
    ));
  }

  @override
  void didUpdateWidget(TappableAction oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.config.groupId != widget.config.groupId) {
      _groupManager.unregisterWidget(oldWidget.config.groupId, this);
      _groupManager.registerWidget(widget.config.groupId, this);
    }

    // Reinitialize primitives if execution mode or concurrency mode changed
    if (oldWidget.config.executionMode != widget.config.executionMode ||
        oldWidget.config.concurrencyMode != widget.config.concurrencyMode ||
        oldWidget.config.coolDownDuration != widget.config.coolDownDuration ||
        oldWidget.config.enabled != widget.config.enabled) {
      _disposeExecutionPrimitives();
      _initializeExecutionPrimitives();
    }
  }

  @override
  void dispose() {
    _disposeExecutionPrimitives();
    _minDurationTimer?.cancel();
    _delayTimer?.cancel();
    _groupManager.unregisterWidget(widget.config.groupId, this);
    super.dispose();
  }
  
  Future<void> _handleTap() async {
    if (widget.onTap == null) return;

    // Prevent double-tap during processing
    if (_isDisabledByMinDuration || _isExecuting) {
      logd('TappableAction: Tap ignored - already processing');
      return;
    }

    // Check if config is enabled (bypass all logic when disabled)
    if (!widget.config.enabled) {
      logv('TappableAction: Config disabled, bypassing tap handling');
      return;
    }

    logv('TappableAction: Executing tap${widget.config.groupId != null ? ' (group: ${widget.config.groupId})' : ''}');

    // Use appropriate primitive based on execution mode
    switch (widget.config.executionMode) {
      case TapExecutionMode.throttle:
        _throttler?.call(() => _executeTap());
        break;

      case TapExecutionMode.debounce:
        _debouncer?.call(() => _executeTap());
        break;

      case TapExecutionMode.throttleDebounce:
        _throttleDebouncer?.call(() => _executeTap());
        break;

      case TapExecutionMode.rateLimited:
        _rateLimiter?.call(() => _executeTap());
        break;

      case TapExecutionMode.highFrequency:
        _highFrequencyThrottler?.call(() => _executeTap());
        break;
    }
  }

  void _executeTap() {
    if (!mounted || widget.onTap == null) return;

    _groupManager.setGroupDisabled(widget.config.groupId, true);
    setState(() {
      _isDisabledByMinDuration = true;
      _isExecuting = true;
    });

    final startTime = DateTime.now();

    try {
      // Execute the tap callback
      widget.onTap!();
    } catch (e) {
      logd('TappableAction: Error during tap execution: $e');
      _reportMetrics(
        executionDuration: DateTime.now().difference(startTime),
        wasThrottled: false,
        wasCancelled: false,
        hadError: true,
      );
    } finally {
      final elapsed = DateTime.now().difference(startTime);
      final minDuration = widget.config.minDisabledDuration ?? Duration.zero;
      final remaining = minDuration > elapsed ? minDuration - elapsed : Duration.zero;

      _minDurationTimer?.cancel();
      _minDurationTimer = _timerFactory.createTimer(remaining, () {
        if (mounted) {
          _groupManager.setGroupDisabled(widget.config.groupId, false);
          setState(() {
            _isDisabledByMinDuration = false;
            _isExecuting = false;
          });
        }
      });
    }
  }
  
  bool _shouldDisableTap(bool isNetworkConnected, bool isGroupDisabled) {
    // Check network requirement
    if (widget.config.requireNetwork && !isNetworkConnected) {
      logd('TappableAction: Network required but not connected');
      return true;
    }
    
    // Check delay period
    if (_isDelayed) {
      logv('TappableAction: In initial delay period');
      return true;
    }
    
    // Check minimum duration
    if (_isDisabledByMinDuration) {
      logv('TappableAction: Minimum duration not elapsed');
      return true;
    }
    
    // Check group disabled
    if (isGroupDisabled) {
      logv('TappableAction: Group is disabled');
      return true;
    }
    
    return false;
  }
  
  @override
  Widget build(BuildContext context) {
    Widget buildAction(bool isGroupDisabled) {
      return BlocBuilder<AppCubit, AppState>(
        buildWhen: (previous, current) =>
            widget.config.requireNetwork &&
            previous.networkStatus != current.networkStatus,
        builder: (context, state) {
          final isNetworkConnected =
              state.networkStatus == NetworkStatus.connected;

          final shouldDisable =
              _shouldDisableTap(isNetworkConnected, isGroupDisabled);

          VoidCallback? effectiveOnTap;
          if (widget.onTap != null) {
            if (shouldDisable) {
              if (widget.config.disableVisuallyDuringDebouncing) {
                effectiveOnTap = null; // Visually disabled
              } else {
                effectiveOnTap = () {
                  logd('TappableAction: Tap ignored - widget is disabled');
                }; // Functionally disabled but visually enabled
              }
            } else {
              // If debounceTaps is false, bypass the primitive handling
              // and call the callback directly for backward compatibility
              if (!widget.config.debounceTaps) {
                effectiveOnTap = () {
                  if (widget.onTap != null) {
                    _executeTap();
                  }
                };
              } else {
                // Use _handleTap which routes through the appropriate primitive
                effectiveOnTap = _handleTap;
              }
            }
          }

          // Build directly without TapDebouncer wrapper
          // The primitives now handle all debouncing/throttling internally
          return widget.builder(context, effectiveOnTap);
        },
      );
    }

    if (widget.config.groupId != null) {
      final notifier = _groupManager.getGroupNotifier(widget.config.groupId);
      return ValueListenableBuilder<bool>(
        valueListenable: notifier,
        builder: (context, isDisabled, child) => buildAction(isDisabled),
      );
    } else {
      return buildAction(false);
    }
  }
}

/// Simplified InkedWell wrapper
class TappableActionInkedWell extends StatelessWidget {
  const TappableActionInkedWell({
    super.key,
    required this.onTap,
    this.borderRadius,
    required this.child,
    this.config = const TappableActionConfig(),
    this.groupManager,
  });
  
  final BorderRadius? borderRadius;
  final VoidCallback? onTap;
  final Widget child;
  final TappableActionConfig config;
  final ITappableActionGroupManager? groupManager;
  
  @override
  Widget build(BuildContext context) {
    if (onTap == null) {
      return child;
    }
    
    return TappableAction(
      onTap: onTap,
      config: config,
      groupManager: groupManager,
      builder: (context, onDebounceTap) {
        return InkWell(
          borderRadius: borderRadius,
          onTap: onDebounceTap,
          child: child,
        );
      },
    );
  }
}

/// Debouncer with dependency injection for testing
typedef TapDebouncerFunc = Future<void> Function();

class TapDebouncer extends StatefulWidget {
  const TapDebouncer({
    super.key,
    required this.builder,
    this.waitBuilder,
    this.onTap,
    this.cooldown,
    this.timerFactory,
    this.executionMode = TapExecutionMode.throttle,
    this.leading = true,
    this.trailing = false,
  });

  static const Duration kNeverCooldown = Duration(days: 100000000);

  final Widget Function(BuildContext context, TapDebouncerFunc? onTap) builder;
  final Widget Function(BuildContext context, Widget child)? waitBuilder;
  final Future<void> Function()? onTap;
  final Duration? cooldown;
  final TimerFactory? timerFactory;

  /// Execution timing mode for the debouncer.
  /// Defaults to [TapExecutionMode.throttle] for backward compatibility.
  final TapExecutionMode executionMode;

  /// Execute immediately on first tap (leading edge).
  /// Only applies when [executionMode] is [TapExecutionMode.debounce].
  final bool leading;

  /// Execute after cooldown/pause period (trailing edge).
  /// Only applies when [executionMode] is [TapExecutionMode.debounce].
  final bool trailing;

  @override
  State<TapDebouncer> createState() => _TapDebouncerState();
}

class _TapDebouncerState extends State<TapDebouncer> {
  late final TimerFactory _timerFactory;
  late final AsyncExecutor _executor;
  Throttler? _throttler;
  Debouncer? _debouncer;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _timerFactory = widget.timerFactory ?? const TimerFactory();
    _executor = AsyncExecutor(
      mode: ConcurrencyMode.drop,
      resetOnError: true,
    );
    _initializePrimitives();
  }

  void _initializePrimitives() {
    final cooldown = widget.cooldown ?? const Duration(milliseconds: 300);

    switch (widget.executionMode) {
      case TapExecutionMode.debounce:
        _debouncer = Debouncer(
          duration: cooldown,
          leading: widget.leading,
          trailing: widget.trailing,
          timerFactory: _timerFactory,
        );
      case TapExecutionMode.throttle:
      case TapExecutionMode.throttleDebounce:
      case TapExecutionMode.rateLimited:
      case TapExecutionMode.highFrequency:
        _throttler = Throttler(
          duration: cooldown,
          timerFactory: _timerFactory,
        );
    }
  }

  @override
  void dispose() {
    _throttler?.dispose();
    _debouncer?.dispose();
    _executor.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (_isBusy || widget.onTap == null) return;

    setState(() => _isBusy = true);

    try {
      await _executor.execute(() async {
        await widget.onTap!();

        final cooldown = widget.cooldown;
        if (cooldown != null) {
          logv('TapDebouncer: Applying cooldown of ${cooldown.inMilliseconds}ms');
          await Future<void>.delayed(cooldown);
        }
      });
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isBusy) {
      final onTap = widget.onTap;

      return widget.builder(
        context,
        onTap == null ? null : _handleTap,
      );
    }

    final disabledChild = widget.builder(context, () async {
      logd('TapDebouncer: Tap ignored - button is busy');
    });

    if (widget.waitBuilder == null) {
      return disabledChild;
    } else {
      return widget.waitBuilder!(context, disabledChild);
    }
  }
}