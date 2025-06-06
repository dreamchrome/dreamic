import 'dart:async';

import 'package:exponential_back_off/exponential_back_off.dart';
import 'package:dreamic/app/app_config_base.dart';
import 'package:dreamic/utils/logger.dart';
// import 'package:retry/retry.dart';

Future<T> retryIt<T>(
  Future<T> Function() fn, {
  int? maxAttempts,
}) async {
  maxAttempts ??= AppConfigBase.retryAttemptsCountMax;

  final exponentialBackOff = ExponentialBackOff(
    maxAttempts: maxAttempts,
    // interval: Duration(seconds: 1),
    // maxRandomizationFactor: 0.0,
    // maxDelay: Duration(seconds: 10),
  );

  final result = await exponentialBackOff.start<T>(
    () async => await fn.call(),
    retryIf: (e) => true,
    onRetry: (error) {
      logd(
          '-------------------------------------------------------- retryIt attempt: ${exponentialBackOff.attemptCounter}');
      logd('error: $error');
    },
  );

  final returnVal = result.fold(
    (error) {
      logd('-------------------------------------------------------- retryIt error: $error');
      throw error;
    },
    // (value) {
    //   // logd('-------------------------------------------------------- retryIt value: $value');
    //   return value;
    // },
    (value) => value,
  );

  // throw Exception('retryIt failed to process fold with result: $result');

  return returnVal;

  // var retryOptions = RetryOptions(
  //   maxAttempts: maxAttempts,
  // );

  // T returnVal;

  // logd('Retrying with maxAttempts: $maxAttempts');

  // try {
  //   returnVal = await retryOptions.retry<T>(
  //     () async {
  //       try {
  //         return await fn();
  //       } catch (e) {
  //         logd('--------------------exception in retryIt... ${e.toString()}');
  //         rethrow;
  //       }
  //     },
  //     onRetry: (e) => logd('--------------------retrying... ${e.toString()}'),
  //     retryIf: (p0) => true,
  //   );
  // } finally {}

  // return returnVal;
}
