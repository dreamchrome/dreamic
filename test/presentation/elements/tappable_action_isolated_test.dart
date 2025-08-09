import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mock timer factory for testing
class MockTimerFactory {
  final List<MockTimer> timers = [];
  
  Timer createTimer(Duration duration, VoidCallback callback) {
    final timer = MockTimer(duration, callback);
    timers.add(timer);
    return timer;
  }
  
  void advanceTime(Duration duration) {
    for (final timer in timers) {
      timer.advanceTime(duration);
    }
  }
  
  void triggerAllTimers() {
    for (final timer in timers) {
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

/// Isolated group manager for testing without dependencies
class IsolatedGroupManager {
  final MockTimerFactory timerFactory;
  final Map<String, ValueNotifier<bool>> _groupNotifiers = {};
  final Map<String, Set<Object>> _groupWidgets = {};
  final Map<String, Timer?> _groupResetTimers = {};
  final Map<String, int> _groupTapCounts = {};
  
  IsolatedGroupManager({MockTimerFactory? timerFactory}) 
    : timerFactory = timerFactory ?? MockTimerFactory();
  
  bool isGroupDisabled(String? groupId) {
    if (groupId == null) return false;
    return _getNotifier(groupId).value;
  }
  
  void setGroupDisabled(String? groupId, bool isDisabled) {
    if (groupId == null) return;
    
    final wasDisabled = isGroupDisabled(groupId);
    if (wasDisabled == isDisabled) return;
    
    _getNotifier(groupId).value = isDisabled;
    
    if (isDisabled) {
      _groupTapCounts[groupId] = (_groupTapCounts[groupId] ?? 0) + 1;
    } else {
      _cancelAutoReset(groupId);
    }
  }
  
  ValueNotifier<bool> getGroupNotifier(String? groupId) {
    if (groupId == null) return ValueNotifier<bool>(false);
    return _getNotifier(groupId);
  }
  
  void registerWidget(String? groupId, Object widget) {
    if (groupId == null) return;
    
    final widgets = _groupWidgets.putIfAbsent(groupId, () => {});
    final wasEmpty = widgets.isEmpty;
    widgets.add(widget);
    
    if (wasEmpty && _groupResetTimers[groupId] != null) {
      _cancelAutoReset(groupId);
      
      if (isGroupDisabled(groupId)) {
        setGroupDisabled(groupId, false);
      }
    }
  }
  
  void unregisterWidget(String? groupId, Object widget) {
    if (groupId == null) return;
    
    _groupWidgets[groupId]?.remove(widget);
    final remaining = _groupWidgets[groupId]?.length ?? 0;
    
    if (remaining == 0 && isGroupDisabled(groupId)) {
      _scheduleAutoReset(groupId);
    }
  }
  
  void resetGroup(String? groupId) {
    if (groupId == null) return;
    _cancelAutoReset(groupId);
    setGroupDisabled(groupId, false);
    _groupTapCounts[groupId] = 0;
  }
  
  void resetAllGroups() {
    for (final groupId in _groupNotifiers.keys.toList()) {
      resetGroup(groupId);
    }
  }
  
  void dispose() {
    for (final timer in _groupResetTimers.values) {
      timer?.cancel();
    }
    _groupResetTimers.clear();
    _groupNotifiers.clear();
    _groupWidgets.clear();
    _groupTapCounts.clear();
  }
  
  Map<String, dynamic> getDebugInfo() {
    final allGroupIds = {
      ..._groupNotifiers.keys,
      ..._groupWidgets.keys,
    };
    
    return {
      'groups': allGroupIds.map((id) => {
        'id': id,
        'disabled': isGroupDisabled(id),
        'widgetCount': _groupWidgets[id]?.length ?? 0,
        'tapCount': _groupTapCounts[id] ?? 0,
        'hasResetTimer': _groupResetTimers[id] != null,
      }).toList(),
    };
  }
  
  ValueNotifier<bool> _getNotifier(String groupId) =>
      _groupNotifiers.putIfAbsent(groupId, () => ValueNotifier<bool>(false));
  
  void _scheduleAutoReset(String groupId) {
    _cancelAutoReset(groupId);
    
    _groupResetTimers[groupId] = timerFactory.createTimer(
      const Duration(milliseconds: 500),
      () {
        if ((_groupWidgets[groupId]?.isEmpty ?? true) && isGroupDisabled(groupId)) {
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
}

/// Simple tappable action for testing without external dependencies
class SimpleTappableAction extends StatefulWidget {
  const SimpleTappableAction({
    super.key,
    required this.onTap,
    required this.builder,
    this.groupId,
    this.networkRequired = false,
    this.isNetworkConnected = true,
    this.delayDuration,
    this.minDisabledDuration,
    this.groupManager,
    this.timerFactory,
  });
  
  final VoidCallback? onTap;
  final Widget Function(BuildContext context, VoidCallback? onTap) builder;
  final String? groupId;
  final bool networkRequired;
  final bool isNetworkConnected;
  final Duration? delayDuration;
  final Duration? minDisabledDuration;
  final IsolatedGroupManager? groupManager;
  final MockTimerFactory? timerFactory;
  
  @override
  State<SimpleTappableAction> createState() => _SimpleTappableActionState();
}

class _SimpleTappableActionState extends State<SimpleTappableAction> {
  late final IsolatedGroupManager _groupManager;
  late final MockTimerFactory _timerFactory;
  
  bool _isDelayed = false;
  bool _isDisabledByMinDuration = false;
  Timer? _minDurationTimer;
  Timer? _delayTimer;
  
  @override
  void initState() {
    super.initState();
    
    _groupManager = widget.groupManager ?? IsolatedGroupManager();
    _timerFactory = widget.timerFactory ?? MockTimerFactory();
    
    _groupManager.registerWidget(widget.groupId, this);
    
    if (widget.delayDuration != null) {
      _isDelayed = true;
      _delayTimer = _timerFactory.createTimer(
        widget.delayDuration!,
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
  void dispose() {
    _minDurationTimer?.cancel();
    _delayTimer?.cancel();
    _groupManager.unregisterWidget(widget.groupId, this);
    super.dispose();
  }
  
  bool get _shouldDisable {
    if (widget.networkRequired && !widget.isNetworkConnected) return true;
    if (_isDelayed) return true;
    if (_isDisabledByMinDuration) return true;
    if (_groupManager.isGroupDisabled(widget.groupId)) return true;
    return false;
  }
  
  void _handleTap() {
    if (widget.onTap == null || _shouldDisable) return;
    
    _groupManager.setGroupDisabled(widget.groupId, true);
    setState(() {
      _isDisabledByMinDuration = true;
    });
    
    final startTime = DateTime.now();
    
    try {
      widget.onTap!();
    } catch (e) {
      // Handle error silently in test
    } finally {
      final elapsed = DateTime.now().difference(startTime);
      final minDuration = widget.minDisabledDuration ?? Duration.zero;
      final remaining = minDuration > elapsed ? minDuration - elapsed : Duration.zero;
      
      _minDurationTimer?.cancel();
      _minDurationTimer = _timerFactory.createTimer(remaining, () {
        if (mounted) {
          _groupManager.setGroupDisabled(widget.groupId, false);
          setState(() {
            _isDisabledByMinDuration = false;
          });
        }
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _groupManager.getGroupNotifier(widget.groupId),
      builder: (context, isGroupDisabled, child) {
        final effectiveOnTap = _shouldDisable ? null : _handleTap;
        return widget.builder(context, effectiveOnTap);
      },
    );
  }
}

void main() {
  group('Isolated Group Manager', () {
    late MockTimerFactory timerFactory;
    late IsolatedGroupManager groupManager;
    
    setUp(() {
      timerFactory = MockTimerFactory();
      groupManager = IsolatedGroupManager(timerFactory: timerFactory);
    });
    
    tearDown(() {
      timerFactory.clear();
      groupManager.dispose();
    });
    
    test('should start with groups enabled', () {
      expect(groupManager.isGroupDisabled('test-group'), false);
    });
    
    test('should disable and enable groups', () {
      groupManager.setGroupDisabled('test-group', true);
      expect(groupManager.isGroupDisabled('test-group'), true);
      
      groupManager.setGroupDisabled('test-group', false);
      expect(groupManager.isGroupDisabled('test-group'), false);
    });
    
    test('should handle null group IDs', () {
      expect(groupManager.isGroupDisabled(null), false);
      groupManager.setGroupDisabled(null, true);
      expect(groupManager.isGroupDisabled(null), false);
    });
    
    test('should track widgets in groups', () {
      final widget1 = Object();
      final widget2 = Object();
      
      groupManager.registerWidget('group1', widget1);
      groupManager.registerWidget('group1', widget2);
      
      final debugInfo = groupManager.getDebugInfo();
      expect(debugInfo['groups'], isA<List>());
      
      final groups = debugInfo['groups'] as List;
      expect(groups.length, 1);
      
      final group1Info = groups.first as Map<String, dynamic>;
      expect(group1Info['id'], 'group1');
      expect(group1Info['widgetCount'], 2);
    });
    
    test('should auto-reset empty disabled groups', () {
      final widget = Object();
      
      groupManager.registerWidget('auto-group', widget);
      groupManager.setGroupDisabled('auto-group', true);
      expect(groupManager.isGroupDisabled('auto-group'), true);
      
      groupManager.unregisterWidget('auto-group', widget);
      expect(groupManager.isGroupDisabled('auto-group'), true);
      
      timerFactory.advanceTime(const Duration(milliseconds: 500));
      expect(groupManager.isGroupDisabled('auto-group'), false);
    });
    
    test('should cancel auto-reset if widget is re-registered', () {
      final widget1 = Object();
      final widget2 = Object();
      
      groupManager.registerWidget('cancel-group', widget1);
      groupManager.setGroupDisabled('cancel-group', true);
      
      groupManager.unregisterWidget('cancel-group', widget1);
      
      groupManager.registerWidget('cancel-group', widget2);
      expect(groupManager.isGroupDisabled('cancel-group'), false);
    });
    
    test('should track tap counts', () {
      groupManager.setGroupDisabled('count-group', true);
      groupManager.setGroupDisabled('count-group', false);
      groupManager.setGroupDisabled('count-group', true);
      
      final debugInfo = groupManager.getDebugInfo();
      final groupInfo = (debugInfo['groups'] as List).firstWhere(
        (g) => g['id'] == 'count-group',
      );
      expect(groupInfo['tapCount'], 2);
    });
  });
  
  group('SimpleTappableAction Widget', () {
    late MockTimerFactory timerFactory;
    late IsolatedGroupManager groupManager;
    
    setUp(() {
      timerFactory = MockTimerFactory();
      groupManager = IsolatedGroupManager(timerFactory: timerFactory);
    });
    
    tearDown(() {
      timerFactory.clear();
      groupManager.dispose();
    });
    
    testWidgets('should execute tap when enabled', (WidgetTester tester) async {
      int tapCount = 0;
      
      await tester.pumpWidget(
        MaterialApp(
          home: SimpleTappableAction(
            onTap: () => tapCount++,
            groupManager: groupManager,
            timerFactory: timerFactory,
            builder: (context, onTap) => ElevatedButton(
              onPressed: onTap,
              child: const Text('Tap Me'),
            ),
          ),
        ),
      );
      
      await tester.tap(find.text('Tap Me'));
      await tester.pump();
      
      expect(tapCount, 1);
    });
    
    testWidgets('should block tap when network required but unavailable', (WidgetTester tester) async {
      int tapCount = 0;
      
      await tester.pumpWidget(
        MaterialApp(
          home: SimpleTappableAction(
            onTap: () => tapCount++,
            networkRequired: true,
            isNetworkConnected: false,
            groupManager: groupManager,
            timerFactory: timerFactory,
            builder: (context, onTap) => ElevatedButton(
              onPressed: onTap,
              child: const Text('Tap Me'),
            ),
          ),
        ),
      );
      
      await tester.tap(find.text('Tap Me'));
      await tester.pump();
      
      expect(tapCount, 0);
    });
    
    testWidgets('should respect initial delay', (WidgetTester tester) async {
      int tapCount = 0;
      
      await tester.pumpWidget(
        MaterialApp(
          home: SimpleTappableAction(
            onTap: () => tapCount++,
            delayDuration: const Duration(milliseconds: 100),
            groupManager: groupManager,
            timerFactory: timerFactory,
            builder: (context, onTap) => ElevatedButton(
              onPressed: onTap,
              child: const Text('Tap Me'),
            ),
          ),
        ),
      );
      
      // Try tapping during delay
      await tester.tap(find.text('Tap Me'));
      await tester.pump();
      expect(tapCount, 0);
      
      // Advance time past delay
      timerFactory.advanceTime(const Duration(milliseconds: 100));
      await tester.pump();
      
      // Now tap should work
      await tester.tap(find.text('Tap Me'));
      await tester.pump();
      expect(tapCount, 1);
    });
    
    testWidgets('should respect minimum disabled duration', (WidgetTester tester) async {
      int tapCount = 0;
      
      await tester.pumpWidget(
        MaterialApp(
          home: SimpleTappableAction(
            onTap: () => tapCount++,
            minDisabledDuration: const Duration(milliseconds: 200),
            groupManager: groupManager,
            timerFactory: timerFactory,
            builder: (context, onTap) => ElevatedButton(
              onPressed: onTap,
              child: const Text('Tap Me'),
            ),
          ),
        ),
      );
      
      // First tap
      await tester.tap(find.text('Tap Me'));
      await tester.pump();
      expect(tapCount, 1);
      
      // Try immediate second tap - should be blocked
      await tester.tap(find.text('Tap Me'));
      await tester.pump();
      expect(tapCount, 1);
      
      // Advance time fully
      timerFactory.advanceTime(const Duration(milliseconds: 200));
      await tester.pump();
      
      // Now should work
      await tester.tap(find.text('Tap Me'));
      await tester.pump();
      expect(tapCount, 2);
    });
    
    testWidgets('should handle group disabling', (WidgetTester tester) async {
      int tap1Count = 0;
      int tap2Count = 0;
      
      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: [
              SimpleTappableAction(
                onTap: () => tap1Count++,
                groupId: 'test-group',
                groupManager: groupManager,
                timerFactory: timerFactory,
                builder: (context, onTap) => ElevatedButton(
                  onPressed: onTap,
                  child: const Text('Button 1'),
                ),
              ),
              SimpleTappableAction(
                onTap: () => tap2Count++,
                groupId: 'test-group',
                groupManager: groupManager,
                timerFactory: timerFactory,
                builder: (context, onTap) => ElevatedButton(
                  onPressed: onTap,
                  child: const Text('Button 2'),
                ),
              ),
            ],
          ),
        ),
      );
      
      // Tap first button - should disable group
      await tester.tap(find.text('Button 1'));
      await tester.pump();
      expect(tap1Count, 1);
      
      // Try tapping second button - should be blocked by group
      await tester.tap(find.text('Button 2'));
      await tester.pump();
      expect(tap2Count, 0);
      
      // Re-enable group
      groupManager.setGroupDisabled('test-group', false);
      await tester.pump();
      
      // Now second button should work
      await tester.tap(find.text('Button 2'));
      await tester.pump();
      expect(tap2Count, 1);
    });
    
    testWidgets('should handle rapid group state changes', (WidgetTester tester) async {
      int tapCount = 0;
      
      await tester.pumpWidget(
        MaterialApp(
          home: SimpleTappableAction(
            onTap: () => tapCount++,
            groupId: 'rapid-group',
            groupManager: groupManager,
            timerFactory: timerFactory,
            builder: (context, onTap) => ElevatedButton(
              onPressed: onTap,
              child: const Text('Tap Me'),
            ),
          ),
        ),
      );
      
      // Rapidly toggle group state
      for (int i = 0; i < 10; i++) {
        groupManager.setGroupDisabled('rapid-group', i % 2 == 0);
        await tester.pump();
      }
      
      // Should be able to tap when enabled
      await tester.tap(find.text('Tap Me'));
      await tester.pump();
      expect(tapCount, 1);
    });
  });
}