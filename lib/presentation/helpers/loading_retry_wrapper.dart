import 'package:dreamic/presentation/helpers/loading_wrapper.dart';
import 'package:dreamic/utils/retry_it.dart';

Future<T> callWithLoadingAndRetry<T>(
  Future<T> Function() fn, {
  void Function(dynamic error)? onError,
  int? timeoutBeforeLoadingMill,
  int? maxAttempts,
}) async {
  return await callWithLoadingAfterTimeout(
    () => retryIt(fn, maxAttempts: maxAttempts),
    onError: onError,
    timeoutBeforeLoadingMill: timeoutBeforeLoadingMill,
  );
}
