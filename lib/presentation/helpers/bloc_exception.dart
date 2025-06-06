abstract class BlocException implements Exception {
  final String? message;
  BlocException([this.message]);

  @override
  String toString() => 'BlocException: ${message ?? 'An unknown error occurred'}';
}

class BlocRetryableException extends BlocException {
  BlocRetryableException([super.message]);

  @override
  String toString() =>
      'BlocRetryableException: ${message ?? 'An unknown retryable error occurred'}';
}

class BlocFatalException extends BlocException {
  BlocFatalException([super.message]);

  @override
  String toString() => 'BlocFatalException: ${message ?? 'An unknown fatal error occurred'}';
}
