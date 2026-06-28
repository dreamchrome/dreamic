import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

import '../app_config_base.dart';
import '../../utils/logger.dart';
import 'app_errorhandling_init.dart';

/// Configuration for dreamic-managed Firebase App Check activation.
///
/// dreamic owns App Check activation as a first-class bootstrap capability (like
/// Remote Config): pass an [AppCheckConfig] to `dreamicBootstrap` and dreamic
/// selects the right providers (with debug fallbacks and the keyless-web guard),
/// activates it **bounded + non-critical**, and enables auto-refresh. Pass `null`
/// (the default) to skip App Check entirely — opt-in by simply providing this.
///
/// **First-class config.** The environment-varying inputs resolve from
/// [AppConfigBase] (dart-define → programmatic default, NOT Remote Config — App
/// Check activates before RC), so the common case is `appCheck: const
/// AppCheckConfig()` with everything driven per flavor:
///   - the web reCAPTCHA site key falls back to
///     [AppConfigBase.appCheckRecaptchaSiteKey] (`APP_CHECK_RECAPTCHA_SITE_KEY`)
///     when [webRecaptchaSiteKey] is empty;
///   - **debug-vs-real attestation** is [AppConfigBase.appCheckUseDebugProviders]
///     (`APP_CHECK_DEBUG`, default: real everywhere except the emulator) — NOT
///     `kDebugMode`, so a debug build can attest for real against staging/prod;
///   - activation is gated by [AppConfigBase.appCheckEnabled] (`APP_CHECK_ENABLED`),
///     a per-build kill switch.
/// The `*Override` fields below remain the last-resort verbatim escape hatch.
///
/// **Why never fatal:** App Check is consumed LAZILY — `activate()` registers the
/// provider and schedules a token; the token is fetched on the first *attested
/// backend call*, and enforcement is *server-side*. Hard-blocking boot on
/// activation would brick the app on a transient reCAPTCHA/network hiccup for
/// zero security gain, so a timeout/failure is reported (so it's visible) and
/// boot continues; App Check then attests lazily.
class AppCheckConfig {
  /// The web reCAPTCHA site key. Empty (the default) ⇒ falls back to
  /// [AppConfigBase.appCheckRecaptchaSiteKey] (`APP_CHECK_RECAPTCHA_SITE_KEY`);
  /// if that is also empty, web uses [WebDebugProvider] (dev / keyless web builds
  /// — a keyless `--release` web build would otherwise throw "Missing required
  /// parameters: sitekey"). Ignored when [webProviderOverride] is set. Prefer
  /// configuring the site key via [AppConfigBase] per flavor and leaving this
  /// empty.
  final String webRecaptchaSiteKey;

  /// When dreamic builds the default web provider from [webRecaptchaSiteKey], use
  /// reCAPTCHA **Enterprise** (true, default) or reCAPTCHA **v3** (false).
  /// Ignored in debug or when [webProviderOverride] is set.
  final bool webRecaptchaEnterprise;

  /// Advanced: a fully-built web provider, used verbatim (bypasses the key /
  /// enterprise / debug selection).
  final WebProvider? webProviderOverride;

  /// Advanced: the Android provider. Defaults to [AndroidPlayIntegrityProvider]
  /// (release) / [AndroidDebugProvider] (debug).
  final AndroidAppCheckProvider? androidProviderOverride;

  /// Advanced: the Apple provider. Defaults to
  /// [AppleAppAttestWithDeviceCheckFallbackProvider] (release) /
  /// [AppleDebugProvider] (debug).
  final AppleAppCheckProvider? appleProviderOverride;

  /// Whether to enable automatic token refresh after activation (default true).
  final bool tokenAutoRefreshEnabled;

  /// Bound on the whole activation. On timeout/failure boot continues and the
  /// failure is reported. Default 8s — a healthy `activate()` returns
  /// near-instantly (it sets up the provider and schedules the token; it does
  /// NOT await a network token), so this only fires on a genuine stall.
  final Duration activationTimeout;

  const AppCheckConfig({
    this.webRecaptchaSiteKey = '',
    this.webRecaptchaEnterprise = true,
    this.webProviderOverride,
    this.androidProviderOverride,
    this.appleProviderOverride,
    this.tokenAutoRefreshEnabled = true,
    this.activationTimeout = const Duration(seconds: 8),
  });

