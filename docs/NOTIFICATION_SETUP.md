# Notification Setup Guide

This guide provides platform-specific configuration examples for implementing notifications in your app using Dreamic's NotificationService.

> **⚠️ IMPORTANT: This feature is completely optional.**
> 
> Your app will **NOT require notification entitlements** unless you follow these setup steps. The Dreamic package itself does not include any platform-specific notification configurations. You only add these to your consuming app when you're ready to implement notifications.

## Table of Contents

- [Quick Start](#quick-start)
- [iOS Configuration](#ios-configuration)
- [Android Configuration](#android-configuration)
- [Web Configuration](#web-configuration)
- [Testing](#testing)
- [Troubleshooting](#troubleshooting)

---

## Quick Start

### Before: Without NotificationService (~300 lines of boilerplate)

```dart
// main.dart - Manual setup required
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  // Background handler setup
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  
  // Request permissions
  final messaging = FirebaseMessaging.instance;
  await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );
  
  // Initialize local notifications
  final localNotifications = FlutterLocalNotificationsPlugin();
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosSettings = DarwinInitializationSettings();
  await localNotifications.initialize(
    InitializationSettings(android: androidSettings, iOS: iosSettings),
    onDidReceiveNotificationResponse: _handleNotificationTap,
  );
  
  // Foreground message handling
  FirebaseMessaging.onMessage.listen((message) {
    // Parse message, show notification...
  });
  
  // Background message handling
  FirebaseMessaging.onMessageOpenedApp.listen((message) {
    // Handle navigation...
  });
  
  // Check initial message
  final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  // Handle cold start...
  
  runApp(MyApp());
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // 50+ lines of background handler logic...
}

// Plus 100+ more lines in app.dart for permission flows, badge management, etc.
```

### After: With NotificationService (1 line in main + simple setup)

```dart
// main.dart - Just register the background handler
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  // That's it! Just 1 line for background notifications
  FirebaseMessaging.onBackgroundMessage(dreamicNotificationBackgroundHandler);
  
  runApp(MyApp());
}

// app_cubit.dart or similar - Initialize with callbacks
@override
Future<void> initialize() async {
  // Initialize notification service with your routing logic
  await NotificationService.instance.initialize(
    onNotificationTapped: (payload) {
      // Handle notification tap - navigate to route
      if (payload.route != null) {
        navigatorKey.currentState?.pushNamed(payload.route!, arguments: payload.data);
      }
    },
    onNotificationAction: (actionId, payload) {
      // Handle action button taps
      print('Action tapped: $actionId');
    },
    onError: (error, stackTrace) {
      // Optional: Report errors
      ErrorReporter.report(error, stackTrace);
    },
    reminderIntervalDays: 30, // Optional: Periodic permission reminders
  );
  
  // Request permissions when appropriate
  final status = await NotificationService.instance.requestPermissions();
  if (status == NotificationPermissionStatus.authorized) {
    print('Notifications enabled!');
  }
}
```

**Reduction: ~300 lines → ~20 lines** 🎉

---

## iOS Configuration

### 1. Update Info.plist

Add notification capability descriptions to `ios/Runner/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Existing keys... -->
    
    <!-- Notification permissions -->
    <key>UIBackgroundModes</key>
    <array>
        <string>fetch</string>
        <string>remote-notification</string>
    </array>
    
    <!-- Optional: If using critical alerts -->
    <key>UIApplicationSupportsIndirectInputEvents</key>
    <true/>
</dict>
</plist>
```

### 2. Enable Push Notifications Capability

1. Open `ios/Runner.xcworkspace` in Xcode
2. Select the **Runner** target
3. Go to **Signing & Capabilities** tab
4. Click **+ Capability**
5. Add **Push Notifications**
6. Add **Background Modes** and check:
   - ✅ Remote notifications
   - ✅ Background fetch (optional)

### 3. Configure APNs Authentication

Choose one of these methods:

#### Option A: APNs Authentication Key (Recommended)

1. Go to [Apple Developer Portal](https://developer.apple.com/account)
2. Navigate to **Certificates, Identifiers & Profiles**
3. Click **Keys** → **+** button
4. Name it (e.g., "FCM Push Key")
5. Check **Apple Push Notifications service (APNs)**
6. Download the `.p8` key file
7. Upload to Firebase Console:
   - Go to **Project Settings** → **Cloud Messaging** → **APNs**
   - Upload `.p8` file
   - Enter **Key ID** and **Team ID**

#### Option B: APNs Certificate

1. Generate a CSR (Certificate Signing Request) from Keychain Access
2. Create APNs certificate in Apple Developer Portal
3. Download and install certificate
4. Export as `.p12` file
5. Upload to Firebase Console

### 4. iOS Entitlements

The entitlements are automatically configured when you add the Push Notifications capability. Verify `ios/Runner/Runner.entitlements` contains:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>aps-environment</key>
    <string>development</string>
    <!-- Changes to 'production' in release builds -->
</dict>
</plist>
```

### 5. iOS Testing Notes

- **Simulator**: Cannot test push notifications (no APNs token)
- **Physical device**: Required for testing
- **Debug builds**: Use `development` APNs environment
- **Release builds**: Automatically use `production` APNs environment

---

## Android Configuration

### 1. Update AndroidManifest.xml

Add notification permissions to `android/app/src/main/AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- Notification permissions -->
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.VIBRATE"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
    
    <!-- Optional: For scheduling notifications -->
    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
    
    <!-- Optional: For full-screen notifications -->
    <uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT"/>
    
    <application
        android:label="Your App Name"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">
        
        <!-- Existing activity configuration... -->
        
        <!-- Notification icon (must be white transparent PNG) -->
        <meta-data
            android:name="com.google.firebase.messaging.default_notification_icon"
            android:resource="@drawable/ic_notification" />
        
        <!-- Notification color (brand color) -->
        <meta-data
            android:name="com.google.firebase.messaging.default_notification_color"
            android:resource="@color/notification_color" />
        
        <!-- Default notification channel ID -->
        <meta-data
            android:name="com.google.firebase.messaging.default_notification_channel_id"
            android:value="default_channel" />
        
    </application>
</manifest>
```

### 2. Create Notification Icons

Android requires a **white transparent icon** for the status bar.

#### Create `android/app/src/main/res/drawable/ic_notification.xml`:

```xml
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24">
    <path
        android:fillColor="#FFFFFF"
        android:pathData="M12,22c1.1,0 2,-0.9 2,-2h-4c0,1.1 0.89,2 2,2zM18,16v-5c0,-3.07 -1.64,-5.64 -4.5,-6.32V4c0,-0.83 -0.67,-1.5 -1.5,-1.5s-1.5,0.67 -1.5,1.5v0.68C7.63,5.36 6,7.92 6,11v5l-2,2v1h16v-1l-2,-2z"/>
</vector>
```

> **💡 Tip:** Use [Android Asset Studio](http://romannurik.github.io/AndroidAssetStudio/icons-notification.html) to generate notification icons from your logo.

### 3. Create Notification Color Resource

Create `android/app/src/main/res/values/colors.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- Brand color for notification (e.g., your primary color) -->
    <color name="notification_color">#2196F3</color>
</resources>
```

### 4. Android 13+ Runtime Permissions

For Android 13 (API 33) and above, notifications require runtime permission. NotificationService handles this automatically:

```dart
// The permission request is handled by NotificationService
final status = await NotificationService.instance.requestPermissions();

if (status == NotificationPermissionStatus.authorized) {
  print('Notifications enabled!');
} else if (status == NotificationPermissionStatus.denied) {
  print('User denied notification permissions');
  // Show rationale or settings prompt
}
```

### 5. Notification Channels

NotificationService automatically creates default channels:

- **High Priority** (`high_priority_channel`): Urgent notifications with sound/vibration
- **Default** (`default_channel`): Standard notifications
- **Low Priority** (`low_priority_channel`): Silent notifications
- **Silent** (`silent_channel`): No sound, no vibration

Create custom channels:

```dart
final channelManager = NotificationChannelManager.instance;

await channelManager.createChannel(
  const AndroidNotificationChannel(
    'promotions',
    'Promotional Offers',
    description: 'Special deals and promotions',
    importance: Importance.low,
    playSound: false,
    enableVibration: false,
  ),
);

// Use custom channel
await NotificationService.instance.showNotification(
  NotificationPayload(
    title: 'Special Offer!',
    body: '50% off today only',
    channelId: 'promotions', // Use custom channel
  ),
);
```

### 6. Android Testing Notes

- **Emulator**: Can test notifications (no FCM token required for local)
- **Physical device**: Required for testing FCM push notifications
- **Android 13+**: Must grant runtime permission
- **Android 12 and below**: Permission granted automatically at install

---

## Web Configuration

### 1. Create Firebase Messaging Service Worker

Create `web/firebase-messaging-sw.js`:

```javascript
importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-messaging-compat.js');

// Initialize Firebase with your config
firebase.initializeApp({
  apiKey: "YOUR_API_KEY",
  authDomain: "YOUR_PROJECT.firebaseapp.com",
  projectId: "YOUR_PROJECT_ID",
  storageBucket: "YOUR_PROJECT.appspot.com",
  messagingSenderId: "YOUR_SENDER_ID",
  appId: "YOUR_APP_ID",
  measurementId: "YOUR_MEASUREMENT_ID"
});

const messaging = firebase.messaging();

// Handle background notifications
messaging.onBackgroundMessage((payload) => {
  console.log('Received background message:', payload);
  
  const notificationTitle = payload.notification?.title || 'New Notification';
  const notificationOptions = {
    body: payload.notification?.body || '',
    icon: payload.notification?.icon || '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    tag: payload.data?.tag || 'notification',
    data: payload.data,
  };
  
  return self.registration.showNotification(notificationTitle, notificationOptions);
});

// Handle notification clicks
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  
  const urlToOpen = event.notification.data?.click_action || '/';
  
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUninstalled: false })
      .then((clientList) => {
        // Focus existing window if available
        for (const client of clientList) {
          if (client.url === urlToOpen && 'focus' in client) {
            return client.focus();
          }
        }
        // Open new window
        if (clients.openWindow) {
          return clients.openWindow(urlToOpen);
        }
      })
  );
});
```

### 2. Register Service Worker

Update `web/index.html` to register the service worker:

```html
<!DOCTYPE html>
<html>
<head>
  <!-- Existing head content... -->
</head>
<body>
  <script>
    window.addEventListener('load', function() {
      // Register service worker for notifications
      if ('serviceWorker' in navigator) {
        navigator.serviceWorker.register('/firebase-messaging-sw.js')
          .then((registration) => {
            console.log('Service Worker registered:', registration);
          })
          .catch((error) => {
            console.error('Service Worker registration failed:', error);
          });
      }
    });
  </script>
  
  <script src="main.dart.js" type="application/javascript"></script>
</body>
</html>
```

### 3. Add Web App Configuration

Update `web/manifest.json` to include notification settings:

```json
{
  "name": "Your App Name",
  "short_name": "App",
  "start_url": ".",
  "display": "standalone",
  "background_color": "#FFFFFF",
  "theme_color": "#2196F3",
  "description": "Your app description",
  "orientation": "portrait-primary",
  "prefer_related_applications": false,
  "icons": [
    {
      "src": "icons/Icon-192.png",
      "sizes": "192x192",
      "type": "image/png",
      "purpose": "maskable any"
    },
    {
      "src": "icons/Icon-512.png",
      "sizes": "512x512",
      "type": "image/png",
      "purpose": "maskable any"
    }
  ],
  "gcm_sender_id": "103953800507"
}
```

> **Note:** `gcm_sender_id` is always `103953800507` for FCM web.

### 4. Configure Firebase Console

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select your project
3. Go to **Project Settings** → **Cloud Messaging**
4. Under **Web configuration**, add your domain
5. Generate a **Web Push certificate** (VAPID key)
6. Copy the key pair and add to your app:

```dart
// In your initialization code
await FirebaseMessaging.instance.getToken(
  vapidKey: 'YOUR_VAPID_KEY_HERE',
);
```

### 5. Web Browser Support

| Browser | Support | Notes |
|---------|---------|-------|
| Chrome | ✅ Full | Best support |
| Firefox | ✅ Full | Good support |
| Safari | ⚠️ Limited | macOS 13+, iOS 16.4+ only |
| Edge | ✅ Full | Chromium-based |
| Opera | ✅ Full | Chromium-based |

### 6. Web Testing Notes

- **HTTPS required**: Notifications only work on HTTPS (except localhost)
- **User gesture**: First permission request must be triggered by user action
- **Service worker**: Must be at root path (`/firebase-messaging-sw.js`)
- **CORS**: Ensure Firebase storage allows your domain for image notifications

---

## Testing

### Test Checklist

#### iOS
- [ ] Build runs without notification entitlement errors
- [ ] Permission dialog appears when requested
- [ ] Foreground notifications display correctly
- [ ] Background notifications wake the app
- [ ] Notification tap opens correct route
- [ ] Action buttons work (iOS 10+)
- [ ] Images load in rich notifications
- [ ] Badge count updates correctly
- [ ] Critical alerts work (if implemented)

#### Android
- [ ] Build runs without permission errors
- [ ] Permission dialog appears on Android 13+ when requested
- [ ] Notification channels created correctly
- [ ] Foreground notifications display correctly
- [ ] Background notifications work when app is closed
- [ ] Notification tap opens correct route
- [ ] Action buttons work
- [ ] Images display in BigPictureStyle
- [ ] Custom notification icon shows in status bar
- [ ] Badge count updates (requires launcher support)

#### Web
- [ ] Service worker registers successfully
- [ ] Permission dialog appears when requested
- [ ] Foreground notifications display as browser notifications
- [ ] Background notifications work when tab is closed
- [ ] Notification click focuses/opens correct tab
- [ ] Images load in notifications
- [ ] HTTPS works correctly (not just localhost)

### Manual Testing

#### 1. Test Local Notifications

```dart
// Test basic notification
await NotificationService.instance.showNotification(
  NotificationPayload(
    id: 1,
    title: 'Test Notification',
    body: 'This is a test notification',
  ),
);

// Test notification with route
await NotificationService.instance.showNotification(
  NotificationPayload(
    id: 2,
    title: 'Tap to Navigate',
    body: 'This will navigate to profile',
    route: '/profile',
    data: {'userId': '123'},
  ),
);

// Test rich notification with image
await NotificationService.instance.showNotification(
  NotificationPayload(
    id: 3,
    title: 'Rich Notification',
    body: 'With image and actions',
    imageUrl: 'https://example.com/image.jpg',
    actions: [
      NotificationAction(id: 'view', label: 'View'),
      NotificationAction(id: 'dismiss', label: 'Dismiss'),
    ],
  ),
);
```

#### 2. Test FCM Push Notifications

Use Firebase Console to send test messages:

1. Go to **Firebase Console** → **Cloud Messaging**
2. Click **Send test message**
3. Enter your FCM token (get from `FirebaseMessaging.instance.getToken()`)
4. Send notification

Or use curl:

```bash
curl -X POST https://fcm.googleapis.com/fcm/send \
  -H "Authorization: key=YOUR_SERVER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "to": "DEVICE_FCM_TOKEN",
    "notification": {
      "title": "Test Push",
      "body": "Testing FCM delivery"
    },
    "data": {
      "route": "/messages",
      "messageId": "123"
    }
  }'
```

#### 3. Test Permission Flows

```dart
// Test permission check
final status = await NotificationService.instance.getPermissionStatus();
print('Current status: $status');

// Test permission request
final newStatus = await NotificationService.instance.requestPermissions();
print('New status: $newStatus');

// Test denied state
if (newStatus == NotificationPermissionStatus.denied) {
  // Should open settings
  await NotificationService.instance.openSettings();
}
```

---

## Troubleshooting

### iOS Issues

#### "No APNs token received"
- **Cause**: Device doesn't have APNs token
- **Solution**: 
  - Use physical device (simulator doesn't support APNs)
  - Check Push Notifications capability is enabled
  - Verify APNs certificate/key is uploaded to Firebase

#### "Missing Push Notifications entitlement"
- **Cause**: Capability not added in Xcode
- **Solution**: Add Push Notifications capability in Xcode (see iOS Configuration)

#### "Notification permission always denied"
- **Cause**: User denied once, iOS doesn't re-prompt
- **Solution**: 
  - Use `openSettings()` to send user to Settings app
  - User must manually enable notifications

### Android Issues

#### "Notification doesn't display"
- **Cause**: Missing notification channel or invalid configuration
- **Solution**:
  - Ensure `default_notification_channel_id` in AndroidManifest matches created channel
  - Check channel importance is not set to NONE
  - Verify notification permission granted on Android 13+

#### "Notification icon is gray square"
- **Cause**: Icon is not white transparent PNG
- **Solution**: 
  - Create white transparent icon (see Android Configuration)
  - Use Android Asset Studio to generate proper icons

#### "FCM token not received"
- **Cause**: `google-services.json` not configured correctly
- **Solution**:
  - Download latest `google-services.json` from Firebase Console
  - Place in `android/app/` directory
  - Clean and rebuild: `flutter clean && flutter pub get`

### Web Issues

#### "Service worker not registering"
- **Cause**: File path incorrect or HTTPS not enabled
- **Solution**:
  - Ensure `firebase-messaging-sw.js` is at web root
  - Use HTTPS (or localhost for development)
  - Check browser console for errors

#### "Permission request doesn't appear"
- **Cause**: Not triggered by user gesture
- **Solution**:
  - Call `requestPermissions()` in response to button tap
  - Can't auto-request on page load

#### "Notifications don't show when tab is closed"
- **Cause**: Service worker not handling background messages
- **Solution**:
  - Check `firebase-messaging-sw.js` is loaded
  - Verify `onBackgroundMessage` handler is defined
  - Check browser console for service worker errors

### General Issues

#### "Notification tap doesn't navigate"
- **Cause**: `onNotificationTapped` callback not set or route invalid
- **Solution**:
  - Ensure callback is provided to `initialize()`
  - Check route name matches your app's route table
  - Add debug print in callback to verify it's called

#### "Images don't load in notifications"
- **Cause**: Network error, timeout, or invalid URL
- **Solution**:
  - Check image URL is publicly accessible
  - Verify HTTPS (not HTTP)
  - Check image size (< 1MB recommended)
  - Increase timeout if needed: `NotificationImageLoader.downloadImage(url, timeout: Duration(seconds: 20))`

#### "Background notifications not working"
- **Cause**: Background handler not registered or Firebase not initialized
- **Solution**:
  - Ensure `FirebaseMessaging.onBackgroundMessage(dreamicNotificationBackgroundHandler)` in main()
  - Must be called BEFORE `runApp()`
  - Handler must be top-level function (not inside class)

---

## Next Steps

Once platform setup is complete:

1. **Test on physical devices** for each platform
2. **Customize notification UI** - Use Dreamic's permission UI components
3. **Integrate with your backend** - Send targeted push notifications
4. **Monitor delivery** - Use Firebase Console analytics
5. **Handle edge cases** - Permission denials, network failures, etc.

For implementation details, see:
- [NOTIFICATION_GUIDE.md](./NOTIFICATION_GUIDE.md) - Complete implementation guide
- [DREAMIC_FEATURES_GUIDE.md](./DREAMIC_FEATURES_GUIDE.md) - Quick API reference

---

## Support

If you encounter issues not covered here:

1. Check [Firebase Documentation](https://firebase.google.com/docs/cloud-messaging)
2. Review [Flutter Local Notifications](https://pub.dev/packages/flutter_local_notifications)
3. Open an issue in the Dreamic repository

---

**Last Updated:** November 13, 2025
