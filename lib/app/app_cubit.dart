import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_core/firebase_core.dart';
// import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:dreamic/app/app_config_base.dart';
import 'package:dreamic/app/helpers/app_version_update_service.dart';
import 'package:dreamic/app/helpers/app_lifecycle_service.dart';
import 'package:dreamic/utils/logger.dart';
import 'package:dreamic/presentation/helpers/cubit_helpers.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';

// import '../domain/repos/input_repo_int.dart';

part 'app_cubit_state.dart';

class AppCubit extends Cubit<AppState> with SafeEmitMixin<AppState> {
  // final InputRepoInt inputRepo = GetIt.I.get<InputRepoInt>();

  Uri? entranceUri;
  bool networkRequired;
  bool hasProcessedEntrance = false;
  InternetConnectionChecker? connectionChecker;
  StreamSubscription? connectionCheckerSubscription;
  StreamSubscription<VersionUpdateInfo>? versionUpdateSubscription;
  StreamSubscription<AppLifecycleState>? lifecycleSubscription;

  static const Duration _networkCheckTimeout = Duration(seconds: 10);

  // InputGroup? _inputGroup;
  // PageController? pageController;

  AppCubit({
    this.entranceUri,
    this.networkRequired = true,
  }) : super(const AppState());

  @override
  Future<void> close() {
    connectionChecker?.dispose(); // Dispose of the InternetConnectionChecker instance
    versionUpdateSubscription?.cancel();
    lifecycleSubscription?.cancel();
    AppVersionUpdateService().dispose();
    AppLifecycleService().dispose();
    return super.close();
  }

  Future<void> getInitialData() async {
    try {
      emitSafe(state.copyWith(appStatus: AppStatus.loading));

      // Initialize version update service
      await _initializeVersionUpdateService();

      // Initialize app lifecycle service
      _initializeLifecycleService();

      final isNetworkRequiredOrOverriden = (AppConfigBase.networkRequiredOverride == 'null')
          ? networkRequired
          : (AppConfigBase.networkRequiredOverride == 'true');

      if (!isNetworkRequiredOrOverriden) {
        logd(
            'Network connection not required during app start - setting networkStatus to connected');
        emitSafe(state.copyWith(networkStatus: NetworkStatus.connected));
        await _finalizeAppStartup();
      } else {
        logd('Checking network connection as required during app start');
        await _initializeNetworkChecking();
      }
    } catch (e) {
      loge(e, 'Error in getInitialData');
      emitSafe(state.copyWith(
        appStatus: AppStatus.error,
        networkErrorMessage: 'Failed to initialize app: ${e.toString()}',
      ));
    }
  }

  Future<void> _initializeVersionUpdateService() async {
    try {
      logd('Initializing version update service');

      // Initialize the version update service
      await AppVersionUpdateService().initialize();

      // Subscribe to version update notifications
      versionUpdateSubscription = AppVersionUpdateService().updateStream.listen(
        (versionUpdateInfo) {
          _handleVersionUpdate(versionUpdateInfo);
        },
        onError: (error) {
          loge('Error in version update stream: $error');
        },
      );
    } catch (e) {
      loge('Error initializing version update service: $e');
    }
  }

  void _handleVersionUpdate(VersionUpdateInfo updateInfo) {
    logd(
        '📊 Update details - Current: ${updateInfo.currentVersion}, Required: ${updateInfo.requiredVersion}, Recommended: ${updateInfo.recommendedVersion}');

    if (updateInfo.updateType == VersionUpdateType.required) {
      // For required updates, block the app
      logd('🚨 Setting app status to updateRequired - blocking app usage');
      emitSafe(state.copyWith(
        appStatus: AppStatus.updateRequired,
        versionUpdateInfo: updateInfo,
        showVersionUpdateBanner: false,
      ));
    } else if (updateInfo.updateType == VersionUpdateType.recommended) {
      // For recommended updates, show banner
      logd('💡 Setting showVersionUpdateBanner to true for recommended update');
      emitSafe(state.copyWith(
        versionUpdateInfo: updateInfo,
        showVersionUpdateBanner: true,
      ));
    } else {
      // No update needed, clear any previous update state
      logd('✨ No update needed, clearing version update state');
      emitSafe(state.copyWith(
        versionUpdateInfo: updateInfo,
        showVersionUpdateBanner: false,
      ));
    }
  }

