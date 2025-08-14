// ignore_for_file: constant_identifier_names

import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:dreamic/data/repos/remote_config_repo_int.dart';
import 'package:dreamic/utils/get_it_utils.dart';
import 'package:dreamic/utils/logger.dart';
import 'package:dreamic/utils/device_utils.dart';
import 'package:dreamic/utils/network_utils.dart';

// import 'platform_helpers/platform_helpers_stub.dart' as platform_helper;

class AppConfigBase {
  ///
  /// Do this in main
  ///
  static init() async {
    // Initialize iOS simulator detection for proper FCM configuration
    await _initializeSimulatorDetection();

    //TOOD: make this work on the web
    // _isSimulatorDevice ??= (String.fromEnvironment('IS_SIMULATOR_DEVICE_OVERRIDE',
    //         defaultValue: (await _isRunningOnIOSSimulator()) ? 'true' : 'false')) ==
    //     'true';
  }

  //
  // Remote Config
  //

  static Map<String, dynamic> defaultRemoteConfig = {
    'minimumAppVersionRequiredApple': '0.0.0',
    'minimumAppVersionRequiredGoogle': '0.0.0',
    'minimumAppVersionRequiredWeb': '0.0.0',
    'minimumAppVersionRecommendedApple': '0.0.0',
    'minimumAppVersionRecommendedGoogle': '0.0.0',
    'minimumAppVersionRecommendedWeb': '0.0.0',
    'logLevel': kDebugMode ? 'debug' : 'error',
    'retryAttemptsCountMax': kDebugMode ? 1 : 5,
    'timeoutBeforeShowingLoadingMill': 750,
    'timeoutNetworkProcessMill': 10000,
    'firebaseFunctionTimeoutSecs': kDebugMode ? 540 : 70,
    'firebaseFunctionTimeoutSecsLong': kDebugMode ? 540 : 140,
    'connectionCheckerUrlOverride': '',
  };

  static set minimumAppVersionRequiredAppleDefault(String value) =>
      defaultRemoteConfig['minimumAppVersionRequiredApple'] = value;
  static set minimumAppVersionRequiredGoogleDefault(String value) =>
      defaultRemoteConfig['minimumAppVersionRequiredGoogle'] = value;
  static set minimumAppVersionRequiredWebDefault(String value) =>
      defaultRemoteConfig['minimumAppVersionRequiredWeb'] = value;
  static set minimumAppVersionRecommendedAppleDefault(String value) =>
      defaultRemoteConfig['minimumAppVersionRecommendedApple'] = value;
  static set minimumAppVersionRecommendedGoogleDefault(String value) =>
      defaultRemoteConfig['minimumAppVersionRecommendedGoogle'] = value;
  static set minimumAppVersionRecommendedWebDefault(String value) =>
      defaultRemoteConfig['minimumAppVersionRecommendedWeb'] = value;
  static set logLevelDefault(String value) => defaultRemoteConfig['logLevel'] = value;
  static set retryAttemptsCountMaxDefault(int value) =>
      defaultRemoteConfig['retryAttemptsCountMax'] = value;
  static set timeoutBeforeShowingLoadingMillDefault(int value) =>
      defaultRemoteConfig['timeoutBeforeShowingLoadingMill'] = value;
  static set timeoutNetworkProcessMillDefault(int value) =>
      defaultRemoteConfig['timeoutNetworkProcessMill'] = value;
  static set firebaseFunctionTimeoutSecsDefault(int value) =>
      defaultRemoteConfig['firebaseFunctionTimeoutSecs'] = value;
  static set firebaseFunctionTimeoutSecsLongDefault(int value) =>
      defaultRemoteConfig['firebaseFunctionTimeoutSecsLong'] = value;
  static set connectionCheckerUrlOverrideDefault(String value) =>
      defaultRemoteConfig['connectionCheckerUrlOverride'] = value;

