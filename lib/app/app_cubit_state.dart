part of 'app_cubit.dart';

enum AppAuthStatus {
  noauth,
  anonymous,
  loggedIn,
  loggedInButNoRequiredClaims,
}

extension AppAuthStatusX on AppAuthStatus {
  bool get isNotLoggedIn => this == AppAuthStatus.noauth;
  bool get isAuthed => this == AppAuthStatus.anonymous || this == AppAuthStatus.loggedIn;
}

enum AppStatus {
  loading,
  overlayLoading,
  overlayProgressing,
  overlyFullScreen,
  normal,
  error,
  networkError,
  updateRequired,
}

enum NetworkStatus {
  none,
  connected,
  unknown,
}

class AppState extends Equatable {
  const AppState({
    this.appAuthStatus = AppAuthStatus.noauth,
    this.appStatus = AppStatus.normal,
    this.progress = 0.0,
    this.progressHeaderText = '',
    this.currentPath = '',
    this.colorThemeIndex = 0,
    this.overlayFullScreenChild,
    this.overlayFullScreenChildCount = 0,
    this.unreadNotificationsCount = 0,
    this.networkStatus = NetworkStatus.unknown,
    this.networkErrorMessage = '',
    this.showNetworkRetry = false,
    this.versionUpdateInfo,
    this.showVersionUpdateBanner = false,
  });

  final AppAuthStatus appAuthStatus;
  final AppStatus appStatus;
  final double progress;
  final String progressHeaderText;
  // final Section currentSection;
  final String currentPath;
  final int colorThemeIndex;
  final List<Widget Function()>? overlayFullScreenChild;
  final int overlayFullScreenChildCount;
  final int unreadNotificationsCount;
  final NetworkStatus networkStatus;
  final String networkErrorMessage;
  final bool showNetworkRetry;
  final VersionUpdateInfo? versionUpdateInfo;
  final bool showVersionUpdateBanner;

  AppState copyWith({
    AppAuthStatus? appAuthStatus,
    AppStatus? appStatus,
    double? progress,
    String? progressHeaderText,
    String? currentPath,
    int? colorThemeIndex,
    ValueGetter<List<Widget Function()>>? overlayFullScreenChild,
    int? overlayFullScreenChildCount,
    int? unreadNotificationsCount,
    NetworkStatus? networkStatus,
    String? networkErrorMessage,
    bool? showNetworkRetry,
    VersionUpdateInfo? versionUpdateInfo,
    bool? showVersionUpdateBanner,
  }) {
    return AppState(
      appAuthStatus: appAuthStatus ?? this.appAuthStatus,
      appStatus: appStatus ?? this.appStatus,
      progress: progress ?? this.progress,
      progressHeaderText: progressHeaderText ?? this.progressHeaderText,
      currentPath: currentPath ?? this.currentPath,
      colorThemeIndex: colorThemeIndex ?? this.colorThemeIndex,
      overlayFullScreenChild:
          overlayFullScreenChild != null ? overlayFullScreenChild() : this.overlayFullScreenChild,
      overlayFullScreenChildCount: overlayFullScreenChildCount ?? this.overlayFullScreenChildCount,
      unreadNotificationsCount: unreadNotificationsCount ?? this.unreadNotificationsCount,
      networkStatus: networkStatus ?? this.networkStatus,
      networkErrorMessage: networkErrorMessage ?? this.networkErrorMessage,
      showNetworkRetry: showNetworkRetry ?? this.showNetworkRetry,
      versionUpdateInfo: versionUpdateInfo ?? this.versionUpdateInfo,
      showVersionUpdateBanner: showVersionUpdateBanner ?? this.showVersionUpdateBanner,
    );
  }

  @override
  List<Object?> get props => [
        appAuthStatus,
        appStatus,
        progress,
        progressHeaderText,
        currentPath,
        colorThemeIndex,
        overlayFullScreenChild,
        overlayFullScreenChildCount,
        unreadNotificationsCount,
        networkStatus,
        networkErrorMessage,
        showNetworkRetry,
        versionUpdateInfo,
        showVersionUpdateBanner,
      ];
}

// class AppInitial extends AppState {}
