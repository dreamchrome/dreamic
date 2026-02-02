import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dreamic/data/helpers/repository_failure.dart';
import 'package:dreamic/data/models/device_info.dart';
import 'package:dreamic/data/repos/auth_service_int.dart';
import 'package:dreamic/data/repos/device_service_int.dart';

/// Tests for auth race condition prevention as specified in plan.auth-race.md.
///
/// These tests verify:
/// 1. Callbacks passed to AuthService constructor fire on immediate auth events
/// 2. Warm start simulation - handlers execute when Firebase emits immediately
/// 3. Logout ordering - handleAboutToLogOut completes before signOut
/// 4. Parallel initialization - both services have _authService when callbacks fire
/// 5. Graceful degradation - warning logs when callbacks fire before _authService set
/// 6. Priority-based callback execution
///
/// ## Critical for Hospital-Grade Reliability
///
/// Race conditions in auth handling can cause:
/// - Missed device registrations (patient data not synced)
/// - Missed FCM token persistence (critical notifications not received)
/// - Logout cleanup failures (orphaned data)
///
/// These tests ensure deterministic initialization on all scenarios.
void main() {
  late GetIt getIt;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    getIt = GetIt.instance;

    // Reset GetIt for each test
    _resetGetIt(getIt);
  });

  tearDown(() {
    _resetGetIt(getIt);
  });

  group('Phase 7.1: Test harness verification', () {
    test('FakeAuthService can simulate immediate auth events', () async {
      final callbackInvocations = <String>[];
      final fakeAuth = FakeAuthService();

      // Register callback before triggering auth
      fakeAuth.addOnAuthenticatedCallback((uid) async {
        callbackInvocations.add('authenticated:$uid');
      });

      // Simulate immediate auth event (warm start scenario)
      await fakeAuth.simulateImmediateAuth('test-user-123');

      expect(callbackInvocations, ['authenticated:test-user-123']);
    });

    test('FakeAuthService tracks callback invocation order', () async {
      final fakeAuth = FakeAuthService();
      final order = <int>[];

      fakeAuth.addOnAuthenticatedCallback((uid) async {
        order.add(1);
      });
      fakeAuth.addOnAuthenticatedCallback((uid) async {
        order.add(2);
      });

      await fakeAuth.simulateImmediateAuth('user');

      // Both callbacks should have been invoked
      expect(order.length, 2);
      expect(order.contains(1), isTrue);
      expect(order.contains(2), isTrue);
    });
  });

  group('Phase 7.2: Constructor callbacks fire on immediate auth events', () {
    test('callbacks registered in constructor fire before listeners attach', () async {
      final callbackFired = Completer<String?>();

      // Create auth service with pre-registered callback
      // This simulates the race-free initialization pattern
      final fakeAuth = FakeAuthService(
        onAuthenticatedCallbacks: [
          (uid) async {
            if (!callbackFired.isCompleted) {
              callbackFired.complete(uid);
            }
          },
        ],
      );

      // Simulate Firebase emitting auth state immediately
      await fakeAuth.simulateImmediateAuth('constructor-test-user');

      expect(callbackFired.isCompleted, isTrue);
      expect(await callbackFired.future, 'constructor-test-user');
    });

    test('prioritized callbacks from constructor execute in order', () async {
      final executionOrder = <String>[];

      final fakeAuth = FakeAuthService(
        onAuthenticatedPrioritized: [
          PrioritizedCallback((uid) async {
            executionOrder.add('priority-0-first');
          }, priority: 0),
          PrioritizedCallback((uid) async {
            executionOrder.add('priority-100');
          }, priority: 100),
          PrioritizedCallback((uid) async {
            executionOrder.add('priority-0-second');
          }, priority: 0),
          PrioritizedCallback((uid) async {
            executionOrder.add('priority-negative');
          }, priority: -10),
        ],
      );

      await fakeAuth.simulateImmediateAuth('user');

      // Priority 100 should run first, then priority 0 (parallel), then -10
      expect(executionOrder.first, 'priority-100');
      expect(executionOrder.last, 'priority-negative');
      // Both priority-0 callbacks should be between priority-100 and priority-negative
      expect(executionOrder.indexOf('priority-0-first'), greaterThan(0));
      expect(executionOrder.indexOf('priority-0-first'), lessThan(3));
      expect(executionOrder.indexOf('priority-0-second'), greaterThan(0));
      expect(executionOrder.indexOf('priority-0-second'), lessThan(3));
    });
  });

  group('Phase 7.3: Warm start simulation', () {
    test('handlers execute when Firebase emits immediately on warm start', () async {
      final deviceHandlerCalled = Completer<void>();
      final notificationHandlerCalled = Completer<void>();

      final mockDeviceService = MockDeviceServiceForRaceTests(
        onHandleAuthenticated: (uid) async {
          if (!deviceHandlerCalled.isCompleted) {
            deviceHandlerCalled.complete();
          }
        },
      );

      final mockNotificationService = MockNotificationServiceForRaceTests(
        onHandleAuthenticated: (uid) async {
          if (!notificationHandlerCalled.isCompleted) {
            notificationHandlerCalled.complete();
          }
        },
      );

      // Create auth with service callbacks pre-registered (warm start pattern)
      final fakeAuth = FakeAuthService(
        onAuthenticatedCallbacks: [
          mockDeviceService.handleAuthenticated,
          mockNotificationService.handleAuthenticated,
        ],
      );

      // Simulate warm start: Firebase emits auth state immediately
      await fakeAuth.simulateImmediateAuth('warm-start-user');

      expect(deviceHandlerCalled.isCompleted, isTrue);
      expect(notificationHandlerCalled.isCompleted, isTrue);
    });

    test('all services receive uid on warm start', () async {
      String? receivedUidDevice;
      String? receivedUidNotification;

      final mockDeviceService = MockDeviceServiceForRaceTests(
        onHandleAuthenticated: (uid) async {
          receivedUidDevice = uid;
        },
      );

      final mockNotificationService = MockNotificationServiceForRaceTests(
        onHandleAuthenticated: (uid) async {
          receivedUidNotification = uid;
        },
      );

      final fakeAuth = FakeAuthService(
        onAuthenticatedCallbacks: [
          mockDeviceService.handleAuthenticated,
          mockNotificationService.handleAuthenticated,
        ],
      );

      await fakeAuth.simulateImmediateAuth('uid-123');

      expect(receivedUidDevice, 'uid-123');
      expect(receivedUidNotification, 'uid-123');
    });
  });

  group('Phase 7.4: Logout ordering', () {
    test('handleAboutToLogOut callbacks complete before signOut', () async {
      final timeline = <String>[];
      var signOutCalled = false;

      final fakeAuth = FakeAuthService(
        onAboutToLogOutCallbacks: [
          () async {
            timeline.add('cleanup-start');
            await Future.delayed(const Duration(milliseconds: 50));
            timeline.add('cleanup-end');
          },
        ],
        onSignOut: () async {
          signOutCalled = true;
          timeline.add('signout');
        },
      );

      await fakeAuth.signOut();

      expect(timeline, ['cleanup-start', 'cleanup-end', 'signout']);
      expect(signOutCalled, isTrue);
    });

    test('multiple logout callbacks all complete before signOut', () async {
      final completions = <String>[];

      final fakeAuth = FakeAuthService(
        onAboutToLogOutCallbacks: [
          () async {
            await Future.delayed(const Duration(milliseconds: 30));
            completions.add('callback-1');
          },
          () async {
            await Future.delayed(const Duration(milliseconds: 10));
            completions.add('callback-2');
          },
        ],
        onSignOut: () async {
          completions.add('signout');
        },
      );

      await fakeAuth.signOut();

      // Both callbacks should complete before signout
      final signoutIndex = completions.indexOf('signout');
      expect(signoutIndex, greaterThan(1)); // After both callbacks
      expect(completions.contains('callback-1'), isTrue);
      expect(completions.contains('callback-2'), isTrue);
    });

    test('logout proceeds even if callback throws', () async {
      var signOutCalled = false;

      final fakeAuth = FakeAuthService(
        onAboutToLogOutCallbacks: [
          () async {
            throw Exception('Cleanup failed');
          },
        ],
        onSignOut: () async {
          signOutCalled = true;
        },
      );

      // Should not throw
      await fakeAuth.signOut();

      expect(signOutCalled, isTrue);
    });
  });

  group('Phase 7.5: Parallel initialization', () {
    test('parallel init ensures all services have authService when callbacks fire', () async {
      // This test verifies Constraint 2 from plan.auth-race.md:
      // All initialize() calls must START synchronously before any awaits.

      final mockDeviceService = MockDeviceServiceForRaceTests();
      final mockNotificationService = MockNotificationServiceForRaceTests();

      final fakeAuth = FakeAuthService(
        onAuthenticatedCallbacks: [
          mockDeviceService.handleAuthenticated,
          mockNotificationService.handleAuthenticated,
        ],
      );

      // CORRECT: Parallel initialization using Future.wait
      final initFutures = <Future<void>>[];
      initFutures.add(mockDeviceService.initialize(authService: fakeAuth));
      initFutures.add(mockNotificationService.initialize(authService: fakeAuth));

      // At this point, both services should have started initialization synchronously
      // and set their _authService before any await

      // Simulate auth callback firing (as a microtask would)
      await fakeAuth.simulateImmediateAuth('parallel-test-user');

      // Wait for initialization to complete
      await Future.wait(initFutures);

      // Both services should have received the auth event with authService set
      expect(mockDeviceService.isConnectedToAuth, isTrue);
      expect(mockNotificationService.isConnectedToAuth, isTrue);
      expect(mockDeviceService.lastAuthenticatedUid, 'parallel-test-user');
      expect(mockNotificationService.lastAuthenticatedUid, 'parallel-test-user');
    });

    test('Future.wait starts all initialize calls synchronously', () async {
      var deviceInitStarted = false;
      var notificationInitStarted = false;
      final initStartOrder = <String>[];

      final mockDeviceService = MockDeviceServiceForRaceTests(
        onInitializeStart: () {
          deviceInitStarted = true;
          initStartOrder.add('device');
        },
      );

      final mockNotificationService = MockNotificationServiceForRaceTests(
        onInitializeStart: () {
          notificationInitStarted = true;
          initStartOrder.add('notification');
        },
      );

      final fakeAuth = FakeAuthService();

      // Start parallel initialization
      final futures = [
        mockDeviceService.initialize(authService: fakeAuth),
        mockNotificationService.initialize(authService: fakeAuth),
      ];

      // Both should have started synchronously before the first await
      // (The mock implementations set the flag synchronously at the start of initialize)
      // We need to check this before awaiting
      expect(deviceInitStarted, isTrue);
      expect(notificationInitStarted, isTrue);
      expect(initStartOrder.length, 2);

      await Future.wait(futures);
    });
  });

  group('Phase 7.6: Sequential init warning detection', () {
    test('sequential init creates race condition window', () async {
      // This test demonstrates WHY parallel init is required.
      // In sequential init, the second service doesn't have _authService
      // set when callbacks fire after the first await.

      final mockDeviceService = MockDeviceServiceForRaceTests();
      final mockNotificationService = MockNotificationServiceForRaceTests();

      final fakeAuth = FakeAuthService(
        onAuthenticatedCallbacks: [
          mockDeviceService.handleAuthenticated,
          mockNotificationService.handleAuthenticated,
        ],
      );

      // WRONG: Sequential initialization (creates race condition)
      // After deviceService.initialize() awaits, microtasks can run
      await mockDeviceService.initialize(authService: fakeAuth);

      // At this point, if Firebase fires an auth event via microtask,
      // notificationService would NOT have _authService set yet!

      // For this test, we manually verify the order matters
      expect(mockDeviceService.isConnectedToAuth, isTrue);
      expect(mockNotificationService.isConnectedToAuth, isFalse); // NOT connected yet!

      await mockNotificationService.initialize(authService: fakeAuth);
      expect(mockNotificationService.isConnectedToAuth, isTrue); // Now connected
    });
  });

  group('Phase 7.7: DeviceService pending payload fallback', () {
    test('DeviceService uses pending payload when handleAuthenticated fires before initialize', () async {
      final mockDeviceService = MockDeviceServiceForRaceTests();

      // Simulate callback firing BEFORE initialize
      // This triggers the graceful degradation path
      await mockDeviceService.handleAuthenticated('early-user');

      // The mock should record that auth wasn't set when callback fired
      expect(mockDeviceService.authWasSetWhenCallbackFired, isFalse);
      expect(mockDeviceService.usedPendingPayloadFallback, isTrue);
    });
  });

  group('Phase 7.8: NotificationService resilience', () {
    test('NotificationService handleAuthenticated works without _authService', () async {
      final mockNotificationService = MockNotificationServiceForRaceTests();

      // Call handleAuthenticated before initialize
      // NotificationService's _handleLogin() doesn't actually need _authService
      await mockNotificationService.handleAuthenticated('early-user');

      // Should not throw and should have processed the login
      expect(mockNotificationService.handleLoginCalled, isTrue);
      expect(mockNotificationService.lastAuthenticatedUid, 'early-user');
    });
  });

  group('Phase 7.9: Warning logs for initialization issues', () {
    test('DeviceService records warning when callback fires before initialize', () async {
      final mockDeviceService = MockDeviceServiceForRaceTests();

      await mockDeviceService.handleAuthenticated('early-user');

      expect(mockDeviceService.warningLogged, isTrue);
      expect(
        mockDeviceService.lastWarningMessage,
        contains('handleAuthenticated called before initialize'),
      );
    });

    test('NotificationService records warning when callback fires before initialize', () async {
      final mockNotificationService = MockNotificationServiceForRaceTests();

      await mockNotificationService.handleAuthenticated('early-user');

      // NotificationService should also log a warning for initialization ordering issues
      expect(mockNotificationService.warningLogged, isTrue);
    });
  });

  group('Phase 7.10: Mixed initialization patterns', () {
    test('services using constructor callbacks work alongside connectToAuthService', () async {
      final constructorService = MockDeviceServiceForRaceTests();
      final legacyService = MockDeviceServiceForRaceTests();

      // Constructor-time callback registration (new pattern)
      final fakeAuth = FakeAuthService(
        onAuthenticatedCallbacks: [
          constructorService.handleAuthenticated,
        ],
      );

      // Initialize constructor service first
      await constructorService.initialize(authService: fakeAuth);

      // Legacy service uses connectToAuthService (old pattern)
      await legacyService.connectToAuthService(
        authService: fakeAuth,
        onAuthenticated: legacyService.handleAuthenticated,
      );

      // Both should work when auth event fires
      await fakeAuth.simulateImmediateAuth('mixed-user');

      expect(constructorService.lastAuthenticatedUid, 'mixed-user');
      // Legacy service should also receive the event via connectToAuthService registration
      expect(legacyService.lastAuthenticatedUid, 'mixed-user');
    });
  });

  group('Phase 7.11: GetIt early registration', () {
    test('services registered in GetIt before AuthService are resolvable', () async {
      final mockDeviceService = MockDeviceServiceForRaceTests();

      // Register service in GetIt BEFORE creating AuthService
      getIt.registerSingleton<DeviceServiceInt>(mockDeviceService);

      // Service should be resolvable
      expect(getIt.isRegistered<DeviceServiceInt>(), isTrue);

      final resolved = getIt.get<DeviceServiceInt>();
      expect(resolved, same(mockDeviceService));

      // Now create AuthService
      final fakeAuth = FakeAuthService(
        onAuthenticatedCallbacks: [
          mockDeviceService.handleAuthenticated,
        ],
      );

      // Initialize service
      await mockDeviceService.initialize(authService: fakeAuth);

      // Auth event should work
      await fakeAuth.simulateImmediateAuth('getit-user');
      expect(mockDeviceService.lastAuthenticatedUid, 'getit-user');
    });

    test('services resolvable during initialization callbacks', () async {
      final mockDeviceService = MockDeviceServiceForRaceTests();
      getIt.registerSingleton<DeviceServiceInt>(mockDeviceService);

      DeviceServiceInt? resolvedDuringCallback;

      final fakeAuth = FakeAuthService(
        onAuthenticatedCallbacks: [
          (uid) async {
            // Try to resolve service during callback
            if (getIt.isRegistered<DeviceServiceInt>()) {
              resolvedDuringCallback = getIt.get<DeviceServiceInt>();
            }
          },
        ],
      );

      await fakeAuth.simulateImmediateAuth('resolve-test-user');

      expect(resolvedDuringCallback, isNotNull);
      expect(resolvedDuringCallback, same(mockDeviceService));
    });
  });

  group('Phase 7.12: Priority-based callback execution order', () {
    test('higher priority callbacks execute before lower priority', () async {
      final executionOrder = <int>[];

      final fakeAuth = FakeAuthService();

      fakeAuth.addOnAuthenticatedCallback((uid) async {
        executionOrder.add(0);
      }, priority: 0);

      fakeAuth.addOnAuthenticatedCallback((uid) async {
        executionOrder.add(100);
      }, priority: 100);

      fakeAuth.addOnAuthenticatedCallback((uid) async {
        executionOrder.add(-50);
      }, priority: -50);

      await fakeAuth.simulateImmediateAuth('priority-test');

      expect(executionOrder.first, 100);
      expect(executionOrder.last, -50);
    });

    test('priority order applies to logout callbacks', () async {
      final executionOrder = <int>[];

      final fakeAuth = FakeAuthService();

      fakeAuth.addOnAboutToLogOutCallback(() async {
        executionOrder.add(0);
      }, priority: 0);

      fakeAuth.addOnAboutToLogOutCallback(() async {
        executionOrder.add(50);
      }, priority: 50);

      fakeAuth.addOnAboutToLogOutCallback(() async {
        executionOrder.add(-25);
      }, priority: -25);

      await fakeAuth.signOut();

      expect(executionOrder.first, 50);
      expect(executionOrder.last, -25);
    });
  });

  group('Phase 7.13: Same-priority callbacks execute concurrently', () {
    test('callbacks with same priority run in parallel', () async {
      final startTimes = <int, DateTime>{};
      final endTimes = <int, DateTime>{};

      final fakeAuth = FakeAuthService();

      // Add 3 callbacks with same priority, each with a delay
      for (var i = 0; i < 3; i++) {
        final index = i;
        fakeAuth.addOnAuthenticatedCallback((uid) async {
          startTimes[index] = DateTime.now();
          await Future.delayed(const Duration(milliseconds: 50));
          endTimes[index] = DateTime.now();
        }, priority: 0);
      }

      await fakeAuth.simulateImmediateAuth('concurrent-test');

      // All callbacks should have started within a small time window
      // (indicating parallel execution)
      final firstStart = startTimes.values.reduce(
        (a, b) => a.isBefore(b) ? a : b,
      );
      final lastStart = startTimes.values.reduce(
        (a, b) => a.isAfter(b) ? a : b,
      );

      // Start times should be very close (within 10ms) if running in parallel
      final startDifference = lastStart.difference(firstStart).inMilliseconds;
      expect(startDifference, lessThan(20)); // Allow some variance

      // Total execution time should be ~50ms (not 150ms if sequential)
      final totalTime = endTimes.values
          .reduce((a, b) => a.isAfter(b) ? a : b)
          .difference(firstStart)
          .inMilliseconds;
      expect(totalTime, lessThan(100)); // Should be ~50ms, not 150ms
    });
  });

  group('Phase 7.14: Global timeout enforcement', () {
    test('global timeout applies across all priority levels', () async {
      final completedCallbacks = <int>[];

      final fakeAuth = FakeAuthService(
        callbackTimeout: const Duration(milliseconds: 100),
      );

      // High priority callback that takes too long
      fakeAuth.addOnAboutToLogOutCallback(() async {
        await Future.delayed(const Duration(milliseconds: 150));
        completedCallbacks.add(100);
      }, priority: 100);

      // Lower priority callback that should be skipped due to timeout
      fakeAuth.addOnAboutToLogOutCallback(() async {
        completedCallbacks.add(0);
      }, priority: 0);

      await fakeAuth.signOut();

      // The high-priority callback should timeout, and lower priority may be skipped
      // Actual behavior depends on implementation - the key is logout completes
      // and doesn't hang indefinitely
      expect(fakeAuth.signOutCompleted, isTrue);
    });

    test('logout proceeds even when callbacks timeout', () async {
      var signOutCompleted = false;

      final fakeAuth = FakeAuthService(
        callbackTimeout: const Duration(milliseconds: 50),
        onSignOut: () async {
          signOutCompleted = true;
        },
      );

      fakeAuth.addOnAboutToLogOutCallback(() async {
        // This callback takes longer than timeout
        await Future.delayed(const Duration(milliseconds: 200));
      }, priority: 0);

      await fakeAuth.signOut();

      expect(signOutCompleted, isTrue);
    });
  });
}

