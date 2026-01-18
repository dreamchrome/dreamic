# Plan: Integrate flutter_debounce_throttle into TappableAction

## Overview

Integrate the `flutter_debounce_throttle` package into the dreamic package's `TappableAction` widgets to gain battle-tested debouncing/throttling primitives while preserving dreamic-specific features like network awareness and group management.

## Goals

1. **Add all features from `flutter_debounce_throttle`:**
   - Leading/trailing edge execution
   - True debouncing vs throttling (separate concepts)
   - Async cancellation with call ID tracking
   - Concurrency control modes (drop/replace/enqueue/keepLatest)
   - Token bucket rate limiting
   - Batch processing
   - Metrics/observability callbacks
   - Enable/disable toggle

2. **Preserve dreamic-specific features:**
   - Network connection awareness (`requireNetwork`)
   - Group-based tap coordination (`TappableActionGroupManager`)
   - Widget registration/lifecycle management
   - Visual disable options during debouncing
   - Delay before first tap
   - Minimum disabled duration

3. **Maintain backward compatibility:**
   - Existing `TappableAction` API continues to work
   - Existing `TappableActionConfig` parameters honored
   - `TappableActionInkedWell` convenience widget unchanged

---

## Package Analysis

### flutter_debounce_throttle Features to Integrate

| Feature | Class/Mixin | Use Case |
|---------|-------------|----------|
| Throttling | `Throttler` | Prevent rapid repeated taps |
| Debouncing | `Debouncer` | Wait for pause in activity (search input) |
| Async throttling | `AsyncThrottler` | Async tap handlers with cancellation |
| Concurrency modes | `ConcurrentAsyncThrottler` | Advanced async handling |
| Rate limiting | `RateLimiter` | High-frequency interactions (sliders) |
| Batch processing | `BatchThrottler` | Consolidate multiple calls |
| Auto-disposal | `EventLimiterMixin` | Lifecycle-aware cleanup |
| Leading/trailing edge | All classes | Immediate vs delayed execution |

### Dreamic Features to Preserve

| Feature | Current Location | Purpose |
|---------|-----------------|---------|
| Network awareness | `_shouldDisableTap()` | Block taps when offline |
| Group management | `TappableActionGroupManager` | Coordinate multiple widgets |
| Widget registration | `registerWidget/unregisterWidget` | Track active widgets per group |
| Auto-reset on app resume | `didChangeAppLifecycleState` | Reset stuck states |
| Delay before first tap | `delayBeforeFirstTapDuration` | Prevent accidental taps |
| Min disabled duration | `minDisabledDuration` | Ensure visual feedback |
| Visual disable options | `disableVisuallyDuringDebouncing` | UX control |

---

## Architecture

### New Class Hierarchy

```
┌─────────────────────────────────────────────────────────────────┐
│                    TappableActionConfig                         │
│  (Extended with new options from flutter_debounce_throttle)     │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                       TappableAction                            │
│  - Uses EventLimiterMixin for auto-disposal                     │
│  - Composes Throttler/Debouncer/AsyncThrottler internally       │
│  - Adds network awareness layer                                 │
│  - Delegates to TappableActionGroupManager for coordination     │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                 TappableActionGroupManager                      │
│  (Unchanged - manages group coordination)                       │
└─────────────────────────────────────────────────────────────────┘
```

### Integration Points

```dart
// TappableAction internally uses package primitives:
class _TappableActionState extends State<TappableAction>
    with EventLimiterMixin<TappableAction> {  // Auto-disposal from package

  // Package primitives (created based on config)
  Throttler? _throttler;
  Debouncer? _debouncer;
  AsyncThrottler? _asyncThrottler;

  // Dreamic-specific (preserved)
  late final ITappableActionGroupManager _groupManager;
  bool _isDelayed = false;

  // Composed tap handler
  void _handleTap() {
    // 1. Check network (dreamic)
    // 2. Check group disabled (dreamic)
    // 3. Check delay period (dreamic)
    // 4. Delegate to throttler/debouncer (package)
    // 5. Execute with async cancellation (package)
    // 6. Update group state (dreamic)
  }
}
```

---

## Detailed Changes

### 1. Add Dependency

**File:** `pubspec.yaml`

```yaml
dependencies:
  flutter_debounce_throttle: ^2.0.0
```

### 2. Extend TappableActionConfig

**File:** `lib/presentation/elements/tappable_action.dart`

