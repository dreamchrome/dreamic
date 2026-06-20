import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../data/repos/dreamic_services.dart';
import '../helpers/app_configs_init.dart';
import '../helpers/app_cubit_init.dart';
import '../helpers/app_errorhandling_init.dart';
import '../helpers/app_firebase_init.dart';
import '../helpers/app_remote_config_init.dart';

/// A plain `FutureOr<void>` hook the consuming app composes into the bootstrap
/// sequence. Hooks run at fixed ordering points (see [dreamicBootstrap]) and
/// **must be idempotent** — they re-run on every gate retry.
///
/// A throw from a hook propagates as **fatal** (`dreamicBootstrap()` does NOT
/// wrap hooks, Issue 84): an uncaught hook throw aborts the bootstrap Future →
/// the gate's `errorWidget` → retry. An app that does NON-critical work in a
/// hook (e.g. `TimezoneService.initialize()`, cold deep-link capture) must
/// `try/catch`-and-continue around that work itself.
typedef DreamicBootstrapHook = FutureOr<void> Function();

/// App-supplied services initializer. Called at the services step with the
/// initialized [FirebaseApp]; the app calls `DreamicServices.initialize(...)`
/// with its own auth-lifecycle and notification callbacks and returns the
/// result.
///
/// Kept as an app-supplied callback (rather than threading every
/// `DreamicServices.initialize` parameter through [dreamicBootstrap]) so
/// dreamic-core does not need to know each consumer's callback set. This is a
/// **fatal** step — a throw here aborts the Future (Issue 81 per-task policy).
typedef DreamicServicesInitializer = Future<DreamicServicesResult> Function(
  FirebaseApp firebaseApp,
);

/// Runs the cold-start init chain that today sits in `main()` — Firebase, error
/// backend attach, remote config, app configs base, emulator connect,
/// `DreamicServices.initialize`, `appInitAppCubit` — now **behind the splash**
/// rather than before `runApp`. Returns a single `Future<void>` the
/// `DreamicAppInitHost`/`DreamicAppInitGate` gates the router on.
///
/// ## Ordering (fixed)
///
/// ```
/// appInitFirebase
///   → [hook] afterFirebaseInit          (Firebase/Firestore instance settings)
///   → appInitErrorHandling              (attach Crashlytics + FLUSH early buffer)
///   → appInitRemoteConfig
///   → appInitAppConfigsBase
///   → appInitConnectToFirebaseEmulatorIfNecessary
///   → [hook] registerBeforeServices     (DDS-006: AppRouter + UserRepoInt)
///   → servicesInitializer               (DreamicServices.initialize)
///   → [hook] registerAfterServices
///   → appInitAppCubit                   (network check inside the splash)
///   → [hook] captureEntryIntents        (cold deep-link capture)
/// ```
///
/// The whole sequence is wrapped in an **outer hang-timeout**
/// ([bootstrapTimeout], default 45s, nullable to disable) so a true hang
/// becomes an init-error (gate `errorWidget`) rather than an infinite splash.
///
/// ## Per-task failure policy (Issues 81/84)
///
/// - **Fatal** (uncaught throw aborts the Future → gate retry): `appInitFirebase`,
///   `appInitErrorHandling`, `appInitAppConfigsBase`, emulator connect,
///   `servicesInitializer` (`DreamicServices.initialize`), `appInitAppCubit`,
///   **and any uncaught throw from an app hook** — dreamic-core does not wrap
///   hooks.
/// - **Non-fatal** dreamic-core-owned: only `appInitRemoteConfig`, which already
///   internally swallows its fetch error and falls back to defaults, so it needs
///   no extra wrapper here. Non-critical *hook* work is the app's own
///   `try/catch` responsibility.
///
/// ## Idempotency (REQUIRED for retry to recover)
///
/// Every dreamic-core step is re-runnable: Firebase init is guarded,
/// remote-config / app-cubit registrations are `isRegistered`-guarded, the
/// emulator-connect and isolate-listener adds are apply-once. App hooks must be
/// idempotent too (the app's responsibility).
Future<void> dreamicBootstrap({
  required FirebaseOptions firebaseOptions,
  required DreamicServicesInitializer servicesInitializer,
  Map<String, dynamic>? additionalRemoteConfigDefaults,
  DreamicBootstrapHook? afterFirebaseInit,
  DreamicBootstrapHook? registerBeforeServices,
  DreamicBootstrapHook? registerAfterServices,
  DreamicBootstrapHook? captureEntryIntents,
  bool appCubitNetworkRequired = true,
  Uri? appCubitEntranceUri,
  Duration? bootstrapTimeout = const Duration(seconds: 45),
}) {
  final future = _runBootstrap(
    firebaseOptions: firebaseOptions,
    servicesInitializer: servicesInitializer,
    additionalRemoteConfigDefaults: additionalRemoteConfigDefaults,
    afterFirebaseInit: afterFirebaseInit,
    registerBeforeServices: registerBeforeServices,
    registerAfterServices: registerAfterServices,
    captureEntryIntents: captureEntryIntents,
    appCubitNetworkRequired: appCubitNetworkRequired,
    appCubitEntranceUri: appCubitEntranceUri,
  );

  // Compose the outer hang-timeout INSIDE the bootstrap Future (the gate has no
  // internal timeout). On expiry a `TimeoutException` is thrown → gate
  // `errorWidget`. Null disables (tests, special cases). No in-Future
  // retry-with-backoff — recovery is the user-facing idempotent re-mount
  // (Issue 81). Note: `Future.timeout` does NOT cancel the underlying work
  // (accepted stop-gap, Issue 53).
  if (bootstrapTimeout == null) {
    return future;
  }
  return future.timeout(bootstrapTimeout);
}

