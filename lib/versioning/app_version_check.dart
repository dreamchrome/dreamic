import 'package:dreamic/app/app_config_base.dart';
import 'package:dreamic/utils/logger.dart';

Future<bool> appIsVersionValid(
  String minimumAppVersion, {
  bool allowToRunIfServerVersionIsEmpty = true,
}) async {
  final deviceInfo = await AppConfigBase.getPackageInfo();

  // Strip build number suffix (e.g., "2.2.5+71" → "2.2.5")
  final deviceVersion = deviceInfo.version.split('+').first;
  int deviceMajor = int.tryParse(deviceVersion.split('.')[0]) ?? 0;
  int deviceMinor = int.tryParse(deviceVersion.split('.')[1]) ?? 0;
  int devicePatch = int.tryParse(deviceVersion.split('.')[2]) ?? 0;

  logv('App version: ${deviceInfo.version} (parsed: $deviceMajor.$deviceMinor.$devicePatch)');

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
    logv('Server version is empty, allowing app to run.');
    return true;
  }

  // Strip build number suffix if present
  final serverVersion = serverInfo.split('+').first;
  int appVersionMajor = int.tryParse(serverVersion.split('.')[0]) ?? 0;
  int appVersionMinor = int.tryParse(serverVersion.split('.')[1]) ?? 0;
  int appVersionPatch = int.tryParse(serverVersion.split('.')[2]) ?? 0;

  logv('Server versions: = $appVersionMajor.$appVersionMinor.$appVersionPatch');

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