```dart
/// Execution timing mode
enum TapExecutionMode {
  /// Execute immediately, block subsequent (current behavior)
  throttle,

  /// Wait for pause in activity before executing
  debounce,

  /// Token bucket - allow bursts with sustained rate limit
  rateLimited,
}

/// Concurrency control for async tap handlers
enum TapConcurrencyMode {
  /// Ignore new taps while processing (current behavior)
  drop,

  /// Cancel current operation and start new one
  replace,

  /// Queue taps in order
  enqueue,

  /// Keep current + latest only, drop intermediate
  keepLatest,
}

@immutable
class TappableActionConfig {
  // === EXISTING (preserved) ===
  final bool requireNetwork;
  final bool debounceTaps;  // Deprecated: use executionMode
  final Duration? coolDownDuration;
  final Duration? delayBeforeFirstTapDuration;
  final bool disableVisuallyDuringFirstDelay;
  final Duration? minDisabledDuration;
  final String? groupId;
  final bool disableVisuallyDuringDebouncing;

  // === NEW (from flutter_debounce_throttle) ===

  /// Execution timing mode (throttle, debounce, or rate-limited)
  final TapExecutionMode executionMode;

  /// Execute immediately on first tap (leading edge)
  final bool executeOnLeadingEdge;

  /// Execute after cooldown/pause period (trailing edge)
  final bool executeOnTrailingEdge;

  /// Concurrency control for async handlers
  final TapConcurrencyMode concurrencyMode;

  /// Rate limiter config (when executionMode == rateLimited)
  final int rateLimitMaxTokens;
  final Duration rateLimitRefillInterval;
  final int rateLimitTokensPerRefill;

  /// Metrics callback for observability
  final void Function(TapMetrics)? onMetrics;

  /// Enable/disable toggle (bypass all logic when false)
  final bool enabled;

  /// Reset state if tap handler throws exception
  final bool resetOnError;

  const TappableActionConfig({
    // Existing
    this.requireNetwork = true,
    @Deprecated('Use executionMode instead') this.debounceTaps = true,
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
    this.resetOnError = true,
  });

  // Existing presets (updated)
  const TappableActionConfig.highFrequency({...});
  const TappableActionConfig.critical({...});

  // NEW presets

  /// For search inputs - debounce with leading edge for responsiveness
  const TappableActionConfig.search({
    this.requireNetwork = true,
    this.executionMode = TapExecutionMode.debounce,
    this.coolDownDuration = const Duration(milliseconds: 300),
    this.executeOnLeadingEdge = true,
    this.executeOnTrailingEdge = true,
    // ... other defaults
  });

  /// For like/favorite buttons - immediate feedback, prevent double-tap
  const TappableActionConfig.toggle({
    this.requireNetwork = true,
    this.executionMode = TapExecutionMode.throttle,
    this.coolDownDuration = const Duration(milliseconds: 500),
    this.executeOnLeadingEdge = true,
    this.executeOnTrailingEdge = false,
    this.concurrencyMode = TapConcurrencyMode.replace,
    // ... other defaults
  });

  /// For sliders/high-frequency - rate limited with burst capacity
  const TappableActionConfig.slider({
    this.requireNetwork = false,
    this.executionMode = TapExecutionMode.rateLimited,
    this.rateLimitMaxTokens = 20,
    this.rateLimitRefillInterval = const Duration(milliseconds: 100),
    // ... other defaults
  });
}
```

### 3. Add TapMetrics Class

```dart
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
}
```

### 4. Update TappableAction State

