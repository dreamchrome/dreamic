# Notification Setup Guide

This guide covers platform configuration and code setup for push notifications using Dreamic's NotificationService.

> **This feature is completely optional.** Your app will not require notification entitlements unless you follow these steps.

## Table of Contents

- [Quick Start (All Platforms)](#quick-start-all-platforms)
- [iOS Configuration](#ios-configuration)
- [Android Configuration](#android-configuration)
- [Web Configuration](#web-configuration)
- [Advanced Configuration](#advanced-configuration)
- [Testing](#testing)
- [Troubleshooting](#troubleshooting)

---

## Quick Start (All Platforms)

### Step 1: Register the Background Handler

In your `main.dart`, register the background handler before `runApp()`:

```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:dreamic/dreamic.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Register background handler (required for background/terminated notifications)
  FirebaseMessaging.onBackgroundMessage(dreamicNotificationBackgroundHandler);

  runApp(MyApp());
}
```

### Step 2: Initialize NotificationService

In your app initialization (e.g., in a Cubit, Provider, or state manager):

```dart
await NotificationService().initialize(
  onNotificationTapped: (route, data) {
    // Navigate when user taps a notification
    if (route != null) {
      navigatorKey.currentState?.pushNamed(route, arguments: data);
    }
  },
);
```

This sets up the notification infrastructure:
- Configures local notifications on both platforms
- Sets up FCM message listeners
- Syncs FCM tokens with your backend (when connected to AuthService)

### Step 3: Request Notification Permissions

**Important:** Notification permissions are NOT automatically requested on login. You must explicitly trigger the permission flow at an appropriate time in your app (e.g., after onboarding, or when the user first encounters a feature that benefits from notifications).

```dart
// Option 1: Full flow with value proposition dialog (recommended)
final result = await NotificationService().runNotificationPermissionFlow(context);

// Option 2: Direct permission request (no pre-dialog)
final result = await NotificationService().initializeNotifications();
```

See [Requesting Permissions](#requesting-permissions) for more details on these methods.

### Step 4: Platform Configuration

Complete the platform-specific setup below for each platform you support:
- [iOS Configuration](#ios-configuration) - APNs setup required
- [Android Configuration](#android-configuration) - Manifest and icons
- [Web Configuration](#web-configuration) - Service worker (optional, disabled by default)

---

## iOS Configuration

### 1. Enable Capabilities in Xcode

1. Open `ios/Runner.xcworkspace` in Xcode
2. Select the **Runner** target
3. Go to **Signing & Capabilities** tab
4. Click **+ Capability** and add:
   - **Push Notifications**
   - **Background Modes** (check "Remote notifications")

### 2. Update Info.plist

Add to `ios/Runner/Info.plist`:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
    <string>remote-notification</string>
</array>
```

### 3. Configure APNs in Firebase

1. Go to [Apple Developer Portal](https://developer.apple.com/account) → Keys → Create new key
2. Enable **Apple Push Notifications service (APNs)**
3. Download the `.p8` file
4. In [Firebase Console](https://console.firebase.google.com) → Project Settings → Cloud Messaging:
   - Upload the `.p8` file
   - Enter your Key ID and Team ID

### iOS Notes

- **Simulator**: Cannot receive push notifications (no APNs). Use a physical device.
- **First denial is permanent**: iOS won't re-show the permission dialog. Use `openNotificationSettings()` to direct users to Settings.

---

## Android Configuration

### 1. Update AndroidManifest.xml

Add permissions and metadata to `android/app/src/main/AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- Required permissions -->
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.VIBRATE"/>

    <application ...>
        <!-- Notification icon (white transparent PNG) -->
        <meta-data
            android:name="com.google.firebase.messaging.default_notification_icon"
            android:resource="@drawable/ic_notification" />

        <!-- Notification accent color -->
        <meta-data
            android:name="com.google.firebase.messaging.default_notification_color"
            android:resource="@color/notification_color" />

        <!-- Default channel ID -->
        <meta-data
            android:name="com.google.firebase.messaging.default_notification_channel_id"
            android:value="default_channel" />
    </application>
</manifest>
```

### 2. Create Notification Icon

Create `android/app/src/main/res/drawable/ic_notification.xml`:

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

> **Tip:** Use [Android Asset Studio](http://romannurik.github.io/AndroidAssetStudio/icons-notification.html) to generate icons from your logo.

### 3. Create Color Resource

Create `android/app/src/main/res/values/colors.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="notification_color">#2196F3</color>
</resources>
```

### Android Notes

- **Android 13+**: Runtime permission required. NotificationService handles this automatically.
- **Two denials = permanent**: After two denials, users must enable via Settings.

---

## Web Configuration

> **Web FCM is disabled by default.** Only follow these steps if you need web push notifications.

### 1. Enable Web FCM

```dart
// Before Firebase.initializeApp()
AppConfigBase.useFCMWebDefault = true;

// Or via build flag
// flutter run --dart-define USE_FCM_WEB=true
```

### 2. Create Service Worker

Create `web/firebase-messaging-sw.js`:

```javascript
importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: "YOUR_API_KEY",
  authDomain: "YOUR_PROJECT.firebaseapp.com",
  projectId: "YOUR_PROJECT_ID",
  storageBucket: "YOUR_PROJECT.appspot.com",
  messagingSenderId: "YOUR_SENDER_ID",
  appId: "YOUR_APP_ID"
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const { title, body, icon } = payload.notification || {};
  return self.registration.showNotification(title || 'Notification', {
    body: body || '',
    icon: icon || '/icons/Icon-192.png',
    data: payload.data,
  });
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(clients.openWindow(event.notification.data?.click_action || '/'));
});
```

### 3. Register Service Worker

Add to `web/index.html` before `</body>`:

```html
<script>
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.register('/firebase-messaging-sw.js');
  }
</script>
```

### 4. Get VAPID Key

1. Firebase Console → Project Settings → Cloud Messaging
2. Under "Web configuration", generate a Web Push certificate
3. Use the key when getting FCM token (handled automatically by NotificationService)

### Web Notes

- **HTTPS required** (except localhost)
- **Cannot open Settings programmatically**: Show instructions for users to enable manually
- **Safari**: Limited support (macOS 13+, iOS 16.4+)

---

## Advanced Configuration

### Requesting Permissions

By default, notification permissions are NOT automatically requested. You control when to show the permission prompt by calling one of these methods:

**Option 1: Full Permission Flow (Recommended)**

Shows a value proposition dialog before the system permission prompt:

```dart
final result = await NotificationService().runNotificationPermissionFlow(context);

switch (result) {
  case NotificationFlowResult.granted:
  case NotificationFlowResult.alreadyGranted:
    // Success - notifications are enabled
    break;
  case NotificationFlowResult.deniedPermission:
  case NotificationFlowResult.deniedPermanently:
    // User denied - handle gracefully
    break;
  case NotificationFlowResult.declinedValueProposition:
    // User declined before seeing system prompt
    break;
  // ... other cases
}
```

**Option 2: Direct Permission Request**

Directly requests permission without a pre-dialog:

```dart
final result = await NotificationService().initializeNotifications();

if (result == NotificationInitResult.success) {
  // Notifications enabled
}
```

### Auto-Initialize on Login (Legacy Behavior)

If you prefer the legacy behavior where permissions are requested automatically on login:

```dart
// Before Firebase.initializeApp()
AppConfigBase.fcmAutoInitializeDefault = true;

// Or via build flag
// flutter run --dart-define FCM_AUTO_INITIALIZE=true
```

### Full Initialize Options

```dart
await NotificationService().initialize(
  // Called when user taps a notification
  onNotificationTapped: (route, data) {
    if (route != null) {
      navigator.pushNamed(route, arguments: data);
    }
  },

  // Called when user taps an action button
  onNotificationAction: (actionId, payload) {
    print('Action: $actionId');
  },

  // Handle foreground messages (default: show as notification)
  onForegroundMessage: (message) {
    // Custom handling
  },

  // Error reporting
  onError: (error, stackTrace) {
    crashlytics.recordError(error, stackTrace);
  },

  // Show notifications when app is in foreground (default: true)
  showNotificationsInForeground: true,

  // Custom token sync (default: uses Firebase callable)
  onTokenChanged: (newToken, oldToken) async {
    await myBackend.updateToken(newToken);
  },

  // Auto-connect to AuthService for token management (default: true)
  autoConnectAuth: true,
);
```

### Permission Re-Request Timing

By default, the permission flow uses exponential backoff when re-requesting permissions after denials. This can be configured via Remote Config, build flags, or code.

**Configuration Options:**

| Setting | Default | Build Define | Description |
|---------|---------|--------------|-------------|
| `notificationAskAgainDays` | `7` | `notificationAskAgainDays` | Base number of days to wait before re-requesting |
| `notificationAskAgainMultiplier` | `3.0` | `notificationAskAgainMultiplier` | Multiplier applied for each subsequent denial |
| `notificationMaxAskCount` | `3` | `notificationMaxAskCount` | Maximum times to ask after denials |

**Example Behavior (with defaults):**
- After 1st denial: wait 7 days
- After 2nd denial: wait 21 days (7 × 3.0)
- After 3rd denial: stop asking (maxCount reached)

**Setting via Code:**
```dart
// Set defaults before Firebase.initializeApp()
AppConfigBase.notificationAskAgainDaysDefault = 14;
AppConfigBase.notificationAskAgainMultiplierDefault = 2.0;
AppConfigBase.notificationMaxAskCountDefault = 5;
```

**Setting via Build Flags:**
```bash
flutter run \
  --dart-define notificationAskAgainDays=14 \
  --dart-define notificationAskAgainMultiplier=2.0 \
  --dart-define notificationMaxAskCount=5
```

**Setting via Firebase Remote Config:**

Add these keys to your Remote Config:
- `notificationAskAgainDays` (integer)
- `notificationAskAgainMultiplier` (number)
- `notificationMaxAskCount` (integer)

### Using NotificationFlowConfig

**Default behavior (uses Remote Config automatically)**

```dart
// AppConfigBase values (including Remote Config) are used automatically
final result = await NotificationService().runNotificationPermissionFlow(context);
```

**Manual configuration (overrides Remote Config)**

```dart
final result = await NotificationService().runNotificationPermissionFlow(
  context,
  config: NotificationFlowConfig(
    // Re-ask timing with exponential backoff
    askAgainAfter: Duration(days: 7),
    askAgainMultiplier: 2.0,  // double the wait each time
    maxAskCount: 5,

    // Go-to-settings behavior
    showGoToSettingsPrompt: true,
    goToSettingsMaxAskCount: 3,
    goToSettingsAskAgainAfter: Duration(days: 30),
  ),
);
```

### Custom Permission Flow UI

```dart
// Use fromAppConfig().copyWith() when you need to customize dialogs
// while keeping Remote Config values for timing settings
final result = await NotificationService().runNotificationPermissionFlow(
  context,
  config: NotificationFlowConfig.fromAppConfig().copyWith(
    // Custom value proposition dialog
    valuePropositionBuilder: (context) async {
      return await showMyCustomDialog(context);
    },

    // Override specific settings if needed
    goToSettingsMaxAskCount: 3,
    goToSettingsAskAgainAfter: Duration(days: 7),
  ),
);
```

### Custom Notification Channels (Android)

```dart
await NotificationChannelManager.instance.createChannel(
  const AndroidNotificationChannel(
    'promotions',
    'Promotional Offers',
    description: 'Special deals and promotions',
    importance: Importance.low,
  ),
);

// Use the channel
await NotificationService().showNotification(
  NotificationPayload(
    title: 'Special Offer',
    body: '50% off today',
    channelId: 'promotions',
  ),
);
```

### Configuration Flags Summary

| Flag | Default | Build Define | Description |
|------|---------|--------------|-------------|
| `useFCM` | `true`* | `USE_FCM` | Enable/disable FCM entirely |
| `useFCMWeb` | `false` | `USE_FCM_WEB` | Enable web FCM (requires setup above) |
| `fcmAutoInitialize` | `false` | `FCM_AUTO_INITIALIZE` | Auto-request permission on login (set `true` for legacy behavior) |
| `notificationAskAgainDays` | `7` | `notificationAskAgainDays` | Base days before re-requesting permission |
| `notificationAskAgainMultiplier` | `3.0` | `notificationAskAgainMultiplier` | Multiplier for exponential backoff |
| `notificationMaxAskCount` | `3` | `notificationMaxAskCount` | Max times to re-ask after denials |

*`useFCM` defaults to `false` on iOS Simulator (no APNs available).

All notification re-request settings support Firebase Remote Config for dynamic adjustment without app updates.

---

## Testing

### Test Local Notifications

```dart
await NotificationService().showNotification(
  NotificationPayload(
    id: 1,
    title: 'Test Notification',
    body: 'This is a test',
    route: '/test',
  ),
);
```

### Test FCM Push

Use Firebase Console → Cloud Messaging → Send test message with your device's FCM token.

### Test Checklist

**iOS:**
- [ ] Permission dialog appears
- [ ] Background notifications work
- [ ] Notification tap navigates correctly
- [ ] `openNotificationSettings()` opens Settings app

**Android:**
- [ ] Permission dialog appears (Android 13+)
- [ ] Custom icon shows in status bar
- [ ] Notification channels created
- [ ] `openNotificationSettings()` opens Settings

**Web (if enabled):**
- [ ] Service worker registers
- [ ] Permission dialog appears
- [ ] Background notifications work

---

## Troubleshooting

### iOS: "No APNs token received"
- Use a physical device (simulators don't support APNs)
- Verify Push Notifications capability is enabled in Xcode
- Check APNs key is uploaded to Firebase Console

### iOS: Permission dialog never appears
- User already denied once (permanent on iOS)
- Use `openNotificationSettings()` to direct to Settings

### Android: Notification icon is gray square
- Icon must be white with transparent background
- Use the provided XML or generate with Android Asset Studio

### Android: "Permission denied" on Android 13+
- POST_NOTIFICATIONS permission required in manifest
- Runtime permission handled automatically by NotificationService

### Web: Service worker not registering
- Must be served over HTTPS (or localhost)
- File must be at web root: `/firebase-messaging-sw.js`

### General: Token not syncing
- Ensure `autoConnectAuth: true` (default) or provide `onTokenChanged`
- Check AuthService is registered in GetIt

---

## Related Documentation

- [NOTIFICATION_GUIDE.md](./NOTIFICATION_GUIDE.md) - Detailed API reference and implementation patterns
- [DREAMIC_FEATURES_GUIDE.md](./DREAMIC_FEATURES_GUIDE.md) - Overview of all Dreamic features
