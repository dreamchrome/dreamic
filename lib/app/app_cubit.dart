import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_core/firebase_core.dart';
// import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:dreamic/app/app_config_base.dart';
import 'package:dreamic/data/models/notification_permission_status.dart';
import 'package:dreamic/notifications/notification_service.dart';
import 'package:dreamic/versioning/app_version_update_service.dart';
import 'package:dreamic/app/helpers/app_lifecycle_service.dart';
import 'package:dreamic/utils/logger.dart';
import 'package:dreamic/presentation/helpers/cubit_helpers.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';

// import '../domain/repos/input_repo_int.dart';

part 'app_cubit_state.dart';

class AppCubit extends Cubit<AppState> with SafeEmitMixin<AppState> {
  // final InputRepoInt inputRepo = GetIt.I.get<InputRepoInt>();

  Uri? entranceUri;
  bool networkRequired;
  bool hasProcessedEntrance = false;
  InternetConnection? connectionChecker;
  StreamSubscription? connectionCheckerSubscription;
  StreamSubscription<VersionUpdateInfo>? versionUpdateSubscription;
  StreamSubscription<AppLifecycleState>? lifecycleSubscription;
  StreamSubscription<int>? notificationBadgeSubscription;

  static const Duration _networkCheckTimeout = Duration(seconds: 10);

  /// Guards against multiple calls to getInitialData()
  bool _hasInitialized = false;

  // InputGroup? _inputGroup;
  // PageController? pageController;

  AppCubit({
    this.entranceUri,
    this.networkRequired = true,
  }) : super(const AppState());

  @override
  Future<void> close() async {
    // Clean up all stream subscriptions and services
    // Use try-catch for each to ensure all cleanup happens even if one fails
    try {
      await connectionCheckerSubscription?.cancel();
    } catch (e) {
      loge(e, 'Error canceling connection checker subscription');
    }

    try {
      await versionUpdateSubscription?.cancel();
    } catch (e) {
      loge(e, 'Error canceling version update subscription');
    }

    try {
      await lifecycleSubscription?.cancel();
    } catch (e) {
      loge(e, 'Error canceling lifecycle subscription');
    }

    try {
      await notificationBadgeSubscription?.cancel();
    } catch (e) {
      loge(e, 'Error canceling notification badge subscription');
    }

    // Note: internet_connection_checker_plus doesn't have a dispose() method.
    // Cleanup happens automatically when the subscription is cancelled.

    try {
      AppVersionUpdateService().dispose();
    } catch (e) {
      loge(e, 'Error disposing AppVersionUpdateService');
    }

    try {
      AppLifecycleService().dispose();
    } catch (e) {
      loge(e, 'Error disposing AppLifecycleService');
    }

    // Always call super.close() even if cleanup fails
    return super.close();
  }

  Future<void> getInitialData() async {
    // Guard against multiple calls (e.g., when AppRootWidget rebuilds)
    if (_hasInitialized) {
      logv('getInitialData: Already initialized, skipping');
      return;
    }
    _hasInitialized = true;

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
    logv(
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
      logv('✨ No update needed, clearing version update state');
      emitSafe(state.copyWith(
        versionUpdateInfo: updateInfo,
        showVersionUpdateBanner: false,
      ));
    }
  }