  Future<void> checkForAppUpdates() async {
    try {
      logd('Manually checking for app updates');
      await AppVersionUpdateService().forceVersionCheck();
    } catch (e) {
      loge('Error checking for app updates: $e');
    }
  }

  void dismissVersionUpdateBanner() {
    logd('Dismissing version update banner');
    emitSafe(state.copyWith(showVersionUpdateBanner: false));
  }

  Future<void> _initializeNetworkChecking() async {
    try {
      final projectId = Firebase.app().options.projectId;
      var defaultHostingUrl = (AppConfigBase.doUseBackendEmulator)
          ? AppConfigBase.firebaseFunctionUri('sysConnectionCheck').toString()
          : 'https://$projectId.web.app';

      if (AppConfigBase.connectionCheckerUrlOverride.isNotEmpty) {
        logd(
            'Using connectionCheckerUrlOverride for network checking: ${AppConfigBase.connectionCheckerUrlOverride}');
        defaultHostingUrl = AppConfigBase.connectionCheckerUrlOverride;
      } else {
        logd('Using default hosting URL for network checking: $defaultHostingUrl');
      }

      connectionChecker = InternetConnectionChecker.createInstance(
        addresses: List<AddressCheckOption>.unmodifiable(<AddressCheckOption>[
          AddressCheckOption(uri: Uri.parse(defaultHostingUrl)),
        ]),
      );

      // Check network with timeout
      final networkAvailable = await _checkNetworkWithTimeout();

      if (networkAvailable) {
        logd('Network connection confirmed during startup');
        emitSafe(state.copyWith(networkStatus: NetworkStatus.connected));
        await _finalizeAppStartup();
      } else {
        logd('Network connection failed during startup');
        emitSafe(state.copyWith(
          appStatus: AppStatus.networkError,
          networkStatus: NetworkStatus.none,
          networkErrorMessage:
              'Unable to connect to the server. Please check your connection and try again.',
          showNetworkRetry: true,
        ));
      }

      // Subscribe to connection changes after initial check
      _subscribeToNetworkChanges();
    } catch (e) {
      loge(e, 'Error initializing network checking');
      emitSafe(state.copyWith(
        appStatus: AppStatus.networkError,
        networkStatus: NetworkStatus.none,
        networkErrorMessage: 'Network initialization failed. Please try again.',
        showNetworkRetry: true,
      ));
    }
  }

  Future<bool> _checkNetworkWithTimeout() async {
    try {
      final result = await connectionChecker?.hasConnection.timeout(_networkCheckTimeout);
      return result ?? false;
    } catch (e) {
      logd('Network check timed out or failed: $e');
      return false;
    }
  }

  void _subscribeToNetworkChanges() {
    logd('Subscribing to network connection changes');
    connectionCheckerSubscription = connectionChecker?.onStatusChange.listen(
      (InternetConnectionStatus status) {
        if (status == InternetConnectionStatus.connected) {
          logd('Network connection detected connected');
          emitSafe(state.copyWith(networkStatus: NetworkStatus.connected));

          // If we were in network error state, try to complete startup
          if (state.appStatus == AppStatus.networkError) {
            _finalizeAppStartup();
          }
        } else {
          logd('Network connection detected DISCONNECTED');
          emitSafe(state.copyWith(networkStatus: NetworkStatus.none));
        }
      },
    );
  }

  Future<void> _finalizeAppStartup() async {
    // Log version info
    _logVersion();

    logd('Initial data fetched, setting app status to normal');
    emitSafe(state.copyWith(
      appStatus: AppStatus.normal,
      showNetworkRetry: false,
      networkErrorMessage: '',
    ));
  }

  void _initializeLifecycleService() {
    try {
      logd('Initializing app lifecycle service');

      // Initialize the lifecycle service
      AppLifecycleService().initialize();

      // Subscribe to lifecycle events
      lifecycleSubscription = AppLifecycleService().lifecycleStream.listen(
        (AppLifecycleState state) {
          logd('App lifecycle state changed: $state');
          // The lifecycle service already handles version checking internally
          // We just log the state change here for debugging
        },
        onError: (error) {
          loge('Error in lifecycle stream: $error');
        },
      );
    } catch (e) {
      loge('Error initializing lifecycle service: $e');
    }
  }

