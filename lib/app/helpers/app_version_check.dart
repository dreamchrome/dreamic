import 'package:dreamic/app/app_config_base.dart';
import 'package:dreamic/utils/logger.dart';

Future<bool> appIsVersionValid(
  String minimumAppVersion, {
  bool allowToRunIfServerVersionIsEmpty = true,
}) async {
  final deviceInfo = await AppConfigBase.getAppVersion();

  int deviceMajor = int.tryParse(deviceInfo.version.split('.')[0]) ?? 0;
  int deviceMinor = int.tryParse(deviceInfo.version.split('.')[1]) ?? 0;
  int devicePatch = int.tryParse(deviceInfo.version.split('.')[2]) ?? 0;

  logd('App version: ${deviceInfo.version}');

  // var serverInfo = (await Get.find<SystemInfoRepoInt>().getSystemInfo()).fold(
  //   (l) {
  //     return l.maybeWhen<SystemInfo>(
  //       expectedRecordNotFound: () => SystemInfo(),
  //       //TODO: handle this better, it crashes the whole app with no feedback!!!
  //       orElse: () => throw StateError('Error getting version'),
  //     );
  //   },
  //   (r) => r,
  // );

  // var serverInfo = GetIt.I.get<RemoteConfigRepoInt>().getString('minimumAppVersion');
  final serverInfo = minimumAppVersion;

  if (serverInfo.isEmpty && allowToRunIfServerVersionIsEmpty) {
    logd('Server version is empty, allowing app to run.');
    return true;
  }

  int appVersionMajor = int.tryParse(serverInfo.split('.')[0]) ?? 0;
  int appVersionMinor = int.tryParse(serverInfo.split('.')[1]) ?? 0;
  int appVersionPatch = int.tryParse(serverInfo.split('.')[2]) ?? 0;

  logd('Server versions: = $appVersionMajor.$appVersionMinor.$appVersionPatch');

  if (deviceMajor > appVersionMajor) {
    return true;
  }
  if (deviceMajor == appVersionMajor) {
    if (deviceMinor > appVersionMinor) {
      return true;
    }
    if (deviceMinor == appVersionMinor) {
      if (devicePatch >= appVersionPatch) {
        return true;
      }
    }
  }

  return false;
}
