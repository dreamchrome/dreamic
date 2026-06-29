// VM / mobile no-op stub for the web-JS error-handler module.
//
// The real implementation lives in `web_error_handlers_web.dart` and uses
// `dart:js_interop` + `package:web`, which cannot compile on non-web targets. A
// runtime `if (kIsWeb)` does NOT prevent compile-time symbol resolution, so the
// js_interop code is isolated behind a conditional import
// (`import 'web_error_handlers_stub.dart' if (dart.library.js_interop)
// 'web_error_handlers_web.dart'`) and this stub keeps VM/mobile builds
// compiling (ERH-015).

import 'package:flutter/foundation.dart';

import 'package:dreamic/app/helpers/app_errorhandling_init.dart';

/// No-op on non-web targets. (On web this installs the apply-once
/// `window.addEventListener('error' | 'unhandledrejection')` handlers.)
void installEarlyWebErrorHandlers() {
  // Intentionally empty: there is no `window` on VM/mobile.
}

/// Test-only seam (ERH-009): routes a synthesized `(error, stack)` through the
/// chokepoint exactly as a real web-JS handler would, BYPASSING `window`, so a
/// VM unit test (which resolves this stub via the conditional import) can cover
/// the routing without a browser. The web library's copy does the same against a
/// real `WebJsError`. (Because it bypasses `window`, it cannot catch a defect in
/// the real `window`→`WebJsError` serialization — that needs an E2E smoke.)
@visibleForTesting
void simulateWebError(Object error, StackTrace? stack) {
  recordCapturedError(error, stack);
}