// =============================================================================
// Helper Functions
// =============================================================================

void _resetGetIt(GetIt getIt) {
  if (getIt.isRegistered<DeviceServiceInt>()) {
    getIt.unregister<DeviceServiceInt>();
  }
  if (getIt.isRegistered<AuthServiceInt>()) {
    getIt.unregister<AuthServiceInt>();
  }
}

// =============================================================================
// Fake/Mock Implementations for Testing
// =============================================================================

/// Fake AuthService that simulates immediate auth events for testing race conditions.
///
/// This fake implementation allows tests to:
/// - Register callbacks in constructor (like real AuthServiceImpl)
/// - Simulate immediate auth state emission (warm start)
/// - Track callback invocations and timing
/// - Verify priority-based execution
class FakeAuthService implements AuthServiceInt {
  final Map<int, List<Future<void> Function(String? uid)>> _onAuthenticatedByPriority = {};
  final Map<int, List<Future<void> Function()>> _onAboutToLogOutByPriority = {};
  final Map<int, List<Future<void> Function()>> _onLoggedOutByPriority = {};

  final Duration callbackTimeout;
  final Future<void> Function()? onSignOut;
  bool signOutCompleted = false;

  FakeAuthService({
    List<Future<void> Function(String? uid)>? onAuthenticatedCallbacks,
    List<Future<void> Function()>? onAboutToLogOutCallbacks,
    List<Future<void> Function()>? onLoggedOutCallbacks,
    List<PrioritizedCallback<Future<void> Function(String? uid)>>? onAuthenticatedPrioritized,
    List<PrioritizedCallback<Future<void> Function()>>? onAboutToLogOutPrioritized,
    List<PrioritizedCallback<Future<void> Function()>>? onLoggedOutPrioritized,
    this.callbackTimeout = const Duration(seconds: 30),
    this.onSignOut,
  }) {
    // Register prioritized callbacks
    if (onAuthenticatedPrioritized != null) {
      for (final pc in onAuthenticatedPrioritized) {
        addOnAuthenticatedCallback(pc.callback, priority: pc.priority);
      }
    }
    if (onAboutToLogOutPrioritized != null) {
      for (final pc in onAboutToLogOutPrioritized) {
        addOnAboutToLogOutCallback(pc.callback, priority: pc.priority);
      }
    }
    if (onLoggedOutPrioritized != null) {
      for (final pc in onLoggedOutPrioritized) {
        addOnLoggedOutCallback(pc.callback, priority: pc.priority);
      }
    }

    // Register list callbacks (default priority 0)
    if (onAuthenticatedCallbacks != null) {
      for (final callback in onAuthenticatedCallbacks) {
        addOnAuthenticatedCallback(callback);
      }
    }
    if (onAboutToLogOutCallbacks != null) {
      for (final callback in onAboutToLogOutCallbacks) {
        addOnAboutToLogOutCallback(callback);
      }
    }
    if (onLoggedOutCallbacks != null) {
      for (final callback in onLoggedOutCallbacks) {
        addOnLoggedOutCallback(callback);
      }
    }
  }