  static String get minimumAppVersionRequiredApple {
    const envValue = String.fromEnvironment('minimumAppVersionRequiredApple');
    if (envValue.isNotEmpty) {
      // logd('AppConfigBase.minimumAppVersionRequiredApple from environment: $envValue');
      return envValue;
    } else {
      final remoteValue = g<RemoteConfigRepoInt>().getString('minimumAppVersionRequiredApple');
      if (remoteValue.isNotEmpty) {
        // logd('AppConfigBase.minimumAppVersionRequiredApple from Remote Config: $remoteValue');
        return remoteValue;
      } else {
        final defaultValue = defaultRemoteConfig['minimumAppVersionRequiredApple'] as String;
        // logd('AppConfigBase.minimumAppVersionRequiredApple using default: $defaultValue');
        return defaultValue;
      }
    }
  }

  static String get minimumAppVersionRequiredGoogle {
    const envValue = String.fromEnvironment('minimumAppVersionRequiredGoogle');
    if (envValue.isNotEmpty) {
      return envValue;
    } else {
      final remoteValue = g<RemoteConfigRepoInt>().getString('minimumAppVersionRequiredGoogle');
      if (remoteValue.isNotEmpty) {
        return remoteValue;
      } else {
        return defaultRemoteConfig['minimumAppVersionRequiredGoogle'] as String;
      }
    }
  }

  static String get minimumAppVersionRequiredWeb {
    const envValue = String.fromEnvironment('minimumAppVersionRequiredWeb');
    if (envValue.isNotEmpty) {
      return envValue;
    } else {
      final remoteValue = g<RemoteConfigRepoInt>().getString('minimumAppVersionRequiredWeb');
      if (remoteValue.isNotEmpty) {
        return remoteValue;
      } else {
        return defaultRemoteConfig['minimumAppVersionRequiredWeb'] as String;
      }
    }
  }

  static String get minimumAppVersionRecommendedApple {
    const envValue = String.fromEnvironment('minimumAppVersionRecommendedApple');
    if (envValue.isNotEmpty) {
      // logd('AppConfigBase.minimumAppVersionRecommendedApple from environment: $envValue');
      return envValue;
    } else {
      final remoteValue = g<RemoteConfigRepoInt>().getString('minimumAppVersionRecommendedApple');
      if (remoteValue.isNotEmpty) {
        // logd('AppConfigBase.minimumAppVersionRecommendedApple from Remote Config: $remoteValue');
        return remoteValue;
      } else {
        final defaultValue = defaultRemoteConfig['minimumAppVersionRecommendedApple'] as String;
        // logd('AppConfigBase.minimumAppVersionRecommendedApple using default: $defaultValue');
        return defaultValue;
      }
    }
  }

  static String get minimumAppVersionRecommendedGoogle {
    const envValue = String.fromEnvironment('minimumAppVersionRecommendedGoogle');
    if (envValue.isNotEmpty) {
      return envValue;
    } else {
      final remoteValue = g<RemoteConfigRepoInt>().getString('minimumAppVersionRecommendedGoogle');
      if (remoteValue.isNotEmpty) {
        return remoteValue;
      } else {
        return defaultRemoteConfig['minimumAppVersionRecommendedGoogle'] as String;
      }
    }
  }

  static String get minimumAppVersionRecommendedWeb {
    const envValue = String.fromEnvironment('minimumAppVersionRecommendedWeb');
    if (envValue.isNotEmpty) {
      return envValue;
    } else {
      final remoteValue = g<RemoteConfigRepoInt>().getString('minimumAppVersionRecommendedWeb');
      if (remoteValue.isNotEmpty) {
        return remoteValue;
      } else {
        return defaultRemoteConfig['minimumAppVersionRecommendedWeb'] as String;
      }
    }
  }

  static LogLevel get logLevel {
    const envValue = String.fromEnvironment('logLevel');
    String value;
    if (envValue.isNotEmpty) {
      value = envValue;
    } else {
      final remoteValue = g<RemoteConfigRepoInt>().getString('logLevel');
      if (remoteValue.isNotEmpty) {
        value = remoteValue;
      } else {
        value = defaultRemoteConfig['logLevel'] as String;
      }
    }
    return LogLevel.values.firstWhere((e) => e.name == value, orElse: () => LogLevel.error);
  }

  static int get retryAttemptsCountMax {
    const envValue = int.fromEnvironment('retryAttemptsCountMax', defaultValue: -1);
    if (envValue != -1) {
      return envValue;
    } else {
      final remoteValue = g<RemoteConfigRepoInt>().getInt('retryAttemptsCountMax');
      if (remoteValue > 0) {
        return remoteValue;
      } else {
        return defaultRemoteConfig['retryAttemptsCountMax'] as int;
      }
    }
  }

