import 'dart:async';
import 'package:dreamic/utils/get_it_utils.dart';
import 'package:dreamic/data/repos/auth_service_int.dart';
import 'package:dreamic/utils/logger.dart';

/// Wraps a stream and automatically cancels it when the user signs out
class AuthAwareStreamSubscription<T> {
  final StreamSubscription<T> _subscription;
  final StreamSubscription<bool>? _authSubscription;

  AuthAwareStreamSubscription._(this._subscription, this._authSubscription);

  static AuthAwareStreamSubscription<T> listen<T>(
    Stream<T> stream,
    void Function(T event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final authService = g<AuthServiceInt>();
    StreamSubscription<bool>? authSubscription;

    final subscription = stream.listen(
      onData,
      onError: (error) {
        // Check if it's an auth error
        final errorString = error.toString().toLowerCase();
        if (errorString.contains('permission-denied') ||
            errorString.contains('unauthenticated') ||
            errorString.contains('unauthorized')) {
          // Silently ignore auth errors
          return;
        }
        onError?.call(error);
      },
      onDone: onDone,
      cancelOnError: cancelOnError,
    );

    // Listen to auth state changes
    authSubscription = authService.isLoggedInStream.listen((isLoggedIn) {
      if (!isLoggedIn) {
        logd('User logged out, cancelling stream subscription for stream type ${T.toString()}');
        subscription.cancel();
        authSubscription?.cancel();
      }
    });

    return AuthAwareStreamSubscription._(subscription, authSubscription);
  }

  Future<void> cancel() async {
    await _subscription.cancel();
    await _authSubscription?.cancel();
  }

  void pause([Future<void>? resumeSignal]) {
    _subscription.pause(resumeSignal);
  }

  void resume() {
    _subscription.resume();
  }

  bool get isPaused => _subscription.isPaused;
}
