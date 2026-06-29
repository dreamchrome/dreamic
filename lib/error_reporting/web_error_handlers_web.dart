// Web-only error-handler module (ERH-015, ERH-010, ERH-035, ERH-037).
//
// Installs Dart `window.addEventListener('error', ...)` and
// `'unhandledrejection'` listeners so JavaScript errors that would otherwise be
// seen only by the JS SDK (`window.onerror`/`onunhandledrejection`) are routed
// through dreamic's single Dart error chokepoint — gaining Dart context, the
// re-entrancy guard, cross-surface dedup, redaction, and pre-attach buffering
// (BEH-1, BEH-5). This is the SOLE web capture surface under Path A′ (the JS SDK
// is disabled on web); the consumer's `main()` decides whether to call
// [installEarlyWebErrorHandlers] (gated by `kWebDartCapture` — Phase 6).
//
// Isolated behind a conditional import so VM/mobile never compile this
// `dart:js_interop` / `package:web` code (`web_error_handlers_stub.dart` is the
// no-op fallback).

import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'package:dreamic/app/helpers/app_errorhandling_init.dart';
import 'web_js_error.dart';

/// Minimal JS-interop view of a JavaScript `Error`-shaped object, used to read
/// the `message` / `name` / `stack` properties off `ErrorEvent.error` /
/// `PromiseRejectionEvent.reason` when they are real `Error`s. Every property is
/// nullable because the JS value may be a non-`Error` thrown value (a string, an
/// object literal, …) — `external` getters return `null`/undefined-coerced when
/// the property is absent.
extension type _JsError._(JSObject _) implements JSObject {
  external String? get message;
  external String? get name;
  external String? get stack;
}

/// Apply-once guard. `window.addEventListener` does NOT de-duplicate, and a web
/// hot-restart re-runs `main()` — without this guard the listeners would stack
/// and each JS error would report N times (ERH-035, mirrors
/// `_isolateErrorListenerAdded`). Module-level so it survives a hot-restart
/// re-run within the same web session.
bool _webErrorListenersInstalled = false;

/// Installs the apply-once `window` JS-error listeners. The consumer `main()`
/// calls this at boot-step-3 (only under Path A′). Idempotent: a second call is
/// a no-op.
void installEarlyWebErrorHandlers() {
  if (_webErrorListenersInstalled) {
    return;
  }
  _webErrorListenersInstalled = true;

  // 'error': synchronous JS errors reaching `window.onerror`.
  web.window.addEventListener(
    'error',
    ((web.ErrorEvent event) {
      _handleErrorEvent(event);
    }).toJS,
  );

  // 'unhandledrejection': rejected Promises with no handler.
  web.window.addEventListener(
    'unhandledrejection',
    ((web.PromiseRejectionEvent event) {
      _handleRejectionEvent(event);
    }).toJS,
  );
}

/// Non-throwing handler for a `window` `'error'` event. Serializes to a typed
/// [WebJsError] and routes through the chokepoint, then suppresses the browser's
/// default console handling so the Dart handler stays the sole web surface
/// (ERH-037).
void _handleErrorEvent(web.ErrorEvent event) {
  try {
    final webError = _toWebJsError(
      message: event.message,
      jsValue: event.error,
    );
    recordCapturedError(webError, webError.stack);
  } catch (e) {
    // Capture must never throw out of the JS event loop.
    debugPrint('Web error handler failed (suppressed): $e');
  } finally {
    // Suppress the browser's default `onerror` console handling — the app relies
    // on no browser-native default; the Dart handler is the sole web surface.
    try {
      event.preventDefault();
    } catch (_) {
      // Defensive: never let suppression failure escape.
    }
  }
}

/// Non-throwing handler for a `window` `'unhandledrejection'` event. The
/// rejection `reason` is any JS value; serialize it the same way.
void _handleRejectionEvent(web.PromiseRejectionEvent event) {
  try {
    final webError = _toWebJsError(
      message: null,
      jsValue: event.reason,
    );
    recordCapturedError(webError, webError.stack);
  } catch (e) {
    debugPrint('Web rejection handler failed (suppressed): $e');
  } finally {
    try {
      event.preventDefault();
    } catch (_) {
      // Defensive.
    }
  }
}

/// Serializes a JS error/value into a typed [WebJsError] (ERH-010):
///  - [message] preserved verbatim (for redaction) — the `ErrorEvent.message`
///    when present, else the JS `Error.message`, else the value's string form.
///  - `name` from the JS `Error.name` when available.
///  - `stack` parsed from the JS `Error.stack` via `StackTrace.fromString`, with
///    `StackTrace.current` as the fallback (for symbolication + dedup keying).
WebJsError _toWebJsError({
  required String? message,
  required JSAny? jsValue,
}) {
  String? jsMessage;
  String? jsName;
  String? jsStack;
  String? jsValueString;

  if (jsValue != null) {
    if (jsValue.isA<JSObject>()) {
      // A real Error-shaped object: read its props defensively (each getter
      // tolerates an absent property).
      final asError = jsValue as _JsError;
      jsMessage = asError.message;
      jsName = asError.name;
      jsStack = asError.stack;
    } else {
      // A non-Error thrown value (string, number, …): keep its string form.
      jsValueString = jsValue.dartify()?.toString();
    }
  }

  // Message: ErrorEvent.message > JS Error.message > the JS value's string form.
  final resolvedMessage = (message != null && message.isNotEmpty)
      ? message
      : (jsMessage != null && jsMessage.isNotEmpty)
          ? jsMessage
          : (jsValueString != null && jsValueString.isNotEmpty
              ? jsValueString
              : 'Unknown web error');

  final stack = (jsStack != null && jsStack.isNotEmpty)
      ? StackTrace.fromString(jsStack)
      : StackTrace.current;

  return WebJsError(resolvedMessage, jsName, stack);
}

/// Test-only seam (ERH-009): synthesizes the chokepoint routing a real web-JS
/// handler performs, BYPASSING `window`, so VM unit tests can cover the routing
/// without a browser. (Note: because it bypasses `window`, it cannot catch a
/// defect in the real `window`→[WebJsError] serialization — that needs an E2E
/// smoke, per the Testing strategy.)
@visibleForTesting
void simulateWebError(Object error, StackTrace? stack) {
  recordCapturedError(error, stack);
}
