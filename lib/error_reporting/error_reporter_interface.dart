import 'package:flutter/foundation.dart';

/// Interface for an external error-reporting backend.
///
/// dreamic is **backend-agnostic**: it ships no concrete reporter and depends on
/// no specific crash-reporting SDK. To report errors, implement this in your app
/// (or copy a ready-made template — e.g. the Crashlytics / Sentry reporters in
/// the docs), then register it via `configureErrorReporting(...)` before
/// `dreamicBootstrap()` runs `appInitErrorHandling()`. Every signal dreamic
/// produces — uncaught Flutter/platform/isolate errors, `loge()` calls, the
/// early-error buffer, bootstrap diagnostics, and breadcrumbs — is routed to the
/// **one** registered reporter.
///
/// **Extend, don't implement.** [recordError] is the only required member;
/// [initialize], [recordFlutterError], [addBreadcrumb], [setUser] and [clearUser]
/// have sensible default bodies, so `extends ErrorReporter` lets a minimal
/// reporter override just what it supports. (`implements ErrorReporter` forces
/// you to supply all six.)
///
/// ## Canonical examples + sync (ERH-024, ERH-025)
///
/// The **canonical reporter references** are the COMMENTED examples in
/// `error_reporter_example.dart` (beside this file) — Sentry, Crashlytics, and a
/// Sentry+Crashlytics [CompositeErrorReporter], each carrying the full hardening
/// (`maxBreadcrumbs = 250`, `beforeBreadcrumb`/`beforeSend` redaction safety net,
/// the Sentry-side `LogLevel`→`SentryLevel` map, and the Path-A′ web-capture
/// config). Copy/reconcile your reporter against them. The dreamic-dev
/// `scaffolding/app/template_*_error_reporter.dart` files are retired and point
/// here. Reporters stay in sync with the canonical example via the dreamic
/// **`CHANGELOG.md`** version-bump entry (which lists every contract change with
/// per-backend migration steps) — there is **no automated parity test**.
///
/// ## Load-bearing rules (ERH-020, ERH-025)
///
///  - **All breadcrumbs flow through `Logger.breadcrumb()` / `logBreadcrumb()`**
///    — never `Sentry.addBreadcrumb()` (or any SDK breadcrumb API) directly. The
///    `Logger` applies the `breadcrumbLevel` gate + central fail-closed redaction
///    before forwarding here; a direct SDK call bypasses both (only the SDK's own
///    `beforeBreadcrumb` net can then catch it). This is the redaction ingress
///    contract.
///  - **`main()` wraps `runApp` in `DreamicErrorHandling.runGuarded(...)`** — the
///    lifelong, outermost guarded zone, so every uncaught async error reaches the
///    chokepoint (boot order: `installEarlyErrorHandlers()` → (Path A′ only)
///    `DreamicErrorHandling.installEarlyWebErrorHandlers()` →
///    `configureErrorReporting()` → `runGuarded(() => runApp(...))`).
///  - **Wakelock is mobile-only** — dreamic guards `WakelockPlus.enable()` with
///    `!kIsWeb` for you (it is never requested on web), so no reporter wiring is
///    needed; just don't re-enable it on web.
///  - Every override here must be **non-throwing** (failures are swallowed so the
///    capture path never crashes the app — BEH-11).
///
/// Example (Sentry — abbreviated; the full hardened version is the canonical
/// commented example in `error_reporter_example.dart`):
/// ```dart
/// class SentryErrorReporter extends ErrorReporter {
///   @override
///   Future<void> initialize() async {
///     await SentryFlutter.init((o) => o.dsn = 'your-dsn');
///   }
///
///   @override
///   void recordError(Object error, StackTrace? stackTrace) =>
///       Sentry.captureException(error, stackTrace: stackTrace);
///
///   @override
///   void addBreadcrumb(String message, {String? category, Map<String, dynamic>? data}) =>
///       Sentry.addBreadcrumb(Breadcrumb(message: message, category: category, data: data));
///
///   @override
///   void setUser(String userId, {String? email, String? username}) =>
///       Sentry.configureScope((s) => s.setUser(SentryUser(id: userId, email: email, username: username)));
///
///   @override
///   void clearUser() => Sentry.configureScope((s) => s.setUser(null));
/// }
/// ```
abstract class ErrorReporter {
  /// Initialize the reporting backend. Called once by `appInitErrorHandling()`
  /// when the reporter attaches. Default is a no-op — override if your SDK needs
  /// async setup (and leave it empty when the SDK is initialized elsewhere, e.g.
  /// `SentryFlutter.init` with `appRunner`).
  Future<void> initialize() async {}

