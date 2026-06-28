import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../data/repos/dreamic_services.dart';
import '../helpers/app_check_init.dart';
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

/// Names the bootstrap step currently in flight, so the outer hang-timeout can
/// report WHICH step hung.
///
/// A hang has no stack trace of its own — when [bootstrapTimeout] fires, the
/// `TimeoutException` thrown by `Future.timeout` carries no clue as to where the
/// sequence stalled. Each step in [_runBootstrap] stamps this before it runs, so
/// the timeout's `onTimeout` can name the stalled step in the exception message
/// (which then reaches the attached error reporter — see
/// `attachErrorReportingFirst`). Module-level (the sequence is single-flight per
/// generation; a concurrent auto-retry only ever overwrites a diagnostic
/// string, never load-bearing state).
String _currentBootstrapStep = 'not-started';

/// Resolves whether to attach the error reporter BEFORE Firebase init.
///
/// [explicitOverride] wins when an app passes one to [dreamicBootstrap].
/// Otherwise (`null`) dreamic derives a great default from the configured
/// [errorReportingConfig]: a self-contained reporter (e.g. Sentry) needs no
/// Firebase, so it SHOULD attach as early as possible (step 0) to catch the most
/// startup errors; a Firebase-dependent reporter (e.g. Crashlytics, declared via
/// `reporterRequiresFirebase: true`) must attach at the post-Firebase step.
/// Hence: attach early iff there is a reporter that does NOT require Firebase.
///
/// Reads [errorReportingConfig], so `configureErrorReporting(...)` must run
/// before [dreamicBootstrap] (the canonical pre-`runApp` `main()` line). When
/// nothing is configured there is no reporter, so the derivation yields `false`
/// (no early attach).
@visibleForTesting
bool resolveAttachErrorReportingFirst(bool? explicitOverride) {
  if (explicitOverride != null) return explicitOverride;
  final config = errorReportingConfig;
  return config.customReporter != null && !config.reporterRequiresFirebase;
}

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
///   → appInitAppCheck                   (dreamic-owned, opt-in via [appCheck])
///   → appInitErrorHandling              (attach reporter + FLUSH early buffer)
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
/// On expiry the thrown `TimeoutException` names the step that was in flight
/// (the `→ [stepName]` stamped above), so a hang is diagnosable in the backend.
///
/// ## Early error-reporting attach ([attachErrorReportingFirst])
///
/// `appInitErrorHandling` (the reporter attach + early-buffer flush) can run at
/// one of two points:
///
/// - **step 2**, AFTER Firebase init + the `afterFirebaseInit` hook — required
///   for a Firebase-dependent reporter (e.g. Crashlytics), which cannot attach
///   until Firebase exists; but a hang or throw in step 1 / that hook then
///   reports only into the early buffer, which never transmits if the bootstrap
///   then hangs (the gate's `loge` fires before any backend is attached);
/// - **step 0**, BEFORE Firebase — possible for a self-contained reporter
///   (Sentry and the like) that needs no Firebase, catching the most startup
///   errors (a step-1 / `afterFirebaseInit` failure, including the outer
///   hang-timeout firing during them, reaches the backend). The step-2 attach
///   is then skipped (single init).
///
/// **Great default (no app wiring):** when [attachErrorReportingFirst] is left
/// `null` (the default), dreamic derives the right choice from the configured
/// [errorReportingConfig] — attach at step 0 **iff** there is a reporter that
/// does NOT require Firebase (`reporterRequiresFirebase: false`, e.g. Sentry),
/// else step 2. So a self-contained (Sentry-style) consumer gets maximal startup
/// coverage for free; a Firebase-dependent reporter (e.g. Crashlytics, declared
/// with `reporterRequiresFirebase: true`) keeps the post-Firebase attach. Pass an
/// explicit `true`/`false` only to override this derivation. For the derivation
/// to see it, `configureErrorReporting(...)` must run before `dreamicBootstrap` —
/// the canonical pre-`runApp` `main()` line.
///
/// ## Per-step Firebase-init recovery ([firebaseInitTimeout] +
/// [firebaseRecoverIfRegisteredAfter])
///
/// Bounds step 1 (`appInitFirebase`) — the CONFIRMED hang site on a returning
/// **iOS WebKit** device: `Firebase.initializeApp` registers the app, then auth's
/// `onWaitInitState` permanently hangs on the persisted-session IndexedDB read of
/// `firebaseLocalStorageDb`. These thread into `appInitFirebase` as a **two-tier**
/// recovery (no per-app tuning needed):
///
/// - [firebaseRecoverIfRegisteredAfter] (short grace, default 4s): if init hasn't
///   settled but the app IS registered, recover via `Firebase.app()` on the FIRST
///   attempt — fast, no error screen / retry cycle. Reports the occurrence (which
///   reaches the backend whether the reporter attached before or after Firebase).
/// - [firebaseInitTimeout] (outer settle bound, default 30s): if the app is NOT
///   registered at the grace (a slow-but-healthy SDK load), keep waiting the
///   remainder rather than false-tripping a slow cold start into a retry; on the
///   bound, recover if finally registered, else throw a diagnosable
///   `TimeoutException` into the host's auto-retry / error path.
///
/// These defaults make the recovery universal — every consumer (incl. Crashlytics
/// apps) benefits with zero per-app config. The outer [bootstrapTimeout] remains a
/// coarse whole-sequence backstop. Pass `firebaseInitTimeout: null` to disable the
/// bound entirely (the grace is then ignored).
///
/// ## App Check ([appCheck])
///
/// dreamic owns App Check activation as a first-class capability (like Remote
/// Config): pass an [AppCheckConfig] (with the web reCAPTCHA site key + optional
/// provider overrides) and dreamic selects providers (debug fallbacks +
/// keyless-web guard), activates **bounded + non-critical**, and enables
/// auto-refresh. Opt-in by presence — a `null` [appCheck] (the default) skips it.
/// Activation NEVER blocks boot: App Check is consumed lazily (token fetched on
/// the first attested call; enforcement is server-side), so a timeout/failure is
/// reported (defer/flush, so Crashlytics consumers see it) and boot continues.
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
  bool? attachErrorReportingFirst,
  Duration? firebaseInitTimeout = const Duration(seconds: 30),
  Duration? firebaseRecoverIfRegisteredAfter = const Duration(seconds: 4),
  AppCheckConfig? appCheck,
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
    attachErrorReportingFirst:
        resolveAttachErrorReportingFirst(attachErrorReportingFirst),
    firebaseInitTimeout: firebaseInitTimeout,
    firebaseRecoverIfRegisteredAfter: firebaseRecoverIfRegisteredAfter,
    appCheck: appCheck,
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
  // The `onTimeout` names the step that was in flight so the resulting error is
  // diagnosable. A pure `Future.timeout(d)` throws a bare `TimeoutException`
  // ("Future not completed") with no clue where the sequence stalled — useless
  // for a hang that, by definition, leaves no stack trace. With
  // `attachErrorReportingFirst` the reporter is already attached when this
  // throws, so the named message reaches the backend (Sentry/Crashlytics) via
  // the gate's `onError → loge`.
  return future.timeout(
    bootstrapTimeout,
    onTimeout: () => throw TimeoutException(
      'dreamicBootstrap hung for ${bootstrapTimeout.inSeconds}s '
      'during step "$_currentBootstrapStep"',
      bootstrapTimeout,
    ),
  );
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
  required bool attachErrorReportingFirst,
  required Duration? firebaseInitTimeout,
  required Duration? firebaseRecoverIfRegisteredAfter,
  required AppCheckConfig? appCheck,
}) async {
  // 0. (opt-in) Attach the error backend + FLUSH the early buffer BEFORE
  //    Firebase. The default ordering attaches the reporter at step 2 (after
  //    Firebase init + the afterFirebaseInit hook), so a hang/throw in step 1
  //    or that hook is reported only via the early buffer — and never transmits
  //    if the bootstrap then hangs (the gate's `loge` has no backend attached
  //    yet). Apps whose reporter does NOT need Firebase (a custom reporter like
  //    Sentry; NOT Firebase Crashlytics, which requires Firebase first) can opt
  //    into attaching here so step-1/afterFirebaseInit failures — including the
  //    outer hang-timeout firing during them — reach the backend. When set, the
  //    step-2 attach below is SKIPPED to avoid a double-init of the reporter.
  if (attachErrorReportingFirst) {
    _currentBootstrapStep = 'appInitErrorHandling (early)';
    await appInitErrorHandling();
  }

  // 1. Firebase (fatal; guarded against duplicate-app on retry).
  //
  //    Two-tier bound (CONFIRMED iOS-WebKit hang site: initializeApp registers
  //    the app, then auth's onWaitInitState permanently hangs on the
  //    firebaseLocalStorageDb IndexedDB read). `appInitFirebase` recovers on the
  //    FIRST attempt via the registered app — fast after the short grace, or
  //    after the settle bound if the SDK was just loading slowly — reporting the
  //    occurrence (delivered before- or after-attach). Only a genuine
  //    no-app-registered hang throws a diagnosable TimeoutException into the
  //    host's auto-retry / error path. Outer [bootstrapTimeout] is the coarse
  //    whole-sequence backstop.
  _currentBootstrapStep = 'appInitFirebase';
  final fbApp = await appInitFirebase(
    firebaseOptions,
    settleTimeout: firebaseInitTimeout,
    recoverIfRegisteredAfter: firebaseRecoverIfRegisteredAfter,
  );

  // [hook] afterFirebaseInit — Firebase/Firestore instance settings that MUST
  // precede the first Firestore touch (fatal; the app guards its own
  // apply-once config).
  if (afterFirebaseInit != null) {
    _currentBootstrapStep = 'afterFirebaseInit hook';
    await afterFirebaseInit();
  }

  // 1b. App Check (dreamic-owned, opt-in via a non-null [appCheck] config).
  //     Bounded + NON-CRITICAL: a hung/failed activation is reported (via the
  //     defer/flush path, so Crashlytics consumers see it too) and boot
  //     continues — App Check is consumed lazily on the first attested callable,
  //     so it must never block startup. Activated here (early, before RC /
  //     services) so it is in place before any attested backend call. No-op when
  //     [appCheck] is null.
  _currentBootstrapStep = 'appInitAppCheck';
  await appInitAppCheck(appCheck);

  // 2. Attach the error backend (Crashlytics / custom reporter) and FLUSH the
  //    early buffer to it (fatal). The afterFirebaseInit hook only applies
  //    instance settings, and the early handlers already cover that sub-window,
  //    so attaching here loses no coverage. Skipped when already attached at
  //    step 0 (attachErrorReportingFirst).
  if (!attachErrorReportingFirst) {
    _currentBootstrapStep = 'appInitErrorHandling';
    await appInitErrorHandling();
  }

  // 3. Remote config — the ONE dreamic-core-owned non-fatal task (it internally
  //    swallows its fetch error and falls back to defaults), so no extra
  //    wrapper is needed here.
  _currentBootstrapStep = 'appInitRemoteConfig';
  await appInitRemoteConfig(
    additionalDefaultConfigs: additionalRemoteConfigDefaults,
  );

  // 4. App configs base (fatal).
  _currentBootstrapStep = 'appInitAppConfigsBase';
  await appInitAppConfigsBase();

  // 5. Emulator connect (fatal; apply-once-guarded for dev retries).
  _currentBootstrapStep = 'appInitConnectToFirebaseEmulatorIfNecessary';
  await appInitConnectToFirebaseEmulatorIfNecessary(fbApp);

  // [hook] registerBeforeServices — DDS-006: the app registers AppRouter +
  //   UserRepoInt here so the cold-start notification tap (fired INSIDE
  //   DreamicServices.initialize) can resolve them (fatal; load-bearing).
  if (registerBeforeServices != null) {
    _currentBootstrapStep = 'registerBeforeServices hook';
    await registerBeforeServices();
  }

  // 6. DreamicServices.initialize via the app-supplied initializer (fatal).
  _currentBootstrapStep = 'servicesInitializer (DreamicServices.initialize)';
  await servicesInitializer(fbApp);

  // [hook] registerAfterServices — post-services app DI / late auth-lifecycle
  //   callbacks (fatal; the app wraps its own non-critical work).
  if (registerAfterServices != null) {
    _currentBootstrapStep = 'registerAfterServices hook';
    await registerAfterServices();
  }

  // 7. AppCubit — runs its network check inside the splash; on failure it sets
  //    AppStatus.networkError WITHOUT throwing, so the Future still completes
  //    and the gate mounts the router (shell networkError, not the gate error
  //    path). Early-returns the existing cubit on retry (fatal otherwise).
  _currentBootstrapStep = 'appInitAppCubit';
  await appInitAppCubit(
    networkRequired: appCubitNetworkRequired,
    entranceUri: appCubitEntranceUri,
  );

  // [hook] captureEntryIntents — the app captures the cold deep link
  //   (getInitialLink()) here, wrapped in its own try/catch (its output has no
  //   downstream bootstrap consumer, so a swallowed capture failure degrades to
  //   a normal launch — fatal only if the app lets it throw).
  if (captureEntryIntents != null) {
    _currentBootstrapStep = 'captureEntryIntents hook';
    await captureEntryIntents();
  }

  _currentBootstrapStep = 'completed';
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

/// Runs **non-critical** [work] inside a bootstrap hook with a hard [timeout],
/// swallowing any failure (a throw OR the timeout) so it can NEVER abort or
/// stall the bootstrap.
///
/// dreamic-core treats an app hook's throw as **fatal** (it does not wrap
/// hooks), and a hook that hangs stalls the whole bootstrap until the outer
/// [bootstrapTimeout]. Work that is NOT required for the app to start — e.g.
/// App Check activation (attested calls fetch a token lazily later), an
/// analytics warm-up, a timezone service — should be wrapped here so a
/// slow/locked/failed dependency degrades to "continue boot" instead of an
/// init-error or a hang. This is the reusable form of the "app wraps its own
/// non-critical hook work" contract: the *mechanism* lives in dreamic; the
/// *policy* (which work is non-critical) stays with the app at the call site.
///
/// On timeout or failure the error is reported via [reportBootstrapDiagnostic] —
/// so it reaches the backend whether the reporter attached before Firebase
/// (Sentry early-attach) or after (Crashlytics; deferred + flushed on attach) —
/// tagged with [label] for context, then this returns normally. The underlying
/// [work] Future is **not** cancelled (Dart cannot), so it keeps running in the
/// background — the desired behavior for fire-and-settle setup whose in-flight
/// call completes shortly after.
///
/// NOTE: dreamic now owns App Check activation directly (see [AppCheckConfig] /
/// the `appCheck` bootstrap param), so apps no longer need to wrap it here; this
/// remains for any *other* non-critical post-init work (analytics warm-up, a
/// timezone service, etc.).
Future<void> runBoundedNonCritical(
  Future<void> Function() work, {
  required Duration timeout,
  required String label,
}) async {
  try {
    await work().timeout(timeout);
  } catch (e, st) {
    reportBootstrapDiagnostic(
      e,
      'Non-critical bootstrap work "$label" timed out or failed — continuing boot',
      st,
    );
  }
}
