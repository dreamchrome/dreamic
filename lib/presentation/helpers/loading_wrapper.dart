import 'dart:async';

import 'package:dreamic/app/app_cubit.dart';
import 'package:dreamic/app/app_config_base.dart';
import 'package:dreamic/utils/get_it_utils.dart';
import 'package:dreamic/utils/logger.dart';

int _activeLoadingCallsCount = 0;

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
  bool isCompleted = false;
  bool loadingWasShown = false;
  Timer? timer;

  // Create timer with proper error handling
  timer = Timer(
    Duration(
      milliseconds: timeoutBeforeLoadingMill ?? AppConfigBase.timeoutBeforeShowingLoadingMill,
    ),
    () {
      try {
        // Double-check that the function hasn't completed yet
        if (!isCompleted) {
          loadingWasShown = true;
          _activeLoadingCallsCount++;
          logd('Loading started, active count: $_activeLoadingCallsCount');
          (onLoadingStart ?? _defaultLoadingStart)();
        }
      } catch (e) {
        loge('Error in loading start callback: $e');
      }
    },
  );

  try {
    final result = await fn();
    return result;
  } catch (error) {
    onError?.call(error);
    rethrow;
  } finally {
    // Mark as completed first to prevent race conditions
    isCompleted = true;

    // Cancel timer to prevent it from firing after completion
    timer.cancel();

    // Only decrement and potentially hide loading if we actually showed it
    if (loadingWasShown) {
      _activeLoadingCallsCount--;
      logd('Loading finished, active count: $_activeLoadingCallsCount');

      // Ensure counter doesn't go negative (defensive programming)
      if (_activeLoadingCallsCount < 0) {
        logw('Loading counter went negative, resetting to 0');
        _activeLoadingCallsCount = 0;
      }

      // Only call finish loading when this is the last active loading call
      if (_activeLoadingCallsCount == 0) {
        try {
          (onLoadingFinish ?? _defaultLoadingFinish)();
        } catch (e) {
          loge('Error in loading finish callback: $e');
        }
      }
    }
  }
}

/// Reset the loading state - useful for error recovery
void resetLoadingState() {
  logd('Resetting loading state, previous count: $_activeLoadingCallsCount');
  _activeLoadingCallsCount = 0;
  try {
    _defaultLoadingFinish();
  } catch (e) {
    loge('Error resetting loading state: $e');
  }
}

/// Get current active loading calls count - useful for debugging
int getActiveLoadingCallsCount() => _activeLoadingCallsCount;