  /// Record a generic error with an optional stack trace. The one required
  /// member — every other method has a default.
  void recordError(Object error, StackTrace? stackTrace);

  /// Record a Flutter-framework error. Defaults to forwarding to [recordError]
  /// with the details' exception and stack; override if your SDK has a richer
  /// Flutter-specific capture.
  void recordFlutterError(FlutterErrorDetails details) =>
      recordError(details.exception, details.stack);

  /// Record a breadcrumb — a trail event attached to the next captured error for
  /// context (e.g. the bootstrap / Firebase-init sequence before a startup-hang
  /// report). dreamic emits breadcrumbs internally and via `logBreadcrumb(...)`.
  /// Default no-op; override to forward to your backend (e.g.
  /// `Sentry.addBreadcrumb`, `FirebaseCrashlytics.instance.log`). Must be
  /// non-throwing.
  void addBreadcrumb(String message, {String? category, Map<String, dynamic>? data}) {}

  /// Set the current user for subsequent reports. Default no-op; override to
  /// forward to your backend. Wire from your auth-lifecycle callbacks (see the
  /// error-reporting guide). Must be non-throwing.
  void setUser(String userId, {String? email, String? username}) {}

  /// Clear the current user (e.g. on logout). Default no-op; override to forward
  /// to your backend. Must be non-throwing.
  void clearUser() {}
}

/// Configuration for error reporting.
///
/// dreamic has no built-in reporter, so reporting is active only when
/// [customReporter] is supplied. Pass this to `configureErrorReporting(...)`
/// before `dreamicBootstrap()`.
class ErrorReportingConfig {
  /// The reporting backend (e.g. a Crashlytics or Sentry reporter). `null`
  /// (the default) means **no error reporting** — dreamic logs to the console
  /// only.
  final ErrorReporter? customReporter;

  /// Whether to report errors in debug mode (default `false`).
  final bool enableInDebug;

  /// Whether to report errors on web (default `false`).
  final bool enableOnWeb;

  /// Whether the reporter installs its **own** Flutter/platform error handlers
  /// (e.g. Sentry via `SentryFlutter.init` with `appRunner`). When `true`,
  /// dreamic does not install duplicate handlers — it still wires `loge()` to the
  /// reporter and flushes the early buffer.
  final bool customReporterManagesErrorHandlers;

  /// Whether [customReporter] requires Firebase to be initialized before it can
  /// attach (e.g. a Firebase Crashlytics reporter). Default `false` (a
  /// self-contained reporter such as Sentry). This is the **only** input to the
  /// default `attachErrorReportingFirst` derivation: a self-contained reporter
  /// attaches **before** Firebase (maximal startup coverage), while a
  /// Firebase-dependent reporter attaches **after** Firebase. Set `true` for a
  /// Crashlytics reporter.
  final bool reporterRequiresFirebase;

  const ErrorReportingConfig({
    this.customReporter,
    this.enableInDebug = false,
    this.enableOnWeb = false,
    this.customReporterManagesErrorHandlers = false,
    this.reporterRequiresFirebase = false,
  });

  /// Configuration for a single reporter.
  ///
  /// Set [managesOwnErrorHandlers] `true` if the reporter installs its own error
  /// handlers (e.g. `SentryFlutter.init` with `appRunner`). Set
  /// [requiresFirebase] `true` for a reporter that needs Firebase first (e.g.
  /// Crashlytics) so it attaches after Firebase init.
  const ErrorReportingConfig.customOnly({
    required ErrorReporter reporter,
    bool enableInDebug = false,
    bool enableOnWeb = true,
    bool managesOwnErrorHandlers = false,
    bool requiresFirebase = false,
  }) : this(
          customReporter: reporter,
          enableInDebug: enableInDebug,
          enableOnWeb: enableOnWeb,
          customReporterManagesErrorHandlers: managesOwnErrorHandlers,
          reporterRequiresFirebase: requiresFirebase,
        );
}
