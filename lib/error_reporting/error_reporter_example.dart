// ignore_for_file: unused_import

/// CANONICAL error-reporter examples for dreamic — the single source of truth.
///
/// Dreamic is **backend-agnostic** — it ships no concrete reporter and depends
/// on no crash-reporting SDK. To report errors you implement [ErrorReporter] in
/// your app and register it. These COMMENTED examples are the canonical
/// references every consumer copies/reconciles against; the dreamic-dev
/// `scaffolding/app/template_*_error_reporter.dart` files are retired and point
/// here (ERH-024). Consumers self-sync against the dreamic `CHANGELOG.md`
/// version-bump entry — there is **no automated parity test** (ERH-025).
///
/// All backend imports are kept **commented** so dreamic-public stays
/// dependency-free (no Sentry/Crashlytics/Firebase dependency is added here).
///
/// What each canonical reporter must carry (the full hardening of this package's
/// error-reporting contract — see the `ErrorReporter` docstring + CHANGELOG):
///  - **Full parity:** override `recordError`, `recordFlutterError`,
///    `addBreadcrumb`, `setUser`, and `clearUser` (extend, not implement, so a
///    backend without one of these can omit it).
///  - **`maxBreadcrumbs = 250` on ALL platforms** (Sentry) so verbose `logd`
///    volume does not evict the high-signal info/warn/error trail. Measure
///    against the ~1 MB per-event payload limit at `breadcrumbLevel = debug`;
///    lower (e.g. 150) if a realistic verbose event approaches it (BEH-10).
///  - **A `beforeBreadcrumb` / `beforeSend` redaction safety net** (Sentry) for
///    SDK-auto / web-JS breadcrumbs that bypass `Logger.breadcrumb()`'s central
///    redaction. dreamic's `Logger` redacts everything routed through it; this
///    is the second layer for what isn't (BEH-8).
///  - **The `LogLevel`→`SentryLevel` map IN THE SENTRY EXAMPLE ONLY** (ERH-026)
///    — it is Sentry-specific and must NOT live in dreamic-public (which has no
///    Sentry type). dreamic-public gating uses `LogLevel` only.
///  - **The spike-gated web-capture config** — Path A′ (the recorded decision,
///    see the Sentry example): `options.autoInitializeNativeSdk = false` PLUS an
///    explicit `options.transport = HttpTransport(...)` on web. Do NOT attempt
///    the infeasible `globalHandlersIntegration` exclusion (ERH-042 / ERH-002
///    superseded).
///
/// **The load-bearing rules** (also in the `ErrorReporter` contract docstring +
/// CHANGELOG):
///  - All breadcrumbs flow through `Logger.breadcrumb()` (never
///    `Sentry.addBreadcrumb()` directly) — the central-redaction ingress
///    contract (ERH-020).
///  - `main()` wraps `runApp` in `DreamicErrorHandling.runGuarded(...)`, and calls
///    `WidgetsFlutterBinding.ensureInitialized()` as the FIRST line INSIDE that
///    zone — never above it. The binding must be initialized in the SAME zone
///    `runApp` runs in, or Flutter logs a "Zone mismatch" warning (runGuarded forks
///    a child `runZonedGuarded` zone). See the canonical mains below.
///  - Wakelock is mobile-only (dreamic guards it `!kIsWeb` for you).
library;

import 'package:dreamic/error_reporting/composite_error_reporter.dart';
import 'package:dreamic/error_reporting/error_reporter_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
// import 'package:sentry_flutter/sentry_flutter.dart'; // add to YOUR pubspec.yaml
// import 'package:firebase_crashlytics/firebase_crashlytics.dart'; // add to YOUR pubspec.yaml
//
// Path-A′ web capture needs the explicit transport, which `package:sentry`
// does NOT export (only the abstract `Transport`). Import the implementation:
// import 'package:sentry/src/transport/http_transport.dart'; // ignore: implementation_imports
// import 'package:sentry/src/transport/rate_limiter.dart';   // ignore: implementation_imports
// (Stable for the pinned sentry_flutter 9.22.0 — re-verify on any bump; or wrap
// a small custom public `Transport`.) See the Sentry `initialize()` below.