  Future<void> retryNetworkConnection() async {
    logd('Retrying network connection');
    emitSafe(state.copyWith(
      appStatus: AppStatus.loading,
      showNetworkRetry: false,
      networkErrorMessage: '',
    ));

    final isNetworkRequiredOrOverriden = (AppConfigBase.networkRequiredOverride == 'null')
        ? networkRequired
        : (AppConfigBase.networkRequiredOverride == 'true');

    if (isNetworkRequiredOrOverriden) {
      await _initializeNetworkChecking();
    } else {
      logd('Network connection not required during retry - setting networkStatus to connected');
      emitSafe(state.copyWith(networkStatus: NetworkStatus.connected));
      await _finalizeAppStartup();
    }
  }

  Future<void> _logVersion() async {
    final version = await AppConfigBase.getAppVersion();
    debugPrint('App version: ${version.packageName} ${version.version}+${version.buildNumber}');
  }

  Future<void> onNavHappened(String path) async {
    logd('============onNavHappened: $path');
    emitSafe(state.copyWith(currentPath: path));
  }

  void overlayLoadingStart() {
    logd('overlayLoadingStart');
    emitSafe(state.copyWith(appStatus: AppStatus.overlayLoading));
  }

  void overlayLoadingFinish() {
    logd('overlayLoadingFinish');
    emitSafe(state.copyWith(appStatus: AppStatus.normal));
  }

  void overlayProgressingStart({String? headerText}) {
    logd('overlayProgressingStart');
    emitSafe(state.copyWith(
      appStatus: AppStatus.overlayProgressing,
      progress: 0.0,
      progressHeaderText: headerText ?? '',
    ));
  }

  void overlayProgressingUpdate(double progress) {
    emitSafe(state.copyWith(progress: progress));
  }

  void overlayProgressingFinish() {
    logd('overlayProgressingFinish');
    emitSafe(state.copyWith(
      appStatus: AppStatus.normal,
      progress: 0.0,
      progressHeaderText: '',
    ));
  }

  void overlayFullScreenSetChild(Widget Function() child) {
    logd('overlayFullScreenSetChild');
    emitSafe(
      state.copyWith(
        overlayFullScreenChild: () =>
            (state.overlayFullScreenChild ?? <Widget Function()>[])..add(child),
        overlayFullScreenChildCount: state.overlayFullScreenChildCount + 1,
      ),
    );
  }

  void overlayFullScreenSetChildAndStart(Widget Function()? child) {
    logd('overlayFullScreenSetChildAndStart');
    emitSafe(state.copyWith(
      overlayFullScreenChild: () =>
          (state.overlayFullScreenChild ?? <Widget Function()>[])..add(child!),
      overlayFullScreenChildCount: state.overlayFullScreenChildCount + 1,
      appStatus: AppStatus.overlyFullScreen,
    ));
  }

  void overlayFullScreenStart() {
    //TODO: this doesn't work perfectly yet with the new list of widgets
    logd('overlayFullScreenStart');
    emitSafe(
      state.copyWith(appStatus: AppStatus.overlyFullScreen),
    );
  }

  void overlayFullScreenFinish() {
    logd('overlayFullScreenFinish');
    emitSafe(
      state.copyWith(
        appStatus: state.overlayFullScreenChildCount <= 1 ? AppStatus.normal : state.appStatus,
        overlayFullScreenChild: () =>
            (state.overlayFullScreenChild ?? <Widget Function()>[])..removeLast(),
        overlayFullScreenChildCount: state.overlayFullScreenChildCount - 1,
      ),
    );
  }

  Future<void> setColorThemeIndex(int index) async {
    emitSafe(state.copyWith(appStatus: AppStatus.loading));

    // emitSafe(state.copyWith(
    //   // appStatus: AppStatus.normal,
    //   colorThemeIndex: index,
    // ));

    await Future.delayed(const Duration(milliseconds: 500));

    emitSafe(state.copyWith(
      appStatus: AppStatus.normal,
      colorThemeIndex: index,
    ));
  }
}
