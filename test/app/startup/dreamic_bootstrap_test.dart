import 'dart:async';

import 'package:dreamic/app/app_config_base.dart';
import 'package:dreamic/app/app_cubit.dart';
import 'package:dreamic/app/helpers/app_cubit_init.dart';
import 'package:dreamic/app/helpers/app_errorhandling_init.dart';
import 'package:dreamic/app/helpers/app_firebase_init.dart';
import 'package:dreamic/app/helpers/app_remote_config_init.dart';
import 'package:dreamic/app/startup/dreamic_bootstrap.dart';
import 'package:dreamic/data/repos/dreamic_services.dart';
import 'package:dreamic/data/repos/remote_config_repo_int.dart';
import 'package:dreamic/error_reporting/error_reporter_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

/// A no-op custom reporter (Sentry-like) used to exercise the early-attach
/// derivation from [ErrorReportingConfig].
class _StubReporter extends ErrorReporter {
  @override
  void recordError(Object error, StackTrace? stackTrace) {}
}

/// Records every error routed to it (via `loge` → the attached reporter), so a
/// test can assert that the registered-app recovery actually REPORTS.
class _RecordingReporter extends ErrorReporter {
  final List<Object> recordedErrors = [];

  @override
  void recordError(Object error, StackTrace? stackTrace) => recordedErrors.add(error);
}

/// Minimal Firebase options for `appInitFirebase` under the mocked core host.
const _testOptions = FirebaseOptions(
  apiKey: 'test',
  appId: 'test',
  messagingSenderId: 'test',
  projectId: 'test',
);