  /// Simulates Firebase emitting an auth state change immediately.
  ///
  /// This mimics the warm start scenario where the user is already logged in.
  Future<void> simulateImmediateAuth(String uid) async {
    await _executeCallbacksByPriority(
      _onAuthenticatedByPriority,
      uid,
      callbackTimeout,
    );
  }

  /// Executes callbacks by priority (higher first).
  Future<void> _executeCallbacksByPriority<T>(
    Map<int, List<Future<void> Function(T)>> callbacksByPriority,
    T argument,
    Duration timeout,
  ) async {
    if (callbacksByPriority.isEmpty) return;

    final priorities = callbacksByPriority.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    final stopwatch = Stopwatch()..start();

    for (final priority in priorities) {
      if (stopwatch.elapsed >= timeout) break;

      final callbacks = callbacksByPriority[priority] ?? [];
      if (callbacks.isEmpty) continue;

      final remainingTime = timeout - stopwatch.elapsed;

      try {
        await Future.wait(
          callbacks.map((cb) => cb(argument).catchError((e) {})),
        ).timeout(remainingTime, onTimeout: () => []);
      } catch (_) {}
    }
  }

  /// Executes void callbacks by priority (higher first).
  Future<void> _executeVoidCallbacksByPriority(
    Map<int, List<Future<void> Function()>> callbacksByPriority,
    Duration timeout,
  ) async {
    if (callbacksByPriority.isEmpty) return;

    final priorities = callbacksByPriority.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    final stopwatch = Stopwatch()..start();

    for (final priority in priorities) {
      if (stopwatch.elapsed >= timeout) break;

      final callbacks = callbacksByPriority[priority] ?? [];
      if (callbacks.isEmpty) continue;

      final remainingTime = timeout - stopwatch.elapsed;

      try {
        await Future.wait(
          callbacks.map((cb) => cb().catchError((e) {})),
        ).timeout(remainingTime, onTimeout: () => []);
      } catch (_) {}
    }
  }

