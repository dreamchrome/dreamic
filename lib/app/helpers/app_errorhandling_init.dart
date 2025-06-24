import 'dart:async';
import 'dart:isolate';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:dreamic/app/app_config_base.dart';
import 'package:dreamic/utils/logger.dart';

Future<void> appInitErrorHandling() async {
  // Disable analytics and crashlytics for web
  if (AppConfigBase.doUseBackendEmulator || kIsWeb) {
    FlutterError.onError = (details) {
      loge(details.stack ?? StackTrace.current, details.exceptionAsString());
    };

    //TODO: implement this for release, maybe crashlytics
    PlatformDispatcher.instance.onError = (exception, stackTrace) {
      loge(stackTrace, exception.toString());
      return true;
    };
  } else {
    // Pass all uncaught errors from the framework to Crashlytics.
    // FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterError;
    // FirebaseAnalytics analytics = FirebaseAnalytics.instance;
    // analytics.setAnalyticsCollectionEnabled(true);

    runZonedGuarded<Future<void>>(() async {
      WidgetsFlutterBinding.ensureInitialized();
      await Firebase.initializeApp();
      // The following lines are the same as previously explained in "Handling uncaught errors"
      FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterError;
    }, (error, stack) => FirebaseCrashlytics.instance.recordError(error, stack));

    //
    // Catch errors outside of the Flutter framework
    //
    Isolate.current.addErrorListener(
      RawReceivePort((pair) async {
        final List<dynamic> errorAndStacktrace = pair;
        await FirebaseCrashlytics.instance.recordError(
          errorAndStacktrace.first,
          errorAndStacktrace.last,
        );
      }).sendPort,
    );
  }
}