  static int get timeoutBeforeShowingLoadingMill {
    const envValue = int.fromEnvironment('timeoutBeforeShowingLoadingMill', defaultValue: -1);
    if (envValue != -1) {
      return envValue;
    } else {
      final remoteValue = g<RemoteConfigRepoInt>().getInt('timeoutBeforeShowingLoadingMill');
      if (remoteValue > 0) {
        return remoteValue;
      } else {
        return defaultRemoteConfig['timeoutBeforeShowingLoadingMill'] as int;
      }
    }
  }

  static int get timeoutNetworkProcessMill {
    const envValue = int.fromEnvironment('timeoutNetworkProcessMill', defaultValue: -1);
    if (envValue != -1) {
      return envValue;
    } else {
      final remoteValue = g<RemoteConfigRepoInt>().getInt('timeoutNetworkProcessMill');
      if (remoteValue > 0) {
        return remoteValue;
      } else {
        return defaultRemoteConfig['timeoutNetworkProcessMill'] as int;
      }
    }
  }

  static int get firebaseFunctionTimeoutSecs {
    const envValue = int.fromEnvironment('firebaseFunctionTimeoutSecs', defaultValue: -1);
    if (envValue != -1) {
      return envValue;
    } else {
      final remoteValue = g<RemoteConfigRepoInt>().getInt('firebaseFunctionTimeoutSecs');
      if (remoteValue > 0) {
        return remoteValue;
      } else {
        return defaultRemoteConfig['firebaseFunctionTimeoutSecs'] as int;
      }
    }
  }

  static int get firebaseFunctionTimeoutSecsLong {
    const envValue = int.fromEnvironment('firebaseFunctionTimeoutSecsLong', defaultValue: -1);
    if (envValue != -1) {
      return envValue;
    } else {
      final remoteValue = g<RemoteConfigRepoInt>().getInt('firebaseFunctionTimeoutSecsLong');
      if (remoteValue > 0) {
        return remoteValue;
      } else {
        return defaultRemoteConfig['firebaseFunctionTimeoutSecsLong'] as int;
      }
    }
  }

  static String get connectionCheckerUrlOverride {
    const envValue = String.fromEnvironment('connectionCheckerUrlOverride');
    if (envValue.isNotEmpty) {
      return envValue;
    } else {
      final remoteValue = g<RemoteConfigRepoInt>().getString('connectionCheckerUrlOverride');
      // For this parameter, empty string might be intentional, so return it
      return remoteValue.isNotEmpty
          ? remoteValue
          : defaultRemoteConfig['connectionCheckerUrlOverride'] as String;
    }
  }

  //
  // Compile-time configs
  //

  // static int? _firebaseFunctionTimeoutSecs;
  // static int get firebaseFunctionTimeoutSecs {
  //   _firebaseFunctionTimeoutSecs ??= const int.fromEnvironment('FIREBASE_FUNCTION_TIMEOUT_SECS',
  //       defaultValue: kReleaseMode ? 70 : 540);
  //   return _firebaseFunctionTimeoutSecs!;
  // }

  // static int? _firebaseFunctionTimeoutSecsLong;
  // static int get firebaseFunctionTimeoutSecsLong {
  //   _firebaseFunctionTimeoutSecsLong ??= const int.fromEnvironment(
  //       'FIREBASE_FUNCTION_TIMEOUT_SECS_LONG',
  //       defaultValue: kReleaseMode ? 340 : 540);
  //   return _firebaseFunctionTimeoutSecsLong!;
  // }

  static bool? _lockOrientationToPortraitDefault;
  static set lockOrientationToPortraitDefault(bool value) =>
      _lockOrientationToPortraitDefault = value;
  static bool? _lockOrientationToPortrait;
  static bool get lockOrientationToPortrait {
    _lockOrientationToPortrait ??=
        const String.fromEnvironment('LOCK_ORIENTATION_PORTRAIT', defaultValue: '').isNotEmpty
            ? const String.fromEnvironment('LOCK_ORIENTATION_PORTRAIT', defaultValue: 'false') ==
                'true'
            : (_lockOrientationToPortraitDefault ?? false);
    return _lockOrientationToPortrait!;
  }

