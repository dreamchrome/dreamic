# Notification Service Guide

## Overview

The Dreamic Notification Service provides a comprehensive, production-ready notification system for Flutter apps. It abstracts away the complexity of Firebase Cloud Messaging (FCM), local notifications, permission handling, and platform-specific quirks.

**This feature is completely optional.** Your app will not require notification entitlements unless you follow these setup steps.

## Why Use This Service?

### Before: ~300 Lines of Boilerplate

Without this service, apps need to implement:

**In `main.dart` (~150 lines):**
- Create `setupFlutterNotifications()` function
- Define top-level `_firebaseMessagingBackgroundHandler()`
- Create `AndroidNotificationChannel` manually
- Initialize `FlutterLocalNotificationsPlugin`
- Register background message handler
- Request iOS permissions
- Create notification channels

**In `app.dart` (~100 lines):**
- Handle `FirebaseMessaging.instance.getInitialMessage()`
- Listen to `FirebaseMessaging.onMessage`
- Listen to `FirebaseMessaging.onMessageOpenedApp`
- Implement notification tap navigation logic
- Refresh user data after notifications
- Display foreground notifications manually

**Poor Permission UX:**
- Permission prompt appears immediately after authentication
- No control over when/where to ask
- Can't provide context or rationale
- Hurts App Store review and user trust

### After: One `initialize()` Call

```dart
// In main.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  // Register background handler (required by Dart)
  FirebaseMessaging.onBackgroundMessage(dreamicNotificationBackgroundHandler);
  
  // Initialize notification service - ONE LINE
  await NotificationService().initialize(
    onNotificationTapped: (route, data) {
      if (route != null) appRouter.navigateNamed(route);
    },
  );
  
  runApp(MyApp());
}

// Request permissions when appropriate - ONE LINE
await NotificationService().requestPermissions();
```

Everything else is handled automatically:
- ✅ Notification channels created
- ✅ FCM streams set up
- ✅ Foreground notifications displayed
- ✅ Background messages handled
- ✅ Notification taps routed
- ✅ Permission state tracked

## Getting Started

### 1. Add Dependencies

The dependencies are already included in Dreamic's `pubspec.yaml`:
- `flutter_local_notifications: ^18.0.1`
- `app_badge_plus: ^1.1.5`
- `firebase_messaging` (already in Dreamic)

### 2. Platform Configuration

⚠️ **Only add these configurations if your app uses notifications.**

<details>
<summary><b>iOS Configuration</b></summary>

Add to `ios/Runner/Info.plist`:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>remote-notification</string>
</array>
```

No additional entitlements are required. The permission prompt will only show when you explicitly call `requestPermissions()`.

</details>

<details>
<summary><b>Android Configuration</b></summary>

Add to `android/app/src/main/AndroidManifest.xml`:

**Basic Notification Permissions:**
```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.VIBRATE" />
```

For Android 13+ (API 33+), the POST_NOTIFICATIONS permission will be requested at runtime when you call `requestPermissions()`.

**Badge Support (Optional):**

If you want to use badge counts (via `NotificationService().updateBadgeCount()`), add launcher-specific permissions for the Android devices you need to support:

```xml
<!-- Samsung -->
<uses-permission android:name="com.sec.android.provider.badge.permission.READ"/>
<uses-permission android:name="com.sec.android.provider.badge.permission.WRITE"/>

<!-- HTC -->
<uses-permission android:name="com.htc.launcher.permission.READ_SETTINGS"/>
<uses-permission android:name="com.htc.launcher.permission.UPDATE_SHORTCUT"/>

<!-- Sony -->
<uses-permission android:name="com.sonyericsson.home.permission.BROADCAST_BADGE"/>
<uses-permission android:name="com.sonymobile.home.permission.PROVIDER_INSERT_BADGE"/>

<!-- Apex -->
<uses-permission android:name="com.anddoes.launcher.permission.UPDATE_COUNT"/>

<!-- Solid -->
<uses-permission android:name="com.majeur.launcher.permission.UPDATE_BADGE"/>

