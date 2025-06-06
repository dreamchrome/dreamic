import 'package:flutter/services.dart';
import 'package:dreamic/app/app_config_base.dart';
import 'package:dreamic/utils/logger.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

appInitAppConfigsBase() async {
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
    WakelockPlus.enable();
  }
}