  static bool? _lockOrientationToLandscapeDefault;
  static set lockOrientationToLandscapeDefault(bool value) =>
      _lockOrientationToLandscapeDefault = value;
  static bool? _lockOrientationToLandscape;
  static bool get lockOrientationToLandscape {
    _lockOrientationToLandscape ??=
        const String.fromEnvironment('LOCK_ORIENTATION_LANDSCAPE', defaultValue: '').isNotEmpty
            ? const String.fromEnvironment('LOCK_ORIENTATION_LANDSCAPE', defaultValue: 'false') ==
                'true'
            : (_lockOrientationToLandscapeDefault ?? false);
    return _lockOrientationToLandscape!;
  }

  static bool? _wakelockEnabledAllTheTime;
  static bool get wakelockEnabledAllTheTime {
    _wakelockEnabledAllTheTime ??=
        const String.fromEnvironment('WAKELOCK_ENABLED_ALL_THE_TIME', defaultValue: 'false') ==
            'true';
    return _wakelockEnabledAllTheTime!;
  }

  static bool? _doPrefillInputs;
  static bool get doPrefillInputs {
    _doPrefillInputs ??=
        const String.fromEnvironment('DO_PREFILL_INPUTS', defaultValue: 'false') == 'true';
    return _doPrefillInputs!;
  }

  static String? _backendEmulatorRemoteAddress;
  static bool _emulatorAddressInitialized = false;

  static String get backendEmulatorRemoteAddress {
    if (_backendEmulatorRemoteAddress == null) {
      const envValue = String.fromEnvironment('BACKEND_EMULATOR_REMOTE_ADDRESS');
      if (envValue.isNotEmpty) {
        _backendEmulatorRemoteAddress = envValue;
      } else {
        _backendEmulatorRemoteAddress = _getDefaultEmulatorAddress();
      }
    }
    return _backendEmulatorRemoteAddress!;
  }

  /// Initialize the emulator address with automatic discovery if needed
  /// Call this before connecting to Firebase emulators
  /// This is separate from the main init because it is expensive and should not block app startup outside
  /// of using the Firebase emulator
  static Future<void> initializeEmulatorAddress() async {
    if (_emulatorAddressInitialized) {
      return; // Already initialized
    }

    // Check if environment variable is set first
    const envValue = String.fromEnvironment('BACKEND_EMULATOR_REMOTE_ADDRESS');
    if (envValue.isNotEmpty) {
      _backendEmulatorRemoteAddress = envValue;
      logd('Using environment-specified emulator address: $envValue');
      _emulatorAddressInitialized = true;
      return;
    }

    try {
      // Check if we're running on an emulator/simulator
      final isEmulator = await DeviceUtils.isRunningOnEmulator();
      logd('Running on emulator/simulator: $isEmulator');

      if (isEmulator) {
        // Use platform-specific emulator addresses
        _backendEmulatorRemoteAddress = _getPlatformDefaultEmulatorAddress();
        logd('Using platform default emulator address: $_backendEmulatorRemoteAddress');
      } else {
        // Physical device - discover the host machine IP
        logd('Physical device detected, discovering Firebase emulator host...');

        final discoveredIp =
            await NetworkUtils.discoverFirebaseEmulatorHost(port: backendEmulatorFunctionsPort);

        if (discoveredIp != null) {
          _backendEmulatorRemoteAddress = discoveredIp;
          logd('Using discovered emulator host: $discoveredIp');
        } else {
          _backendEmulatorRemoteAddress = _getPlatformDefaultEmulatorAddress();
          logw(
              'Could not discover emulator host, using platform default: $_backendEmulatorRemoteAddress');
        }
      }
    } catch (e) {
      _backendEmulatorRemoteAddress = _getPlatformDefaultEmulatorAddress();
      loge(
          'Error during emulator address initialization: $e, using default: $_backendEmulatorRemoteAddress');
    } finally {
      _emulatorAddressInitialized = true;
    }
  }

  static String _getDefaultEmulatorAddress() {
    // If we have already initialized the address, return it
    if (_backendEmulatorRemoteAddress != null) {
      return _backendEmulatorRemoteAddress!;
    }

    // Otherwise return platform default
    return _getPlatformDefaultEmulatorAddress();
  }

