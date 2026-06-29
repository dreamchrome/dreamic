import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:dreamic/app/helpers/app_errorhandling_init.dart';

// Conditional import of the web-JS handler module so VM/mobile compile against
// the no-op stub and web compiles against the `dart:js_interop` implementation
// (ERH-015). The `installEarlyWebErrorHandlers` / `simulateWebError` symbols are
// re-exposed via the static methods below.
import 'web_error_handlers_stub.dart'
    if (dart.library.js_interop) 'web_error_handlers_web.dart' as web_handlers;

/// Public, backend-agnostic entry points for dreamic's error-capture surfaces
/// (ERH-001).
///
/// The internal chokepoint (`_recordErrorSafe`) stays private; this facade is
/// the public production surface a consumer `main()` wires up:
///  - [runGuarded] — the lifelong, outermost `runZonedGuarded` wrap around
///    `runApp` (BEH-1).
///  - [recordZoneError] — the public record entry the zone's `onError` (and the
///    web-JS handlers) route through.
///  - [installEarlyWebErrorHandlers] — the apply-once web `window` JS-error
///    listener install (no-op on VM/mobile via the conditional import).
abstract final class DreamicErrorHandling {
  /// Wraps [body] (typically `() => runApp(...)`) in a lifelong, outermost
  /// `runZonedGuarded` so EVERY uncaught async error in the app surfaces through
  /// [onError] — which should forward to [recordZoneError] (ERH-001 / BEH-1).
  ///
  /// Call this from `main()` AFTER `installEarlyErrorHandlers()` →
  /// (Path A′ only) [installEarlyWebErrorHandlers] → `configureErrorReporting()`.
  ///
  /// [onError] defaults to [recordZoneError] when omitted, so the common case is
  /// just `DreamicErrorHandling.runGuarded(() => runApp(...))`. A custom
  /// [onError] (e.g. to add app-specific logging) should still forward to
  /// [recordZoneError] so the error reaches the chokepoint.
  static void runGuarded(
    void Function() body, [
    void Function(Object error, StackTrace stackTrace)? onError,
  ]) {
    runZonedGuarded(
      body,
      onError ?? recordZoneError,
    );
  }

  /// Public production entry into the single error chokepoint, used by the
  /// guarded zone's `onError` (ERH-001). Forwards into the private
  /// `_recordErrorSafe` (re-entrancy guard + cross-surface dedup + redaction +
  /// pre-attach buffering). Non-throwing.
  static void recordZoneError(Object error, StackTrace stackTrace) {
    recordCapturedError(error, stackTrace);
  }

  /// Installs the apply-once web `window` `'error'`/`'unhandledrejection'`
  /// listeners (the sole web capture surface under Path A′). No-op on VM/mobile
  /// via the conditional import. The consumer `main()` calls this at boot-step-3
  /// only under Path A′ (`kWebDartCapture` — Phase 6).
  static void installEarlyWebErrorHandlers() {
    web_handlers.installEarlyWebErrorHandlers();
  }

  /// Test-only seam (ERH-009): routes a synthesized web error through the
  /// chokepoint exactly as a real `window` JS-error handler would, bypassing
  /// `window`, so the routing is unit-testable on the VM. On VM/mobile this
  /// resolves the stub (which also routes through the chokepoint); on web it
  /// resolves the web library's copy.
  @visibleForTesting
  static void simulateWebError(Object error, StackTrace? stack) {
    // The underlying module fn is itself @visibleForTesting; this facade member
    // is the @visibleForTesting public seam, so forwarding is intended.
    // ignore: invalid_use_of_visible_for_testing_member
    web_handlers.simulateWebError(error, stack);
  }
}
