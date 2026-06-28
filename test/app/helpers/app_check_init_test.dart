import 'dart:async';

import 'package:dreamic/app/app_config_base.dart';
import 'package:dreamic/app/helpers/app_check_init.dart';
import 'package:dreamic/app/helpers/app_errorhandling_init.dart';
import 'package:dreamic/error_reporting/error_reporter_interface.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records every error routed to it (via `loge` → the attached reporter), so the
/// activation-failure tests can assert "swallowed AND reported".
class _RecordingReporter extends ErrorReporter {
  final List<Object> recordedErrors = [];

  @override
  void recordError(Object error, StackTrace? stackTrace) => recordedErrors.add(error);
}

void main() {
  // The App Check provider/site-key/enable resolution now derives from
  // AppConfigBase. Reset the test overrides after every case so resolution is
  // order-independent.
  tearDown(() {
    AppConfigBase.appCheckUseDebugProvidersOverride = null;
    AppConfigBase.appCheckRecaptchaSiteKeyOverride = null;
    AppConfigBase.appCheckEnabledOverride = null;
  });

  group('AppCheckConfig.resolveWebProvider — explicit isDebug', () {
    test('release + key → reCAPTCHA Enterprise (default)', () {
      const c = AppCheckConfig(webRecaptchaSiteKey: 'site-key');
      expect(c.resolveWebProvider(isDebug: false), isA<ReCaptchaEnterpriseProvider>());
    });

    test('release + key + enterprise:false → reCAPTCHA v3', () {
      const c = AppCheckConfig(
        webRecaptchaSiteKey: 'site-key',
        webRecaptchaEnterprise: false,
      );
      expect(c.resolveWebProvider(isDebug: false), isA<ReCaptchaV3Provider>());
    });

    test('release + EMPTY key (and no AppConfigBase key) → WebDebugProvider (keyless-web guard)',
        () {
      AppConfigBase.appCheckRecaptchaSiteKeyOverride = '';
      const c = AppCheckConfig();
      expect(c.resolveWebProvider(isDebug: false), isA<WebDebugProvider>());
    });

    test('debug → WebDebugProvider regardless of key', () {
      const c = AppCheckConfig(webRecaptchaSiteKey: 'site-key');
      expect(c.resolveWebProvider(isDebug: true), isA<WebDebugProvider>());
    });

    test('override wins over key/debug selection', () {
      final override = WebDebugProvider();
      final c = AppCheckConfig(
        webRecaptchaSiteKey: 'site-key',
        webProviderOverride: override,
      );
      expect(c.resolveWebProvider(isDebug: false), same(override));
    });
  });

  group('AppCheckConfig.resolveWebProvider — AppConfigBase-driven defaults', () {
    test('empty field falls back to AppConfigBase.appCheckRecaptchaSiteKey', () {
      AppConfigBase.appCheckRecaptchaSiteKeyOverride = 'config-key';
      const c = AppCheckConfig(); // no webRecaptchaSiteKey
      // Real (not debug) so the key path is taken.
      expect(c.resolveWebProvider(isDebug: false), isA<ReCaptchaEnterpriseProvider>());
    });

    test('config field wins over AppConfigBase fallback', () {
      AppConfigBase.appCheckRecaptchaSiteKeyOverride = 'config-key';
      const c = AppCheckConfig(webRecaptchaSiteKey: 'explicit-key', webRecaptchaEnterprise: false);
      expect(c.resolveWebProvider(isDebug: false), isA<ReCaptchaV3Provider>());
    });

    test('isDebug defaults to AppConfigBase.appCheckUseDebugProviders (false → real)', () {
      AppConfigBase.appCheckUseDebugProvidersOverride = false;
      AppConfigBase.appCheckRecaptchaSiteKeyOverride = 'config-key';
      const c = AppCheckConfig();
      expect(c.resolveWebProvider(), isA<ReCaptchaEnterpriseProvider>());
    });

    test('isDebug defaults to AppConfigBase.appCheckUseDebugProviders (true → debug)', () {
      AppConfigBase.appCheckUseDebugProvidersOverride = true;
      AppConfigBase.appCheckRecaptchaSiteKeyOverride = 'config-key';
      const c = AppCheckConfig();
      expect(c.resolveWebProvider(), isA<WebDebugProvider>());
    });
  });

  group('AppCheckConfig.resolveAndroidProvider', () {
    test('explicit release → Play Integrity', () {
      expect(const AppCheckConfig().resolveAndroidProvider(isDebug: false),
          isA<AndroidPlayIntegrityProvider>());
    });

    test('explicit debug → AndroidDebugProvider', () {
      expect(const AppCheckConfig().resolveAndroidProvider(isDebug: true),
          isA<AndroidDebugProvider>());
    });

    test('default isDebug follows AppConfigBase.appCheckUseDebugProviders', () {
      AppConfigBase.appCheckUseDebugProvidersOverride = false;
      expect(const AppCheckConfig().resolveAndroidProvider(),
          isA<AndroidPlayIntegrityProvider>());
    });

    test('override wins', () {
      const override = AndroidDebugProvider();
      expect(
        const AppCheckConfig(androidProviderOverride: override)
            .resolveAndroidProvider(isDebug: false),
        same(override),
      );
    });
  });

  group('AppCheckConfig.resolveAppleProvider', () {
    test('explicit release → App Attest with Device Check fallback', () {
      expect(const AppCheckConfig().resolveAppleProvider(isDebug: false),
          isA<AppleAppAttestWithDeviceCheckFallbackProvider>());
    });

    test('explicit debug → AppleDebugProvider', () {
      expect(const AppCheckConfig().resolveAppleProvider(isDebug: true),
          isA<AppleDebugProvider>());
    });

    test('default isDebug follows AppConfigBase.appCheckUseDebugProviders', () {
      AppConfigBase.appCheckUseDebugProvidersOverride = true;
      expect(const AppCheckConfig().resolveAppleProvider(), isA<AppleDebugProvider>());
    });

    test('override wins', () {
      const override = AppleDebugProvider();
      expect(
        const AppCheckConfig(appleProviderOverride: override)
            .resolveAppleProvider(isDebug: false),
        same(override),
      );
    });
  });

  group('appInitAppCheck', () {
    test('null config is a no-op (opt-out) and completes', () async {
      await expectLater(appInitAppCheck(null), completes);
    });

    test('APP_CHECK_ENABLED=false makes a non-null config a no-op and completes', () async {
      AppConfigBase.appCheckEnabledOverride = false;
      // Even with a config, the kill switch short-circuits before touching
      // FirebaseAppCheck.instance (which is unavailable in the unit test VM).
      await expectLater(appInitAppCheck(const AppCheckConfig()), completes);
    });
  });

  // The real activation hits FirebaseAppCheck.instance (unavailable in the VM),
  // so the bounded + non-critical wrapper (timeout → report → continue boot) is
  // exercised via the [debugAppCheckActivatorOverride] seam.
  group('appInitAppCheck — bounded + non-critical wrapper (activation seam)', () {
    late _RecordingReporter reporter;
    FlutterExceptionHandler? savedFlutterOnError;
    bool Function(Object, StackTrace)? savedPlatformOnError;

    setUp(() async {
      reporter = _RecordingReporter();
      // Force reporting on under the debug test runner so a swallowed failure is
      // observably reported through the attached reporter.
      AppConfigBase.doUseBackendEmulatorOverride = false;
      AppConfigBase.doDisableErrorReportingOverride = false;
      AppConfigBase.doForceErrorReportingOverride = true;
      // Capture BEFORE appInitErrorHandling installs its own handlers.
      savedFlutterOnError = FlutterError.onError;
      savedPlatformOnError = PlatformDispatcher.instance.onError;
      resetEarlyErrorHandlersForTest();
      configureErrorReporting(
        ErrorReportingConfig.customOnly(
          reporter: reporter,
          enableInDebug: true,
          enableOnWeb: true,
        ),
      );
      await appInitErrorHandling(); // attach → reportBootstrapDiagnostic reports now
    });

    tearDown(() {
      FlutterError.onError = savedFlutterOnError;
      PlatformDispatcher.instance.onError = savedPlatformOnError;
      debugAppCheckActivatorOverride = null;
      AppConfigBase.doUseBackendEmulatorOverride = null;
      AppConfigBase.doDisableErrorReportingOverride = null;
      AppConfigBase.doForceErrorReportingOverride = null;
      configureErrorReporting(const ErrorReportingConfig());
      resetEarlyErrorHandlersForTest();
    });

    test('success → completes, activator invoked with the config, nothing reported',
        () async {
      AppCheckConfig? seen;
      debugAppCheckActivatorOverride = (c) async => seen = c;

      const config = AppCheckConfig();
      await appInitAppCheck(config);

      expect(seen, same(config));
      expect(reporter.recordedErrors, isEmpty);
    });

    test('activation throw → swallowed (boot continues) and reported', () async {
      final boom = StateError('activate failed');
      debugAppCheckActivatorOverride = (c) async => throw boom;

      await expectLater(appInitAppCheck(const AppCheckConfig()), completes);
      expect(reporter.recordedErrors, contains(boom));
    });

    test('activation hang → bounded by activationTimeout, swallowed and reported',
        () async {
      debugAppCheckActivatorOverride = (c) => Completer<void>().future; // never settles

      await expectLater(
        appInitAppCheck(
          const AppCheckConfig(activationTimeout: Duration(milliseconds: 20)),
        ),
        completes,
      );
      expect(reporter.recordedErrors.whereType<TimeoutException>(), isNotEmpty);
    });
  });
}
