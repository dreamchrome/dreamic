import 'package:flutter/material.dart';
import 'package:dreamic/presentation/helpers/app_reloader/appreloader.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class OutdatedApp extends StatelessWidget {
  const OutdatedApp({
    super.key,
    required this.appStoreUrl,
  });

  final String appStoreUrl;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Outdated App Version',
      home: Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Center(
                  child: Text(
                    kIsWeb
                        ? 'This app requires an update.\nPlease refresh this page:'
                        : 'This app requires an update.\nPlease download the newest version:',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 20),
                if (kIsWeb) ...[
                  ElevatedButton(
                    onPressed: () {
                      reloadApp();
                    },
                    child: const Text('Refresh'),
                  ),
                ] else ...[
                  ElevatedButton(
                    onPressed: () {
                      launchUrlString(appStoreUrl);
                    },
                    child: const Text('Update App'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
