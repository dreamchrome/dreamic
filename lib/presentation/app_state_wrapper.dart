import 'package:flutter/material.dart';
import 'package:dreamic/presentation/elements/loading_indicator.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../app/app_cubit.dart';
import 'network_error_widget.dart';

class AppStateWrapper extends StatelessWidget {
  final Widget child;

  const AppStateWrapper({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppCubit, AppState>(
      builder: (context, state) {
        switch (state.appStatus) {
          case AppStatus.loading:
            return const LoadingIndicator();

          case AppStatus.networkError:
            return NetworkErrorWidget(
              message: state.networkErrorMessage,
              showRetry: state.showNetworkRetry,
            );

          case AppStatus.error:
            return Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 80,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Something went wrong',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    if (state.networkErrorMessage.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        state.networkErrorMessage,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            );

          default:
            return child;
        }
      },
    );
  }
}
