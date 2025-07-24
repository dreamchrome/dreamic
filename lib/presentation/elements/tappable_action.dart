import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dreamic/app/app_cubit.dart';
import 'package:dreamic/utils/logger.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class TappableActionGroupManager with WidgetsBindingObserver {
  static final TappableActionGroupManager _instance = TappableActionGroupManager._internal();

  factory TappableActionGroupManager() {
    return _instance;
  }

  TappableActionGroupManager._internal() {
    // Listen to app lifecycle events for automatic group cleanup
    WidgetsBinding.instance.addObserver(this);
  }

  final Map<String, ValueNotifier<bool>> _groupNotifiers = {};
  final Map<String, Set<Object>> _groupWidgets = {}; // Track widgets using each group
  final Map<String, Timer?> _groupResetTimers = {}; // Auto-reset timers

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // Reset all groups when app resumes - this handles browser back navigation edge cases
    if (state == AppLifecycleState.resumed) {
      logv('TappableActionGroupManager: App resumed, resetting all disabled groups');
      resetAllGroups();
    }
  }

  /// Clean up resources when disposed
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final timer in _groupResetTimers.values) {
      timer?.cancel();
    }
    _groupResetTimers.clear();
  }

  ValueNotifier<bool> _getNotifier(String groupId) =>
      _groupNotifiers.putIfAbsent(groupId, () => ValueNotifier<bool>(false));

  bool isGroupDisabled(String? groupId) {
    if (groupId == null) return false;
    return _getNotifier(groupId).value;
  }

  void setGroupDisabled(String? groupId, bool isDisabled) {
    if (groupId == null) return;
    logv('TappableActionGroupManager: ${isDisabled ? 'Disabling' : 'Enabling'} group "$groupId"');
    _getNotifier(groupId).value = isDisabled;

    // If enabling, cancel any pending reset timer
    if (!isDisabled) {
      _groupResetTimers[groupId]?.cancel();
      _groupResetTimers[groupId] = null;
    }
  }

  ValueNotifier<bool> getGroupNotifier(String? groupId) {
    if (groupId == null) return ValueNotifier<bool>(false);
    return _getNotifier(groupId);
  }

  /// Register a widget as using this group
  void registerWidget(String? groupId, Object widget) {
    if (groupId == null) return;
    _groupWidgets.putIfAbsent(groupId, () => {}).add(widget);
    logv(
        'TappableActionGroupManager: Registered widget for group "$groupId" (${_groupWidgets[groupId]?.length} total)');

    // If there's a pending auto-reset timer for this group, cancel it since we have active widgets again
    if (_groupResetTimers[groupId] != null) {
      logv(
          'TappableActionGroupManager: Cancelling auto-reset timer for group "$groupId" - new widget registered');
      _groupResetTimers[groupId]?.cancel();
      _groupResetTimers[groupId] = null;

      // If the group is disabled and we now have widgets, immediately enable it
      if (isGroupDisabled(groupId)) {
        logd(
            'TappableActionGroupManager: Auto-enabling group "$groupId" - new widget registered while group was disabled');
        setGroupDisabled(groupId, false);
      }
    }
  }

  /// Unregister a widget from this group
  void unregisterWidget(String? groupId, Object widget) {
    if (groupId == null) return;
    _groupWidgets[groupId]?.remove(widget);
    logv(
        'TappableActionGroupManager: Unregistered widget from group "$groupId" (${_groupWidgets[groupId]?.length ?? 0} remaining)');

    // If no widgets left in group and group is disabled, schedule auto-reset
    if ((_groupWidgets[groupId]?.isEmpty ?? true) && isGroupDisabled(groupId)) {
      logv('TappableActionGroupManager: Scheduling auto-reset for empty disabled group "$groupId"');
      _groupResetTimers[groupId]?.cancel();
      _groupResetTimers[groupId] = Timer(const Duration(milliseconds: 100), () {
        // Double-check the group is still empty and disabled
        if ((_groupWidgets[groupId]?.isEmpty ?? true) && isGroupDisabled(groupId)) {
          logd('TappableActionGroupManager: Auto-resetting empty group "$groupId"');
          setGroupDisabled(groupId, false);
        }
      });
    }
  }

  /// Force reset a group (useful for navigation scenarios)
  void resetGroup(String? groupId) {
    if (groupId == null) return;
    logd('TappableActionGroupManager: Force resetting group "$groupId"');
    setGroupDisabled(groupId, false);
  }

  /// Reset all groups (useful for major navigation changes)
  void resetAllGroups() {
    logd('TappableActionGroupManager: Resetting all groups');
    for (final groupId in _groupNotifiers.keys.toList()) {
      setGroupDisabled(groupId, false);
    }
  }
}