Future<void> _runBootstrap({
  required FirebaseOptions firebaseOptions,
  required DreamicServicesInitializer servicesInitializer,
  Map<String, dynamic>? additionalRemoteConfigDefaults,
  DreamicBootstrapHook? afterFirebaseInit,
  DreamicBootstrapHook? registerBeforeServices,
  DreamicBootstrapHook? registerAfterServices,
  DreamicBootstrapHook? captureEntryIntents,
  required bool appCubitNetworkRequired,
  Uri? appCubitEntranceUri,
}) async {
  // 1. Firebase (fatal; guarded against duplicate-app on retry).
  final fbApp = await appInitFirebase(firebaseOptions);

  // [hook] afterFirebaseInit — Firebase/Firestore instance settings that MUST
  // precede the first Firestore touch (fatal; the app guards its own
  // apply-once config).
  if (afterFirebaseInit != null) {
    await afterFirebaseInit();
  }

  // 2. Attach the error backend (Crashlytics / custom reporter) and FLUSH the
  //    early buffer to it (fatal). The afterFirebaseInit hook only applies
  //    instance settings, and the early handlers already cover that sub-window,
  //    so attaching here loses no coverage.
  await appInitErrorHandling();

  // 3. Remote config — the ONE dreamic-core-owned non-fatal task (it internally
  //    swallows its fetch error and falls back to defaults), so no extra
  //    wrapper is needed here.
  await appInitRemoteConfig(
    additionalDefaultConfigs: additionalRemoteConfigDefaults,
  );

  // 4. App configs base (fatal).
  await appInitAppConfigsBase();

  // 5. Emulator connect (fatal; apply-once-guarded for dev retries).
  await appInitConnectToFirebaseEmulatorIfNecessary(fbApp);

  // [hook] registerBeforeServices — DDS-006: the app registers AppRouter +
  //   UserRepoInt here so the cold-start notification tap (fired INSIDE
  //   DreamicServices.initialize) can resolve them (fatal; load-bearing).
  if (registerBeforeServices != null) {
    await registerBeforeServices();
  }

  // 6. DreamicServices.initialize via the app-supplied initializer (fatal).
  await servicesInitializer(fbApp);

  // [hook] registerAfterServices — post-services app DI / late auth-lifecycle
  //   callbacks (fatal; the app wraps its own non-critical work).
  if (registerAfterServices != null) {
    await registerAfterServices();
  }

  // 7. AppCubit — runs its network check inside the splash; on failure it sets
  //    AppStatus.networkError WITHOUT throwing, so the Future still completes
  //    and the gate mounts the router (shell networkError, not the gate error
  //    path). Early-returns the existing cubit on retry (fatal otherwise).
  await appInitAppCubit(
    networkRequired: appCubitNetworkRequired,
    entranceUri: appCubitEntranceUri,
  );

  // [hook] captureEntryIntents — the app captures the cold deep link
  //   (getInitialLink()) here, wrapped in its own try/catch (its output has no
  //   downstream bootstrap consumer, so a swallowed capture failure degrades to
  //   a normal launch — fatal only if the app lets it throw).
  if (captureEntryIntents != null) {
    await captureEntryIntents();
  }
}

/// Resets the dreamic-core bootstrap idempotency apply-once flags between test
/// cases (Issue 63/87). Module-level statics persist across cases in one VM, so
/// without this the "fresh-run applies / re-run skips" assertions become
/// order-dependent.
///
/// Resets ONLY the dreamic-core-owned flags:
/// - the Firebase emulator-connect flag (`_emulatorConnected`, Issue 32),
/// - the isolate error-listener flag (Issue 31).
///
/// **Not** MPP's `_firestoreSettingsApplied` — that lives in MPP's
/// `afterFirebaseInit` hook (MPP-owned) and is reset MPP-side (Issue 87). Also
/// clears the static cache backing `DreamicServices.initialize`'s
/// "already-initialized" early-return (Issue 75 / Issue 47) so the re-entrancy
/// test (clean success → later-step failure → retry early-returns the cache) is
/// order-independent.
///
/// Call from the idempotency tests' `setUp()` alongside `GetIt.reset()`.
@visibleForTesting
void resetDreamicBootstrapIdempotencyForTest() {
  resetEmulatorConnectedFlag();
  resetIsolateErrorListenerFlag();
  DreamicServices.resetDreamicServicesInitializedForTest();
}
