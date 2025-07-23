import 'package:web/web.dart' as web;

bool isIOSBrowser() =>
    web.window.navigator.userAgent.toLowerCase().contains('iphone') ||
    web.window.navigator.userAgent.toLowerCase().contains('ipad') ||
    web.window.navigator.userAgent.toLowerCase().contains('ipod');

bool isAndroidBrowser() => web.window.navigator.userAgent.toLowerCase().contains('android');

bool isWindowsBrowser() => web.window.navigator.userAgent.toLowerCase().contains('windows');

bool isMacBrowser() => web.window.navigator.userAgent.toLowerCase().contains('macintosh');

bool isMobileBrowser() => isIOSBrowser() || isAndroidBrowser();

bool isDesktopBrowser() => !isMobileBrowser();
