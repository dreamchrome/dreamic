import 'package:dreamic/app/app_config_base.dart';
import 'package:dreamic/utils/logger.dart';

Future<bool> appIsVersionValid(
  String minimumAppVersion, {
  bool allowToRunIfServerVersionIsEmpty = true,
}) async {
  final deviceInfo = await AppConfigBase.getPackageInfo();

  // Strip build number suffix (e.g., "2.2.5+71" → "2.2.5")
  final deviceVersion = deviceInfo.version.split('+').first;
  final deviceParts = deviceVersion.split('.');
  int deviceMajor = _safePart(deviceParts, 0);
  int deviceMinor = _safePart(deviceParts, 1);
  int devicePatch = _safePart(deviceParts, 2);

  logv('App version: ${deviceInfo.version} (parsed: $deviceMajor.$deviceMinor.$devicePatch)');

  final serverInfo = minimumAppVersion;

  if (serverInfo.isEmpty && allowToRunIfServerVersionIsEmpty) {
    logv('Server version is empty, allowing app to run.');
    return true;
  }

  // Strip build number suffix if present
  final serverVersion = serverInfo.split('+').first;
  final serverParts = serverVersion.split('.');
  int appVersionMajor = _safePart(serverParts, 0);
  int appVersionMinor = _safePart(serverParts, 1);
  int appVersionPatch = _safePart(serverParts, 2);

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

int _safePart(List<String> parts, int index) {
  return parts.length > index ? int.tryParse(parts[index]) ?? 0 : 0;
}
