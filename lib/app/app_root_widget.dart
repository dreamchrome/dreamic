import 'package:flutter/material.dart';
import 'package:dreamic/app/app_cubit.dart';
import 'package:dreamic/presentation/elements/loading_indicator.dart';
import 'package:dreamic/utils/logger.dart';
import 'package:dreamic/presentation/elements/error_message_widget.dart';
import 'package:dreamic/presentation/elements/overlay_submitting_widget.dart';
import 'package:dreamic/presentation/elements/overlay_progress.dart';
import 'package:dreamic/presentation/elements/app_update_widgets.dart';
import 'package:dreamic/presentation/elements/connection_toaster.dart';
import 'package:dreamic/presentation/network_error_widget.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

class AppRootWidget extends StatelessWidget {
  const AppRootWidget({
    super.key,
    this.errorMessageWidgetBuilder,
    this.useConnectionToaster = false,
    this.showConnectionToastOnInitialConnection = false,
    this.connectionToastDelay = Duration.zero,
    required this.child,
  });

  final Widget child;
  final WidgetBuilder? errorMessageWidgetBuilder;

  /// Whether to use the built-in ConnectionToaster for network status updates.
  /// Defaults to false for backward compatibility.
  final bool useConnectionToaster;

  /// Whether to show connection toast during initial app load/resume.
  /// When false (default), toasts only appear for connection losses during normal usage.
  /// This prevents intrusive "Connecting..." messages on every app resume.
  final bool showConnectionToastOnInitialConnection;

  /// Delay before showing the connection toast. Allows quick reconnections
  /// to complete without showing UI. Defaults to zero (immediate).
  /// Set to a longer duration (e.g., Duration(seconds: 1)) to prevent
  /// flashing toasts for brief connection checks.
  final Duration connectionToastDelay;

  @override
  Widget build(BuildContext context) {
    return Material(
      // Wrap with Overlay to provide an overlay for toasts and other overlays
      // This ensures ConnectionToaster can show toasts regardless of where
      // the MaterialApp's Navigator/Overlay is in the widget tree
      child: Overlay(
        initialEntries: [
          OverlayEntry(
            builder: (context) => BlocProvider<AppCubit>.value(
              // create: (context) => GetIt.I.get<AppCubit>(),
              value: GetIt.I.get<AppCubit>()..getInitialData(),
              // child: child,
              child: Builder(
                builder: (context) {
                  return _buildAppContent(
                    context,
                    enableConnectionToaster: useConnectionToaster,
                    showConnectionToastOnInitialConnection:
                        showConnectionToastOnInitialConnection,
                    connectionToastDelay: connectionToastDelay,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppContent(
    BuildContext context, {
    required bool enableConnectionToaster,
    required bool showConnectionToastOnInitialConnection,
    required Duration connectionToastDelay,
  }) {
    return BlocBuilder<AppCubit, AppState>(
      buildWhen: (previous, current) =>
          previous.appStatus != current.appStatus ||
          previous.overlayFullScreenChildCount != current.overlayFullScreenChildCount ||
          previous.showVersionUpdateBanner != current.showVersionUpdateBanner ||
          previous.versionUpdateInfo != current.versionUpdateInfo,
      builder: (context, state) {
        // logd(
        //     '🏠 AppRootWidget BlocBuilder - Status: ${state.appStatus}, ShowBanner: ${state.showVersionUpdateBanner}, HasUpdateInfo: ${state.versionUpdateInfo != null}');

        if (state.versionUpdateInfo != null) {
          // logd(
          //     '📋 Update info details - Type: ${state.versionUpdateInfo!.updateType}, Current: ${state.versionUpdateInfo!.currentVersion}, Target: ${state.versionUpdateInfo!.targetVersion}');
        }

        switch (state.appStatus) {
          case AppStatus.loading:
            return const Center(
                child: LoadingIndicator(
              radius: 40,
            ));
          case AppStatus.updateRequired:
            // Show update dialog for required updates
            return state.versionUpdateInfo != null
                ? AppUpdateDialog(
                    updateInfo: state.versionUpdateInfo!,
                  )
                // : const LoadingIndicator();
                : const ErrorMessageWidget(
                    errorMessage: 'Update required but no version info available',
                  );
          case AppStatus.overlayLoading:
          case AppStatus.overlayProgressing:
          case AppStatus.overlyFullScreen:
          case AppStatus.normal:
            // Allows virtual keyboard to be dismissed by tapping anywhere on screen
            return GestureDetector(
              onTap: () {
                // logd('Unfocused in AppRootWidget.');
                FocusManager.instance.primaryFocus?.unfocus();
              },
              child: Stack(
                children: [
                  // ConnectionToaster wraps child if enabled
                  // The Overlay widget above provides the overlay for toasts
                  if (enableConnectionToaster)
                    ConnectionToaster(
                      showOnInitialConnection: showConnectionToastOnInitialConnection,
                      delayBeforeShowing: connectionToastDelay,
                      child: child,
                    )
                  else
                    child,
                  // Version update banner overlay
                  if (state.showVersionUpdateBanner && state.versionUpdateInfo != null) ...[
                    Builder(builder: (context) {
                      logd(
                          '🏷️ Showing version update banner for ${state.versionUpdateInfo!.updateType} update');
                      return Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: AppUpdateBanner(
                          updateInfo: state.versionUpdateInfo!,
                          onDismiss: () {
                            logd('🙈 User dismissed version update banner');
                            context.read<AppCubit>().dismissVersionUpdateBanner();
                          },
                        ),
                      );
                    }),
                  ] else ...[
                    if (state.versionUpdateInfo != null)
                      Builder(builder: (context) {
                        // logd(
                        //     '❌ Not showing banner - showVersionUpdateBanner: ${state.showVersionUpdateBanner}, updateInfo exists: ${state.versionUpdateInfo != null}');
                        return const SizedBox.shrink();
                      })
                    else
                      const SizedBox.shrink(),
                  ],
                  // The loading overlays
                  // AnimatedSwitcher(
                  // duration: const Duration(milliseconds: 220),
                  // duration: const Duration(milliseconds: 0),
                  // child:
                  state.appStatus == AppStatus.overlayLoading
                      ? const OverlaySubmitting()
                      : state.appStatus == AppStatus.overlayProgressing
                          ? OverlayProgress(
                              headerText: state.progressHeaderText,
                            )
                          : state.appStatus == AppStatus.overlyFullScreen
                              ? state.overlayFullScreenChild == null ||
                                      state.overlayFullScreenChild!.isEmpty
                                  ? Container()
                                  : Stack(
                                      children:
                                          state.overlayFullScreenChild!.map((e) => e()).toList(),
                                    )
                              : Container(),
                  // ),
                ],
              ),
            );
          case AppStatus.networkError:
            return NetworkErrorWidget(
              message: state.networkErrorMessage,
              showRetry: state.showNetworkRetry,
            );
          case AppStatus.error:
            return errorMessageWidgetBuilder?.call(context) ?? const ErrorMessageWidget();
        }
      },
    );
  }
}
