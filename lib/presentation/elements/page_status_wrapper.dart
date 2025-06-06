import 'package:flutter/material.dart';
import 'package:dreamic/presentation/elements/error_message_widget.dart';
import 'package:dreamic/presentation/elements/loading_indicator.dart';
import 'package:dreamic/presentation/helpers/cubit_base.dart';
import 'package:dreamic/presentation/helpers/page_statuses.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class PageStatusWrapper<T extends CubitBase<S>, S extends CubitBaseState> extends StatelessWidget {
  const PageStatusWrapper({
    super.key,
    required this.child,
    required this.cubitFactory,
  });

  final Widget child;
  final T Function() cubitFactory;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => cubitFactory(),
      child: child,
    );
  }
}

class PageStatusBodyWrapper<T extends CubitBase<S>, S extends CubitBaseState>
    extends StatelessWidget {
  const PageStatusBodyWrapper({
    super.key,
    required this.loadedChildBuilder,
    this.errorChildBuilder,
    this.loadingChildBuilder,
  });

  final Widget Function(BuildContext, S) loadedChildBuilder;
  final Widget Function(BuildContext, S)? errorChildBuilder;
  final Widget Function(BuildContext, S)? loadingChildBuilder;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<T, S>(
      buildWhen: (previous, current) => previous.pageStatus != current.pageStatus,
      builder: (context, state) {
        switch (state.pageStatus) {
          case PageStatus.loading:
          case PageStatus.processingAction:
            return loadingChildBuilder?.call(context, state) ??
                const Center(child: LoadingIndicator());
          case PageStatus.error:
            return errorChildBuilder?.call(context, state) ?? const ErrorMessageWidget();
          case PageStatus.empty:
          case PageStatus.loaded:
          //TODO: Handle errorRetryable better
          case PageStatus.errorRetryable:
            return loadedChildBuilder(context, state);
          // default:
          //   return const Center(child: LoadingIndicator());
        }
      },
    );
  }
}