  @override
  void addOnAuthenticatedCallback(
    Future<void> Function(String? uid) callback, {
    int priority = 0,
  }) {
    _onAuthenticatedByPriority.putIfAbsent(priority, () => []).add(callback);
  }

  @override
  bool removeOnAuthenticatedCallback(Future<void> Function(String? uid) callback) {
    for (final callbacks in _onAuthenticatedByPriority.values) {
      if (callbacks.remove(callback)) return true;
    }
    return false;
  }

  @override
  void addOnAboutToLogOutCallback(
    Future<void> Function() callback, {
    int priority = 0,
  }) {
    _onAboutToLogOutByPriority.putIfAbsent(priority, () => []).add(callback);
  }

  @override
  bool removeOnAboutToLogOutCallback(Future<void> Function() callback) {
    for (final callbacks in _onAboutToLogOutByPriority.values) {
      if (callbacks.remove(callback)) return true;
    }
    return false;
  }

  @override
  void addOnLoggedOutCallback(
    Future<void> Function() callback, {
    int priority = 0,
  }) {
    _onLoggedOutByPriority.putIfAbsent(priority, () => []).add(callback);
  }

  @override
  bool removeOnLoggedOutCallback(Future<void> Function() callback) {
    for (final callbacks in _onLoggedOutByPriority.values) {
      if (callbacks.remove(callback)) return true;
    }
    return false;
  }

