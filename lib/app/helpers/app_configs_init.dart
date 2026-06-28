import 'dart:async';

import 'package:flutter/services.dart';
import 'package:dreamic/app/app_config_base.dart';
import 'package:dreamic/utils/logger.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

Future<void> appInitAppConfigsBase() async {
  // Log version info as early as possible
  final version = await AppConfigBase.getReleaseId();
  // ignore: avoid_print
  print('App version info: $version');
  // ignore: avoid_print
  print(
    'Environment: ${AppConfigBase.environmentTypeString}, Region: ${AppConfigBase.backendRegion}',
  );

  await AppConfigBase.init();

  assert(
    AppConfigBase.lockOrientationToLandscape == false ||
        AppConfigBase.lockOrientationToPortrait == false,
    'Cannot lock to both landscape and portrait',
  );

  if (AppConfigBase.lockOrientationToPortrait) {
    SystemChrome.setPreferredOrientations(
      [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ],
    );
  }

  if (AppConfigBase.lockOrientationToLandscape) {
    SystemChrome.setPreferredOrientations(
      [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ],
    );
  }

  if (AppConfigBase.wakelockEnabledAllTheTime) {
    logi('Enabling wakelock due to app config');
    // Fire-and-forget, but the Future MUST be guarded. On web,
    // `navigator.wakeLock.request('screen')` rejects with a NotAllowedError
    // (e.g. "Document is hidden" when the tab isn't visible, or "Permission was
    // denied") and wakelock_plus_web never attaches an onError handler
    // (js_wakelock.dart does `.toDart.then((_) => null)`). An unguarded
    // enable() therefore leaks that rejection as an unhandled Dart Future error
    // → window.onerror → Sentry. Wakelock is a best-effort convenience, so
    // swallow the failure here.
    unawaited(
      WakelockPlus.enable().catchError(
        (Object e) => logw('Failed to enable wakelock (non-fatal): $e'),
      ),
    );
  }
}
