import 'package:flutter/material.dart';
import 'package:dreamic/app/app_cubit.dart';
import 'package:dreamic/presentation/elements/toast.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ConnectionToaster extends StatelessWidget {
  const ConnectionToaster({
    super.key,
    required this.child,
    this.showOnInitialConnection = false,
    this.delayBeforeShowing = Duration.zero,
  });

  final Widget child;

  /// Whether to show the connecting toast during initial connection check
  /// (when transitioning from unknown to none). Defaults to false to avoid
  /// showing toast on every app resume.
  final bool showOnInitialConnection;

  /// Delay before showing the connecting toast. Gives time for quick
  /// reconnections to resolve without showing UI. Defaults to zero (immediate).
  /// Set to a longer duration (e.g., Duration(seconds: 1)) to prevent
  /// flashing toasts for brief connection checks.
  final Duration delayBeforeShowing;

  @override
  Widget build(BuildContext context) {
    return BlocListener<AppCubit, AppState>(
      listenWhen: (previous, current) => previous.networkStatus != current.networkStatus,
      listener: (context, state) {
        if (state.networkStatus == NetworkStatus.none) {
          // Check if we should show the toast
          // By default, only show if app has finished loading (not in initial startup)
          // This prevents intrusive toasts on every app resume
          final isAppLoaded = state.appStatus != AppStatus.loading;
          final shouldShowToast = showOnInitialConnection || isAppLoaded;

          if (shouldShowToast) {
            // Delay before showing to avoid flashing for quick reconnections
            Future.delayed(delayBeforeShowing, () {
              // Check if still disconnected after delay
              if (context.mounted) {
                final currentStatus = context.read<AppCubit>().state.networkStatus;
                if (currentStatus == NetworkStatus.none) {
                  ToastManager.showToast(
                    context,
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Connecting...',
                          style: TextStyle(
                            fontSize: 14,
                          ),
                        ),
                        SizedBox(width: 12),
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator.adaptive(
                            strokeWidth: 2,
                          ),
                        ),
                      ],
                    ),
                    autoDismiss: false,
                    replacePrevious: true,
                  );
                }
              }
            });
          }
        }
        if (state.networkStatus == NetworkStatus.connected) {
          ToastManager.removeToast();
        }
      },
      child: child,
    );
  }
}