  /// Get the default emulator address based on platform
  static String _getPlatformDefaultEmulatorAddress() {
    // Web apps always use localhost
    if (kIsWeb) {
      return '127.0.0.1';
    }

    // For mobile platforms, use appropriate emulator/simulator defaults
    if (!kIsWeb) {
      if (Platform.isIOS) {
        // iOS Simulator uses localhost
        return '127.0.0.1';
      } else if (Platform.isAndroid) {
        // Android Emulator uses special IP for host machine
        return '10.0.2.2';
      }
    }

    // Default fallback
    return '127.0.0.1';
  }

  static int? _backendEmulatorStartingPortDefault;
  static set backendEmulatorStartingPortDefault(int value) =>
      _backendEmulatorStartingPortDefault = value;
  static int? _backendEmulatorStartingPort;
  static int get backendEmulatorStartingPort {
    _backendEmulatorStartingPort ??=
        const int.fromEnvironment('BACKEND_EMULATOR_STARTING_PORT', defaultValue: -1) != -1
            ? const int.fromEnvironment('BACKEND_EMULATOR_STARTING_PORT', defaultValue: -1)
            : (_backendEmulatorStartingPortDefault ?? 5001);
    return _backendEmulatorStartingPort!;
  }

  static String? _backendRegionDefault;
  static set backendRegionDefault(String value) => _backendRegionDefault = value;
  static String? _backendRegion;
  static String get backendRegion {
    _backendRegion ??= const String.fromEnvironment('BACKEND_REGION', defaultValue: '').isNotEmpty
        ? const String.fromEnvironment('BACKEND_REGION', defaultValue: '')
        : (_backendRegionDefault ?? (kReleaseMode ? 'us-central1' : 'us-central1'));
    return _backendRegion!;
  }

  static bool? _doUseBackendEmulator;
  static bool get doUseBackendEmulator {
    _doUseBackendEmulator ??= const String.fromEnvironment('DO_USE_BACKEND_EMULATOR',
            defaultValue: kReleaseMode ? 'false' : 'true') ==
        'true';
    return _doUseBackendEmulator!;
  }

  static bool? _doOverrideUseLiveRemoteConfig;
  static bool get doOverrideUseLiveRemoteConfig {
    _doOverrideUseLiveRemoteConfig ??=
        const String.fromEnvironment('DO_OVERRIDE_USE_LIVE_REMOTE_CONFIG', defaultValue: 'false') ==
            'true';
    return _doOverrideUseLiveRemoteConfig!;
  }

  static bool? _isStandalonePwaOverride;
  static bool get isStandalonePwaOverride {
    _isStandalonePwaOverride ??=
        const String.fromEnvironment('IS_STANDALONE_PWA_OVERRIDE', defaultValue: 'false') == 'true';
    return _isStandalonePwaOverride!;
  }

  static bool? _useHtmlInput;
  static bool get useHtmlInput {
    _useHtmlInput ??= const String.fromEnvironment('USE_HTML_INPUT',
            defaultValue: kReleaseMode ? 'false' : 'false') ==
        'true';
    return _useHtmlInput!;
  }

  static String? _devOnlyUid;
  static String get devOnlyUid {
    _devOnlyUid ??= const String.fromEnvironment('DEV_ONLY_UID', defaultValue: '');
    return _devOnlyUid!;
  }

  static bool? _devOnlyAutoGenerateNewUser;
  static bool get devOnlyAutoGenerateNewUser {
    _devOnlyAutoGenerateNewUser ??=
        const String.fromEnvironment('DEV_ONLY_AUTO_GENERATE_NEW_USER', defaultValue: 'false') ==
            'true';
    return _devOnlyAutoGenerateNewUser!;
  }

  static String? _devOnlyAutoGenerateNewUserAccessLevel;
  static String get devOnlyAutoGenerateNewUserAccessLevel {
    _devOnlyAutoGenerateNewUserAccessLevel ??= const String.fromEnvironment(
        'DEV_ONLY_AUTO_GENERATE_NEW_USER_ACCESS_LEVEL',
        defaultValue: 'full');
    return _devOnlyAutoGenerateNewUserAccessLevel!;
  }

  static bool? _debugDeepStateMode;
  static bool get debugDeepStateMode {
    _debugDeepStateMode ??=
        const String.fromEnvironment('DEBUG_DEEP_STATE_MODE', defaultValue: 'false') == 'true';
    return _debugDeepStateMode!;
  }