// ===========================================================================
// CANONICAL 1 — Sentry (self-contained: needs no Firebase; works on web).
// ===========================================================================
//
// ```dart
// class SentryErrorReporter extends ErrorReporter {
//   SentryErrorReporter({required this.dsn});
//   final String dsn;
//
//   @override
//   Future<void> initialize() async {
//     await SentryFlutter.init((options) {
//       options.dsn = dsn;
//       options.environment = AppConfigBase.environmentType.value;
//       options.release = await AppConfigBase.getReleaseId();
//
//       // maxBreadcrumbs = 250 on ALL platforms (Part 3.3 / BEH-10): keep the
//       // high-signal trail from being evicted by verbose logd volume. Measure
//       // against Sentry's ~1 MB per-event limit at breadcrumbLevel=debug;
//       // lower (e.g. 150) if a realistic verbose event approaches it.
//       options.maxBreadcrumbs = 250;
//
//       // dreamic owns the error handlers — do NOT use SentryFlutter.init's
//       // `appRunner`. main() wraps runApp in DreamicErrorHandling.runGuarded
//       // and registers this reporter with managesOwnErrorHandlers: false.
//
//       // --- redaction SAFETY NET (BEH-8) ---
//       // dreamic's Logger centrally redacts everything routed through
//       // Logger.breadcrumb() / the error chokepoint (fail-closed). These nets
//       // cover SDK-auto + web-JS-layer signals that bypass those Dart hooks.
//       options.beforeBreadcrumb = (crumb, hint) => _redactCrumb(crumb);
//       options.beforeSend = (event, hint) => _redactEvent(event);
//
//       // --- WEB CAPTURE: Path A′ (recorded spike decision, ERH-042/048) ---
//       // On web, disable the JS SDK and let the Dart web-JS handler (installed
//       // by main()'s installEarlyWebErrorHandlers()) be the SOLE web surface,
//       // so web errors gain Dart context + breadcrumbs + redaction + dedup +
//       // exactly-once (BEH-1/5/8/9 on web).
//       //
//       // The flag ALONE silently drops all web events — you MUST also assign an
//       // explicit transport (the flag forces a now-inert JS-bound transport).
//       if (kIsWeb) {
//         options.autoInitializeNativeSdk = false;
//         options.transport = HttpTransport(options, RateLimiter(options));
//       }
//       // Mobile is unaffected: the native SDK + full hardening apply.
//       //
//       // NOTE: this whole web block is gated by the consumer's build-time
//       // `kWebDartCapture` constant, which ALSO gates main()'s
//       // installEarlyWebErrorHandlers() call — so the two can never disagree
//       // (a mismatch would double-report, caught only at BEH-9 test time).
//       // Under Path C (kWebDartCapture=false) you would OMIT this web block and
//       // keep the JS SDK as the web surface; do NOT do both.
//     });
//   }
//
//   @override
//   void recordError(Object error, StackTrace? stackTrace) =>
//       Sentry.captureException(error, stackTrace: stackTrace);
//
//   @override
//   void recordFlutterError(FlutterErrorDetails details) =>
//       Sentry.captureException(details.exception, stackTrace: details.stack);
//
//   @override
//   void addBreadcrumb(String message, {String? category, Map<String, dynamic>? data}) =>
//       Sentry.addBreadcrumb(Breadcrumb(message: message, category: category, data: data));
//
//   @override
//   void setUser(String userId, {String? email, String? username}) =>
//       Sentry.configureScope(
//         (scope) => scope.setUser(SentryUser(id: userId, email: email, username: username)),
//       );
//
//   @override
//   void clearUser() => Sentry.configureScope((scope) => scope.setUser(null));
// }
//
// // The LogLevel→SentryLevel map lives HERE (Sentry-side) — never in
// // dreamic-public, which has no SentryLevel type (ERH-026). Use it wherever you
// // forward a breadcrumb's LogLevel to Sentry.
// SentryLevel sentryLevelFor(LogLevel level) => switch (level) {
//       LogLevel.debugVerbose => SentryLevel.debug,
//       LogLevel.debug => SentryLevel.debug,
//       LogLevel.info => SentryLevel.info,
//       LogLevel.warn => SentryLevel.warning,
//       LogLevel.error => SentryLevel.error,
//     };
//
// // beforeBreadcrumb / beforeSend safety-net redactors (mirror Logger's v1 set:
// // oobCode, Bearer/token, email-in-URL). Apply to message + data values.
// Breadcrumb? _redactCrumb(Breadcrumb? crumb, ...) { /* scrub + return */ }
// SentryEvent? _redactEvent(SentryEvent event, ...) { /* scrub + return */ }
// ```
//
/// RECOMMENDED main() — dreamic owns the handlers; main() wraps runApp in the
/// guarded zone and (Path A′) installs the early web-JS handlers.
void exampleMainSentry() async {
  /*
  // The guarded zone is the OUTERMOST thing in main(). All boot steps — STARTING
  // with WidgetsFlutterBinding.ensureInitialized() — run INSIDE it: the binding
  // must be initialized in the SAME zone runApp runs in (runGuarded forks a child
  // runZonedGuarded zone, and Flutter logs a "Zone mismatch" warning if
  // ensureInitialized() ran in a different zone). Running the rest of boot in-zone
  // also routes any setup-time error through the chokepoint. (If your pre-runApp
  // setup needs an `await`, make the body `() async { ... }` — the future is
  // fire-and-forget and the zone still owns its errors.)
  DreamicErrorHandling.runGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();   // boot step 1 (FIRST, in-zone)
    installEarlyErrorHandlers();                 // boot step 2

    // boot step 3 — Path A′ ONLY (gated by the consumer's kWebDartCapture):
    // install the Dart window 'error'/'unhandledrejection' listeners as the sole
    // web capture surface. Omit under Path C. No-op on mobile.
    if (kWebDartCapture) {
      DreamicErrorHandling.installEarlyWebErrorHandlers();
    }

    // boot step 4 — register the reporter. managesOwnErrorHandlers: false (dreamic
    // installs the handlers); requiresFirebase: false (Sentry attaches BEFORE
    // Firebase for maximal startup coverage, incl. web).
    configureErrorReporting(
      ErrorReportingConfig.customOnly(
        reporter: SentryErrorReporter(dsn: AppConfig.sentryDsn),
        enableOnWeb: true,
      ),
    );

    // boot step 5 — run the app in this SAME zone. onError defaults to
    // DreamicErrorHandling.recordZoneError, so this is all that's needed.
    runApp(DreamicAppInitHost(
      initFutureFactory: () => dreamicBootstrap(/* firebaseOptions, hooks, ... */),
      splash: const DreamicSplash(),
      child: const MyApp(),
    ));
  });
  // dreamicBootstrap() runs appInitErrorHandling() behind the splash: it calls
  // initialize() (initializing Sentry), attaches the reporter, registers the
  // isolate listener, and flushes the early buffers (breadcrumbs-then-errors).
  */
}