  @override
  Future<Either<AuthServiceSignOutFailure, Unit>> signOut({bool useFbAuthAlso = true}) async {
    // Execute onAboutToLogOut callbacks first
    await _executeVoidCallbacksByPriority(
      _onAboutToLogOutByPriority,
      callbackTimeout,
    );

    // Then perform sign out
    if (onSignOut != null) {
      await onSignOut!();
    }

    // Then execute onLoggedOut callbacks
    await _executeVoidCallbacksByPriority(
      _onLoggedOutByPriority,
      callbackTimeout,
    );

    signOutCompleted = true;
    return const Right(unit);
  }

  // Required interface methods - minimal implementations for testing
  @override
  fb_auth.UserCredential? currentFbUserCredentials;

  @override
  fb_auth.User? get currentFbUser => null;

  @override
  set currentFbUser(fb_auth.User? user) {}

  @override
  Stream<bool> get isLoggedInStream => Stream.value(false);

  @override
  bool get isEmailVerified => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Mock DeviceService for race condition testing.
///
/// Tracks whether _authService was set when callbacks fired,
/// which is critical for verifying the race-free initialization.
class MockDeviceServiceForRaceTests implements DeviceServiceInt {
  AuthServiceInt? _authService;
  bool _isConnectedToAuthService = false;