  static bool? _useFCMDefault;
  static set useFCMDefault(bool value) => _useFCMDefault = value;
  static bool? _useFCM;

  static bool get useFCM {
    _useFCM ??= const String.fromEnvironment('USE_FCM', defaultValue: '').isNotEmpty
        ? const String.fromEnvironment('USE_FCM', defaultValue: 'true') == 'true'
        : (_useFCMDefault ?? _getDefaultFCMValue());
    return _useFCM!;
  }

  static bool _getDefaultFCMValue() {
    // Default to false if running on iOS simulator, true otherwise
    if (isIOSSimulator == true) {
      return false;
    }
    return true;
  }

  static String? _networkRequiredOverride;
  static String get networkRequiredOverride {
    _networkRequiredOverride ??=
        const String.fromEnvironment('NETWORK_REQUIRED_OVERRIDE', defaultValue: 'null');
    return _networkRequiredOverride!;
  }

  static bool? _signoutOnReload;
  static bool get signoutOnReload {
    _signoutOnReload ??=
        const String.fromEnvironment('SIGNOUT_ON_RELOAD', defaultValue: 'false') == 'true';
    return _signoutOnReload!;
  }

  static bool? _useCookieFederatedAuthDefault;
  static set useCookieFederatedAuthDefault(bool value) => _useCookieFederatedAuthDefault = value;
  static bool? _useCookieFederatedAuth;
  static bool get useCookieFederatedAuth {
    _useCookieFederatedAuth ??=
        const String.fromEnvironment('USE_COOKIE_FEDERATED_AUTH', defaultValue: '').isNotEmpty
            ? const String.fromEnvironment('USE_COOKIE_FEDERATED_AUTH', defaultValue: 'false') ==
                'true'
            : (_useCookieFederatedAuthDefault ?? false);
    return _useCookieFederatedAuth!;
  }

  static bool? _editorPreviewMode;
  static bool get editorPreviewMode {
    _editorPreviewMode ??=
        const String.fromEnvironment('EDITOR_PREVIEW_MODE', defaultValue: 'false') == 'true';
    return _editorPreviewMode!;
  }

  static set editorPreviewMode(bool value) {
    _editorPreviewMode = value;
  }

  // static String? _appStoreAndroidUrl;
  // static String get appStoreAndroidUrl {
  //   _appStoreAndroidUrl ??= const String.fromEnvironment('APP_STORE_ANDROID_URL', defaultValue: '');
  //   return _appStoreAndroidUrl!;
  // }

  // static String? _appStoreAppleUrl;
  // static String get appStoreAppleUrl {
  //   _appStoreAppleUrl ??= const String.fromEnvironment('APP_STORE_APPLE_URL', defaultValue: '');
  //   return _appStoreAppleUrl!;
  // }

  static String? _appStoreAndroidUrlDefault;
  static set appStoreAndroidUrlDefault(String value) => _appStoreAndroidUrlDefault = value;
  static String? _appStoreAndroidUrl;
  static String get appStoreAndroidUrl {
    _appStoreAndroidUrl ??=
        const String.fromEnvironment('APP_STORE_ANDROID_URL', defaultValue: '').isNotEmpty
            ? const String.fromEnvironment('APP_STORE_ANDROID_URL', defaultValue: '')
            : (_appStoreAndroidUrlDefault ?? '');
    return _appStoreAndroidUrl!;
  }

  static String? _appStoreAppleUrlDefault;
  static set appStoreAppleUrlDefault(String value) => _appStoreAppleUrlDefault = value;
  static String? _appStoreAppleUrl;
  static String get appStoreAppleUrl {
    _appStoreAppleUrl ??=
        const String.fromEnvironment('APP_STORE_APPLE_URL', defaultValue: '').isNotEmpty
            ? const String.fromEnvironment('APP_STORE_APPLE_URL', defaultValue: '')
            : (_appStoreAppleUrlDefault ?? '');
    return _appStoreAppleUrl!;
  }

  //
  // Convenience  configs
  //

  static String get requiredAppVersion => !kIsWeb
      ? Platform.isIOS
          ? minimumAppVersionRequiredApple
          : minimumAppVersionRequiredGoogle
      : minimumAppVersionRequiredWeb;

