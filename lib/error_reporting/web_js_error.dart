/// A web JavaScript error serialized into a typed, platform-agnostic Dart object
/// (ERH-010).
///
/// Lives in its own (non-`js_interop`) file so it compiles on **all** targets —
/// the web handler module (`web_error_handlers_web.dart`) constructs it from a
/// real `ErrorEvent`/`PromiseRejectionEvent`, while VM/mobile tests can
/// reference the type directly.
///
/// Fidelity is load-bearing for two downstream consumers:
///  - **Redaction** operates on [message], so it is preserved **verbatim** (the
///    JS `error.message` / `ErrorEvent.message`).
///  - **Dedup + cloud symbolication** key on [stack], which the handler parses
///    from the JS `error.stack` via `StackTrace.fromString` (falling back to
///    `StackTrace.current` when the JS value carries no stack).
class WebJsError {
  const WebJsError(this.message, this.name, this.stack);

  /// The JS error message, preserved verbatim for redaction.
  final String message;

  /// The JS `Error.name` (e.g. `NotAllowedError`, `TypeError`) when available.
  final String? name;

  /// The parsed JS stack (`StackTrace.fromString(error.stack)`), or
  /// `StackTrace.current` when the JS value carried no stack.
  final StackTrace stack;

  @override
  String toString() =>
      name == null ? message : '$name: $message';
}
