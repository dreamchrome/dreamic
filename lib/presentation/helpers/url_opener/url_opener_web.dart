// import 'dart:js_interop';
import 'package:web/web.dart' as web;

void navigateToUrl(String url, {bool inNewTab = false}) {
  // web.window.location.href = url.toJS as String;
  if (inNewTab) {
    web.window.open(url, '_blank');
    return;
  }
  // For the current tab
  web.window.location.href = url;
}