<!-- Huawei -->
<uses-permission android:name="com.huawei.android.launcher.permission.CHANGE_BADGE"/>
<uses-permission android:name="com.huawei.android.launcher.permission.READ_SETTINGS"/>
<uses-permission android:name="com.huawei.android.launcher.permission.WRITE_SETTINGS"/>
```

**Note:** Badge support varies by manufacturer and launcher. These permissions are only needed if you use badge functionality. Starting with Android 8.0 (API 26), notification badges appear automatically when the app has active notifications.

</details>

<details>
<summary><b>Web Configuration</b></summary>

Web notifications require a service worker. See the [Web Setup Guide](NOTIFICATION_SETUP.md#web) for details.

</details>

### 3. Initialize the Service

In your `main.dart`, **before** calling `runApp()`:

```dart
import 'package:dreamic/app/helpers/notification_background_handler.dart';
import 'package:dreamic/app/helpers/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  // REQUIRED: Register background message handler
  // This must be done before runApp() due to Dart isolate requirements
  FirebaseMessaging.onBackgroundMessage(dreamicNotificationBackgroundHandler);
  
  // Initialize NotificationService
  await NotificationService().initialize(
    onNotificationTapped: (route, data) async {
      // Handle notification tap - navigate to the specified route
      if (route != null) {
        // Use your app's navigation system
        Navigator.of(context).pushNamed(route, arguments: data);
        // OR with go_router:
        // context.go(route, extra: data);
      }
    },
    showNotificationsInForeground: true, // Show notifications even when app is open
  );
  
  runApp(MyApp());
}
```

**That's it!** Your app now has full notification support. The service automatically handles:
- Creating notification channels (Android)
- Listening to FCM messages (foreground, background, terminated)
- Displaying local notifications
- Handling notification taps
- Parsing notification payloads

### 4. Request Permissions

Request notification permissions at the appropriate time in your app flow:

```dart
import 'package:dreamic/app/helpers/notification_service.dart';

// Simple request
final status = await NotificationService().requestPermissions();

if (status == NotificationPermissionStatus.authorized) {
  print('Notifications enabled!');
}
```

**Best Practice:** Show a permission request after the user has experienced value from your app, not immediately on app launch.

## Permission Request Strategies

### Strategy 1: Simple Request

Just request permissions directly:

```dart
final service = NotificationService();
final status = await service.requestPermissions();
```

### Strategy 2: With UI (Recommended)

Use the provided bottom sheet for better UX:

```dart
import 'package:dreamic/presentation/elements/notification_permission_bottom_sheet.dart';

await NotificationPermissionBottomSheet.show(
  context,
  title: 'Stay Updated',
  description: 'Enable notifications to receive important updates about your orders.',
  onResult: (status) {
    if (status == NotificationPermissionStatus.authorized) {
      // Permissions granted!
    }
  },
);
```

### Strategy 3: Periodic Reminders

Ask once a month if user hasn't enabled notifications:

```dart
// Check if should show reminder (default: 30 days since last ask)
final service = NotificationService();
final helper = NotificationPermissionHelper();

if (await helper.isPermissionDenied() && await helper.shouldShowPeriodicReminder()) {
  // Show reminder
  await NotificationPermissionBottomSheet.show(context);
  await helper.updateLastReminderDate();
}
```

## Displaying Notifications

### From Remote FCM Message

Notifications from FCM are automatically displayed. No code needed!

### Manual Local Notification

```dart
import 'package:dreamic/app/helpers/notification_service.dart';
import 'package:dreamic/data/models/notification_payload.dart';

final service = NotificationService();

await service.showNotification(
  NotificationPayload(
    title: 'New Message',
    body: 'You have a new message from John',
    route: '/messages/123',
    data: {'messageId': '123', 'senderId': 'john'},
  ),
);
```

## Notification Routing

When a user taps a notification, the `onNotificationTapped` callback is triggered with the route and data from the notification.

### FCM Notification Payload Format

Your backend should send notifications in this format:

```json
{
  "notification": {
    "title": "New Order",
    "body": "Order #1234 has been placed"
  },
  "data": {
    "route": "/orders/1234",
    "orderId": "1234",
    "status": "pending"
  }
}
```

The service will:
1. Parse the `route` field from data
2. Call `onNotificationTapped(route, data)`
3. Your app navigates to the route

### Supported Route Fields

The service checks multiple fields (in order):
1. `route`
2. `screen`
3. `deepLink`
4. `url`

Use whichever field name your backend already uses.

## Permission Status Checking

```dart
final service = NotificationService();

// Get current status
final status = await service.getPermissionStatus();

// Check specific states
final helper = NotificationPermissionHelper();
final isGranted = await helper.isPermissionGranted();
final isDenied = await helper.isPermissionDenied();
final canPrompt = await helper.canPromptForPermission();
```

## Badge Management

Manage app icon badge counts:

```dart
final service = NotificationService();

// Set badge count
await service.updateBadgeCount(5);

// Clear badge
await service.clearBadge();

