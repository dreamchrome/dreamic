import 'package:dreamic/utils/logger.dart';
import 'package:url_launcher/url_launcher.dart';

void navigateToUrl(String url, {bool inNewTab = false}) {
  launchUrl(
    Uri.parse(url),
    mode: inNewTab ? LaunchMode.externalApplication : LaunchMode.platformDefault,
  ).catchError((error) {
    // Handle error if needed
    loge('Could not launch $url: $error');
    //TODO: what to return here?
    return false;
  });
}