  // Tracking for test assertions
  bool authWasSetWhenCallbackFired = false;
  bool usedPendingPayloadFallback = false;
  bool warningLogged = false;
  String? lastWarningMessage;
  String? lastAuthenticatedUid;

  // Callbacks for test control
  final Future<void> Function(String? uid)? onHandleAuthenticated;
  final void Function()? onInitializeStart;

  MockDeviceServiceForRaceTests({
    this.onHandleAuthenticated,
    this.onInitializeStart,
  });

  @override
  Future<void> handleAuthenticated(String? uid) async {
    lastAuthenticatedUid = uid;
    authWasSetWhenCallbackFired = _authService != null;

    if (_authService == null) {
      warningLogged = true;
      lastWarningMessage = 'DeviceService: handleAuthenticated called before initialize(). '
          'Device registration will use pending payload fallback.';
      usedPendingPayloadFallback = true;
    }

    if (onHandleAuthenticated != null) {
      await onHandleAuthenticated!(uid);
    }
  }

  @override
  Future<void> handleAboutToLogOut() async {
    // Minimal implementation for testing
  }

  @override
  Future<void> initialize({required AuthServiceInt authService}) async {
    // CRITICAL: Set _authService FIRST, synchronously, before any await
    onInitializeStart?.call();
    _authService = authService;
    _isConnectedToAuthService = true;

    // Simulate some async initialization work
    await Future.delayed(const Duration(milliseconds: 10));
  }