// Get current count
final count = await service.getBadgeCount();
```

**Platform Notes:**
- **iOS/macOS**: Works out of the box with notification permissions
- **Android**: Requires launcher-specific permissions (see Android Configuration above)
  - Badge support varies by manufacturer (Samsung, Oppo, Vivo, Huawei are well-supported)
  - Android 8.0+ shows automatic badges when app has active notifications
  - Check `AppBadgePlus.isSupported()` to verify launcher support

## UI Components

Dreamic provides pre-built UI components for common notification scenarios:

### Permission Bottom Sheet

The bottom sheet uses platform-native dialogs (Cupertino on iOS, Material on Android) via the `adaptive_dialog` package. All text is fully customizable for localization.

**Basic Usage:**
```dart
import 'package:dreamic/presentation/elements/notification_permission_bottom_sheet.dart';

await NotificationPermissionBottomSheet.show(
  context,
  title: 'Enable Notifications',
  description: 'Stay informed with timely updates',
  allowButtonText: 'Allow Notifications',
  declineButtonText: 'Not Now',
);
```

**Localized Example:**
```dart
// With flutter_localizations
await NotificationPermissionBottomSheet.show(
  context,
  title: AppLocalizations.of(context).notificationPermissionTitle,
  description: AppLocalizations.of(context).notificationPermissionDescription,
  allowButtonText: AppLocalizations.of(context).allowNotifications,
  declineButtonText: AppLocalizations.of(context).notNow,
  // Customize denied state dialog (shown on iOS when user previously denied)
  deniedDialogTitle: AppLocalizations.of(context).notificationsDeniedTitle,
  deniedDialogMessage: AppLocalizations.of(context).notificationsDeniedMessage,
  openSettingsButtonText: AppLocalizations.of(context).openSettings,
  maybeLaterButtonText: AppLocalizations.of(context).maybeLater,
);
```

**Customizable Parameters:**
- `title`: Main permission request title
- `description`: Explanation of why notifications are needed
- `allowButtonText`: Primary action button (default: "Allow Notifications")
- `declineButtonText`: Secondary action button (default: "Not Now")
- `deniedDialogTitle`: Title for settings prompt when denied (default: "Notifications Disabled")
- `deniedDialogMessage`: Message explaining how to enable in settings
- `openSettingsButtonText`: Button to open system settings (default: "Open Settings")
- `maybeLaterButtonText`: Cancel button for settings dialog (default: "Maybe Later")
- `primaryColor`: Custom button color
- `backgroundColor`: Custom sheet background color
- `icon`: Custom icon widget

### Permission Status Widget

```dart
import 'package:dreamic/presentation/elements/notification_permission_status_widget.dart';

NotificationPermissionStatusWidget(
  onEnablePressed: () {
    // Custom enable flow
  },
)
```

### Permission Builder (Headless Component)

Build completely custom permission UIs while getting automatic status updates:

```dart
import 'package:dreamic/presentation/elements/notification_permission_builder.dart';

NotificationPermissionBuilder(
  builder: (context, status, requestPermissions) {
    // Build your custom UI based on permission status
    if (status == NotificationPermissionStatus.authorized) {
      return YourNotificationsListWidget();
    }
    
    return Column(
      children: [
        Text('Notifications are ${status.name}'),
        ElevatedButton(
          onPressed: requestPermissions,
          child: Text('Enable Notifications'),
        ),
      ],
    );
  },
  onStatusChanged: (status) {
    // Optional: React to status changes
    print('Permission status changed to: ${status.name}');
  },
)
```

**Features:**
- Provides current permission status via builder callback
- Provides `requestPermissions()` function for your UI
- Automatically rebuilds when permission changes
- Detects status changes when app returns from system settings
- Optional `onStatusChanged` callback for side effects

**Use Cases:**
- Conditional content display based on permission status
- Custom permission request UI that matches your app's design
- Integration with your app's existing navigation/routing
- Status-aware feature toggles

### Badge Count Widget

Automatically display notification badge counts synced with NotificationService:

```dart
import 'package:dreamic/presentation/elements/notification_badge_widget.dart';

// Automatic mode - syncs with NotificationService
#### Automatic Mode (Sync with NotificationService)

NotificationBadgeWidget(
  child: Icon(Icons.notifications),
)
// Automatically shows current badge count and updates every second

// Manual mode - display specific count
#### Manual Mode (Custom Count)

NotificationBadgeWidget(
  count: 5,
  child: Icon(Icons.shopping_cart),
)

// With customization
#### Styled Badge