class TappableAction extends StatefulWidget {
  const TappableAction({
    super.key,
    required this.onTap,
    required this.builder,
    this.requireNetwork = true,
    this.debounceTaps = true,
    this.coolDownDuration,
    this.delayBeforeFirstTapDuration,
    this.disableVisuallyDuringFirstDelay = true,
    this.minDisabledDuration,
    this.groupId,
    //TODO: this does not work as expected
    this.disableVisuallyDuringDebouncing = true,
  });

  final Function()? onTap;
  final Widget Function(BuildContext context, Function()? onTap) builder;
  final bool requireNetwork;
  final bool debounceTaps;
  final Duration? coolDownDuration;
  final Duration? delayBeforeFirstTapDuration;
  final bool disableVisuallyDuringFirstDelay;
  final Duration? minDisabledDuration;
  final String? groupId;
  final bool disableVisuallyDuringDebouncing;

  @override
  State<TappableAction> createState() => _TappableActionState();
}

class _TappableActionState extends State<TappableAction> {
  bool _isDelayed = false;
  bool _isDisabledByMinDuration = false;
  Timer? _minDurationTimer;

  @override
  void initState() {
    super.initState();

    // Register this widget with the group manager
    TappableActionGroupManager().registerWidget(widget.groupId, this);

    if (widget.delayBeforeFirstTapDuration != null) {
      setState(() {
        _isDelayed = true;
      });
      Future.delayed(widget.delayBeforeFirstTapDuration!, () {
        if (mounted) {
          setState(() {
            _isDelayed = false;
          });
        }
      });
    }
  }

  @override
  void didUpdateWidget(TappableAction oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Handle group ID changes
    if (oldWidget.groupId != widget.groupId) {
      TappableActionGroupManager().unregisterWidget(oldWidget.groupId, this);
      TappableActionGroupManager().registerWidget(widget.groupId, this);
    }
  }

  @override
  void dispose() {
    _minDurationTimer?.cancel();

    // Unregister this widget from the group manager
    TappableActionGroupManager().unregisterWidget(widget.groupId, this);

    super.dispose();
  }