  static String get recommendedAppVersion => !kIsWeb
      ? Platform.isIOS
          ? minimumAppVersionRecommendedApple
          : minimumAppVersionRecommendedGoogle
      : minimumAppVersionRecommendedWeb;

  static HttpsCallableOptions get firebaseFunctionCallableOptions {
    return HttpsCallableOptions(timeout: Duration(seconds: firebaseFunctionTimeoutSecs));
  }

  static HttpsCallable firebaseFunctionCallable(String name) {
    return FirebaseFunctions.instanceFor(
      region: backendRegion,
    ).httpsCallable(
      name,
      options: firebaseFunctionCallableOptions,
    );
  }

  static Uri firebaseFunctionUri(String name) {
    if (doUseBackendEmulator) {
      return Uri.parse(
          'http://$backendEmulatorRemoteAddress:$backendEmulatorFunctionsPort/${FirebaseFunctions.instanceFor().app.options.projectId}/$backendRegion/$name');
    }
    final projectId = FirebaseFunctions.instanceFor().app.options.projectId;
    return Uri.parse('https://$backendRegion-$projectId.cloudfunctions.net/$name');
  }

  static Duration get timeoutBeforeShowingLoading {
    return Duration(milliseconds: timeoutBeforeShowingLoadingMill);
  }

  static Duration get timeoutNetworkProcess {
    return Duration(milliseconds: timeoutNetworkProcessMill);
  }

  static String get appStoreUrl {
    String returnUrl = '';

    if (kIsWeb) {
      return '';
    }

    if (Platform.isIOS) {
      returnUrl = appStoreAppleUrl;
    } else if (Platform.isAndroid) {
      returnUrl = appStoreAndroidUrl;
    } else {
      //TODO: handle web??
      returnUrl = '';
    }

    return returnUrl;
  }

  static int get backendEmulatorAuthPort {
    return backendEmulatorStartingPort;
  }

  static int get backendEmulatorFunctionsPort {
    return backendEmulatorStartingPort + 1;
  }

  static int get backendEmulatorFirestorePort {
    return backendEmulatorStartingPort + 2;
  }

  static int get backendEmulatorHostingPort {
    return backendEmulatorStartingPort + 3;
  }

  static int get backendEmulatorPubSubPort {
    return backendEmulatorStartingPort + 4;
  }

  static int get backendEmulatorStoragePort {
    return backendEmulatorStartingPort + 5;
  }

  static int get backendEmulatorEventArcPort {
    return backendEmulatorStartingPort + 6;
  }

  static int get backendEmulatorTasksPort {
    return backendEmulatorStartingPort + 7;
  }

  //
  // Determined at run time
  //

  static bool? _isIOSSimulator;
  static bool? _isAndroidSimulator;
  static bool? _isSimulatorDevice;

  /// Initialize iOS simulator detection state for FCM configuration
  /// Call this during app initialization to ensure proper FCM defaults

  static bool get isIOSSimulator {
    if (_isSimulatorDevice == null) {
      throw Exception(
          'Simulator detection not initialized. Call _initializeSimulatorDetection first.');
    }

    _isIOSSimulator ??= !kIsWeb && Platform.isIOS && _isSimulatorDevice!;

    return _isIOSSimulator!;
  }

  static bool get isAndroidSimulator {
    if (_isSimulatorDevice == null) {
      throw Exception(
          'Simulator detection not initialized. Call _initializeSimulatorDetection first.');
    }

    _isAndroidSimulator ??= !kIsWeb && Platform.isAndroid && _isSimulatorDevice!;

    return _isAndroidSimulator!;
  }

  static bool get isSimulatorDevice {
    if (_isSimulatorDevice == null) {
      throw Exception(
          'Simulator detection not initialized. Call _initializeSimulatorDetection first.');
    }

    return _isSimulatorDevice!;
  }

  static Future<void> _initializeSimulatorDetection() async {
    if (_isSimulatorDevice != null) {
      return; // Already initialized
    }

    try {
      _isSimulatorDevice = await DeviceUtils.isRunningOnEmulator();
    } catch (e) {
      loge('Error detecting simulator status: $e');
      _isSimulatorDevice = false;
    }
  }
}
