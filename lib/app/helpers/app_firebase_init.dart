import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:dreamic/app/app_config_base.dart';
import 'package:dreamic/app/helpers/app_errorhandling_init.dart';
import 'package:dreamic/utils/logger.dart';

/// Apply-once guard for the Firebase emulator-connect calls (Issue 32).
///
/// On the emulator (dev) path `_connectToFirebaseEmulator` calls
/// `useAuthEmulator` / `useFirestoreEmulator` / `useFunctionsEmulator` /
/// `useStorageEmulator` unconditionally — and these THROW
/// ("emulator already set" / Firestore-already-used) on a second run. Production
/// no-ops this step (early-returns when `!doUseBackendEmulator`), so a
/// production retry is unaffected; but a dev gate-retry would crash. Module-
/// level so it survives across retries; reset for tests via
/// [resetDreamicBootstrapIdempotencyForTest].
bool _emulatorConnected = false;

/// Initializes the default [FirebaseApp] (idempotent across gate-retry re-runs).
///
/// ## `settleTimeout` — the "hung init but app registered" recovery
///
/// On web, `Firebase.initializeApp()` can REGISTER the app (so it appears in
/// `Firebase.apps`) while its returned Future **never settles**. CONFIRMED root
/// cause (biblequiz, Sentry, iOS WebKit): `initializeApp` registers the JS app
/// and then awaits each plugin's `ensurePluginInitialized`; `firebase_auth_web`'s
/// ends with `await onWaitInitState()`, which blocks on the first
/// `onAuthStateChanged`. On iOS WebKit the persisted-session IndexedDB read of
/// `firebaseLocalStorageDb` never fires its callback, so `onWaitInitState` — and
/// thus `initializeApp` — hangs FOREVER (a 90s watcher never saw it settle or
/// error). Desktop Chrome/Blink is unaffected; a brand-new device (no persisted
/// session) resolves the initial state immediately. A manual retry "fixes it
/// instantly" because it hits the `Firebase.apps.isNotEmpty` guard and
/// short-circuits to `Firebase.app()`, skipping the hung `initializeApp`.
///
/// When [settleTimeout] is supplied, the FIRST attempt does the same thing the
/// retry would, via a **two-tier** bound (see [_awaitFirebaseInit]):
///
///   - [recoverIfRegisteredAfter] (short grace, e.g. 4s): if the init hasn't
///     settled by here but the app IS registered, recover immediately — this
///     catches the permanent hang fast (the app registers near-instantly; a
///     plugin init hangs);
///   - [settleTimeout] (outer bound, e.g. 30s): if the app is NOT registered at
///     the grace (a slow-but-healthy SDK load still loading), keep waiting the
///     remainder rather than false-tripping a slow cold start into a retry.
///
/// A registered-app recovery is **reported as an error** (not silently absorbed)
/// via `reportBootstrapDiagnostic`, so it reaches the backend whether the
/// reporter attached before Firebase (Sentry early-attach → reports now) or
/// after (Crashlytics → deferred + flushed on attach) — see `dreamicBootstrap`'s
/// `attachErrorReportingFirst`.
///
/// If the init genuinely hangs with NO app registered (within [settleTimeout]),
/// a descriptive [TimeoutException] is thrown so the caller's timeout/retry/error
/// path handles it. [settleTimeout] `null` (the default) keeps the unbounded
/// behavior (await to completion) for callers that don't want the bound (and for
/// direct test callers); [recoverIfRegisteredAfter] is ignored then.
Future<FirebaseApp> appInitFirebase(
  FirebaseOptions options, {
  Duration? settleTimeout,
  Duration? recoverIfRegisteredAfter,
}) async {
  // Guard against a gate-retry re-run: `Firebase.initializeApp` throws
  // `[core/duplicate-app]` on a second unconditional call. If the default app
  // already exists, reuse it directly; otherwise initialize (Issue 17 /
  // idempotency). The `duplicate-app` catch is a belt-and-suspenders fallback
  // for the case where the platform layer has the default app registered while
  // the Dart-side `Firebase.apps` cache is momentarily empty.
  FirebaseApp fbApp;
  if (Firebase.apps.isNotEmpty) {
    fbApp = Firebase.app();
  } else {
    try {
      logBreadcrumb(
        'appInitFirebase: calling Firebase.initializeApp '
        '(settleTimeout=${settleTimeout?.inSeconds ?? "none"}s, '
        'recoverIfRegisteredAfter=${recoverIfRegisteredAfter?.inSeconds ?? "none"}s)',
        category: 'bootstrap',
      );
      final initFuture = Firebase.initializeApp(
        // options: DefaultFirebaseOptions.currentPlatform,
        options: options,
      );
      if (settleTimeout == null) {
        fbApp = await initFuture;
      } else {
        fbApp = await _awaitFirebaseInit(initFuture, settleTimeout, recoverIfRegisteredAfter);
      }
    } on FirebaseException catch (e) {
      if (e.code.contains('duplicate-app')) {
        fbApp = Firebase.app();
      } else {
        rethrow;
      }
    }
  }

  // Mark Firebase as initialized and store the app reference for the rest of the package
  AppConfigBase.isFirebaseInitialized = true;
  AppConfigBase.firebaseApp = fbApp;

  return fbApp;
}

