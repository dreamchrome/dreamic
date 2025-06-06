import 'package:flutter/widgets.dart';
import 'package:dreamic/app/app_config_base.dart';
import 'package:dreamic/app/helpers/app_version_check.dart';
import 'package:dreamic/presentation/outdated_app_page.dart';

Future<void> appRunIfValidVersion(
  Function() validAppToRun, {
  Function()? runBeforeValidApp,
}) async {
  final isValidVersion = await appIsVersionValid(AppConfigBase.requiredAppVersion);
  if (!isValidVersion) {
    runApp(OutdatedApp(
      appStoreUrl: AppConfigBase.appStoreUrl,
    ));
  } else {
    runBeforeValidApp?.call();
    runApp(validAppToRun());
  }
}
