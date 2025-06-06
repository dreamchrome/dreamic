import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:dreamic/app/app_config_base.dart';
import 'package:dreamic/utils/logger.dart';

Future<FirebaseApp> appInitFirebase(
  FirebaseOptions options,
) async {
  // Initialize Firebase
  var fbApp = await Firebase.initializeApp(
    // options: DefaultFirebaseOptions.currentPlatform,
    options: options,
  );

  // Set up Firebase Emulator
  // if (AppConfigBase.doUseBackendEmulator) {
  //   await _connectToFirebaseEmulator(fbApp);
  // }

  return fbApp;
}

Future<void> appInitConnectToFirebaseEmulatorIfNecessary(FirebaseApp fbApp) async {
  if (AppConfigBase.doUseBackendEmulator) {
    return await _connectToFirebaseEmulator(fbApp);
  }
  return;
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

  await FirebaseAuth.instanceFor(
    app: fbApp,
  ).useAuthEmulator(emulatorAddress, AppConfigBase.backendEmulatorAuthPort);
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

  FirebaseFirestore.instanceFor(
    app: fbApp,
  ).useFirestoreEmulator(
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