/// Awaits [initFuture] with the two-tier registered-app recovery.
///
/// **Tier 1 — recover-if-registered grace** ([recoverIfRegisteredAfter]): if the
/// init hasn't settled by this short grace but the app IS already registered,
/// recover immediately via `Firebase.app()`. This catches the confirmed
/// permanent-hang fast — the app registers near-instantly and a plugin init
/// (auth's `onWaitInitState`, the iOS WebKit `firebaseLocalStorageDb` read)
/// hangs forever.
///
/// **Tier 2 — settle bound** ([settleTimeout]): if the app is NOT yet registered
/// at the grace (a slow-but-healthy SDK load still in flight), we keep waiting
/// the remainder rather than false-tripping a slow cold start into a retry. On
/// the outer bound we recover if the app finally registered, else throw a
/// diagnosable [TimeoutException] for the caller's retry/error path.
///
/// The grace is skipped when null or >= [settleTimeout] (degrading to a single
/// settle bound).
///
/// [isRegistered] / [registeredApp] are seams over the Firebase singleton
/// (`Firebase.apps.isNotEmpty` / `Firebase.app()`) so the recovery/throw branches
/// — which only engage on an actual hang — are unit-testable without reproducing
/// a hung native `initializeApp`. Both default to the real statics in production.
Future<FirebaseApp> _awaitFirebaseInit(
  Future<FirebaseApp> initFuture,
  Duration settleTimeout,
  Duration? recoverIfRegisteredAfter, {
  bool Function()? isRegistered,
  FirebaseApp Function()? registeredApp,
}) async {
  final appIsRegistered = isRegistered ?? () => Firebase.apps.isNotEmpty;
  final getRegisteredApp = registeredApp ?? () => Firebase.app();
  final grace = recoverIfRegisteredAfter;
  final hasGrace = grace != null && grace < settleTimeout;

  if (hasGrace) {
    try {
      final app = await initFuture.timeout(grace);
      logBreadcrumb('appInitFirebase: initializeApp settled within ${grace.inSeconds}s',
          category: 'bootstrap');
      return app;
    } on TimeoutException {
      if (appIsRegistered()) {
        _reportFirebaseInitRecovered(grace);
        return getRegisteredApp();
      }
      // App not registered yet — the core SDK is likely still loading (a slow
      // but healthy cold start). Fall through and wait the remaining budget
      // rather than false-tripping into a retry.
      logBreadcrumb(
          'appInitFirebase: not settled + not registered at ${grace.inSeconds}s — '
          'waiting up to ${settleTimeout.inSeconds}s (slow SDK load?)',
          category: 'bootstrap');
    }
  }

  final remaining = hasGrace ? settleTimeout - grace : settleTimeout;
  try {
    return await initFuture.timeout(remaining);
  } on TimeoutException {
    if (appIsRegistered()) {
      _reportFirebaseInitRecovered(settleTimeout);
      return getRegisteredApp();
    }
    // Genuinely hung with nothing registered — surface a diagnosable failure to
    // the caller's timeout/retry/error path.
    throw TimeoutException(
      'appInitFirebase: Firebase.initializeApp did not settle within '
      '${settleTimeout.inSeconds}s and no app was registered',
      settleTimeout,
    );
  }
}

/// Test seam over [_awaitFirebaseInit] — exercises the two-tier
/// recovery/throw branches with injected registration probes, without a real
/// (hung) `Firebase.initializeApp`. Not for production use.
@visibleForTesting
Future<FirebaseApp> awaitFirebaseInitForTest(
  Future<FirebaseApp> initFuture, {
  required Duration settleTimeout,
  Duration? recoverIfRegisteredAfter,
  required bool Function() isRegistered,
  required FirebaseApp Function() registeredApp,
}) =>
    _awaitFirebaseInit(
      initFuture,
      settleTimeout,
      recoverIfRegisteredAfter,
      isRegistered: isRegistered,
      registeredApp: registeredApp,
    );