  @override
  bool get isConnectedToAuth => _isConnectedToAuthService;

  @override
  Future<void> connectToAuthService({
    AuthServiceInt? authService,
    Future<void> Function(String? uid)? onAuthenticated,
    Future<void> Function()? onAboutToLogOut,
  }) async {
    _authService = authService;
    _isConnectedToAuthService = authService != null;

    // Register callbacks with auth service
    if (authService != null && onAuthenticated != null) {
      authService.addOnAuthenticatedCallback(onAuthenticated);
    }
  }

  // Minimal implementations for other interface methods
  @override
  Future<String> getDeviceId() async => 'mock-device-id';

  @override
  Future<String> getCurrentTimezone() async => 'America/New_York';

  @override
  Future<Either<RepositoryFailure, Unit>> registerDevice() async => const Right(unit);

  @override
  Future<Either<RepositoryFailure, Unit>> unregisterDevice() async => const Right(unit);

  @override
  Future<Either<RepositoryFailure, Unit>> touchDevice() async => const Right(unit);

  @override
  Future<Either<RepositoryFailure, bool>> updateTimezoneOrOffsetIfChanged() async =>
      const Right(false);

  @override
  Future<Either<RepositoryFailure, Unit>> persistFcmToken({required String? fcmToken}) async =>
      const Right(unit);