  /// The web provider dreamic will pass to `activate`.
  ///
  /// [isDebug] defaults to [AppConfigBase.appCheckUseDebugProviders] (real-vs-
  /// debug per environment, NOT build mode); pass an explicit value in tests to
  /// exercise both branches under the always-debug test runner. The site key
  /// falls back to [AppConfigBase.appCheckRecaptchaSiteKey] when
  /// [webRecaptchaSiteKey] is empty; an empty effective key keeps the keyless-web
  /// guard (returns [WebDebugProvider] rather than throwing on a keyless release
  /// web build).
  WebProvider resolveWebProvider({bool? isDebug}) {
    final override = webProviderOverride;
    if (override != null) return override;
    final debug = isDebug ?? AppConfigBase.appCheckUseDebugProviders;
    final key = webRecaptchaSiteKey.isNotEmpty
        ? webRecaptchaSiteKey
        : AppConfigBase.appCheckRecaptchaSiteKey;
    if (debug) {
      return WebDebugProvider();
    }
    if (key.isEmpty) {
      // Real attestation was intended (debug providers OFF) but no reCAPTCHA site
      // key is configured — fall back to WebDebugProvider rather than letting the
      // SDK throw "Missing required parameters: sitekey" on a keyless release web
      // build. This is a MISCONFIGURATION on a real-attestation build: these
      // tokens will NOT pass real App Check enforcement, so a server with
      // APP_CHECK_ENFORCE=true rejects every call. Fail-soft but warn loudly
      // (the failure is otherwise invisible until runtime rejection).
      logw(
        'AppCheck: real attestation is enabled (APP_CHECK_DEBUG=false) but no web '
        'reCAPTCHA site key is configured (AppCheckConfig.webRecaptchaSiteKey and '
        'APP_CHECK_RECAPTCHA_SITE_KEY are both empty) — falling back to '
        'WebDebugProvider. These tokens will NOT pass real App Check enforcement; '
        'set the reCAPTCHA site key for web release builds.',
      );
      return WebDebugProvider();
    }
    return webRecaptchaEnterprise
        ? ReCaptchaEnterpriseProvider(key)
        : ReCaptchaV3Provider(key);
  }

  /// The Android provider dreamic will pass to `activate`. [isDebug] defaults to
  /// [AppConfigBase.appCheckUseDebugProviders].
  AndroidAppCheckProvider resolveAndroidProvider({bool? isDebug}) {
    final debug = isDebug ?? AppConfigBase.appCheckUseDebugProviders;
    return androidProviderOverride ??
        (debug ? const AndroidDebugProvider() : const AndroidPlayIntegrityProvider());
  }

  /// The Apple provider dreamic will pass to `activate`. [isDebug] defaults to
  /// [AppConfigBase.appCheckUseDebugProviders].
  AppleAppCheckProvider resolveAppleProvider({bool? isDebug}) {
    final debug = isDebug ?? AppConfigBase.appCheckUseDebugProviders;
    return appleProviderOverride ??
        (debug
            ? const AppleDebugProvider()
            : const AppleAppAttestWithDeviceCheckFallbackProvider());
  }
}

/// Activates Firebase App Check per [config] — bounded + non-critical.
///
/// No-op when [config] is null (opt-out). Otherwise selects providers, activates
/// within [AppCheckConfig.activationTimeout], enables auto-refresh, and on ANY
/// timeout/failure REPORTS via [reportBootstrapDiagnostic] (so it reaches the
/// backend whether the reporter attached before Firebase — Sentry early-attach —
/// or after — Crashlytics, deferred + flushed) and CONTINUES. The in-flight
/// `activate` (if it timed out) completes in the background and serves later
/// lazily-attested calls.
///
/// Idempotent across gate-retry re-runs: re-activation is a no-op-ish reconfigure
/// in the underlying SDK, and the debug-token globals are apply-once.
///
/// No-op when [config] is null (opt-out by omission) OR when
/// [AppConfigBase.appCheckEnabled] is false (the per-build `APP_CHECK_ENABLED`
/// kill switch).
Future<void> appInitAppCheck(AppCheckConfig? config) async {
  if (config == null) {
    return;
  }
  if (!AppConfigBase.appCheckEnabled) {
    logBreadcrumb('appInitAppCheck: skipped (APP_CHECK_ENABLED=false)',
        category: 'bootstrap');
    return;
  }
  logBreadcrumb('appInitAppCheck: activating '
      '(debugProviders=${AppConfigBase.appCheckUseDebugProviders})',
      category: 'bootstrap');
  final activate = debugAppCheckActivatorOverride ?? _activateFirebaseAppCheck;
  try {
    await activate(config).timeout(config.activationTimeout);
    logBreadcrumb('appInitAppCheck: activated', category: 'bootstrap');
  } catch (e, st) {
    reportBootstrapDiagnostic(
      e,
      'App Check activation timed out or failed — continuing boot; App Check '
      'will attest lazily on the first attested callable',
      st,
    );
  }
}

/// Performs the real `FirebaseAppCheck.instance` activation for [config]:
/// selects providers, activates, and enables auto-refresh. Extracted so
/// [appInitAppCheck]'s bounded + non-critical wrapper (timeout → report →
/// continue boot) can be exercised in unit tests via
/// [debugAppCheckActivatorOverride], which the platform singleton precludes.
Future<void> _activateFirebaseAppCheck(AppCheckConfig config) async {
  await FirebaseAppCheck.instance.activate(
    providerWeb: config.resolveWebProvider(),
    providerAndroid: config.resolveAndroidProvider(),
    providerApple: config.resolveAppleProvider(),
  );
  if (config.tokenAutoRefreshEnabled) {
    await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);
  }
}

/// Test seam: when non-null, [appInitAppCheck] uses this in place of the real
/// `FirebaseAppCheck.instance` activation ([_activateFirebaseAppCheck]), so the
/// bounded/non-critical wrapper can be unit-tested without the platform
/// singleton (unavailable in the test VM). Null in production; reset to null in
/// test `tearDown`.
@visibleForTesting
Future<void> Function(AppCheckConfig config)? debugAppCheckActivatorOverride;