NotificationBadgeWidget(
  maxCount: 99,              // Shows "99+" for counts > 99
  hideWhenZero: true,        // Hides badge when count is 0
  backgroundColor: Colors.red,
  textColor: Colors.white,
  child: IconButton(
    icon: Icon(Icons.mail),
    onPressed: () {},
  ),
)
// Automatically syncs with NotificationService.badgeCountStream in real-time

// Custom alignment
NotificationBadgeWidget(
  alignment: AlignmentDirectional(-12, -4),  // Top-left
  offset: Offset(4, -4),     // Fine-tune position
  child: YourWidget(),
)
```

**Features:**
- **Automatic sync** with NotificationService badge count (when count parameter omitted)
- **Manual mode** for custom counts (when count parameter provided)
- Uses Flutter's built-in Material 3 Badge widget
- Automatic overflow handling ("99+" for large counts)
- Optional hide-when-zero behavior
- Configurable polling interval (default: 1 second)
- Customizable colors and alignment
- Proper theming and accessibility support

**Use Cases:**
- Notification count badges on tab bars
- Unread message indicators
- Shopping cart item counts
- Alert indicators on settings buttons

## Testing

Use `MockNotificationService` in your tests:

```dart
import 'package:dreamic/test_utils/mock_notification_service.dart';

test('notification flow', () async {
  final mockService = MockNotificationService();
  
  // Simulate notification received
  await mockService.simulateNotificationReceived(
    NotificationPayload(title: 'Test', body: 'Test notification'),
  );
  
  // Verify notification was displayed
  expect(mockService.getDisplayedNotifications().length, 1);
});
```

See the [Testing Guide](../TESTING_GUIDE.md) for more examples.

## Rich Notifications

**Version:** Added in 0.2.0

Dreamic supports rich media notifications with images and action buttons.

### Images

Display images in notifications that are automatically downloaded and cached:

```dart
final service = NotificationService();

await service.showNotification(
  NotificationPayload(
    title: 'New Photo',
    body: 'Check out this amazing picture!',
    imageUrl: 'https://example.com/photo.jpg',
    route: '/photo/123',
  ),
);
```

**How it works:**
- Image is downloaded asynchronously (10-second timeout)
- Cached locally for 7 days to avoid redundant downloads
- Falls back to text-only notification if download fails
- Supported formats: JPG, PNG, GIF, WebP

**Platform implementations:**
- **Android**: BigPictureStyle with full-width expanded image
- **iOS/macOS**: Notification attachment
- **Web**: Not supported

**Manual cache management:**
```dart
import 'package:dreamic/app/helpers/notification_image_loader.dart';

// Clear all cached images
await NotificationImageLoader.clearCache();

// Remove images older than 3 days
await NotificationImageLoader.cleanupOldCache(Duration(days: 3));

// Download image manually
final imagePath = await NotificationImageLoader.downloadImage(
  'https://example.com/image.jpg',
  timeout: Duration(seconds: 5),
);
```

### Action Buttons

Add up to 3 interactive buttons to notifications:

```dart
await service.showNotification(
  NotificationPayload(
    title: 'New Message',
    body: 'Hey, how are you?',
    route: '/messages/456',
    actions: [
      NotificationAction(
        id: 'reply',
        label: 'Reply',
        icon: '@drawable/ic_reply', // Android only
        launchesApp: true,          // Opens app
      ),
      NotificationAction(
        id: 'mark_read',
        label: 'Mark Read',
        launchesApp: false,         // Background action
      ),
      NotificationAction(
        id: 'delete',
        label: 'Delete',
        icon: '@drawable/ic_delete',
        launchesApp: false,
      ),
    ],
  ),
);
```

**Handle action button taps:**
```dart
await NotificationService().initialize(
  onNotificationTapped: (route, data) {
    // Handle regular notification tap
    if (route != null) Navigator.pushNamed(context, route);
  },
  onNotificationAction: (actionId, route, data) {
    // Handle action button tap
    switch (actionId) {
      case 'reply':
        Navigator.pushNamed(context, '/compose', arguments: data);
        break;
      case 'mark_read':
        markMessageAsRead(data?['messageId']);
        break;
      case 'delete':
        deleteMessage(data?['messageId']);
        break;
    }
  },
);
```

**Platform support:**
- **Android**: Full support with icons
- **iOS**: Actions via notification categories (no custom icons)
- **Web**: Not supported

**Best practices:**
- Limit to 2-3 actions for best UX
- Use clear, action-oriented labels
- Consider authentication requirements (`requiresAuth`)
- Test on different Android manufacturers (behavior varies)

### Notification Channels (Android)

Android 8.0+ requires notification channels for granular control:

```dart
import 'package:dreamic/app/helpers/notification_channel_manager.dart';

