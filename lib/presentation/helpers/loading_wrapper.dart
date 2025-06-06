import 'dart:async';

import 'package:dreamic/app/app_cubit.dart';
import 'package:dreamic/app/app_config_base.dart';
import 'package:dreamic/utils/get_it_utils.dart';

int _activeCallsCount = 0;

typedef LoadingStartCallback = void Function();
typedef LoadingFinishCallback = void Function();

LoadingStartCallback _defaultLoadingStart = () => g<AppCubit>().overlayLoadingStart();
LoadingFinishCallback _defaultLoadingFinish = () => g<AppCubit>().overlayLoadingFinish();

void configureTimeoutLoadingCallbacks({
  LoadingStartCallback? onLoadingStart,
  LoadingFinishCallback? onLoadingFinish,
}) {
  if (onLoadingStart != null) {
    _defaultLoadingStart = onLoadingStart;
  }
  if (onLoadingFinish != null) {
    _defaultLoadingFinish = onLoadingFinish;
  }
}

/// Calls the given function and shows a loading overlay after a timeout.
/// The loading overlay is shown only if the function call takes longer than the given timeout.
/// The T type is the return type of the function.
Future<T> callWithLoadingAfterTimeout<T>(
  Future<T> Function() fn, {
  void Function(dynamic error)? onError,
  int? timeoutBeforeLoadingMill,
  LoadingStartCallback? onLoadingStart,
  LoadingFinishCallback? onLoadingFinish,
}) async {
  bool isLoadingShown = false;
  _activeCallsCount++;

  Timer timer = Timer(
    Duration(
      milliseconds: timeoutBeforeLoadingMill ?? AppConfigBase.timeoutBeforeShowingLoadingMill,
    ),
    () {
      isLoadingShown = true;
      (onLoadingStart ?? _defaultLoadingStart)();
    },
  );

  try {
    return await fn();
  } catch (error) {
    onError?.call(error);
    rethrow;
  } finally {
    _activeCallsCount--;
    if (isLoadingShown && _activeCallsCount == 0) {
      (onLoadingFinish ?? _defaultLoadingFinish)();
    }
    timer.cancel();
  }
}
