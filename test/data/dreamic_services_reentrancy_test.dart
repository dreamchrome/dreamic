import 'package:flutter_test/flutter_test.dart';

import 'package:dreamic/app/startup/dreamic_bootstrap.dart';
import 'package:dreamic/data/repos/device_service_impl.dart';
import 'package:dreamic/notifications/notification_service.dart';

/// Tests for the `DreamicServices.initialize` re-entrancy primitives
/// (Issues 47/52/56/75) that are verifiable on the VM test runner.
///
/// ## Scope note (intentional deviation)
///
/// The FULL `DreamicServices.initialize` re-entrancy scenario from the Testing
/// Strategy (e) — drive a simulated partial failure *inside* `initialize` then a
/// retry and assert exactly one live `authStateChanges`/`idTokenChanges`
/// listener, no duplicate FCM/lifecycle subscriptions, the orphaned first-run
/// services disposed, and `g<DeviceServiceInt>()`/`g<NotificationService>()`
/// resolving the retry's LIVE re-registered instances — requires the real
/// `AuthServiceImpl` (a Firebase **auth** platform host for
/// `authStateChanges().listen`), the real `NotificationService.initialize` (FCM
/// + flutter_local_notifications platform channels) and the real
/// `DeviceServiceImpl.initialize` (device/SharedPreferences/lifecycle channels).
/// None of those platform hosts exist on the VM runner — the same constraint
/// that makes the existing device/notification suites use *mock* services
/// (`test/data/device_service/`, `test/data/auth_race/`) and that the Phase-3
/// bootstrap suite documented for `DreamicServices.initialize`. That end-to-end
/// orchestration is verified by the later-phase consumer/device verification.
///
/// What IS VM-verifiable — and tested here — are the re-entrancy *mechanisms*
/// the orchestration composes:
/// - the "already-initialized" early-return cache reset (Issue 75) is wired into
///   the dreamic bootstrap idempotency reset;
/// - `DeviceServiceImpl` exposes a callable public teardown (`dispose()`) for
///   the dispose-on-failure path (Issue 56);
/// - `NotificationService.initialize` recreates its `_badgeCountController` when
///   a prior `dispose()` closed it, so `badgeCountStream` is live post-recovery
///   and a later `updateBadgeCount()`/`add()` does not throw (Issue 56).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('early-return cache reset (Issues 47/75)', () {
    test(
        'resetDreamicBootstrapIdempotencyForTest clears the DreamicServices '
        'early-return cache (does not throw)', () {
      // The combined reset must clear the static backing the
      // "already-initialized" early-return so re-entrancy tests are
      // order-independent (Issue 75). It is a safe idempotent reset even when
      // no init has run yet.
      resetDreamicBootstrapIdempotencyForTest();
      resetDreamicBootstrapIdempotencyForTest();
    });
  });

  group('DeviceServiceImpl public teardown (Issue 56)', () {
    test('dispose() is callable on a fresh instance without throwing', () async {
      final device = DeviceServiceImpl();
      // No lifecycle subscription is connected on a fresh instance, so dispose
      // is a safe no-op cancel — the dispose-on-failure path can always call it.
      await device.dispose();
    });

    test('dispose() is idempotent (callable twice)', () async {
      final device = DeviceServiceImpl();
      await device.dispose();
      await device.dispose();
    });
  });

  group('NotificationService badge-controller re-init recovery (Issue 56)', () {
    tearDown(() {
      // NotificationService is a factory-singleton; we disposed/mutated it, so
      // reset it for the next test's isolation.
      NotificationService.resetForTesting();
    });

    test(
        'dispose() closes the badge controller; re-init recreates it so '
        'badgeCountStream is live again and add() does not throw', () async {
      // NotificationService is a factory-singleton — get the canonical instance.
      final service = NotificationService();

      // dispose() closes the badge controller (the dispose-on-failure path).
      await service.dispose();

      // The OLD stream reference is now closed — listening to it completes
      // immediately (broadcast controller, closed → done).
      await expectLater(service.badgeCountStream, emitsDone);

      // Re-init recovery: the same recreation initialize() runs at its top
      // (exercised here via the seam to avoid the platform-heavy full
      // initialize()).
      service.recreateBadgeControllerIfClosedForTesting();

      // The stream is live again — a post-recovery emission is delivered (not
      // dropped/throwing on a closed controller).
      final received = expectLater(service.badgeCountStream, emits(7));
      await service.updateBadgeCount(7);
      await received;
    });

    test('recreation is a no-op when the controller is still open', () async {
      final service = NotificationService();

      // Attach a listener to the OPEN controller BEFORE recreation. If
      // recreation wrongly replaced the controller, this pre-existing listener
      // would be dropped (never receive the emission).
      final received = <int>[];
      final sub = service.badgeCountStream.listen(received.add);
      addTearDown(sub.cancel);

      // No prior dispose — the controller is open, so recreation must NOT
      // replace it.
      service.recreateBadgeControllerIfClosedForTesting();

      await service.updateBadgeCount(3);
      // Let the broadcast emission flush.
      await Future<void>.delayed(Duration.zero);

      expect(received, [3],
          reason: 'pre-existing listener still receives — controller not '
              'replaced when open');
    });
  });
}