// Access via NotificationService
final channelManager = NotificationService().channelManager;

// Use default channels (automatically created)
await service.showNotification(
  NotificationPayload(
    title: 'Urgent Alert',
    channelId: NotificationChannelManager.channelHighPriority,
  ),
);
```

**Default channels:**
- `channelHighPriority` - Critical alerts with max sound/vibration
- `channelDefault` - Standard notifications
- `channelLowPriority` - Non-urgent updates
- `channelSilent` - Background updates without sound

**Create custom channels:**
```dart
await channelManager?.createChannel(
  AndroidNotificationChannel(
    'promotions',
    'Promotional Offers',
    description: 'Deals and special offers',
    importance: Importance.low,
    playSound: true,
    enableVibration: false,
  ),
);

// Use your custom channel
await service.showNotification(
  NotificationPayload(
    title: 'Flash Sale!',
    channelId: 'promotions',
  ),
);
```

**Channel management:**
```dart
// List all channels
final channels = await channelManager?.getChannels();

// Delete channel (users will need to re-enable if recreated)
await channelManager?.deleteChannel('promotions');
```

**Important notes:**
- Channels can only be created, not modified (Android limitation)
- Users can customize channel settings (sound, vibration, importance)
- Deleting and recreating a channel requires users to re-enable it
- Channel importance determines notification behavior and priority

## Advanced Usage

### Custom Background Handler

If you need custom background notification logic:

```dart
@pragma('vm:entry-point')
Future<void> myBackgroundHandler(RemoteMessage message) async {
  // Your custom pre-processing
  await customLogic(message);
  
  // Use Dreamic's handler for standard processing
  await dreamicNotificationBackgroundHandler(message);
  
  // Your custom post-processing
  await moreCustomLogic(message);
}

// In main.dart
FirebaseMessaging.onBackgroundMessage(myBackgroundHandler);
```

### Foreground Message Callback

React to notifications while app is in foreground:

```dart
await NotificationService().initialize(
  onNotificationTapped: (route, data) {
    // Handle tap
  },
  onForegroundMessage: (payload) async {
    // React to notification arrival
    print('Received: ${payload.title}');
    
    // Update app state, refresh data, etc.
    appCubit.refreshNotifications();
  },
);
```

## Troubleshooting

### Notifications not showing in foreground

Make sure you set `showNotificationsInForeground: true` in `initialize()`.

### Background handler not firing

Ensure you register the handler **before** `runApp()` in `main.dart`:

```dart
FirebaseMessaging.onBackgroundMessage(dreamicNotificationBackgroundHandler);
```

### Permission prompt not showing (iOS)

On iOS, once permissions are denied, you cannot show the prompt again. Users must enable notifications in Settings. Use `NotificationService().openSystemSettings()` to help them.

### Routing not working

Verify your notification data includes a `route` field:

```json
{
  "data": {
    "route": "/your/route",
    "additionalData": "..."
  }
}
```

## Migration from Custom Implementation

See the [Migration Guide](NOTIFICATION_MIGRATION_GUIDE.md) for step-by-step instructions on migrating from a custom notification implementation to this service.

## API Reference

For detailed API documentation, see the dartdoc comments in:
- `NotificationService` - Core service
- `NotificationPayload` - Notification data model
- `NotificationPermissionHelper` - Permission utilities
- `NotificationPermissionBottomSheet` - UI component

## FAQ

**Q: Do I need to add notification entitlements if I don't use this service?**
A: No. This is an optional feature. If you don't initialize `NotificationService`, no notification-related code runs and no entitlements are needed.

**Q: Can I use this with go_router / Navigator 2.0?**
A: Yes! The `onNotificationTapped` callback is framework-agnostic. Use your router's navigation method in the callback.

**Q: Does this work on web?**
A: Yes, but with limitations. Web notifications require service workers and user permission. Badge counts use page title as fallback.

**Q: What about notification channels on Android?**
A: A default high-priority channel is created automatically. Custom channels can be created via `NotificationService` API (coming soon).

**Q: How do I handle notification action buttons?**
A: Action button support is coming in a future update. Use the `onNotificationAction` callback when available.

## Support

For issues or questions:
1. Check the [troubleshooting section](#troubleshooting)
2. Review the [Migration Guide](NOTIFICATION_MIGRATION_GUIDE.md)
3. Check the [Testing Guide](../TESTING_GUIDE.md)
4. Open an issue on GitHub