  Future<void> checkForAppUpdates() async {
    try {
      logv('Manually checking for app updates');
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
      String defaultHostingUrl;

      // Determine the URL for network checking
      if (AppConfigBase.connectionCheckerUrlOverride.isNotEmpty) {
        // Use explicit override URL (works with or without Firebase)
        defaultHostingUrl = AppConfigBase.connectionCheckerUrlOverride;
        logd(
            'Using connectionCheckerUrlOverride for network checking: ${AppConfigBase.connectionCheckerUrlOverride}');
      } else if (AppConfigBase.isFirebaseInitialized) {
        // Use Firebase project URL
        final projectId = Firebase.app().options.projectId;
        defaultHostingUrl = (AppConfigBase.doUseBackendEmulator)
            ? 'http://${AppConfigBase.backendEmulatorRemoteAddress}:${AppConfigBase.backendEmulatorAuthPort}'
            : 'https://$projectId.web.app';
        logd('Using default hosting URL for network checking: $defaultHostingUrl');
      } else {
        // Firebase not initialized and no override - cannot determine URL
        loge(
          'Network checking requires either Firebase initialization or connectionCheckerUrlOverride',
          'Firebase is not initialized and no connectionCheckerUrlOverride is set. '
              'Either call appInitFirebase() before creating AppCubit, or set '
              'AppConfigBase.connectionCheckerUrlOverride to a valid health check URL.',
        );
        emitSafe(state.copyWith(
          appStatus: AppStatus.error,
          networkErrorMessage:
              'Network checking configuration error. Please contact support.',
        ));
        return;
      }

      connectionChecker = InternetConnection.createInstance(
        useDefaultOptions: false,
        customCheckOptions: [
          InternetCheckOption(uri: Uri.parse(defaultHostingUrl)),
        ],
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
      final result = await connectionChecker?.hasInternetAccess.timeout(_networkCheckTimeout);
      return result ?? false;
    } catch (e) {
      logd('Network check timed out or failed: $e');
      return false;
    }
  }

  void _subscribeToNetworkChanges() {
    logd('Subscribing to network connection changes');
    connectionCheckerSubscription = connectionChecker?.onStatusChange.listen(
      (InternetStatus status) {
        if (status == InternetStatus.connected) {
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
    logd('Initial data fetched, setting app status to normal');
    emitSafe(state.copyWith(
      appStatus: AppStatus.normal,
      showNetworkRetry: false,
      networkErrorMessage: '',
    ));
  }

  void _initializeLifecycleService() {
    try {
      logv('Initializing app lifecycle service');

      // Initialize the lifecycle service
      AppLifecycleService().initialize();

      // Subscribe to lifecycle events
      lifecycleSubscription = AppLifecycleService().lifecycleStream.listen(
        (AppLifecycleState state) {
          logv('App lifecycle state changed: $state');
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

  // ============ Notification State Management ============

  /// Initializes notification state sync with NotificationService.
  ///
  /// This subscribes to the NotificationService badge count stream and
  /// syncs the initial permission status. Call this after NotificationService
  /// has been initialized.
  ///
  /// Safe to call multiple times - subsequent calls are ignored.
  Future<void> initializeNotificationSync() async {
    // Already subscribed
    if (notificationBadgeSubscription != null) {
      logv('Notification sync already initialized, skipping');
      return;
    }

    try {
      final notificationService = NotificationService();

      // Only proceed if the service is initialized
      if (!notificationService.isInitialized) {
        logv('NotificationService not initialized, skipping notification sync');
        return;
      }

      logd('Initializing notification state sync');

      // Sync initial badge count
      final initialCount = notificationService.getBadgeCount();
      emitSafe(state.copyWith(unreadNotificationCount: initialCount));

      // Subscribe to badge count changes
      notificationBadgeSubscription = notificationService.badgeCountStream.listen(
        (count) {
          logv('Badge count stream update: $count');
          emitSafe(state.copyWith(unreadNotificationCount: count));
        },
        onError: (error) {
          loge('Error in notification badge stream: $error');
        },
      );

      // Sync initial permission status
      final permissionStatus = await notificationService.getPermissionStatus();
      emitSafe(state.copyWith(notificationPermissionStatus: permissionStatus));

      logd('Notification state sync initialized');
    } catch (e) {
      loge(e, 'Error initializing notification sync');
    }
  }

  /// Updates the unread notification count.
  ///
  /// This is typically called by the NotificationService or when
  /// notifications are read/cleared by the user.
  void updateUnreadNotificationCount(int count) {
    logv('Updating unread notification count: $count');
    emitSafe(state.copyWith(unreadNotificationCount: count));
  }

  /// Increments the unread notification count by 1.
  void incrementUnreadNotificationCount() {
    updateUnreadNotificationCount(state.unreadNotificationCount + 1);
  }

  /// Clears the unread notification count (sets to 0).
  void clearUnreadNotificationCount() {
    updateUnreadNotificationCount(0);
  }

  /// Updates the notification permission status.
  ///
  /// This should be called after checking or requesting permissions
  /// via NotificationService.
  void updateNotificationPermissionStatus(NotificationPermissionStatus status) {
    logv('Updating notification permission status: $status');
    emitSafe(state.copyWith(notificationPermissionStatus: status));
  }

  /// Requests notification permissions and syncs the result to state.
  ///
  /// This is a convenience method that wraps NotificationService.requestPermissions()
  /// and automatically updates the AppState with the result.
  ///
  /// Returns the resulting permission status.
  Future<NotificationPermissionStatus> requestNotificationPermissions({
    bool provisional = false,
  }) async {
    try {
      final notificationService = NotificationService();

      if (!notificationService.isInitialized) {
        logd('NotificationService not initialized, cannot request permissions');
        return NotificationPermissionStatus.notDetermined;
      }

      final status = await notificationService.requestPermissions(
        provisional: provisional,
      );

      // Sync to state
      emitSafe(state.copyWith(notificationPermissionStatus: status));

      return status;
    } catch (e) {
      loge(e, 'Error requesting notification permissions');
      return NotificationPermissionStatus.denied;
    }
  }

  /// Refreshes the notification permission status from the system.
  ///
  /// Call this when returning from app settings or when the app resumes
  /// to ensure the permission status is up to date.
  Future<void> refreshNotificationPermissionStatus() async {
    try {
      final notificationService = NotificationService();

      if (!notificationService.isInitialized) {
        return;
      }

      final status = await notificationService.getPermissionStatus();
      emitSafe(state.copyWith(notificationPermissionStatus: status));
    } catch (e) {
      loge(e, 'Error refreshing notification permission status');
    }
  }
}