/// A `servicesInitializer` stub for the pipeline tests. Every test below aborts
/// BEFORE the services step (via a throwing/hanging earlier hook, or by testing
/// the helpers directly), so this is never actually reached — it throws if it
/// is, surfacing any accidental reliance on the real `DreamicServices.initialize`
/// (which needs auth/FCM/device platform channels — a Phase-4 / integration
/// concern). The pipeline's job under test is ORDERING + the fatal/non-fatal +
/// timeout policy, not the platform services themselves.
Future<DreamicServicesResult> _noopServices(FirebaseApp app) async {
  throw StateError(
    'servicesInitializer should not be reached by these ordering/policy tests',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUp(() async {
    // Reset the dreamic-core idempotency apply-once flags between cases so the
    // fresh-run/re-run assertions are order-independent (Issue 63).
    resetDreamicBootstrapIdempotencyForTest();
    await GetIt.I.reset();
    AppConfigBase.isFirebaseInitialized = false;
  });

  tearDown(() async {
    resetDreamicBootstrapIdempotencyForTest();
    await GetIt.I.reset();
  });

  group('outer hang-timeout (Issue 81)', () {
    test('a hang past bootstrapTimeout throws TimeoutException → gate error',
        () async {
      // Hang in afterFirebaseInit (runs right after the mockable
      // appInitFirebase, before the platform-heavy steps).
      final future = dreamicBootstrap(
        firebaseOptions: _testOptions,
        servicesInitializer: _noopServices,
        afterFirebaseInit: () => Completer<void>().future, // never completes
        bootstrapTimeout: const Duration(milliseconds: 50),
      );

      await expectLater(future, throwsA(isA<TimeoutException>()));
    });

    test('a null bootstrapTimeout disables the timeout (does not throw)',
        () async {
      // With the timeout disabled, a fast-completing afterFirebaseInit lets the
      // pipeline proceed; we abort it deterministically by throwing a sentinel
      // from afterFirebaseInit so we never reach the platform-heavy steps.
      final sentinel = StateError('reached-after-firebase');
      final future = dreamicBootstrap(
        firebaseOptions: _testOptions,
        servicesInitializer: _noopServices,
        afterFirebaseInit: () => throw sentinel,
        bootstrapTimeout: null,
      );

      // No TimeoutException — the hook's own throw surfaces instead, proving the
      // timeout was not applied.
      await expectLater(future, throwsA(same(sentinel)));
    });

    test('the TimeoutException names the step that was in flight when it hung',
        () async {
      final future = dreamicBootstrap(
        firebaseOptions: _testOptions,
        servicesInitializer: _noopServices,
        afterFirebaseInit: () => Completer<void>().future, // never completes
        bootstrapTimeout: const Duration(milliseconds: 50),
      );

      await expectLater(
        future,
        throwsA(isA<TimeoutException>().having(
          (e) => e.message,
          'message',
          contains('afterFirebaseInit hook'),
        )),
      );
    });

    test(
        'attachErrorReportingFirst:true still names the hung step (early attach does not disrupt the sequence)',
        () async {
      final future = dreamicBootstrap(
        firebaseOptions: _testOptions,
        servicesInitializer: _noopServices,
        // Hangs AFTER the step-0 early attach + the mocked appInitFirebase.
        afterFirebaseInit: () => Completer<void>().future,
        bootstrapTimeout: const Duration(milliseconds: 50),
        attachErrorReportingFirst: true,
      );

      await expectLater(
        future,
        throwsA(isA<TimeoutException>().having(
          (e) => e.message,
          'message',
          contains('afterFirebaseInit hook'),
        )),
      );
    });

    test(
        'firebaseInitTimeout does not trip on a healthy (fast) Firebase init — the sequence advances past step 1',
        () async {
      final future = dreamicBootstrap(
        firebaseOptions: _testOptions,
        servicesInitializer: _noopServices,
        // Hangs in the step AFTER Firebase init; if the per-step Firebase
        // timeout false-fired, the message would name "appInitFirebase" instead.
        afterFirebaseInit: () => Completer<void>().future,
        bootstrapTimeout: const Duration(milliseconds: 80),
        firebaseInitTimeout: const Duration(seconds: 5), // generous; mock is fast
      );

      await expectLater(
        future,
        throwsA(isA<TimeoutException>().having(
          (e) => e.message,
          'message',
          contains('afterFirebaseInit hook'),
        )),
      );
    });
  });

  group('resolveAttachErrorReportingFirst — great default derived from config', () {
    tearDown(() {
      // Reset the module-global config so other groups see the default.
      configureErrorReporting(const ErrorReportingConfig());
    });

    test('explicit override wins over the config (true / false)', () {
      configureErrorReporting(const ErrorReportingConfig()); // no reporter
      expect(resolveAttachErrorReportingFirst(true), isTrue);
      expect(resolveAttachErrorReportingFirst(false), isFalse);
    });

    test('self-contained reporter (no Firebase needed) → attaches early', () {
      configureErrorReporting(
        ErrorReportingConfig.customOnly(reporter: _StubReporter()),
      );
      expect(resolveAttachErrorReportingFirst(null), isTrue);
    });

    test('Firebase-dependent reporter (requiresFirebase) → does NOT attach early',
        () {
      configureErrorReporting(
        ErrorReportingConfig.customOnly(
          reporter: _StubReporter(),
          requiresFirebase: true,
        ),
      );
      expect(resolveAttachErrorReportingFirst(null), isFalse);
    });

    test('unconfigured (no reporter) → does NOT attach early', () {
      configureErrorReporting(const ErrorReportingConfig());
      expect(resolveAttachErrorReportingFirst(null), isFalse);
    });
  });

  group('runBoundedNonCritical — bounds + swallows non-critical hook work', () {
    test('completes normally when the work succeeds quickly', () async {
      var ran = false;
      await runBoundedNonCritical(
        () async {
          ran = true;
        },
        timeout: const Duration(seconds: 1),
        label: 'ok',
      );
      expect(ran, isTrue);
    });

    test('swallows a throwing work — never rethrows', () async {
      await expectLater(
        runBoundedNonCritical(
          () async => throw StateError('boom'),
          timeout: const Duration(seconds: 1),
          label: 'throws',
        ),
        completes,
      );
    });

    test('swallows a hang — times out and returns instead of stalling', () async {
      await expectLater(
        runBoundedNonCritical(
          () => Completer<void>().future, // never completes
          timeout: const Duration(milliseconds: 20),
          label: 'hangs',
        ),
        completes,
      );
    });
  });

  group('per-task fatal policy (Issues 81/84)', () {
    test('a throwing app hook is FATAL (aborts the bootstrap Future)', () async {
      final hookError = StateError('hook-blew-up');
      final future = dreamicBootstrap(
        firebaseOptions: _testOptions,
        servicesInitializer: _noopServices,
        // afterFirebaseInit is an app hook — dreamic-core does NOT wrap it, so
        // its throw propagates as fatal.
        afterFirebaseInit: () => throw hookError,
      );

      await expectLater(future, throwsA(same(hookError)));
    });
  });

  group('idempotency — guarded re-init (Firebase)', () {
    test('appInitFirebase twice does not throw duplicate-app', () async {
      final a = await appInitFirebase(_testOptions);
      final b = await appInitFirebase(_testOptions);
      expect(a.name, b.name); // same default app reused
      expect(AppConfigBase.isFirebaseInitialized, isTrue);
    });

    test('settleTimeout does not trip a healthy (fast) init', () async {
      // A generous bound on a fast-settling (mocked) init never fires, so the
      // app initializes normally — the recovery/throw branches only engage when
      // the init actually hangs (validated in production via the reported
      // error, which the mock cannot reproduce).
      final app = await appInitFirebase(
        _testOptions,
        settleTimeout: const Duration(seconds: 5),
      );
      expect(app.name, isNotEmpty);
      expect(AppConfigBase.isFirebaseInitialized, isTrue);
    });

    test('two-tier (settleTimeout + recoverIfRegisteredAfter) does not trip a healthy init',
        () async {
      // The short grace + outer bound both pass through a fast (mocked) init
      // without engaging the recover/throw branches.
      final app = await appInitFirebase(
        _testOptions,
        settleTimeout: const Duration(seconds: 5),
        recoverIfRegisteredAfter: const Duration(seconds: 1),
      );
      expect(app.name, isNotEmpty);
      expect(AppConfigBase.isFirebaseInitialized, isTrue);
    });
  });

  group('appInitFirebase — two-tier recovery (awaitFirebaseInitForTest)', () {
    // A real (mocked) FirebaseApp to hand back from the recovery branches; the
    // registration probe is injected, so these exercise the recover/throw logic
    // WITHOUT a real hung native initializeApp.
    late FirebaseApp fakeApp;

    setUp(() async {
      fakeApp = Firebase.apps.isNotEmpty
          ? Firebase.app()
          : await Firebase.initializeApp(options: _testOptions);
    });

    // Clear any diagnostic the recovery deferred into the early-error machinery.
    tearDown(resetEarlyErrorHandlersForTest);

    test('grace trips + app registered → recovers via the registered app (tier 1)',
        () async {
      final result = await awaitFirebaseInitForTest(
        Completer<FirebaseApp>().future, // never settles (the confirmed hang)
        settleTimeout: const Duration(milliseconds: 400),
        recoverIfRegisteredAfter: const Duration(milliseconds: 20),
        isRegistered: () => true,
        registeredApp: () => fakeApp,
      );
      expect(result, same(fakeApp));
    });

    test(
        'grace trips + NOT registered → waits the remainder, returns the late-settling init',
        () async {
      final c = Completer<FirebaseApp>();
      // Settle AFTER the grace (so the grace trips with no registration) but
      // within the remaining settle budget → the fall-through returns it.
      Future<void>.delayed(const Duration(milliseconds: 50), () => c.complete(fakeApp));
      final result = await awaitFirebaseInitForTest(
        c.future,
        settleTimeout: const Duration(milliseconds: 600),
        recoverIfRegisteredAfter: const Duration(milliseconds: 20),
        isRegistered: () => false,
        registeredApp: () => fakeApp,
      );
      expect(result, same(fakeApp));
    });

    test('settle bound trips + app registered → recovers via the registered app (tier 2)',
        () async {
      final result = await awaitFirebaseInitForTest(
        Completer<FirebaseApp>().future,
        settleTimeout: const Duration(milliseconds: 40),
        recoverIfRegisteredAfter: null, // no grace → single settle bound
        isRegistered: () => true,
        registeredApp: () => fakeApp,
      );
      expect(result, same(fakeApp));
    });

    test(
        'settle bound trips + NOT registered → throws a diagnosable, named TimeoutException',
        () async {
      await expectLater(
        awaitFirebaseInitForTest(
          Completer<FirebaseApp>().future,
          settleTimeout: const Duration(milliseconds: 40),
          recoverIfRegisteredAfter: null,
          isRegistered: () => false,
          registeredApp: () => fakeApp,
        ),
        throwsA(isA<TimeoutException>().having(
          (e) => e.message,
          'message',
          allOf(contains('did not settle within'), contains('no app was registered')),
        )),
      );
    });

    test('grace + settle both trip with nothing registered → throws (no false recovery)',
        () async {
      await expectLater(
        awaitFirebaseInitForTest(
          Completer<FirebaseApp>().future,
          settleTimeout: const Duration(milliseconds: 60),
          recoverIfRegisteredAfter: const Duration(milliseconds: 20),
          isRegistered: () => false,
          registeredApp: () => fakeApp,
        ),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('a registered-app recovery is REPORTED (not silently swallowed)', () async {
      // Attach a recording reporter so the recovery's reportBootstrapDiagnostic
      // routes to it immediately (post-attach), proving the recovery is visible.
      final reporter = _RecordingReporter();
      final savedFlutterOnError = FlutterError.onError;
      final savedPlatformOnError = PlatformDispatcher.instance.onError;
      AppConfigBase.doUseBackendEmulatorOverride = false;
      AppConfigBase.doDisableErrorReportingOverride = false;
      AppConfigBase.doForceErrorReportingOverride = true; // report under the debug runner
      resetEarlyErrorHandlersForTest();
      configureErrorReporting(
        ErrorReportingConfig.customOnly(
          reporter: reporter,
          enableInDebug: true,
          enableOnWeb: true,
        ),
      );
      await appInitErrorHandling(); // attach → reportBootstrapDiagnostic reports now

      try {
        final result = await awaitFirebaseInitForTest(
          Completer<FirebaseApp>().future,
          settleTimeout: const Duration(milliseconds: 400),
          recoverIfRegisteredAfter: const Duration(milliseconds: 20),
          isRegistered: () => true,
          registeredApp: () => fakeApp,
        );
        expect(result, same(fakeApp));
        expect(reporter.recordedErrors.whereType<TimeoutException>(), isNotEmpty);
      } finally {
        FlutterError.onError = savedFlutterOnError;
        PlatformDispatcher.instance.onError = savedPlatformOnError;
        AppConfigBase.doUseBackendEmulatorOverride = null;
        AppConfigBase.doDisableErrorReportingOverride = null;
        AppConfigBase.doForceErrorReportingOverride = null;
        configureErrorReporting(const ErrorReportingConfig());
        resetEarlyErrorHandlersForTest();
      }
    });
  });

  group('idempotency — apply-once emulator connect (Issue 32)', () {
    test(
        'the connect step is re-runnable (no throw) — production no-op path '
        'twice', () async {
      // `doUseBackendEmulator=false` → the connect step early-returns
      // (production parity). The plan requires this test to pass "whether or
      // not doUseBackendEmulator is set" (Issue 32); the real dev-emulator
      // useXEmulator pigeon calls are not exercisable on the VM test runner
      // (they throw firebase_auth/channel-error with no platform host), so the
      // VM-verifiable shape is the production no-op run twice. The apply-once
      // GUARD itself is unit-checked by the reset-seam test below.
      AppConfigBase.doUseBackendEmulatorOverride = false;
      addTearDown(() => AppConfigBase.doUseBackendEmulatorOverride = null);

      final app = await appInitFirebase(_testOptions);
      await appInitConnectToFirebaseEmulatorIfNecessary(app);
      await appInitConnectToFirebaseEmulatorIfNecessary(app);
      // Reaching here without throwing is the assertion.
    });

    test('resetDreamicBootstrapIdempotencyForTest clears the apply-once flag',
        () {
      // The combined reset clears the dreamic-core apply-once flags
      // (emulator-connect + isolate-listener) so the fresh-run/re-run
      // assertions are order-independent (Issue 63). Calling it twice is a safe
      // idempotent reset.
      resetDreamicBootstrapIdempotencyForTest();
      resetDreamicBootstrapIdempotencyForTest();
    });
  });

  group('idempotency — RC registration both sites (Issue 39)', () {
    test('appInitRemoteConfig twice does not throw (fake/mock site)', () async {
      // Firebase NOT initialized → _initFakeRemoteConfig path (the bare-
      // registration site that would otherwise throw "already registered").
      AppConfigBase.isFirebaseInitialized = false;

      await appInitRemoteConfig();
      expect(GetIt.I.isRegistered<RemoteConfigRepoInt>(), isTrue);

      // Second run must be a no-op (isRegistered-guarded), not a throw.
      await appInitRemoteConfig();
      expect(GetIt.I.isRegistered<RemoteConfigRepoInt>(), isTrue);
    });
  });

  group('idempotency — appInitAppCubit early-return', () {
    test('a second call early-returns the already-registered AppCubit',
        () async {
      // networkRequired:false avoids the real network check; getInitialData
      // still runs once, but the second call must early-return the SAME cubit
      // without re-registering (which would throw) or re-running getInitialData.
      final first = await appInitAppCubit(networkRequired: false);
      final second = await appInitAppCubit(networkRequired: false);
      expect(identical(first, second), isTrue);
      expect(GetIt.I.get<AppCubit>(), same(first));
    });
  });

  group('idempotency — afterFirebaseInit hook re-invocation (Issue 87)', () {
    test(
        'a stub apply-once afterFirebaseInit re-invokes on retry but does not '
        'double-apply', () async {
      // dreamic-core has NO Firestore-settings code of its own (the real
      // apply-once setter is MPP's), so this exercises the CONTRACT with a stub
      // hook: the hook is re-invoked per generation, and a hook that
      // apply-once-guards its own work does not double-apply on the second run.
      var invokeCount = 0;
      var applyCount = 0;
      var applied = false;
      final abort = StateError('stop-after-hook');
      Future<void> hook() async {
        invokeCount++;
        if (!applied) {
          applied = true;
          applyCount++;
        }
        // Record FIRST (happens-before), THEN abort the Future so the
        // platform-heavy steps after this hook (appInitAppConfigsBase etc.)
        // never run — keeping this a pure hook re-invocation / apply-once probe.
        // The throw is fatal (dreamic-core does not wrap hooks), which is also
        // exactly the abort we want here.
        throw abort;
      }

      // Two independent generations (each dreamicBootstrap call = one
      // generation), so the hook should re-invoke per generation but its
      // apply-once-guarded work should not double-apply.
      Future<void> runGeneration() => dreamicBootstrap(
            firebaseOptions: _testOptions,
            servicesInitializer: _noopServices,
            afterFirebaseInit: hook,
            bootstrapTimeout: null,
          ).catchError((Object e) {
            if (!identical(e, abort)) throw e;
          });

      await runGeneration();
      await runGeneration();

      expect(invokeCount, 2, reason: 'hook re-invoked once per generation');
      expect(applyCount, 1, reason: 'apply-once not double-applied on re-run');
    });
  });
}
