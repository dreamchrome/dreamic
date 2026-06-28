// ignore_for_file: unused_import

/// Example: implementing an [ErrorReporter] for Dreamic.
///
/// Dreamic is **backend-agnostic** — it ships no concrete reporter and depends on
/// no crash-reporting SDK. To report errors you implement [ErrorReporter] in your
/// app (or copy a ready-made template) and register it:
///
/// 1. `configureErrorReporting(ErrorReportingConfig.customOnly(reporter: ...))`
/// 2. `dreamicBootstrap()` runs `appInitErrorHandling()` for you (behind the
///    splash), which attaches the reporter and flushes the early-error buffer.
///
/// `extends ErrorReporter` (not `implements`) so you only override what you
/// support — `recordError` is the one required member; `initialize`,
/// `recordFlutterError`, `addBreadcrumb`, `setUser`, and `clearUser` have default
/// bodies.
library;

import 'package:dreamic/error_reporting/error_reporter_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
// import 'package:sentry_flutter/sentry_flutter.dart'; // add to your pubspec.yaml

/// A Sentry reporter (self-contained — needs no Firebase).
///
/// ```dart
/// class SentryErrorReporter extends ErrorReporter {
///   final String dsn;
///   SentryErrorReporter({required this.dsn});
///
///   @override
///   Future<void> initialize() async {
///     // Empty when using SentryFlutter.init with appRunner (it inits Sentry
///     // itself — see exampleMainSentryWrapper). Otherwise init Sentry here.
///     await SentryFlutter.init((o) => o.dsn = dsn);
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
///       Sentry.configureScope((s) =>
///           s.setUser(SentryUser(id: userId, email: email, username: username)));
///
///   @override
///   void clearUser() => Sentry.configureScope((s) => s.setUser(null));
/// }
/// ```
///
/// RECOMMENDED main() — let Sentry own the error handlers via appRunner:
void exampleMainSentryWrapper() async {
  /*
  WidgetsFlutterBinding.ensureInitialized();
  installEarlyErrorHandlers();

  // managesOwnErrorHandlers: Sentry's appRunner installs FlutterError.onError etc.
  // requiresFirebase: false (default) → dreamic attaches it BEFORE Firebase for
  // maximal startup coverage.
  configureErrorReporting(
    ErrorReportingConfig.customOnly(
      reporter: SentryErrorReporter(dsn: AppConfig.sentryDsn),
      managesOwnErrorHandlers: true,
      enableOnWeb: true,
    ),
  );

  await SentryFlutter.init(
    (o) {
      o.dsn = AppConfig.sentryDsn;
      o.environment = AppConfigBase.environmentType.value;
      o.release = await AppConfigBase.getReleaseId();
    },
    appRunner: () => runApp(DreamicAppInitHost(
      initFutureFactory: () => dreamicBootstrap(/* firebaseOptions, hooks, ... */),
      splash: const DreamicSplash(),
      child: const MyApp(),
    )),
  );
  */
}

/// A Firebase Crashlytics reporter (consumer-provided — Crashlytics is no longer
/// bundled in dreamic). Add `firebase_crashlytics` to YOUR pubspec.
///
/// ```dart
/// class CrashlyticsErrorReporter extends ErrorReporter {
///   @override
///   Future<void> initialize() async {} // Crashlytics inits with Firebase
///
///   @override
///   void recordError(Object error, StackTrace? stackTrace) =>
///       FirebaseCrashlytics.instance.recordError(error, stackTrace);
///
///   @override
///   void recordFlutterError(FlutterErrorDetails details) =>
///       FirebaseCrashlytics.instance.recordFlutterError(details);
///
///   @override
///   void addBreadcrumb(String message, {String? category, Map<String, dynamic>? data}) =>
///       FirebaseCrashlytics.instance.log(category != null ? '[$category] $message' : message);
///
///   @override
///   void setUser(String userId, {String? email, String? username}) =>
///       FirebaseCrashlytics.instance.setUserIdentifier(userId);
///
///   @override
///   void clearUser() => FirebaseCrashlytics.instance.setUserIdentifier('');
/// }
/// ```
///
/// main() — Crashlytics REQUIRES Firebase first, so flag it so dreamic attaches
/// it at the post-Firebase step (NOT web — guard the reporter off on web):
void exampleMainCrashlytics() async {
  /*
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
  */
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
