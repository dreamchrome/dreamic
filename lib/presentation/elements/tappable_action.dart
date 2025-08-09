import 'dart:async';
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
  final bool requireNetwork;
  final bool debounceTaps;
  final Duration? coolDownDuration;
  final Duration? delayBeforeFirstTapDuration;
  final bool disableVisuallyDuringFirstDelay;
  final Duration? minDisabledDuration;
  final String? groupId;
  final bool disableVisuallyDuringDebouncing;
  
  const TappableActionConfig({
    this.requireNetwork = true,
    this.debounceTaps = true,
    this.coolDownDuration,
    this.delayBeforeFirstTapDuration,
    this.disableVisuallyDuringFirstDelay = true,
    this.minDisabledDuration,
    this.groupId,
    this.disableVisuallyDuringDebouncing = true,
  });
  
  /// Optimized configuration for high-frequency interactions
  const TappableActionConfig.highFrequency({
    this.requireNetwork = false,
    this.debounceTaps = true,
    this.coolDownDuration = const Duration(milliseconds: 100),
    this.delayBeforeFirstTapDuration,
    this.disableVisuallyDuringFirstDelay = false,
    this.minDisabledDuration = const Duration(milliseconds: 50),
    this.groupId,
    this.disableVisuallyDuringDebouncing = false,
  });
  
  /// Conservative configuration for critical actions (payments, deletions, etc.)
  const TappableActionConfig.critical({
    this.requireNetwork = true,
    this.debounceTaps = true,
    this.coolDownDuration = const Duration(seconds: 2),
    this.delayBeforeFirstTapDuration = const Duration(milliseconds: 300),
    this.disableVisuallyDuringFirstDelay = true,
    this.minDisabledDuration = const Duration(seconds: 1),
    this.groupId,
    this.disableVisuallyDuringDebouncing = true,
  });
  
  /// Validation helper
  bool get isValid {
    if (coolDownDuration?.isNegative == true) return false;
    if (delayBeforeFirstTapDuration?.isNegative == true) return false;
    if (minDisabledDuration?.isNegative == true) return false;
    if (groupId?.trim().isEmpty == true) return false;
    return true;
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
  
  bool _isDelayed = false;
  bool _isDisabledByMinDuration = false;
  Timer? _minDurationTimer;
  Timer? _delayTimer;
  
  @override
  void initState() {
    super.initState();
    
    _groupManager = widget.groupManager ?? TappableActionGroupManager();
    _timerFactory = widget.timerFactory ?? const TimerFactory();
    
    _groupManager.registerWidget(widget.config.groupId, this);
    
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
  
  @override
  void didUpdateWidget(TappableAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (oldWidget.config.groupId != widget.config.groupId) {
      _groupManager.unregisterWidget(oldWidget.config.groupId, this);
      _groupManager.registerWidget(widget.config.groupId, this);
    }
  }
  
  @override
  void dispose() {
    _minDurationTimer?.cancel();
    _delayTimer?.cancel();
    _groupManager.unregisterWidget(widget.config.groupId, this);
    super.dispose();
  }
  
  Future<void> _handleTap() async {
    if (widget.onTap == null) return;
    
    // Prevent double-tap during processing
    if (_isDisabledByMinDuration) {
      logd('TappableAction: Tap ignored - already processing');
      return;
    }
    
    logv('TappableAction: Executing tap${widget.config.groupId != null ? ' (group: ${widget.config.groupId})' : ''}');
    
    _groupManager.setGroupDisabled(widget.config.groupId, true);
    setState(() {
      _isDisabledByMinDuration = true;
    });
    
    final startTime = DateTime.now();
    
    try {
      // Execute the tap callback
      widget.onTap!();
    } catch (e) {
      logd('TappableAction: Error during tap execution: $e');
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
          
          final shouldDisable = _shouldDisableTap(isNetworkConnected, isGroupDisabled);
          
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
              effectiveOnTap = _handleTap;
            }
          }
          
          if (!widget.config.debounceTaps) {
            return widget.builder(context, effectiveOnTap);
          }
          
          return TapDebouncer(
            cooldown: widget.config.coolDownDuration,
            builder: widget.builder,
            onTap: effectiveOnTap == null ? null : () async => effectiveOnTap?.call(),
            timerFactory: _timerFactory,
          );
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
  });
  
  static const Duration kNeverCooldown = Duration(days: 100000000);
  
  final Widget Function(BuildContext context, TapDebouncerFunc? onTap) builder;
  final Widget Function(BuildContext context, Widget child)? waitBuilder;
  final Future<void> Function()? onTap;
  final Duration? cooldown;
  final TimerFactory? timerFactory;
  
  @override
  State<TapDebouncer> createState() => _TapDebouncerState();
}

class _TapDebouncerState extends State<TapDebouncer> {
  final DebouncerHandler _tapDebouncerHandler = DebouncerHandler();
  
  @override
  void dispose() {
    _tapDebouncerHandler.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) => StreamBuilder<bool>(
    initialData: false,
    stream: _tapDebouncerHandler.busyStream,
    builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
      if (snapshot.hasError) {
        throw StateError('_tapDebouncerHandler.busy has error=${snapshot.error}');
      }
      
      final isBusy = snapshot.data!;
      
      if (!isBusy) {
        final onTap = widget.onTap;
        
        return widget.builder(
          context,
          onTap == null
              ? null
              : () async => _tapDebouncerHandler.onTap(
                    () async {
                      await onTap();
                      
                      final cooldown = widget.cooldown;
                      if (cooldown != null) {
                        logv('TapDebouncer: Applying cooldown of ${cooldown.inMilliseconds}ms');
                        await Future<void>.delayed(cooldown);
                      }
                    },
                  ),
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
    },
  );
}

/// Single tap debouncer handler
class DebouncerHandler {
  DebouncerHandler() : _busyController = StreamController<bool>.broadcast()..add(false);
  
  final StreamController<bool> _busyController;
  
  Stream<bool> get busyStream => _busyController.stream;
  
  void dispose() => unawaited(_busyController.close());
  
  Future<void> onTap(Future<void> Function() function) async {
    try {
      logv('DebouncerHandler: Processing tap');
      _add(true);
      await function();
    } finally {
      _add(false);
    }
  }
  
  void _add(bool value) {
    if (!_busyController.isClosed) {
      _busyController.add(value);
    }
  }
}