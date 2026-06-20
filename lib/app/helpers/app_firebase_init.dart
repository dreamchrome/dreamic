import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:dreamic/app/app_config_base.dart';
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

Future<FirebaseApp> appInitFirebase(
  FirebaseOptions options,
) async {
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
      fbApp = await Firebase.initializeApp(
        // options: DefaultFirebaseOptions.currentPlatform,
        options: options,
      );
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
