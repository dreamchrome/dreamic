import 'package:cloud_functions/cloud_functions.dart';
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

/// Safely extracts a Map from a Cloud Function result.
/// Throws [StateError] if the response is not a Map — callers are expected
/// to catch this via their existing try/catch → RepositoryFailure.unexpected.
Map<String, dynamic> safeResultData(HttpsCallableResult result) {
  final data = result.data;
  if (data is Map) {
    return Map<String, dynamic>.from(data);
  }
  throw StateError(
      'Expected Map response from Cloud Function, got ${data.runtimeType}');
}
