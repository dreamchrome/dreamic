// import 'package:bloc/bloc.dart';
// import 'package:flutter/material.dart';
// import 'package:dreamic/common/logger.dart';
// import 'package:dreamic/presentation/helpers/cubit_helpers.dart';
// import 'package:equatable/equatable.dart';

// part 'app_cubit_base_state.dart';

// abstract class AppCubitBase<T extends AppCubitBaseState> extends Cubit<T> with SafeEmitMixin<T> {
//   // final AuthServiceInt authService =
//   // bool hasProcessedEntrance = false;

//   // InputGroup? _inputGroup;
//   // PageController? pageController;

//   AppCubitBase(super.initialState);

//   Future<void> getInitialData() async {
//     if (state.appStatus != AppStatus.loading) {
//       emitSafe(state.copyWith(appStatus: AppStatus.loading) as T);

//       // await Future.delayed(Duration(seconds: 2));

//       emitSafe(state.copyWith(appStatus: AppStatus.normal) as T);
//     }
//   }

//   // Future<void> updateUnreadNotificationsCount({UserPrivate? myUserPrivate}) async {
//   //   logd('AppCubit::: updateUnreadNotificationsCount()');
//   //   try {
//   //     final count = myUserPrivate?.unreadNotifications ??
//   //         (await userRepo.getMyUserPrivateCached())
//   //             .getOrElse(() => throw Exception())
//   //             .unreadNotifications;

//   //     emitSafe(state.copyWith(unreadNotificationsCount: count ?? 0));
//   //   } catch (e) {
//   //     loge(StackTrace.current, 'updateUnreadNotificationsCount error: $e');
//   //   }
//   // }

//   Future<void> onNavHappened(String path) async {
//     logd('============onNavHappened: $path');
//     emitSafe(state.copyWith(currentPath: path) as T);
//   }

//   void overlayLoadingStart() {
//     logd('overlayLoadingStart');
//     emitSafe(state.copyWith(appStatus: AppStatus.overlayLoading) as T);
//   }

//   void overlayLoadingFinish() {
//     logd('overlayLoadingFinish');
//     emitSafe(state.copyWith(appStatus: AppStatus.normal) as T);
//   }

//   void overlayProgressingStart() {
//     logd('overlayProgressingStart');
//     emitSafe(state.copyWith(
//       appStatus: AppStatus.overlayProgressing,
//       progress: 0.0,
//     ) as T);
//   }

//   void overlayProgressingUpdate(double progress) {
//     emitSafe(state.copyWith(progress: progress) as T);
//   }

//   void overlayProgressingFinish() {
//     logd('overlayProgressingFinish');
//     emitSafe(state.copyWith(appStatus: AppStatus.normal) as T);
//   }

//   void overlayFullScreenSetChild(Widget Function() child) {
//     logd('overlayFullScreenSetChild');
//     emitSafe(state.copyWith(overlayFullScreenChild: () => child) as T);
//   }

//   void overlayFullScreenSetChildAndStart(Widget Function()? child) {
//     logd('overlayFullScreenSetChildAndStart');
//     emitSafe(state.copyWith(
//       overlayFullScreenChild: () => child,
//       appStatus: AppStatus.overlyFullScreen,
//     ) as T);
//   }

//   void overlayFullScreenStart() {
//     logd('overlayFullScreenStart');
//     emitSafe(state.copyWith(appStatus: AppStatus.overlyFullScreen) as T);
//   }

//   void overlayFullScreenFinish() {
//     logd('overlayFullScreenFinish');
//     emitSafe(state.copyWith(appStatus: AppStatus.normal) as T);
//   }

//   Future<void> setColorThemeIndex(int index) async {
//     emitSafe(state.copyWith(appStatus: AppStatus.loading) as T);

//     // emitSafe(state.copyWith(
//     //   // appStatus: AppStatus.normal,
//     //   colorThemeIndex: index,
//     // ));

//     await Future.delayed(const Duration(milliseconds: 500));

//     emitSafe(state.copyWith(
//       appStatus: AppStatus.normal,
//       colorThemeIndex: index,
//     ) as T);
//   }
// }
