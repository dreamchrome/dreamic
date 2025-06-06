import 'package:firebase_core/firebase_core.dart';

import '../../app/app_config_base.dart';

class RepoHelpers {
  static String getFunctionUrl(FirebaseApp app, String funcName) {
    // final projectId = app.options.projectId;
    // final address = AppConfigBase.doUseBackendEmulator
    //     ? '${AppConfigBase.backendEmulatorRemoteAddress}:5000'
    //     : 'cloudfunctions.net';
    String url = '/$funcName';

    if (AppConfigBase.doUseBackendEmulator) {
      url = 'http://${AppConfigBase.backendEmulatorRemoteAddress}:5000/$funcName';
    } else {}

    return url;
  }
}