```dart
class _TappableActionState extends State<TappableAction>
    with EventLimiterMixin<TappableAction> {

  late final ITappableActionGroupManager _groupManager;

  // Package primitives (lazy-initialized based on config)
  Throttler? _throttler;
  Debouncer? _debouncer;
  AsyncThrottler? _asyncThrottler;
  RateLimiter? _rateLimiter;

  // Dreamic-specific state (preserved)
  bool _isDelayed = false;
  Timer? _delayTimer;
  int _tapCount = 0;

  @override
  void initState() {
    super.initState();

    _groupManager = widget.groupManager ?? TappableActionGroupManager();
    _groupManager.registerWidget(widget.config.groupId, this);

    _initializeExecutionPrimitive();
    _initializeDelayTimer();
  }

  void _initializeExecutionPrimitive() {
    final duration = widget.config.coolDownDuration ??
                     const Duration(milliseconds: 300);

    switch (widget.config.executionMode) {
      case TapExecutionMode.throttle:
        _throttler = createThrottler(duration: duration);
        break;

      case TapExecutionMode.debounce:
        _debouncer = createDebouncer(
          duration: duration,
          leading: widget.config.executeOnLeadingEdge,
          trailing: widget.config.executeOnTrailingEdge,
        );
        break;

      case TapExecutionMode.rateLimited:
        _rateLimiter = RateLimiter(
          maxTokens: widget.config.rateLimitMaxTokens,
          refillInterval: widget.config.rateLimitRefillInterval,
          tokensPerRefill: widget.config.rateLimitTokensPerRefill,
        );
        break;
    }

    // Async throttler for concurrency control
    if (widget.config.concurrencyMode != TapConcurrencyMode.drop) {
      _asyncThrottler = createAsyncThrottler(
        duration: duration,
        mode: _mapConcurrencyMode(widget.config.concurrencyMode),
      );
    }
  }

  Future<void> _handleTap() async {
    if (!widget.config.enabled) {
      widget.onTap?.call();
      return;
    }

    final startTime = DateTime.now();
    var wasThrottled = false;
    var wasCancelled = false;
    var hadError = false;

    try {
      // 1. Check dreamic-specific conditions
      if (!_canExecuteTap()) {
        wasThrottled = true;
        return;
      }

      // 2. Update group state
      _groupManager.setGroupDisabled(widget.config.groupId, true);
      _tapCount++;

      // 3. Execute via appropriate primitive
      switch (widget.config.executionMode) {
        case TapExecutionMode.throttle:
          _throttler?.call(() => _executeCallback());
          break;

        case TapExecutionMode.debounce:
          _debouncer?.call(() => _executeCallback());
          break;

        case TapExecutionMode.rateLimited:
          if (_rateLimiter?.tryConsume() ?? false) {
            _executeCallback();
          } else {
            wasThrottled = true;
          }
          break;
      }
    } catch (e) {
      hadError = true;
      if (widget.config.resetOnError) {
        _groupManager.setGroupDisabled(widget.config.groupId, false);
      }
      rethrow;
    } finally {
      // 4. Report metrics
      widget.config.onMetrics?.call(TapMetrics(
        executionDuration: DateTime.now().difference(startTime),
        wasThrottled: wasThrottled,
        wasCancelled: wasCancelled,
        hadError: hadError,
        tapCountInWindow: _tapCount,
        groupId: widget.config.groupId,
        executionMode: widget.config.executionMode,
        timestamp: startTime,
      ));
    }
  }

  bool _canExecuteTap() {
    // Network check (dreamic-specific)
    if (widget.config.requireNetwork) {
      final appState = context.read<AppCubit>().state;
      if (appState.networkStatus != NetworkStatus.connected) {
        logd('TappableAction: Network required but not connected');
        return false;
      }
    }

    // Delay check (dreamic-specific)
    if (_isDelayed) {
      logv('TappableAction: In initial delay period');
      return false;
    }

    // Group check (dreamic-specific)
    if (_groupManager.isGroupDisabled(widget.config.groupId)) {
      logv('TappableAction: Group is disabled');
      return false;
    }

    return true;
  }

  void _executeCallback() {
    try {
      widget.onTap?.call();
    } finally {
      // Re-enable after min duration
      _scheduleReEnable();
    }
  }

  void _scheduleReEnable() {
    final minDuration = widget.config.minDisabledDuration ?? Duration.zero;
    Future.delayed(minDuration, () {
      if (mounted) {
        _groupManager.setGroupDisabled(widget.config.groupId, false);
      }
    });
  }

  // ... rest of implementation
}
```

### 5. Update TapDebouncer (Simplified)

Replace custom `TapDebouncer` with a thin wrapper around package primitives:

```dart
/// Simplified debouncer using flutter_debounce_throttle internally
class TapDebouncer extends StatefulWidget {
  const TapDebouncer({
    super.key,
    required this.builder,
    this.waitBuilder,
    this.onTap,
    this.cooldown,
    this.leading = false,
    this.trailing = true,
  });

  final Widget Function(BuildContext context, TapDebouncerFunc? onTap) builder;
  final Widget Function(BuildContext context, Widget child)? waitBuilder;
  final Future<void> Function()? onTap;
  final Duration? cooldown;
  final bool leading;
  final bool trailing;

  @override
  State<TapDebouncer> createState() => _TapDebouncerState();
}

class _TapDebouncerState extends State<TapDebouncer>
    with EventLimiterMixin<TapDebouncer> {

  late final AsyncThrottler _throttler;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _throttler = createAsyncThrottler(
      duration: widget.cooldown ?? const Duration(milliseconds: 300),
    );
  }

  Future<void> _handleTap() async {
    if (_isBusy) return;

    setState(() => _isBusy = true);

    try {
      await _throttler.call(() async {
        await widget.onTap?.call();
      });
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isBusy && widget.waitBuilder != null) {
      return widget.waitBuilder!(
        context,
        widget.builder(context, null),
      );
    }

    return widget.builder(
      context,
      widget.onTap == null ? null : _handleTap,
    );
  }
}
```

### 6. Remove DebouncerHandler

The `DebouncerHandler` class can be removed as its functionality is now provided by the package's `AsyncThrottler` with better error handling and cancellation support.

---

## Migration Guide

### For Existing Code

Existing code using `TappableAction` with current config will continue to work:

```dart
// This still works exactly as before
TappableAction(
  config: const TappableActionConfig(
    requireNetwork: true,
    debounceTaps: true,
    coolDownDuration: Duration(milliseconds: 300),
    groupId: 'my-group',
  ),
  onTap: () => doSomething(),
  builder: (context, onTap) => ElevatedButton(
    onPressed: onTap,
    child: Text('Tap me'),
  ),
)
```

### For New Features

```dart
// Using new features
TappableAction(
  config: const TappableActionConfig(
    requireNetwork: true,
    executionMode: TapExecutionMode.debounce,
    executeOnLeadingEdge: true,
    executeOnTrailingEdge: true,
    concurrencyMode: TapConcurrencyMode.replace,
    coolDownDuration: Duration(milliseconds: 300),
    onMetrics: (metrics) => analytics.track('tap', metrics),
  ),
  onTap: () => doSomething(),
  builder: (context, onTap) => ElevatedButton(
    onPressed: onTap,
    child: Text('Tap me'),
  ),
)

// Using presets
TappableAction(
  config: const TappableActionConfig.search(),
  onTap: () => performSearch(),
  builder: ...,
)

TappableAction(
  config: const TappableActionConfig.toggle(),
  onTap: () => toggleFavorite(),
  builder: ...,
)
```

---

## Tasks

### Phase 1: Add Dependency & Core Integration
- [ ] Add `flutter_debounce_throttle: ^2.0.0` to pubspec.yaml
- [ ] Run `flutter pub get`
- [ ] Add new enums (`TapExecutionMode`, `TapConcurrencyMode`)
- [ ] Add `TapMetrics` class
- [ ] Extend `TappableActionConfig` with new fields
- [ ] Add new config presets (`.search()`, `.toggle()`, `.slider()`)

### Phase 2: Update TappableAction
- [ ] Add `EventLimiterMixin` to `_TappableActionState`
- [ ] Initialize appropriate primitive based on `executionMode`
- [ ] Update `_handleTap` to use package primitives
- [ ] Preserve network awareness check
- [ ] Preserve group management integration
- [ ] Add metrics reporting

### Phase 3: Simplify TapDebouncer
- [ ] Rewrite `TapDebouncer` using `AsyncThrottler`
- [ ] Remove `DebouncerHandler` class
- [ ] Update tests for new implementation

### Phase 4: Testing
- [ ] Verify backward compatibility with existing tests
- [ ] Add tests for new execution modes
- [ ] Add tests for concurrency modes
- [ ] Add tests for metrics callback
- [ ] Test network awareness preservation
- [ ] Test group management preservation

### Phase 5: Documentation
- [ ] Update doc comments on all modified classes
- [ ] Add usage examples in comments
- [ ] Update any external documentation

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Breaking existing behavior | Maintain backward compatibility via deprecation, not removal |
| Package abandonment | Package is actively maintained; core logic is simple enough to fork if needed |
| Performance regression | Package is lightweight with zero dependencies; benchmark critical paths |
| Timer leak regression | Package verified with LeakTracker; add integration tests |

---

## Success Criteria

1. All existing tests pass without modification
2. New features from `flutter_debounce_throttle` are accessible
3. Network awareness continues to work correctly
4. Group management continues to work correctly
5. No memory leaks detected
6. No performance regression in tap handling