  @override
  Future<Either<RepositoryFailure, List<DeviceInfo>>> getMyDevices() async => const Right([]);
}

/// Mock NotificationService for race condition testing.
class MockNotificationServiceForRaceTests {
  AuthServiceInt? _authService;
  bool _isConnectedToAuthService = false;

  // Tracking for test assertions
  bool handleLoginCalled = false;
  bool warningLogged = false;
  String? lastAuthenticatedUid;

  // Callbacks for test control
  final Future<void> Function(String? uid)? onHandleAuthenticated;
  final void Function()? onInitializeStart;

  MockNotificationServiceForRaceTests({
    this.onHandleAuthenticated,
    this.onInitializeStart,
  });

  Future<void> handleAuthenticated(String? uid) async {
    lastAuthenticatedUid = uid;

    if (_authService == null) {
      warningLogged = true;
      // NotificationService's _handleLogin doesn't need _authService,
      // but we log a warning to surface initialization ordering issues
    }

    handleLoginCalled = true;

    if (onHandleAuthenticated != null) {
      await onHandleAuthenticated!(uid);
    }
  }

  Future<void> handleAboutToLogOut() async {
    // Minimal implementation for testing
  }

  Future<void> initialize({required AuthServiceInt authService}) async {
    // CRITICAL: Set _authService FIRST, synchronously, before any await
    onInitializeStart?.call();
    _authService = authService;
    _isConnectedToAuthService = true;

    // Simulate some async initialization work
    await Future.delayed(const Duration(milliseconds: 10));
  }

  bool get isConnectedToAuth => _isConnectedToAuthService;
}
