import 'package:dreamic/app/app_cubit.dart';
import 'package:get_it/get_it.dart';

/// Initialize the AppCubit and register it with GetIt.
///
/// This should be called in main.dart after other Firebase/config initialization
/// but before running the app.
///
/// Example:
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await appInitFirebase(DefaultFirebaseOptions.currentPlatform);
///   await appInitErrorHandling();
///   await appInitRemoteConfig();
///   await appInitAppConfigsBase();
///   await appInitConnectToFirebaseEmulatorIfNecessary(fbApp);
///
///   // Initialize AppCubit - handles network checking and app lifecycle
///   await appInitAppCubit(networkRequired: true);
///
///   runApp(MyApp());
/// }
/// ```
Future<AppCubit> appInitAppCubit({
  bool networkRequired = true,
  Uri? entranceUri,
}) async {
  final appCubit = AppCubit(
    networkRequired: networkRequired,
    entranceUri: entranceUri,
  );

  GetIt.I.registerSingleton<AppCubit>(appCubit);

  // Initialize app data once here during startup.
  // This must NOT be done in AppRootWidget since widget builds can happen multiple times.
  await appCubit.getInitialData();

  return appCubit;
}