  Future<void> _handleTap() async {
    if (widget.onTap != null) {
      logv(
          'TappableAction: Executing tap${widget.groupId != null ? ' (group: ${widget.groupId})' : ''}');
      TappableActionGroupManager().setGroupDisabled(widget.groupId, true);
      setState(() {
        _isDisabledByMinDuration = true;
      });
      final startTime = DateTime.now();
      final result = widget.onTap!();
      if (result is Future) {
        await result;
      }
      final elapsed = DateTime.now().difference(startTime);
      final minDuration = widget.minDisabledDuration ?? Duration.zero;
      final remaining = minDuration > elapsed ? minDuration - elapsed : Duration.zero;
      _minDurationTimer?.cancel();
      _minDurationTimer = Timer(remaining, () {
        if (mounted) {
          TappableActionGroupManager().setGroupDisabled(widget.groupId, false);
          setState(() {
            _isDisabledByMinDuration = false;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget buildAction(ValueNotifier<bool> groupNotifier) {
      return BlocBuilder<AppCubit, AppState>(
        buildWhen: (previous, current) => previous.networkStatus != current.networkStatus,
        builder: (context, state) {
          // Compute effective onTap based on network.
          Function()? effectiveOnTap = widget.onTap != null &&
                  (!widget.requireNetwork || state.networkStatus == NetworkStatus.connected)
              ? _handleTap
              : null;

          // Log network-related tap blocking
          if (widget.onTap != null &&
              widget.requireNetwork &&
              state.networkStatus != NetworkStatus.connected) {
            logd(
                'TappableAction: Tap ignored due to network requirement (status: ${state.networkStatus})${widget.groupId != null ? ' (group: ${widget.groupId})' : ''}');
          }

          // During delay, if disableVisuallyDuringFirstDelay is true, disable onTap visually;
          // otherwise, allow appearance of pressability but ignore tap.
          if (_isDelayed) {
            if (widget.disableVisuallyDuringFirstDelay) {
              logv(
                  'TappableAction: Tap disabled visually during initial delay${widget.groupId != null ? ' (group: ${widget.groupId})' : ''}');
              effectiveOnTap = null;
            } else {
              logd(
                  'TappableAction: Tap ignored during initial delay (visual feedback allowed)${widget.groupId != null ? ' (group: ${widget.groupId})' : ''}');
              effectiveOnTap = () {};
            }
          }

          if (_isDisabledByMinDuration || groupNotifier.value) {
            String reason =
                _isDisabledByMinDuration ? 'minimum duration not elapsed' : 'group disabled';
            if (widget.disableVisuallyDuringDebouncing) {
              logv(
                  'TappableAction: Tap disabled visually due to $reason${widget.groupId != null ? ' (group: ${widget.groupId})' : ''}');
              effectiveOnTap = null;
            } else {
              logd(
                  'TappableAction: Tap ignored due to $reason (visual feedback allowed)${widget.groupId != null ? ' (group: ${widget.groupId})' : ''}');
              effectiveOnTap = () {};
            }
          }

          // Use debouncer or bypass.
          if (!widget.debounceTaps) {
            return widget.builder(context, effectiveOnTap);
          }
          return TapDebouncer(
            cooldown: widget.coolDownDuration,
            builder: widget.builder,
            onTap: effectiveOnTap == null ? null : () async => effectiveOnTap?.call(),
          );
        },
      );
    }

    if (widget.groupId != null) {
      final notifier = TappableActionGroupManager().getGroupNotifier(widget.groupId);
      return ValueListenableBuilder<bool>(
        valueListenable: notifier,
        builder: (context, value, child) => buildAction(notifier),
      );
    } else {
      return buildAction(ValueNotifier(false));
    }
  }
}

class TappableActionInkedWell extends StatelessWidget {
  const TappableActionInkedWell({
    super.key,
    required this.onTap,
    this.borderRadius,
    required this.child,
    this.requireNetwork = true,
    this.debounceTaps = true,
    this.delayDuration,
    this.disableTapDuringDelay = true,
    this.minDisabledDuration,
    this.groupId,
    this.disableVisuallyDuringDebouncing = true, // new parameter
  });

  final BorderRadius? borderRadius;
  final Function()? onTap;
  final Widget child;
  final bool requireNetwork;
  final bool debounceTaps;
  final Duration? delayDuration;
  final bool disableTapDuringDelay;
  final Duration? minDisabledDuration;
  final String? groupId;
  final bool disableVisuallyDuringDebouncing; // new property

  @override
  Widget build(BuildContext context) {
    if (onTap == null) {
      return child;
    }
    return TappableAction(
      onTap: onTap,
      requireNetwork: requireNetwork,
      debounceTaps: debounceTaps,
      delayBeforeFirstTapDuration: delayDuration,
      disableVisuallyDuringFirstDelay: disableTapDuringDelay,
      minDisabledDuration: minDisabledDuration,
      groupId: groupId,
      disableVisuallyDuringDebouncing: disableVisuallyDuringDebouncing, // pass new option
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

typedef TapDebouncerFunc = Future<void> Function();

class TapDebouncer extends StatefulWidget {
  const TapDebouncer({
    super.key,
    required this.builder,
    this.waitBuilder,
    this.onTap,
    this.cooldown,
  });

  /// Pass this time to constructor if want to allow only one tap and
  /// then disable button forever
  static const Duration kNeverCooldown = Duration(days: 100000000);

  /// Function that builds button
  /// context is current context
  /// onTap is function to pass to SomeButton or InkWell
  final Widget Function(BuildContext context, TapDebouncerFunc? onTap) builder;

  /// Function that builds special button in wait state
  /// context is current context
  /// child is widget returning from builder method with onTap equal null
  final Widget Function(BuildContext context, Widget child)? waitBuilder;

  /// Function to call on tap
  final Future<void> Function()? onTap;

  /// Cooldown duration - delay after onTap executed (successfully or not)
  final Duration? cooldown;

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
            throw StateError(
              '_tapDebouncerHandler.busy has error=${snapshot.error}',
            );
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

          // When busy, return a disabled button but only log when actually tapped
          final disabledChild = widget.builder(context, () async {
            logd('TapDebouncer: Tap ignored - button is busy (debouncing in progress)');
          });

          if (widget.waitBuilder == null) {
            return disabledChild;
          } else {
            return widget.waitBuilder!(context, disabledChild);
          }
        },
      );
}

/// Single tap debouncer
class DebouncerHandler {
  DebouncerHandler() : _busyController = StreamController<bool>()..add(false);

  final StreamController<bool> _busyController;

  /// Busy state stream
  Stream<bool> get busyStream => _busyController.stream;

  /// Dispose resources
  void dispose() => unawaited(_busyController.close());

  /// Process onTap function
  Future<void> onTap(Future<void> Function() function) async {
    try {
      logv('TapDebouncer: Processing tap');
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