// ===========================================================================
// CANONICAL 2 — Firebase Crashlytics (mobile-only: no web SDK; needs Firebase).
// ===========================================================================
//
// Add `firebase_crashlytics` to YOUR pubspec — dreamic no longer bundles it.
//
// ```dart
// class CrashlyticsErrorReporter extends ErrorReporter {
//   @override
//   Future<void> initialize() async {
//     // Crashlytics initializes with Firebase; nothing to do here. (Optionally
//     // FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(...).)
//   }
//
//   @override
//   void recordError(Object error, StackTrace? stackTrace) {
//     if (kIsWeb) return;
//     FirebaseCrashlytics.instance.recordError(error, stackTrace);
//   }
//
//   @override
//   void recordFlutterError(FlutterErrorDetails details) {
//     if (kIsWeb) return;
//     FirebaseCrashlytics.instance.recordFlutterError(details);
//   }
//
//   @override
//   void addBreadcrumb(String message, {String? category, Map<String, dynamic>? data}) {
//     if (kIsWeb) return;
//     // Crashlytics' breadcrumb analog is log(): a plain string attached to the
//     // next crash report — fold category/data into the string.
//     final suffix = (data != null && data.isNotEmpty) ? ' $data' : '';
//     FirebaseCrashlytics.instance.log(
//       category != null ? '[$category] $message$suffix' : '$message$suffix',
//     );
//   }
//
//   @override
//   void setUser(String userId, {String? email, String? username}) {
//     if (kIsWeb) return;
//     FirebaseCrashlytics.instance.setUserIdentifier(userId);
//   }
//
//   @override
//   void clearUser() {
//     if (kIsWeb) return;
//     FirebaseCrashlytics.instance.setUserIdentifier('');
//   }
// }
// ```
//
/// main() — Crashlytics REQUIRES Firebase first, so flag `requiresFirebase: true`
/// (dreamic attaches it at the post-Firebase bootstrap step) and `enableOnWeb:
/// false` (no web SDK). Under Path A′, web capture is owned by the Dart web-JS
/// handler + a web-capable backend (e.g. Sentry); Crashlytics stays mobile.
void exampleMainCrashlytics() async {
  /*
  // ensureInitialized() is the FIRST line INSIDE the guarded zone — the SAME zone
  // as runApp — or Flutter logs a "Zone mismatch" warning (runGuarded forks a child
  // runZonedGuarded zone). Use `() async { ... }` if your pre-runApp setup needs an
  // `await`.
  DreamicErrorHandling.runGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    installEarlyErrorHandlers();

    configureErrorReporting(
      ErrorReportingConfig.customOnly(
        reporter: CrashlyticsErrorReporter(),
        requiresFirebase: true, // attach AFTER Firebase init (Crashlytics needs it)
        enableOnWeb: false,     // Crashlytics has no web support
      ),
    );

    runApp(DreamicAppInitHost(
      initFutureFactory: () => dreamicBootstrap(/* firebaseOptions, hooks, ... */),
      splash: const DreamicSplash(),
      child: const MyApp(),
    ));
  });
  */
}

