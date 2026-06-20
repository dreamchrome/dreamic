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
  // Idempotency (gate-retry re-run): if an AppCubit is already registered,
  // early-return it. Do NOT construct a throwaway cubit or redundantly re-run
  // getInitialData()'s network check — getInitialData() is `_hasInitialized`-
  // guarded internally, so a second call would be a wasted network round-trip
  // and a bare re-`registerSingleton` would throw "already registered"
  // (Issue 17/39 idempotency).
  if (GetIt.I.isRegistered<AppCubit>()) {
    return GetIt.I.get<AppCubit>();
  }

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
