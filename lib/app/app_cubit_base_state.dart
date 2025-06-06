// part of 'app_cubit_base.dart';

// enum AppAuthStatus {
//   noauth,
//   anonymous,
//   loggedIn,
//   loggedInButNoRequiredClaims,
// }

// extension AppAuthStatusX on AppAuthStatus {
//   bool get isNotLoggedIn => this == AppAuthStatus.noauth;
//   bool get isAuthed => this == AppAuthStatus.anonymous || this == AppAuthStatus.loggedIn;
// }

// enum AppStatus {
//   loading,
//   overlayLoading,
//   overlayProgressing,
//   overlyFullScreen,
//   normal,
//   error,
// }

// class AppCubitBaseState extends Equatable {
//   const AppCubitBaseState({
//     //TODO: different default until this is actually set by the auth service
//     this.appAuthStatus = AppAuthStatus.anonymous,
//     this.appStatus = AppStatus.normal,
//     this.progress = 0.0,
//     this.currentPath = '',
//     this.colorThemeIndex = 0,
//     this.overlayFullScreenChild,
//   });

//   final AppAuthStatus appAuthStatus;
//   final AppStatus appStatus;
//   final double progress;
//   final String currentPath;
//   final int colorThemeIndex;
//   final Widget Function()? overlayFullScreenChild;

//   AppCubitBaseState copyWith({
//     AppAuthStatus? appAuthStatus,
//     AppStatus? appStatus,
//     double? progress,
//     String? currentPath,
//     int? colorThemeIndex,
//     ValueGetter<Widget Function()?>? overlayFullScreenChild,
//   }) {
//     return AppCubitBaseState(
//       appAuthStatus: appAuthStatus ?? this.appAuthStatus,
//       appStatus: appStatus ?? this.appStatus,
//       progress: progress ?? this.progress,
//       currentPath: currentPath ?? this.currentPath,
//       colorThemeIndex: colorThemeIndex ?? this.colorThemeIndex,
//       overlayFullScreenChild: overlayFullScreenChild?.call() ?? this.overlayFullScreenChild,
//     );
//   }

//   @override
//   List<Object?> get props => [
//         appAuthStatus,
//         appStatus,
//         progress,
//         currentPath,
//         colorThemeIndex,
//         overlayFullScreenChild,
//       ];
// }

// // class AppInitial extends AppState {}
