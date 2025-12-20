import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../data/models/notification_payload.dart';
import '../utils/logger.dart';

/// Top-level background message handler for Firebase Cloud Messaging.
///
/// This function is called when a notification is received while the app
/// is in the background or terminated. It must be a top-level function
/// (not a class method) to work with Dart isolates.
///
/// ## Usage
///
/// Register this handler in your app's `main()` function **before** calling `runApp()`:
///
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await Firebase.initializeApp();
///
///   // Register background handler - MUST be done before runApp()
///   FirebaseMessaging.onBackgroundMessage(dreamicNotificationBackgroundHandler);
///
///   runApp(MyApp());
/// }
/// ```
///
/// ## What This Handler Does
///
/// - Initializes Firebase in the background isolate
/// - Parses the incoming FCM message
/// - Logs the notification for debugging
/// - Can be extended to display local notifications in background
///
/// ## Important Notes
///
/// - This handler runs in a separate isolate and cannot access UI
/// - Must be a top-level function (Dart requirement)
/// - Runs even when app is terminated
/// - Has access to SharedPreferences and other platform channels
/// - Cannot access Flutter UI widgets or BuildContext
///
/// ## Customization
///
/// If your app needs custom background notification handling:
/// 1. Create your own top-level handler function
/// 2. Call this function from your handler to leverage Dreamic's parsing
/// 3. Add your custom logic before/after
///
/// ```dart
/// @pragma('vm:entry-point')
/// Future<void> myBackgroundHandler(RemoteMessage message) async {
///   // Your custom logic before
///   await customPreProcessing(message);
///
///   // Use Dreamic's handler
///   await dreamicNotificationBackgroundHandler(message);
///
///   // Your custom logic after
///   await customPostProcessing(message);
/// }
/// ```
@pragma('vm:entry-point')
Future<void> dreamicNotificationBackgroundHandler(RemoteMessage message) async {
  try {
    // Initialize Firebase in the background isolate
    // This is required because background handlers run in a separate isolate
    if (!kIsWeb) {
      await Firebase.initializeApp();
    }

    logi('Background notification received: ${message.messageId}');

    // Parse the message into a NotificationPayload
    final payload = NotificationPayload.fromRemoteMessage(message);

    logi('Background notification payload: '
        'title="${payload.title}", '
        'body="${payload.body}", '
        'route="${payload.route}"');

    // TODO: Optionally display a local notification here
    // For now, we just log the notification
    // The app will handle it when opened
  } catch (e, stackTrace) {
    loge(e, 'Error handling background notification', stackTrace);
  }
}