// ===========================================================================
// CANONICAL 3 — Sentry + Crashlytics via CompositeErrorReporter (both at once).
// ===========================================================================
//
// [CompositeErrorReporter] is a dreamic-public primitive (no SDK dependency)
// that fans every call out to its children, each wrapped in its own try/catch so
// one backend's failure never blocks the others (BEH-2, BEH-11). Single-backend
// stays the common case; use this only when you genuinely run more than one.
//
// ```dart
// final reporter = CompositeErrorReporter([
//   SentryErrorReporter(dsn: AppConfig.sentryDsn), // web + mobile
//   CrashlyticsErrorReporter(),                    // mobile-only (kIsWeb-guarded)
// ]);
// ```
//
/// main() — pass the OR'd config flags across the children you compose (the
/// flags live on `ErrorReportingConfig`, not on the individual reporters —
/// ERH-007). Any Firebase-dependent child ⇒ `requiresFirebase: true`; any child
/// that manages its own handlers ⇒ `managesOwnErrorHandlers: true`. (A Sentry +
/// Crashlytics composite where dreamic owns the handlers ⇒ requiresFirebase:
/// true, managesOwnErrorHandlers: false.)
void exampleMainComposite() async {
  /*
  // ensureInitialized() is the FIRST line INSIDE the guarded zone — the SAME zone
  // as runApp — or Flutter logs a "Zone mismatch" warning (runGuarded forks a child
  // runZonedGuarded zone). Use `() async { ... }` if your pre-runApp setup needs an
  // `await`.
  DreamicErrorHandling.runGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    installEarlyErrorHandlers();
    if (kWebDartCapture) {
      DreamicErrorHandling.installEarlyWebErrorHandlers(); // Path A′ only
    }

    configureErrorReporting(
      ErrorReportingConfig.customOnly(
        reporter: CompositeErrorReporter([
          SentryErrorReporter(dsn: AppConfig.sentryDsn),
          CrashlyticsErrorReporter(),
        ]),
        enableOnWeb: true,       // Sentry is web-capable; Crashlytics self-guards web
        requiresFirebase: true,  // OR'd: Crashlytics needs Firebase first
        // managesOwnErrorHandlers: false → dreamic installs the handlers.
      ),
    );

    runApp(DreamicAppInitHost(
      initFutureFactory: () => dreamicBootstrap(/* firebaseOptions, hooks, ... */),
      splash: const DreamicSplash(),
      child: const MyApp(),
    ));
  });
  */
  // Reference the primitive so the import is exercised in dreamic-public.
  CompositeErrorReporter; // ignore: unnecessary_statements
}

/// No reporting (the default): omit `configureErrorReporting` entirely, or pass
/// `const ErrorReportingConfig()` with a null reporter. dreamic logs to the
/// console only.
void exampleNoReporting() {
  // configureErrorReporting is simply not called.
}

/// Wiring user context from auth-lifecycle callbacks (any reporter that overrides
/// setUser/clearUser):
void exampleUserContext() {
  /*
  final reporter = GetIt.I<ErrorReporter>(); // or your own reference
  authService.addOnAuthenticatedCallback((uid) async {
    if (uid != null) reporter.setUser(uid);
  });
  authService.addOnLoggedOutCallback(() async => reporter.clearUser());
  */
}

/// Breadcrumbs — the ingress contract (ERH-020).
///
/// ALWAYS emit breadcrumbs via `Logger.breadcrumb(...)` / `logBreadcrumb(...)`,
/// NEVER `Sentry.addBreadcrumb(...)` directly. The Logger applies the
/// `breadcrumbLevel` gate (default `info`, lowerable via Remote Config) + central
/// fail-closed redaction, then forwards to the attached reporter (or buffers it
/// pre-attach). A direct SDK call bypasses both — and is only caught by the
/// `beforeBreadcrumb` safety net.
///
/// The optional `level:` param sets the breadcrumb's own level (default
/// `LogLevel.info` — ERH-031); a crumb below `breadcrumbLevel` is dropped.
void exampleBreadcrumb() {
  /*
  logBreadcrumb('user tapped Generate', category: 'ui');                  // info
  logBreadcrumb('cache miss; refetching', category: 'data', level: LogLevel.debug);
  */
}