/// Reports a registered-app recovery: the init didn't settle within [waited] but
/// the app is registered, so we proceed with it. Routed through
/// [reportBootstrapDiagnostic] so it reaches the backend whether the reporter
/// attached before Firebase (Sentry early-attach → reports now) or after
/// (Crashlytics → deferred + flushed on attach). A distinctively-messaged
/// exception so the backend issue is self-explanatory and alertable.
void _reportFirebaseInitRecovered(Duration waited) {
  logBreadcrumb(
    'appInitFirebase: init did not settle in ${waited.inSeconds}s, app IS '
    'registered → recovering via Firebase.app()',
    category: 'bootstrap',
  );
  reportBootstrapDiagnostic(
    TimeoutException(
      'appInitFirebase: Firebase.initializeApp did not settle within '
      '${waited.inSeconds}s but the app IS registered — recovered with the '
      'registered app. CONFIRMED (Sentry, iOS WebKit): a PERMANENT hang in '
      "auth's onWaitInitState — the persisted-session IndexedDB read of "
      'firebaseLocalStorageDb whose callback never fires on iOS WebKit. A manual '
      'retry / this fallback both recover by skipping initializeApp.',
      waited,
    ),
    'Firebase init hang recovered via registered app',
    StackTrace.current,
  );
}

Future<void> appInitConnectToFirebaseEmulatorIfNecessary(FirebaseApp fbApp) async {
  if (AppConfigBase.doUseBackendEmulator) {
    // Apply-once: the emulator-connect calls are not idempotent and throw on a
    // second run, so a dev gate-retry would crash without this guard (Issue 32).
    if (_emulatorConnected) {
      logd('Firebase emulator already connected — skipping re-connect (idempotent retry)');
      return;
    }
    // Initialize the emulator address with automatic discovery
    await AppConfigBase.initializeEmulatorAddress();
    await _connectToFirebaseEmulator(fbApp);
    _emulatorConnected = true;
    return;
  }
  return;
}

/// Resets the emulator-connect apply-once flag (Issue 32/63). Internal
/// test-support seam invoked only by the combined
/// `resetDreamicBootstrapIdempotencyForTest()` (which IS the documented
/// `@visibleForTesting` entry point) — not `@visibleForTesting` itself so the
/// combined reset can call it without a cross-file visibility-lint warning.
void resetEmulatorConnectedFlag() {
  _emulatorConnected = false;
}

/// Connnect to the firebase emulator for Firestore and Authentication
Future<void> _connectToFirebaseEmulator(FirebaseApp fbApp) async {
  String emulatorAddress = AppConfigBase.backendEmulatorRemoteAddress;

  // Figure out if we're running locally in a simulator
  // if (!kIsWeb) {
  //   if (Platform.isIOS) {
  //     if (!(await DeviceInfoPlugin().iosInfo).isPhysicalDevice) {
  //       emulatorAddress = '127.0.0.1';
  //     }
  //   } else if (Platform.isAndroid) {
  //     if (!((await DeviceInfoPlugin().androidInfo).isPhysicalDevice ?? true)) {
  //       emulatorAddress = '10.0.2.2';
  //     }
  //   }
  // }

  await FirebaseAuth.instanceFor(app: fbApp)
      .useAuthEmulator(emulatorAddress, AppConfigBase.backendEmulatorAuthPort);
  logd(
      'Set up Firebase Auth emulator with server $emulatorAddress:${AppConfigBase.backendEmulatorAuthPort}');

  FirebaseFunctions.instanceFor(
    app: fbApp,
    region: AppConfigBase.backendRegion,
  ).useFunctionsEmulator(
    emulatorAddress,
    AppConfigBase.backendEmulatorFunctionsPort,
  );
  logd(
      'Set up Firebase Functions emulator with server $emulatorAddress:${AppConfigBase.backendEmulatorFunctionsPort}');

  // Configure the emulator on the SAME instance the app uses everywhere
  // (AppConfigBase.firestore), so a named Enterprise database id resolves
  // consistently for both the emulator and live data access.
  AppConfigBase.firestore.useFirestoreEmulator(
    emulatorAddress,
    AppConfigBase.backendEmulatorFirestorePort,
  );
  logd(
      'Set up Firebase Firestore emulator with server $emulatorAddress:${AppConfigBase.backendEmulatorFirestorePort}');
  //TODO: this is off for debugging
  // FirebaseFirestore.instance.settings = const Settings(
  //   persistenceEnabled: false,
  // );

  await FirebaseStorage.instanceFor(app: fbApp).useStorageEmulator(
    emulatorAddress,
    AppConfigBase.backendEmulatorStoragePort,
  );
  logd(
      'Set up Firebase Storage emulator with server $emulatorAddress:${AppConfigBase.backendEmulatorStoragePort}');

  //TODO: debugging sign out
  // await FirebaseAuth.instance.signOut();

  logd('FINISHED SETTING UP EMULATORS with server $emulatorAddress');
}
