import 'dart:async';

import 'package:flutter/foundation.dart';
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
    // Wakelock is MOBILE-ONLY — never request it on web (BEH-6 / Part 4).
    //
    // On web, `navigator.wakeLock.request('screen')` rejects with a
    // NotAllowedError (e.g. "Document is hidden" when the tab isn't visible, or
    // "Permission was denied") and wakelock_plus_web never attaches an onError
    // handler (js_wakelock.dart does `.toDart.then((_) => null)`), so an
    // unguarded enable() leaks that rejection as an unhandled Dart Future error
    // → window.onerror → the reporter. The hard `!kIsWeb` guard is the real fix
    // (no web re-enable path, non-configurable — settled); it supersedes the
    // earlier web-only `.catchError` hotfix.
    //
    // The `.catchError` is RETAINED for MOBILE defensiveness: a device can still
    // reject the request (wakelock is a best-effort convenience), and that
    // rejection must not surface as an unhandled Future error.
    if (!kIsWeb) {
      logi('Enabling wakelock due to app config');
      unawaited(
        WakelockPlus.enable().catchError(
          (Object e) => logw('Failed to enable wakelock (non-fatal): $e'),
        ),
      );
    }
  }
}
