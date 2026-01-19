# Dreamic Package - Features Guide

A comprehensive guide to all features available in the Dreamic package for Flutter/Firebase applications.

## Table of Contents

- [Authentication](#authentication)
- [Notifications](#notifications)
- [App Configuration & Remote Config](#app-configuration--remote-config)
- [Network Management](#network-management)
- [App State Management](#app-state-management)
- [Version Management & Updates](#version-management--updates)
- [Loading States & UI](#loading-states--ui)
- [Error Handling](#error-handling)
- [Testing](#testing)
- [Utilities](#utilities)
- [Presentation Components](#presentation-components)
- [Repository Patterns](#repository-patterns)

---

## Authentication

### AuthServiceImpl & AuthServiceInt

Location: `lib/data/repos/auth_service_impl.dart`, `lib/data/repos/auth_service_int.dart`

Comprehensive Firebase Authentication service with multiple authentication methods and advanced features.

#### Key Features

**Login Methods:**
- Email/Password authentication
- Phone number authentication with SMS verification
- Email link authentication (passwordless)
- Anonymous authentication
- Custom token authentication
- Access code-based authentication
- Dev-only authentication (for development)

**Authentication State Management:**
```dart
// Check if user is logged in asynchronously
final isLoggedIn = await authService.isLoggedInAsync();

// Listen to login state changes
authService.isLoggedInStream.listen((isLoggedIn) {
  // Handle login state changes
});

// Wait for auth state to be ready
await authService.waitForCanCheckLoginState();

// Force refresh auth state
await authService.forceRefreshAuthState();
```

**Advanced Features:**
- Token validation with caching (5-minute cache for performance)
- Cookie-based federated auth for multi-domain authentication
- Automatic token refresh handling
- Network-aware authentication (handles offline scenarios)
- Firebase Cloud Messaging (FCM) initialization
- User claims management

**Firebase Cloud Messaging (FCM):**
```dart
// FCM is automatically initialized when enabled in AppConfigBase
// Token updates are handled automatically
// APNS token handling for iOS/macOS
```

**Cookie-Based Federated Auth:**
- Supports multi-domain authentication
- Automatic cookie management via Cloud Functions
- Handles sign-in and sign-out across domains

**User Claims:**
```dart
// Get custom claims for a user
final claims = await authService.getUserClaims<MyClaimsEnum>(
  enumValues: MyClaimsEnum.values,
  forceRefresh: true,
);
```

**Access Code System:**
```dart
// Validate access code
final result = await authService.accessCodeCheckIfValid('CODE123');
result.fold(
  (failure) => print('Error checking code'),
  (data) {
    final (validity, welcomeMessage) = data;
    if (validity == AccessCodeCheckReturn.valid) {
      print('Welcome: $welcomeMessage');
    }
  },
);

// Register with access code
await authService.accessCodeRegisterWithEmailAndPassword(
  email,
  password,
);
```

**Error Types:**
- `AuthServiceSignInFailure`: Invalid email, user not found, wrong password, weak password, etc.
- `AuthServiceEmailLinkFailure`: Invalid link, expired code, etc.
- `PhoneAuthError`: Invalid phone, wrong SMS code, too many requests, etc.
- `AuthServiceSignOutFailure`: Sign out errors

**Callbacks:**
```dart
GetIt.I.registerSingleton<AuthServiceInt>(
  AuthServiceImpl(
    firebaseApp: fbApp,
    onAuthenticated: (uid) async {
      // Called when user signs in or on app start if already logged in
      // uid is the Firebase user ID

      // Example: Initialize RevenueCat with user ID
      if (uid != null) {
        final email = g<AuthServiceInt>().currentFbUser?.email;
        await initRevenueCat(uid, email);
      }

      // Clear caches or refresh data as needed
    },
    onLoggedOut: () async {
      // Called when user signs out
      // Clear all cached data
      g<InputRepoInt>().clearCache();
      await g<UserRepoInt>().clearCache();
      g<GlobalCubit>().clearCache();
    },
  ),
);
```

> **Note:** FCM token management is handled by `NotificationService`, not `AuthServiceImpl`.
> Configure FCM via `AppConfigBase.useFCM` (defaults true on mobile, false on iOS simulator)
> and `AppConfigBase.useFCMWeb` (defaults false, requires VAPID setup).

**Important Notes:**
- `onAuthenticated` is called with `uid` parameter (nullable String)
- `onRefreshed` callback was removed in recent versions
- Use `onAuthenticated` for initialization tasks that depend on user authentication
- Use `onLoggedOut` to clean up user-specific data

**Best Practices:**
1. Always use `isLoggedInAsync()` instead of checking `currentFbUser` directly
2. Wait for `waitForCanCheckLoginState()` before checking auth status on app start
3. Use `forceRefreshAuthState()` when you need to ensure the latest auth state
4. Handle network errors gracefully - the service trusts Firebase's local state during network issues
5. The service automatically caches auth state for 30 seconds for performance

---

## Notifications

### NotificationService

Location: `lib/notifications/notification_service.dart`

**Version:** Added in 0.2.0

Complete notification system that reduces ~300 lines of boilerplate to one `initialize()` call. Handles Firebase Cloud Messaging (FCM), local notifications, permissions, and routing.

**This feature is completely optional.** Zero impact until initialized.

#### Quick Setup

```dart
// 1. In main.dart (before runApp)
import 'package:dreamic/notifications/notification_background_handler.dart';
import 'package:dreamic/notifications/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  // Register background handler
  FirebaseMessaging.onBackgroundMessage(dreamicNotificationBackgroundHandler);
  
  // Initialize service
  await NotificationService().initialize(
    onNotificationTapped: (route, data) async {
      if (route != null) Navigator.of(context).pushNamed(route);
    },
  );
  
  runApp(MyApp());
}

// 2. Request permissions when appropriate
await NotificationService().requestPermissions();
```

#### Platform Configuration

**iOS:**
```xml
<!-- ios/Runner/Info.plist -->
<key>UIBackgroundModes</key>
<array>
    <string>remote-notification</string>
</array>
```

**Android:**
```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.VIBRATE" />

<!-- Optional: Badge support for specific launchers -->
<!-- Samsung -->
<uses-permission android:name="com.sec.android.provider.badge.permission.READ"/>
<uses-permission android:name="com.sec.android.provider.badge.permission.WRITE"/>
<!-- HTC -->
<uses-permission android:name="com.htc.launcher.permission.READ_SETTINGS"/>
<uses-permission android:name="com.htc.launcher.permission.UPDATE_SHORTCUT"/>
<!-- Sony -->
<uses-permission android:name="com.sonyericsson.home.permission.BROADCAST_BADGE"/>
<uses-permission android:name="com.sonymobile.home.permission.PROVIDER_INSERT_BADGE"/>
<!-- Huawei -->
<uses-permission android:name="com.huawei.android.launcher.permission.CHANGE_BADGE"/>
<uses-permission android:name="com.huawei.android.launcher.permission.READ_SETTINGS"/>
<uses-permission android:name="com.huawei.android.launcher.permission.WRITE_SETTINGS"/>
```

> **Note:** Badge permissions are only needed if using `updateBadgeCount()`. Badge support varies by manufacturer.

#### Key Features

**Notification Management:**
```dart
final service = NotificationService();

// Show local notification
await service.showNotification(
  NotificationPayload(
    title: 'New Message',
    body: 'You have a new message',
    route: '/messages',
  ),
);

// Update badge count
await service.updateBadgeCount(5);
await service.clearBadge();

// Get FCM token
final token = await service.getFCMToken();
```

**Permission Management:**
```dart
// Check status
final status = await service.getPermissionStatus();
final isGranted = await service.isPermissionGranted();

// Request permissions
final newStatus = await service.requestPermissions();

// Open system settings
await service.openSystemSettings();
```

**Permission Helper:**
```dart
import 'package:dreamic/notifications/notification_permission_helper.dart';

final helper = NotificationPermissionHelper();

// Check if can prompt
final canPrompt = await helper.canPromptForPermission(); // False on iOS after denial

// Should show settings prompt
final shouldShowSettings = await helper.shouldShowSettingsPrompt();

// Get optimal timing context
final context = await helper.getOptimalContext();
print(context.message); // "Third time's the charm!"
```

#### UI Components

**Permission Bottom Sheet:**
```dart
import 'package:dreamic/presentation/elements/notification_permission_bottom_sheet.dart';

// Shows platform-native dialogs (Cupertino/Material)
// Fully customizable for localization
await NotificationPermissionBottomSheet.show(
  context,
  title: 'Enable Notifications',
  description: 'Stay informed with timely updates',
  allowButtonText: 'Allow Notifications',
  declineButtonText: 'Not Now',
  // Denied state dialog (iOS)
  deniedDialogTitle: 'Notifications Disabled',
  deniedDialogMessage: 'Go to Settings to enable notifications',
  openSettingsButtonText: 'Open Settings',
  maybeLaterButtonText: 'Maybe Later',
);
```

**Status Widget:**
```dart
import 'package:dreamic/presentation/elements/notification_permission_status_widget.dart';

NotificationPermissionStatusWidget(
  onEnablePressed: () async {
    await NotificationService().requestPermissions();
  },
)
```

**Permission Builder (Headless):**
```dart
import 'package:dreamic/presentation/elements/notification_permission_builder.dart';

// Build custom UIs with automatic status updates
NotificationPermissionBuilder(
  builder: (context, status, requestPermissions) {
    if (status == NotificationPermissionStatus.authorized) {
      return NotificationsList();
    }
    return ElevatedButton(
      onPressed: requestPermissions,
      child: Text('Enable Notifications'),
    );
  },
)
```

**Badge Count Widget:**
```dart
import 'package:dreamic/presentation/elements/notification_badge_widget.dart';

// Automatic mode - syncs with NotificationService
NotificationBadgeWidget(
  child: Icon(Icons.notifications),
)

// Manual mode - specific count
NotificationBadgeWidget(
  count: 5,
  maxCount: 99,           // Shows "99+"
  hideWhenZero: true,
  child: Icon(Icons.shopping_cart),
)
```

#### Rich Notifications

**Version:** Added in 0.2.0

**Images in Notifications:**
```dart
await service.showNotification(
  NotificationPayload(
    title: 'New Photo',
    body: 'Check out this amazing picture!',
    imageUrl: 'https://example.com/photo.jpg', // Auto-downloaded & cached
  ),
);
```

**Action Buttons (up to 3):**
```dart
await service.showNotification(
  NotificationPayload(
    title: 'New Message',
    actions: [
      NotificationAction(id: 'reply', label: 'Reply', launchesApp: true),
      NotificationAction(id: 'mark_read', label: 'Mark Read'),
    ],
  ),
);

// Handle in initialize()
await NotificationService().initialize(
  onNotificationAction: (actionId, route, data) {
    // Handle button tap
  },
);
```

**Features:**
- Automatic image download (10s timeout) + 7-day caching
- Android: BigPictureStyle, iOS: Attachments
- Graceful fallback if image fails
- Full route/data passed to handlers

#### Notification Channels (Android)

**Version:** Added in 0.2.0

```dart
// Use default channels
await service.showNotification(
  NotificationPayload(
    channelId: NotificationChannelManager.channelHighPriority,
  ),
);

// Available: channelHighPriority, channelDefault, channelLowPriority, channelSilent

// Create custom channel
final manager = NotificationService().channelManager;
await manager?.createChannel(AndroidNotificationChannel(...));
```

#### Data Models

**NotificationPayload:**
```dart
class NotificationPayload {
  final String? title;
  final String? body;
  final String? route;                        // Deep link route
  final Map<String, dynamic> data;            // Additional data
  final String? imageUrl;                     // Image URL (auto-downloaded)
  final List<NotificationAction> actions;     // Action buttons (up to 3)
  final int? id;                              // Notification ID
  final String? channelId;                    // Android channel
  final String? category;                     // iOS category
  final String? sound;                        // Custom sound
  final int? badge;                           // iOS badge count
  final int? ttl;                             // Time to live (seconds)
  final String? priority;                     // FCM priority
  
  // Create from FCM RemoteMessage
  factory NotificationPayload.fromRemoteMessage(RemoteMessage message);
  
  // JSON serialization
  factory NotificationPayload.fromJson(Map<String, dynamic> json);
  Map<String, dynamic> toJson();
}
```

**NotificationAction:**
```dart
class NotificationAction {
  final String id;                 // Unique action ID
  final String label;              // Button text
  final String? icon;              // Android icon (@drawable/name)
  final bool requiresAuth;         // Requires authentication
  final bool launchesApp;          // Opens app or background
  
  // JSON serialization
  factory NotificationAction.fromJson(Map<String, dynamic> json);
  Map<String, dynamic> toJson();
}
```

#### Dependencies

Automatically included in Dreamic 0.2.0+:
- `flutter_local_notifications: ^18.0.1` - Local notification display
- `app_badge_plus: ^1.1.5` - Badge management (iOS/Android/macOS)
- `adaptive_dialog: ^2.2.0` - Platform-native dialogs
- `http: ^1.5.0` - Image downloading
- `path_provider: ^2.1.5` - Cache directory access

#### Deferred Permission Flow

**Version:** Added in 0.3.0

Control when the notification permission prompt appears instead of asking immediately on login.

**Configuration:**
```dart
// In your app initialization
AppConfigBase.fcmAutoInitializeDefault = false;  // Disable auto-prompt on login
AppConfigBase.useFCMWebDefault = true;           // Enable FCM on web (opt-in)
```

**High-Level Flow (Recommended):**
```dart
// Trigger permission flow at the right moment (e.g., after onboarding)
final result = await NotificationService().runNotificationPermissionFlow(
  context,
  config: NotificationFlowConfig(
    askAgainAfter: const Duration(days: 7),  // Wait 7 days before re-asking
    maxAskCount: 3,                           // Max 3 attempts
    showGoToSettingsPrompt: true,             // Show settings prompt if denied
    strings: NotificationFlowStrings(
      valuePropositionTitle: l10n.notificationTitle,
      valuePropositionMessage: l10n.notificationDescription,
      // ... localized strings
    ),
  ),
);

// Handle result
switch (result) {
  case NotificationFlowResult.granted:
  case NotificationFlowResult.alreadyGranted:
    showSnackbar('Notifications enabled!');
    break;
  case NotificationFlowResult.deniedPermanently:
    // User must enable in settings
    break;
  // ... handle other cases
}
```

**Flow Handles Automatically:**
- Value proposition dialog before system prompt
- "Ask again" dialog with timing/count limits
- "Go to settings" dialog when permanently denied
- Web-specific instructions (can't open browser settings)
- Auto-detection when user returns from settings

**Low-Level Manual Control:**
```dart
// Check current status
final status = await NotificationService().getPermissionStatus();

// Manual initialization
final result = await NotificationService().initializeNotifications();

// Get denial tracking info
final denialInfo = await NotificationService().getNotificationDenialInfo();
if (denialInfo != null && denialInfo.denialCount >= 3) {
  // Maybe show settings prompt
}
```

#### FCM Token Management

**Version:** Added in 0.3.0

FCM token management is now consolidated in `NotificationService` (moved from `AuthServiceImpl`).

**Automatic Auth Integration:**
```dart
// NotificationService auto-wires to AuthService if registered in GetIt
await NotificationService().connectToAuthService(
  onTokenChanged: (newToken, oldToken) async {
    // Custom backend sync (optional - default uses Firebase callable)
    await myBackendService.updateFcmToken(newToken, oldToken);
  },
);
```

**Manual Token Management:**
```dart
// Initialize FCM token manually
await NotificationService().initializeFcmToken(
  onTokenChanged: (newToken, oldToken) async {
    await myBackendService.updateFcmToken(newToken, oldToken);
  },
);

// Get cached token
final token = NotificationService().cachedFcmToken;

// Clear token on logout
await NotificationService().clearFcmToken();
```

**Pre-Logout Cleanup:**
```dart
// Before signing out, unregister token while still authenticated
await NotificationService().preLogoutCleanup();
await authService.signOut();
```

#### App-Level Notification Toggle

**Version:** Added in 0.3.0

Allow users to enable/disable notifications at the app level (separate from OS permission).

```dart
// Check if enabled
final enabled = await NotificationService().isNotificationsEnabled();

// Disable (stops token sync, deletes local token)
await NotificationService().disableNotifications();

// Re-enable (requests permission if needed, syncs new token)
final result = await NotificationService().enableNotifications();
```

#### Best Practices

1. **Initialize early** - Call `initialize()` in `main()` before `runApp()`
2. **Request permissions contextually** - Show permission request at meaningful moments, not immediately on app start
3. **Use the high-level flow** - `runNotificationPermissionFlow()` handles edge cases automatically
4. **Customize all text** - Use localized strings for all UI text parameters
5. **Handle denied state** - Use `NotificationPermissionHelper` to check if you can prompt again
6. **Test badge support** - Badge functionality varies by Android manufacturer
7. **Use the background handler** - Always register `dreamicNotificationBackgroundHandler` for proper background message handling
8. **Optimize images** - Use reasonably sized images (< 2MB) to avoid slow downloads
9. **Limit action buttons** - Use 2-3 actions max for best UX
10. **Test on devices** - Rich notifications behave differently on various Android manufacturers
11. **Use appropriate channels** - Choose the right channel for notification importance
12. **Pre-logout cleanup** - Call `preLogoutCleanup()` before signing out to unregister tokens properly

#### Complete Documentation

This is a **quick reference**. For comprehensive documentation, see **[NOTIFICATION_GUIDE.md](NOTIFICATION_GUIDE.md)**:

**What's in the full guide:**
- Step-by-step setup instructions with platform configurations
- Permission request strategies (simple, with UI, periodic reminders)
- Rich notifications (images, action buttons, channels) with detailed examples
- FCM payload format and routing implementation
- UI components with localization examples
- Background message handling
- Troubleshooting common issues
- Migration guide from custom implementations

**Use this guide for:** Quick API reference and feature discovery  
**Use NOTIFICATION_GUIDE.md for:** Setup, best practices, and detailed implementation

---

## App Configuration & Remote Config

### AppConfigBase

Location: `lib/app/app_config_base.dart`

Central configuration system with Firebase Remote Config integration.

#### Configuration Sources (Priority Order)
1. **Environment Variables** (compile-time via `--dart-define`)
2. **Firebase Remote Config** (runtime, from Firebase console)
3. **Default Values** (fallback, defined in code)

#### Key Configuration Options

**Firebase Settings:**
```dart
// Backend region
AppConfigBase.backendRegion // Default: 'us-central1'

// Emulator settings
AppConfigBase.doUseBackendEmulator // Use Firebase emulator
AppConfigBase.backendEmulatorRemoteAddress // Emulator address

// FCM settings
AppConfigBase.useFCM              // Enable/disable FCM (auto-detects iOS simulator)
AppConfigBase.useFCMWeb           // Enable FCM on web (default: false, requires VAPID)
AppConfigBase.fcmAutoInitialize   // Auto-request permission on login (default: true)
```

**FCM Configuration (Deferred Permission):**

```dart
// Disable auto-permission prompt on login (wait for manual trigger)
AppConfigBase.fcmAutoInitializeDefault = false;

// Enable web FCM (requires VAPID key and service worker setup)
AppConfigBase.useFCMWebDefault = true;

// Or via build flags
// flutter run --dart-define FCM_AUTO_INITIALIZE=false --dart-define USE_FCM_WEB=true
```

| Config | Default | Description |
|--------|---------|-------------|
| `useFCM` | `true` (except iOS simulator) | Master FCM toggle |
| `useFCMWeb` | `false` | Web FCM toggle (requires VAPID setup) |
| `fcmAutoInitialize` | `true` | Auto-request permission on login |

**When to disable `fcmAutoInitialize`:**
- You want to show a value proposition before requesting permission
- You want to delay the prompt until after onboarding
- You need fine-grained control over the permission flow

**When to enable `useFCMWeb`:**
- You've configured a VAPID key in Firebase Console
- You've set up the service worker (`web/firebase-messaging-sw.js`)
- You want push notifications in browsers

**App Version Management:**
```dart
// Minimum required versions by platform
AppConfigBase.minimumAppVersionRequiredApple
AppConfigBase.minimumAppVersionRequiredGoogle
AppConfigBase.minimumAppVersionRequiredWeb

// Recommended versions
AppConfigBase.minimumAppVersionRecommendedApple
AppConfigBase.minimumAppVersionRecommendedGoogle
AppConfigBase.minimumAppVersionRecommendedWeb
```

**Network & Performance:**
```dart
AppConfigBase.retryAttemptsCountMax // Default: 5 (1 in debug)
AppConfigBase.timeoutBeforeShowingLoadingMill // Default: 750ms
AppConfigBase.timeoutNetworkProcessMill // Default: 10000ms
AppConfigBase.firebaseFunctionTimeoutSecs // Default: 70s (540s in debug)
AppConfigBase.firebaseFunctionTimeoutSecsLong // Default: 140s
AppConfigBase.connectionCheckerUrlOverride // Override network check URL
```

**Logging:**
```dart
AppConfigBase.logLevel // 'debug', 'info', 'warn', 'error'
```

**Dev Settings:**
```dart
AppConfigBase.devOnlyUid // Dev-only user ID
AppConfigBase.devOnlyAutoGenerateNewUser // Auto-create dev users
AppConfigBase.signoutOnReload // Sign out on hot reload
```

**Setting Default Values:**
```dart
// In your app initialization
AppConfigBase.minimumAppVersionRequiredAppleDefault = '1.0.0';
AppConfigBase.logLevelDefault = 'info';
AppConfigBase.retryAttemptsCountMaxDefault = 3;
```

**Firebase Callable Functions:**
```dart
// Get a callable function
final callable = AppConfigBase.firebaseFunctionCallable('myFunction');
final result = await callable.call({'param': 'value'});
```

**Firebase Function Names:**

The package uses configurable Firebase Cloud Function names, allowing consuming apps to customize the function names used for authentication and notifications.

```dart
// Auth main callable (grouped function with action parameter)
AppConfigBase.authMainCallableFunction // Default: 'authMainCallable'

// Dev-only sign-in function
AppConfigBase.devOnlyDevSignInFunction // Default: 'devOnlyDevSignIn'

// FCM token update function (supports both standalone and grouped styles)
AppConfigBase.notificationsUpdateFcmTokenFunction // Default: 'notificationsUpdateFcmToken'
AppConfigBase.notificationsUpdateFcmTokenGroupFunction // Default: null (standalone)
AppConfigBase.notificationsUpdateFcmTokenAction // Default: 'updateFcmToken'
```

**Configuring Function Names:**
```dart
// In your app's main.dart, before Firebase initialization

// Simple rename of auth callable
AppConfigBase.authMainCallableFunctionDefault = 'myAuthCallable';

// Rename dev-only sign-in
AppConfigBase.devOnlyDevSignInFunctionDefault = 'myDevSignIn';

// Option 1: Standalone FCM function (default behavior)
AppConfigBase.notificationsUpdateFcmTokenFunctionDefault = 'myFcmTokenFunction';

// Option 2: Grouped FCM function (call a main callable with action parameter)
AppConfigBase.notificationsUpdateFcmTokenGroupFunctionDefault = 'notificationsMain';
AppConfigBase.notificationsUpdateFcmTokenActionDefault = 'updateToken';
// This will call: notificationsMain({'action': 'updateToken', ...data})
```

**How Grouped Functions Work:**
- If `GroupFunction` is **not set** (null/empty) → calls the standalone function directly
- If `GroupFunction` **is set** → calls the group function with `{'action': actionName, ...data}`

This allows you to either:
1. Use individual Cloud Functions for each operation (standalone style)
2. Use a single Cloud Function that handles multiple operations via an `action` parameter (grouped style)

**Environment Variables:**
You can also configure function names via dart-define:
```bash
flutter run \
  --dart-define=AUTH_MAIN_CALLABLE_FUNCTION=myAuthCallable \
  --dart-define=DEV_ONLY_DEV_SIGN_IN_FUNCTION=myDevSignIn \
  --dart-define=NOTIFICATIONS_UPDATE_FCM_TOKEN_FUNCTION=myFcmFunction \
  --dart-define=NOTIFICATIONS_UPDATE_FCM_TOKEN_GROUP_FUNCTION=notificationsMain \
  --dart-define=NOTIFICATIONS_UPDATE_FCM_TOKEN_ACTION=updateToken
```

**Platform Detection:**
```dart
AppConfigBase.isSimulatorDevice // True if running on iOS simulator
await AppConfigBase.init(); // Initialize platform detection
```

**Best Practices:**
1. Initialize AppConfigBase early in your app startup: `await AppConfigBase.init()`
2. Use Remote Config for values that may need to change without app updates
3. Use environment variables for per-environment configuration (dev/staging/prod)
4. Set sensible defaults for all configuration values
5. Use `firebaseFunctionCallable()` for consistent Firebase function setup

### Git Build Information

Dreamic supports injecting git build information at compile time for precise build identification in error reporting, analytics, and debugging.

#### Git Info Getters

```dart
// Git branch name (sanitized: / and \ replaced with -)
AppConfigBase.gitBranch // e.g., "feature-login" (from "feature/login")

// Git tag (for release builds)
AppConfigBase.gitTag // e.g., "v1.0.0"

// Git commit SHA (short, 7 characters)
AppConfigBase.gitCommit // e.g., "abc1234"
```

#### App Release Strings

```dart
// Basic release string (version info only)
final basic = await AppConfigBase.getAppReleaseBuild();
// Returns: "my-app@1.0.0+42"

// Full release string with git info
final full = await AppConfigBase.getAppReleaseFullInfo();
// Returns vary based on available git info (see table below)
```

**Release String Formats:**

| Build Type | Format | Example |
|------------|--------|---------|
| Tag build | `app@ver+build_tag-{tag}` | `my-app@1.0.0+42_tag-v1.0.0` |
| Branch + commit | `app@ver+build_{branch}_{sha}` | `my-app@1.0.0+42_feature-login_abc1234` |
| Branch only | `app@ver+build_{branch}` | `my-app@1.0.0+42_feature-login` |
| Commit only | `app@ver+build_{sha}` | `my-app@1.0.0+42_abc1234` |
| No git info | `app@ver+build` | `my-app@1.0.0+42` |

#### Local Development Builds

```bash
# With branch and commit
flutter run \
  --dart-define=GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD) \
  --dart-define=GIT_COMMIT=$(git rev-parse --short HEAD)

# Tag build (for releases)
flutter build ios --dart-define=GIT_TAG=$(git describe --tags --exact-match 2>/dev/null || echo "")
```

#### GitHub Actions Workflow

GitHub Actions checks out code in detached HEAD mode, so `git rev-parse --abbrev-ref HEAD` won't work. Use GitHub's environment variables instead:

```yaml
name: Build Flutter App

on:
  push:
    branches: [main, develop]
    tags: ['v*']
  pull_request:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Set up Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.x'
      
      - name: Determine git info
        id: git_info
        run: |
          # Short commit SHA (7 chars)
          echo "commit=$(echo $GITHUB_SHA | cut -c1-7)" >> $GITHUB_OUTPUT
          
          # Branch or tag
          if [[ "${{ github.ref_type }}" == "tag" ]]; then
            echo "tag=${{ github.ref_name }}" >> $GITHUB_OUTPUT
            echo "branch=" >> $GITHUB_OUTPUT
          elif [[ "${{ github.event_name }}" == "pull_request" ]]; then
            echo "branch=${{ github.head_ref }}" >> $GITHUB_OUTPUT
            echo "tag=" >> $GITHUB_OUTPUT
          else
            echo "branch=${{ github.ref_name }}" >> $GITHUB_OUTPUT
            echo "tag=" >> $GITHUB_OUTPUT
          fi
      
      - name: Build iOS
        run: |
          flutter build ios --release \
            --dart-define=GIT_BRANCH=${{ steps.git_info.outputs.branch }} \
            --dart-define=GIT_TAG=${{ steps.git_info.outputs.tag }} \
            --dart-define=GIT_COMMIT=${{ steps.git_info.outputs.commit }} \
            --dart-define=ENVIRONMENT_TYPE=production
```

**Key points:**
- `GITHUB_SHA` - Full commit SHA (use `cut -c1-7` for short version)
- `GITHUB_REF_NAME` - Branch name for pushes, tag name for tag pushes
- `GITHUB_HEAD_REF` - Source branch name for pull requests
- `github.ref_type` - Either `'branch'` or `'tag'`

#### Branch Name Sanitization

Branch names like `feature/user-auth` contain `/` which is prohibited by Sentry in release names. Dreamic automatically sanitizes branch names when building release strings:

- `feature/login` → `feature-login`
- `bugfix\issue-123` → `bugfix-issue-123`

The raw `gitBranch` getter returns the original value; sanitization happens in `getAppReleaseFullInfo()`.

---

## Network Management

### NetworkUtils

Location: `lib/utils/network_utils.dart`

Comprehensive network connectivity detection and Firebase emulator discovery.

#### Features

**Firebase Emulator Host Discovery:**
```dart
// Automatically discover Firebase emulator on local network
final host = await NetworkUtils.discoverFirebaseEmulatorHost(port: 5001);

// Returns:
// - '127.0.0.1' on web
// - Cached address if available and still valid
// - Discovered IP address on local network
// - null if not found
```

**Smart Discovery Strategy:**
1. Tests cached address first (from SharedPreferences)
2. Tests localhost
3. Scans device's network subnets
4. Tests common network ranges (home networks, hotspots, corporate networks)
5. Uses parallel batch scanning for performance (20 IPs at a time)
6. Prioritizes common gateway IPs (1, 100, 101, 102, etc.)

**Device IP Address Detection:**
```dart
// Get all network interfaces and IP addresses
final deviceIps = await NetworkUtils.getDeviceIpAddresses();
// Returns: ['192.168.1.50', '10.0.0.123', ...]
```

**Cache Management:**
- Automatically caches discovered emulator address
- Validates cached address before use
- Clears cache if address becomes invalid

**Network Check with AppCubit:**
```dart
// AppCubit automatically checks network connectivity
// Uses InternetConnectionChecker for continuous monitoring
// Emits network status changes

// In your UI:
BlocBuilder<AppCubit, AppState>(
  builder: (context, state) {
    if (state.networkStatus == NetworkStatus.none) {
      return NetworkErrorWidget();
    }
    return YourContent();
  },
);
```

### ConnectionToaster

Location: `lib/presentation/elements/connection_toaster.dart`

Optional UI component that displays toast notifications for network status changes.

#### Features

**Automatic Toast Display:**
- Shows "Connecting..." toast when network connection is lost
- Automatically dismisses when connection is restored
- Smart behavior that avoids intrusive toasts during app startup/resume
- Configurable delay before showing toast
- Always appears above all other UI elements

**Configuration Options:**
```dart
ConnectionToaster(
  showOnInitialConnection: false,        // Show toast during app startup/resume
  delayBeforeShowing: Duration.zero,     // Delay before showing toast
  child: yourWidget,
)
```

**Smart Behavior:**
- By default, does NOT show toast when `AppStatus.loading` (initial app load/resume)
- Only shows toasts for actual connection losses during normal app usage
- This prevents intrusive "Connecting..." messages every time the app resumes

**Delay Handling:**
- Default: `Duration.zero` (immediate display when conditions are met)
- After delay, verifies connection is still down before showing toast
- Prevents flashing toasts for brief network hiccups when delay is configured

**Usage Patterns:**

**Default (recommended):**
```dart
ConnectionToaster(
  child: yourApp,
)
// No toast on app startup/resume, immediate toast on connection loss during normal usage
```

**With custom delay:**
```dart
ConnectionToaster(
  delayBeforeShowing: Duration(seconds: 1),
  child: yourApp,
)
// Wait 1 second before showing toast, allowing quick reconnections to complete
```

**Show on initial connection:**
```dart
ConnectionToaster(
  showOnInitialConnection: true,
  child: yourApp,
)
// Show toast even during app startup/resume network checks
```

**Integration with AppRootWidget:**

`ConnectionToaster` can be optionally enabled via `AppRootWidget`:

```dart
AppRootWidget(
  useConnectionToaster: true,  // Enable ConnectionToaster
  showConnectionToastOnInitialConnection: false,  // Don't show on resume (default)
  connectionToastDelay: Duration.zero,  // Immediate display (default)
  child: yourApp,
)
```

**Best Practices:**
1. Enable `useConnectionToaster` for apps that need visible network status feedback
2. Keep `showOnInitialConnection` as `false` (default) to avoid intrusive toasts on app resume
3. Use default zero delay for most responsive feedback
4. Set a delay (e.g., 1-2 seconds) if your app has frequent brief connection checks
5. The toast automatically handles multiple concurrent network status changes

**Best Practices:**
1. Always use `isLoggedInAsync()` instead of checking `currentFbUser` directly
2. Wait for `waitForCanCheckLoginState()` before checking auth status on app start
3. Use `forceRefreshAuthState()` when you need to ensure the latest auth state
4. Handle network errors gracefully - the service trusts Firebase's local state during network issues
5. The service automatically caches auth state for 30 seconds for performance

---

## App State Management

### AppCubit

Location: `lib/app/app_cubit.dart`

Central application state management using Bloc/Cubit pattern.

#### State Properties

```dart
class AppState {
  final AppStatus appStatus;           // loading, loaded, error
  final NetworkStatus networkStatus;   // connected, disconnected
  final String? networkErrorMessage;
  final bool showOverlayProgress;      // Loading overlay visibility
  final VersionUpdateInfo? versionUpdateInfo; // App update information
}
```

#### Features

**Initialization:**

`AppCubit` is automatically initialized when you use `AppRootWidget`:

```dart
// AppRootWidget automatically calls appCubit.getInitialData()
return AppRootWidget(
  child: child!,
);
```

If you're setting up manually:

```dart
// 1. Register in GetIt during app initialization
GetIt.I.registerSingleton<AppCubit>(AppCubit(
  entranceUri: kIsWeb ? Uri.parse(getCurrentLocation()) : null,
  networkRequired: true, // Whether network is required on startup
));

// 2. AppRootWidget will automatically call getInitialData()
// Or manually call if not using AppRootWidget:
await GetIt.I.get<AppCubit>().getInitialData();
```

**What `getInitialData()` does:**
- Initializes `AppVersionUpdateService` for version checking
- Initializes `AppLifecycleService` for app resume/pause handling
- Starts network connectivity monitoring (if `networkRequired` is true)
- Sets up version update stream subscription

**Network Monitoring:**
- Continuous network connectivity checking
- Automatic reconnection detection
- Network status events in state
- Configurable network requirement

**Version Update Monitoring:**
- Automatic version checking
- Required vs recommended update detection
- Integration with AppVersionUpdateService

**App Lifecycle Management:**
- Responds to app resume/pause events
- Triggers version checks on app resume
- Integration with AppLifecycleService

**Loading Overlay Control:**
```dart
// Show loading overlay
appCubit.overlayLoadingStart();

// Hide loading overlay
appCubit.overlayLoadingFinish();

// Check if overlay is visible
final isVisible = appCubit.state.showOverlayProgress;
```

**Best Practices:**
1. Create AppCubit early in your app initialization
2. Inject it via dependency injection (GetIt)
3. Always dispose of it when done: `await appCubit.close()`
4. Use `BlocProvider` to make it available throughout your widget tree
5. Set `networkRequired` based on your app's needs

### CubitBase

Location: `lib/presentation/helpers/cubit_base.dart`

Base class for all Cubits with safe emission and standard state management.

```dart
abstract class CubitBase<T extends CubitBaseState> extends Cubit<T> 
    with SafeEmitMixin<T> {
  CubitBase(super.initialState);
}

// Your cubits:
class MyCubit extends CubitBase<MyState> {
  MyCubit() : super(MyState.initial());
  
  Future<void> loadData() async {
    emitSafe(state.copyWith(status: PageStatus.loading));
    // Load data...
    emitSafe(state.copyWith(status: PageStatus.loaded));
  }
}
```

---

## Version Management & Updates

### AppVersionUpdateService

Location: `lib/app/helpers/app_version_update_service.dart`

Automatic app version checking and update notifications using Firebase Remote Config.

#### Features

**Initialization:**

The service is **automatically initialized** when you use `AppRootWidget` (which calls `AppCubit.getInitialData()`). You don't need to manually initialize it.

However, if you're not using `AppRootWidget`, you need to initialize it manually:

```dart
// In your AppCubit or main app initialization
await AppVersionUpdateService().initialize();

// Listen to version update events
AppVersionUpdateService().updateStream.listen((versionInfo) {
  if (versionInfo.isRequired) {
    // Show required update dialog
  } else if (versionInfo.isRecommended) {
    // Show optional update prompt
  }
});
```

**Important:** The service must be initialized **after** Remote Config is set up, as it depends on Remote Config values for version checking.

**Version Update Types:**
```dart
enum VersionUpdateType {
  none,         // No update needed
  recommended,  // Optional update available
  required,     // Must update to continue
}

class VersionUpdateInfo {
  final VersionUpdateType updateType;
  final String currentVersion;
  final String requiredVersion;
  final String recommendedVersion;
  final String appStoreUrl;
  
  bool get hasUpdate;
  bool get isRequired;
  bool get isRecommended;
  String get targetVersion;
}
```

**Automatic Checks:**
- Checks version on initialization
- Listens to Remote Config changes
- Triggers check on app resume (after 5+ minutes)
- Web support via polling

**Manual Check:**
```dart
// Force a version check
await AppVersionUpdateService().forceVersionCheck();
```

**Integration with Remote Config:**
The service automatically reads from Remote Config:
- `minimumAppVersionRequiredApple`
- `minimumAppVersionRequiredGoogle`
- `minimumAppVersionRequiredWeb`
- `minimumAppVersionRecommendedApple`
- `minimumAppVersionRecommendedGoogle`
- `minimumAppVersionRecommendedWeb`

**Best Practices:**
1. Initialize once at app startup, after Remote Config
2. Subscribe to `updateStream` in your AppCubit or root widget
3. Show appropriate UI based on update type (required vs recommended)
4. Set minimum versions in Firebase Remote Config console
5. Update Remote Config values to trigger version checks across all users

### AppLifecycleService

Location: `lib/app/helpers/app_lifecycle_service.dart`

Monitors app lifecycle events and triggers appropriate actions.

**Automatic Initialization:**
The service is **automatically initialized** by `AppCubit.getInitialData()` when using `AppRootWidget`. You don't need to manually initialize it.

**Manual Setup (if not using AppRootWidget):**
```dart
// Initialize service
AppLifecycleService().initialize();

// Listen to lifecycle events (optional)
AppLifecycleService().lifecycleStream.listen((state) {
  if (state == AppLifecycleState.resumed) {
    // App came to foreground
  }
});

// Clean up
AppLifecycleService().dispose();
```

**Features:**
- Automatic version check on app resume (after 5-minute cooldown)
- Lifecycle state stream for custom actions
- Singleton pattern for global access
- Integrated with `AppVersionUpdateService` for automatic version checking

**Cooldown Behavior:**
- Version checks are only triggered on app resume if the app was paused for 5+ minutes
- This prevents excessive version checks and respects Firebase Remote Config fetch limits
- First resume always triggers a version check

---

## Loading States & UI

### Loading Wrapper

Location: `lib/presentation/helpers/loading_wrapper.dart`

Intelligent loading overlay that shows only after a timeout, preventing flicker on fast operations.

#### Usage

```dart
// Show loading after 750ms (configurable)
final result = await callWithLoadingAfterTimeout(() async {
  return await someAsyncOperation();
});

// Custom timeout
final result = await callWithLoadingAfterTimeout(
  () async => await someAsyncOperation(),
  timeoutBeforeLoadingMill: 1000, // 1 second
);

// Custom callbacks
final result = await callWithLoadingAfterTimeout(
  () async => await someAsyncOperation(),
  onLoadingStart: () => print('Loading started'),
  onLoadingFinish: () => print('Loading finished'),
  onError: (error) => print('Error: $error'),
);
```

**Features:**
- Only shows loading if operation takes longer than threshold
- Prevents loading flicker on fast operations
- Supports multiple concurrent loading operations
- Automatic reference counting (shows until all operations complete)
- Configurable callbacks
- Error handling

**Configuration:**
```dart
// Configure global callbacks
configureTimeoutLoadingCallbacks(
  onLoadingStart: () => myCustomLoadingStart(),
  onLoadingFinish: () => myCustomLoadingFinish(),
);

// Reset state if needed
resetLoadingState();
```

**Default Behavior:**
- Default timeout: 750ms (from `AppConfigBase.timeoutBeforeShowingLoadingMill`)
- Default callbacks: Uses `AppCubit.overlayLoadingStart/Finish()`
- Handles multiple concurrent operations gracefully

### LoadingRetryWrapper

Location: `lib/presentation/helpers/loading_retry_wrapper.dart`

Similar to LoadingWrapper but with retry capability for failed operations.

### Page Status System

Location: `lib/presentation/helpers/page_statuses.dart`

Standard status enums for consistent state management.

```dart
enum PageStatus {
  loading,          // Initial load
  loaded,           // Successfully loaded
  processingAction, // Performing an action
  empty,            // No data
  error,            // Error occurred
  errorRetryable,   // Error with retry option
}

enum WidgetStatus {
  initial,          // Not started
  loading,
  loaded,
  processingAction,
  empty,
  error,
}
```

**Usage in Cubits:**
```dart
class MyState extends CubitBaseState {
  final PageStatus status;
  final List<Item> items;
  final String? errorMessage;
}

// In cubit:
emitSafe(state.copyWith(status: PageStatus.loading));
// Fetch data...
emitSafe(state.copyWith(
  status: PageStatus.loaded,
  items: fetchedItems,
));
```

---

## Error Handling

### Custom Error Reporting

Location: `lib/app/helpers/error_reporter_interface.dart`, `lib/app/helpers/app_errorhandling_init.dart`

Dreamic supports flexible error reporting through custom error reporting SDKs (like Sentry, Bugsnag, etc.) in addition to or instead of Firebase Crashlytics.

#### Overview

The error reporting system uses an `ErrorReporter` interface that allows you to plug in any error reporting service. This works seamlessly with both manual error logging (via `Logger`) and automatic error capturing.

#### Error Reporter Interface

```dart
abstract class ErrorReporter {
  /// Initialize the error reporter (e.g., Sentry.init)
  Future<void> initialize();
  
  /// Record a generic error
  void recordError(Object error, StackTrace? stackTrace);
  
  /// Record a Flutter-specific error
  void recordFlutterError(FlutterErrorDetails details);
}
```

#### Configuration Options

```dart
class ErrorReportingConfig {
  final bool useFirebaseCrashlytics;        // Enable Firebase Crashlytics
  final ErrorReporter? customReporter;       // Custom error reporter (e.g., Sentry)
  final bool customReporterManagesErrorHandlers; // True if custom reporter sets up handlers
  final bool enableInDebug;                  // Report errors in debug mode
  final bool enableOnWeb;                    // Report errors on web platform
}
```

#### Setup Scenarios

**Scenario 1: Firebase Crashlytics Only (Default)**
```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Firebase only - no custom config needed
  await appInitErrorHandling();
  
  // Or explicitly:
  await appInitErrorHandling(
    config: ErrorReportingConfig.firebaseOnly(
      enableInDebug: false,  // Don't report in debug mode
      enableOnWeb: true,     // Report on web
    ),
  );
  
  runApp(MyApp());
}
```

**Scenario 2: Sentry with appRunner (Recommended)**

Use Sentry's recommended `appRunner` pattern:

```dart
import 'package:flutter/widgets.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:dreamic/dreamic.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Use Sentry's recommended initialization
  await SentryFlutter.init(
    (options) {
      options.dsn = 'your-sentry-dsn';
      options.environment = AppConfigBase.environmentType.value;
      options.release = await AppConfigBase.getAppRelease();
      options.tracesSampleRate = 1.0;
    },
    // Use appRunner with appRunIfValidVersion for version checking
    appRunner: () => appRunIfValidVersion(() => MyApp()),
  );
}
```

**Scenario 3: Sentry Manual Setup (Advanced)**

Implement the full `ErrorReporter` interface for more control:

```dart
class SentryErrorReporter implements ErrorReporter {
  @override
  Future<void> initialize() async {
    // Do NOT use appRunner here - error handlers managed by Dreamic
    await SentryFlutter.init((options) {
      options.dsn = 'your-sentry-dsn';
      options.environment = AppConfigBase.environmentType.value;
      options.release = await AppConfigBase.getAppRelease();
      options.tracesSampleRate = 1.0;
    });
  }
  
  @override
  void recordError(Object error, StackTrace? stackTrace) {
    Sentry.captureException(error, stackTrace: stackTrace);
  }
  
  @override
  void recordFlutterError(FlutterErrorDetails details) {
    Sentry.captureException(
      details.exception,
      stackTrace: details.stack,
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  configureErrorReporting(
    ErrorReportingConfig.customOnly(
      reporter: SentryErrorReporter(),
      enableOnWeb: true,
    ),
  );
  
  await appInitErrorHandling();
  
  runApp(MyApp());
}
```

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await appInitErrorHandling(
    config: ErrorReportingConfig.customOnly(
      reporter: SentryErrorReporter(),
      managesOwnErrorHandlers: false, // Dreamic manages error handlers
      enableInDebug: true,
    ),
  );
  
  runApp(MyApp());
}
```

**Scenario 3: Sentry Only (Using SentryFlutter.init Wrapper)**
```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Configure error reporting BEFORE SentryFlutter.init
  await configureErrorReporting(
    ErrorReportingConfig.customOnly(
      reporter: SentryErrorReporter(),
      managesOwnErrorHandlers: true, // Sentry manages error handlers
      enableInDebug: true,
    ),
  );
  
  // Sentry's wrapper sets up error handlers
  await SentryFlutter.init(
    (options) {
      options.dsn = 'your-sentry-dsn';
      options.tracesSampleRate = 1.0;
    },
    appRunner: () => appRunIfValidVersion(() => MyApp()),
  );
}
```

**Scenario 4: Both Firebase and Sentry (Manual Setup)**
```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase first
  final fbApp = await appInitFirebase(DefaultFirebaseOptions.currentPlatform);
  
  // Both services with Dreamic managing handlers
  await appInitErrorHandling(
    config: ErrorReportingConfig.both(
      reporter: SentryErrorReporter(),
      customReporterManagesErrorHandlers: false, // Dreamic chains handlers
      enableInDebug: true,
    ),
  );
  
  runApp(MyApp());
}
```

**Scenario 5: Both Firebase and Sentry (Using SentryFlutter.init)**
```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase first
  final fbApp = await appInitFirebase(DefaultFirebaseOptions.currentPlatform);
  
  // Configure error reporting BEFORE SentryFlutter.init
  await configureErrorReporting(
    ErrorReportingConfig.both(
      reporter: SentryErrorReporter(),
      customReporterManagesErrorHandlers: true, // Sentry manages handlers
      enableInDebug: true,
    ),
  );
  
  // Sentry's wrapper sets up error handlers, Firebase is added to chain
  await SentryFlutter.init(
    (options) {
      options.dsn = 'your-sentry-dsn';
      options.tracesSampleRate = 1.0;
    },
    appRunner: () => appRunIfValidVersion(() => MyApp()),
  );
}
```

#### Error Capture Coverage

All error types are automatically captured when configured:

| Error Type | Captured By | When |
|------------|-------------|------|
| Flutter errors | `FlutterError.onError` | Synchronous widget errors |
| Async errors | `PlatformDispatcher.instance.onError` | Unhandled async exceptions |
| Isolate errors | `Isolate.current.addErrorListener` | Errors in isolates (non-web) |
| Manual errors | `Logger.error()` / `loge()` | Explicitly logged errors |

#### Manual Error Logging

Errors logged via `Logger` are automatically reported to configured services:

```dart
try {
  await riskyOperation();
} catch (e, stackTrace) {
  // Reports to Firebase and/or custom reporter based on config
  loge(e, 'Failed to perform risky operation', stackTrace);
}
```

#### Handler Management Modes

**`managesOwnErrorHandlers: false` (Default)**
- Dreamic sets up `FlutterError.onError` and `PlatformDispatcher.instance.onError`
- Dreamic chains handlers to report to both Firebase and custom reporter
- Recommended for most custom reporters

**`managesOwnErrorHandlers: true`**
- Custom reporter (e.g., `SentryFlutter.init`) sets up error handlers
- Dreamic adds Firebase reporting to the chain (if enabled)
- Required when using wrapper functions like `SentryFlutter.init`

#### Environment Control

Control when errors are reported:

```dart
ErrorReportingConfig.both(
  reporter: SentryErrorReporter(),
  enableInDebug: true,      // Report during development
  enableOnWeb: true,        // Report on web platform
)
```

**Default behavior:**
- `enableInDebug: false` - Don't report in debug mode
- `enableOnWeb: false` - Don't report on web (some services charge per event)

**Additional controls:**
- `AppConfigBase.doUseBackendEmulator` - Disables reporting when using Firebase emulator

#### Build Configuration (dart-define)

You can configure the build environment type using `--dart-define=ENVIRONMENT_TYPE`:

**Environment Configuration:**
```bash
# Development build
flutter build ios --dart-define=ENVIRONMENT_TYPE=development

# Staging build
flutter build android --dart-define=ENVIRONMENT_TYPE=staging

# Production build
flutter build web --dart-define=ENVIRONMENT_TYPE=production
```

**Access in code:**
```dart
// Access the environment type (uses ENVIRONMENT_TYPE dart-define)
final environment = AppConfigBase.environmentType; // Returns EnvironmentType enum
final environmentString = AppConfigBase.environmentType.value; // Returns string value
// Returns: EnvironmentType.development in debug, EnvironmentType.production in release, or your custom value
```

**Centralized App Version:**

Use `AppConfigBase` methods for version information instead of `PackageInfo` directly:

```dart
import 'package:dreamic/app/app_config_base.dart';

// Get full PackageInfo (cached after first call)
final packageInfo = await AppConfigBase.getAppVersion();

// Convenience methods
final version = await AppConfigBase.getAppVersionString();    // "1.0.0"
final build = await AppConfigBase.getAppBuildNumber();        // "42"
final release = await AppConfigBase.getAppRelease();          // "my-app@1.0.0+42"

// Use in your error reporter
class SentryErrorReporter implements ErrorReporter {
  @override
  Future<void> initialize() async {
    final release = await AppConfigBase.getAppRelease();
    
    // Do NOT use appRunner here - error handlers managed by Dreamic
    await SentryFlutter.init((options) {
      options.dsn = 'your-dsn';
      options.environment = AppConfigBase.environmentType.value;
      options.release = release;
    });
  }
}
```

**Recommended: Use Sentry's appRunner (No ErrorReporter needed):**

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await SentryFlutter.init(
    (options) {
      options.dsn = 'your-dsn';
      options.environment = AppConfigBase.environmentType.value;
      options.release = await AppConfigBase.getAppRelease();
      options.tracesSampleRate = 1.0;
    },
    appRunner: () => appRunIfValidVersion(() => MyApp()),
  );
}
```
```

**Benefits:**
- ✅ Single source of truth for version across your app
- ✅ Works correctly on Flutter Web (where `PackageInfo` can have issues)
- ✅ Cached for performance
- ✅ Consistent formatting for error reporting

#### Complete Example (Recommended: appRunner Pattern)

```dart
// main.dart
import 'package:flutter/widgets.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:dreamic/dreamic.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase if needed
  await appInitFirebase(DefaultFirebaseOptions.currentPlatform);
  
  // Use Sentry's recommended initialization with appRunner
  await SentryFlutter.init(
    (options) {
      options.dsn = 'your-sentry-dsn';
      options.environment = AppConfigBase.environmentType.value;
      options.release = await AppConfigBase.getAppRelease();
      options.tracesSampleRate = 1.0;
    },
    appRunner: () => appRunIfValidVersion(() => MyApp()),
  );
}
```

#### Alternative Example (Manual ErrorReporter Pattern)

```dart
// error_reporter.dart
import 'package:dreamic/app/helpers/error_reporter_interface.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:dreamic/dreamic.dart';

class SentryErrorReporter implements ErrorReporter {
  @override
  Future<void> initialize() async {
    // Do NOT use appRunner here - error handlers managed by Dreamic
    await SentryFlutter.init((options) {
      options.dsn = 'your-sentry-dsn';
      options.environment = AppConfigBase.environmentType.value;
      options.release = await AppConfigBase.getAppRelease();
      options.tracesSampleRate = 1.0;
    });
  }
  
  @override
  void recordError(Object error, StackTrace? stackTrace) {
    Sentry.captureException(error, stackTrace: stackTrace);
  }
  
  @override
  void recordFlutterError(FlutterErrorDetails details) {
    Sentry.captureException(
      details.exception,
      stackTrace: details.stack,
    );
  }
}

// main.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Set defaults
  AppConfigBase.appStoreAndroidUrlDefault = 'your-android-url';
  AppConfigBase.appStoreAppleUrlDefault = 'your-ios-url';
  
  // Initialize Firebase
  final fbApp = await appInitFirebase(DefaultFirebaseOptions.currentPlatform);
  
  // Set up error reporting with both Firebase and Sentry
  await appInitErrorHandling(
    config: ErrorReportingConfig.both(
      reporter: SentryErrorReporter(),
      customReporterManagesErrorHandlers: false,
      enableInDebug: true,
      enableOnWeb: true,
    ),
  );
  
  // Continue with rest of initialization
  await appInitRemoteConfig();
  await appInitAppConfigsBase();
  await appInitConnectToFirebaseEmulatorIfNecessary(fbApp);
  
  setupGetIt(fbApp);
  
  appRunIfValidVersion(() => MyApp());
}
```

#### Testing

The error reporting system is fully tested:

```dart
// All scenarios are tested:
✅ Firebase only
✅ Custom reporter only (manual)
✅ Custom reporter only (wrapper)
✅ Both services (manual)
✅ Both services (wrapper)

// All error types are tested:
✅ Flutter errors (FlutterError.onError)
✅ Async errors (PlatformDispatcher)
✅ Isolate errors
✅ Manual logging (Logger.error)
```

#### Best Practices

1. **Choose the right setup mode:**
   - Use `managesOwnErrorHandlers: false` for manual reporter initialization
   - Use `managesOwnErrorHandlers: true` when using wrapper functions like `SentryFlutter.init`

2. **Control reporting environments:**
   - Set `enableInDebug: false` in production to avoid development noise
   - Set `enableOnWeb` based on your service's pricing model

3. **Initialize in the correct order:**
   - Initialize Firebase first (if using)
   - Configure error reporting before any wrapper functions
   - Initialize your app last

4. **Use manual logging:**
   - Always log caught exceptions with `loge()` for visibility
   - Provides context that automatic capturing might miss

5. **Test your setup:**
   - Trigger test errors to verify both services receive them
   - Check both dashboards (Firebase Console, Sentry, etc.)

#### Additional Documentation

For more detailed information, see:
- **[ERROR_REPORTING_GUIDE.md](ERROR_REPORTING_GUIDE.md)** - Comprehensive error reporting integration guide with:
  - Detailed setup instructions for wrapper-based and manual initialization
  - Sentry integration examples (both approaches)
  - Bugsnag and custom service examples
  - Complete configuration reference
  - Error coverage details
  - Testing guide
  - Best practices
  - Troubleshooting section
  - Full API reference

### Repository Failure

Location: `lib/data/helpers/repository_failure.dart`

Standard error types for repository operations.

```dart
enum RepositoryFailure {
  unexpected,              // Unknown error
  networkError,            // Network connectivity issue
  expectedRecordNotFound,  // Expected data not found
  notAuthorizedToRead,     // Permission denied for read
  notAuthorizedToWrite,    // Permission denied for write
}
```

**Usage with Either (dartz):**
```dart
Future<Either<RepositoryFailure, User>> getUser(String id) async {
  try {
    final user = await firestore.collection('users').doc(id).get();
    if (!user.exists) {
      return left(RepositoryFailure.expectedRecordNotFound);
    }
    return right(User.fromFirestore(user));
  } catch (e) {
    return left(RepositoryFailure.unexpected);
  }
}

// Using the result:
final result = await repo.getUser('123');
result.fold(
  (failure) => print('Error: $failure'),
  (user) => print('Got user: ${user.name}'),
);
```

### Bloc Exception

Location: `lib/presentation/helpers/bloc_exception.dart`

Custom exceptions for Bloc/Cubit error handling.

### Error Handling Best Practices

1. **Use Either for Expected Failures:**
   ```dart
   Future<Either<RepositoryFailure, Data>> getData();
   ```

2. **Use Exceptions for Unexpected Errors:**
   ```dart
   throw BlocRetryableException();
   ```

3. **Handle Network Errors Gracefully:**
   - Check network status before operations
   - Return `RepositoryFailure.networkError` for network issues
   - Use retry mechanisms for transient failures

4. **Provide User-Friendly Error Messages:**
   ```dart
   failure.when(
     networkError: () => 'No internet connection',
     notAuthorizedToRead: () => 'Permission denied',
     unexpected: () => 'Something went wrong',
   );
   ```

---

## Utilities

### Logger

Location: `lib/utils/logger.dart`

Comprehensive logging system with Firebase Crashlytics integration and configurable log levels.

```dart
// Log levels
enum LogLevel {
  debugVerbose,
  debug,
  info,
  warn,
  error,
}

// Convenience functions
logd('Debug message');           // Debug
logdv('Verbose debug message');  // Debug Verbose
logi('Info message');            // Info
logw('Warning message');         // Warn
loge('Error message');           // Error
loge(exception, 'Error with exception'); // With exception

// Set custom log function
Logger.setLogFunction((message) {
  // Custom logging logic
});
```

**Features:**
- Respects `AppConfigBase.logLevel` for filtering
- Automatic Firebase Crashlytics integration
- Stack trace logging for errors
- Custom log function support
- Color-coded console output

### RetryIt

Location: `lib/utils/retry_it.dart`

Exponential backoff retry mechanism for unreliable operations.

```dart
// Retry with default attempts (from AppConfigBase)
final result = await retryIt(() async {
  return await unreliableOperation();
});

// Custom max attempts
final result = await retryIt(
  () async => await unreliableOperation(),
  maxAttempts: 5,
);
```

**Features:**
- Exponential backoff between retries
- Configurable max attempts
- Logs each retry attempt
- Default max attempts from `AppConfigBase.retryAttemptsCountMax`

### GetIt Utilities

Location: `lib/utils/get_it_utils.dart`

Convenience wrapper for GetIt dependency injection with a shorter syntax.

```dart
// The 'g' function is an alias for GetIt.I
import 'package:dreamic/utils/get_it_utils.dart';

// Register a singleton (created immediately)
GetIt.I.registerSingleton<MyService>(MyService());

// Register a lazy singleton (created on first use - RECOMMENDED for repos)
GetIt.I.registerLazySingleton<MyRepo>(() => MyRepoImpl());

// Get an instance using the short syntax
final service = g<MyService>();
final repo = g<MyRepo>();

// You can also use GetIt.I directly
final service2 = GetIt.I.get<MyService>();
```

**Best Practices:**
1. **Use Lazy Singletons for Repositories:** They're created only when first accessed, improving startup time
2. **Use Regular Singletons for Services:** Use for services that need to be initialized at startup (like `AuthServiceInt`, `AppCubit`)
3. **Register Interfaces, Not Implementations:** Register `MyRepoInt`, not `MyRepoImpl`
4. **Order Matters:** Register dependencies before dependents (e.g., register `AuthServiceInt` before repositories that use it)
5. **Use `g<Type>()` in Your Code:** It's shorter and cleaner than `GetIt.I.get<Type>()`

**Example Setup Order:**
```dart
void setupGetIt(FirebaseApp fbApp) {
  // 1. Core services first
  GetIt.I.registerSingleton<AuthServiceInt>(AuthServiceImpl(firebaseApp: fbApp));
  
  // 2. Repositories (lazy)
  GetIt.I.registerLazySingleton<UserRepoInt>(() => UserRepoImpl());
  GetIt.I.registerLazySingleton<ContentRepoInt>(() => ContentRepoImpl());
  
  // 3. App state management
  GetIt.I.registerSingleton<AppCubit>(AppCubit());
  GetIt.I.registerSingleton<GlobalCubit>(GlobalCubit());
  
  // 4. Router last
  GetIt.I.registerSingleton<AppRouter>(AppRouter());
}
```

### Device Utils

Location: `lib/utils/device_utils.dart`

Platform-specific device utilities.

### String Helpers

Location: `lib/utils/string_helpers.dart`

String manipulation utilities.

### String Validators

Location: `lib/utils/string_validators.dart`

String validation utilities (email, phone, etc.).

### List Extensions & Utils

Location: `lib/utils/list_extensions.dart`, `lib/utils/list_utils.dart`

Helpful extensions and utilities for List operations.

---

## Presentation Components

### Provided Widgets

**Network & Connection:**
- `ConnectionToaster` - Toast notifications for network status changes (optional, opt-in)
- `NetworkErrorWidget` - Display network error state

**Error Display:**
- `ErrorMessageWidget` - Display error messages

**Loading Indicators:**
- `LoadingIndicator` - Standard loading spinner
- `OverlayProgress` - Full-screen loading overlay
- `OverlaySubmittingWidget` - Submitting state overlay

**State Wrappers:**
- `AppStateWrapper` - Wraps app-level state
- `PageStatusWrapper` - Wraps page status states
- `LoadingWrapper` - Wraps with loading behavior
- `LoadingRetryWrapper` - Wraps with loading and retry

**App Updates:**
- `AppUpdateWidgets` - UI components for app update prompts
- `OutdatedAppPage` - Full page for required updates

**Other:**
- `TappableAction` - Enhanced button with debouncing and loading states
- `FrostedContainerWidget` - Frosted glass effect container
- `ToastWidget` - Toast notifications
- `AdaptiveIcons` - Platform-adaptive icons

### SafeEmitMixin

Location: `lib/presentation/helpers/cubit_helpers.dart`

Prevents emitting state after Cubit is closed.

```dart
class MyCubit extends Cubit<MyState> with SafeEmitMixin<MyState> {
  void loadData() {
    emitSafe(MyState.loading()); // Won't crash if cubit is closed
  }
}
```

### Widget Helpers

Location: `lib/presentation/helpers/widget_helpers.dart`

Common widget utilities and builders.

### Colors & Sizes

Location: `lib/presentation/helpers/colors_common.dart`, `lib/presentation/helpers/sizes_common.dart`

Common color definitions and size constants for consistent UI.

---

## Repository Patterns

### Best Practices

**Interface Pattern:**
```dart
// Define interface
abstract class MyRepoInt {
  Future<Either<RepositoryFailure, List<Item>>> getItems();
  Future<Either<RepositoryFailure, Unit>> saveItem(Item item);
}

// Implement
class MyRepoImpl implements MyRepoInt {
  @override
  Future<Either<RepositoryFailure, List<Item>>> getItems() async {
    // Implementation
  }
}

// Register with dependency injection
g.registerLazySingleton<MyRepoInt>(() => MyRepoImpl());
```

**Stream Auth-Aware:**
Location: `lib/data/helpers/stream_authaware.dart`

Create Firestore streams that automatically reconnect on auth changes.

**Data Converters:**
Location: `lib/data/helpers/data_converters.dart`, `lib/data/helpers/model_converters.dart`

Helpers for converting between data formats and models.

**Function Streamer:**
Location: `lib/data/helpers/function_streamer.dart`

Stream results from Firebase Cloud Functions.

---

## Setup & Integration

### Overview

The dreamic package provides helper functions to streamline app initialization. These functions handle common setup tasks and ensure proper initialization order:

- `appInitFirebase()` - Initialize Firebase with options
- `appInitErrorHandling()` - Set up error handlers and crash reporting (supports custom error reporters like Sentry)
- `configureErrorReporting()` - Configure error reporting without initializing handlers (for use with wrapper functions)
- `appInitRemoteConfig()` - Fetch and activate Firebase Remote Config
- `appInitAppConfigsBase()` - Initialize AppConfigBase settings
- `appInitConnectToFirebaseEmulatorIfNecessary()` - Connect to Firebase emulator if configured
- `appRunIfValidVersion()` - Run app with version checking wrapper

### Initial Setup

1. **Install the package:**
   ```yaml
   dependencies:
     dreamic:
   ```

2. **Initialize in main.dart:**
   ```dart
   void main() async {
     WidgetsFlutterBinding.ensureInitialized();
     
     // Set default values for AppConfigBase FIRST
     AppConfigBase.appStoreAndroidUrlDefault = 'https://play.google.com/store/apps/details?id=com.yourapp';
     AppConfigBase.appStoreAppleUrlDefault = 'https://apps.apple.com/app/your-app/id123456789';
     AppConfigBase.backendEmulatorStartingPortDefault = 38005;
     AppConfigBase.backendRegionDefault = 'us-central1';
     
     // Initialize Firebase using dreamic helper
     final fbApp = await appInitFirebase(DefaultFirebaseOptions.currentPlatform);
     
     // Set up error handling (supports custom error reporters)
     await appInitErrorHandling(
       config: ErrorReportingConfig.firebaseOnly(), // Or use custom reporter
     );
     
     // Set up remote config (pass any additional defaults your app needs)
     await appInitRemoteConfig(
       additionalDefaultConfigs: {
         'yourCustomKey': 'defaultValue',
       },
     );
     
     // Set up app configs base (must be after remote config)
     await appInitAppConfigsBase();
     
     // Connect to Firebase Emulator if necessary
     await appInitConnectToFirebaseEmulatorIfNecessary(fbApp);
     
     // Setup dependency injection (see step 3)
     setupGetIt(fbApp);
     
     // Run app with version checking
     appRunIfValidVersion(
       runBeforeValidApp: () {
         // Code to run before app starts (e.g., background message handlers)
       },
       () {
         return MyApp();
       },
     );
   }
   ```

3. **Setup dependency injection:**
   ```dart
   void setupGetIt(FirebaseApp fbApp) {
     // Auth Service (first, as others may depend on it)
     GetIt.I.registerSingleton<AuthServiceInt>(
       AuthServiceImpl(
         firebaseApp: fbApp,
         onAuthenticated: (uid) async {
           // Called when user signs in
           // Clear caches, initialize services, etc.
         },
         onLoggedOut: () async {
           // Called when user signs out
           // Clear all caches
         },
       ),
     );
     
     // Repositories (use lazy singletons for better performance)
     GetIt.I.registerLazySingleton<UserRepoInt>(() => UserRepoImpl());
     GetIt.I.registerLazySingleton<ContentRepoInt>(() => ContentRepoImpl());
     // ... other repositories
     
     // AppCubit (required for version checking and network monitoring)
     GetIt.I.registerSingleton<AppCubit>(AppCubit(
       entranceUri: kIsWeb ? Uri.parse(getCurrentLocation()) : null,
       networkRequired: true, // Set based on your app's needs
     ));
     
     // Other app-specific cubits
     GetIt.I.registerSingleton<YourCubit>(YourCubit());
     
     // Router (if using auto_route)
     final appRouter = AppRouter();
     GetIt.I.registerSingleton<AppRouter>(appRouter);
   }
   ```

4. **Wrap app with AppRootWidget:**
   ```dart
   class MyApp extends StatelessWidget {
     @override
     Widget build(BuildContext context) {
       final router = GetIt.I.get<AppRouter>();
       
       return MaterialApp.router(
         builder: (context, child) {
           return AppRootWidget(
             child: child!,
             // Optional: Enable built-in connection toaster
             useConnectionToaster: true,
             showConnectionToastOnInitialConnection: false,
             connectionToastDelay: Duration.zero,
           );
         },
         routerDelegate: AutoRouterDelegate(router),
         routeInformationParser: router.defaultRouteParser(),
         // ... other MaterialApp configuration
       );
     }
   }
   ```
   
   **What `AppRootWidget` provides:**
   - **AppCubit Integration:** Provides `AppCubit` via `BlocProvider.value` and calls `getInitialData()`
   - **Version Management:** 
     - Shows blocking dialog for required updates (`AppUpdateDialog`)
     - Displays dismissible banner for recommended updates (`AppUpdateBanner`)
     - Automatically handles version checking on app resume
   - **Loading States:** Shows `LoadingIndicator` during app initialization
   - **Error Handling:** Displays error messages for failed initialization
   - **Network Errors:** Shows network error widget when connectivity issues occur
   - **Connection Toaster (Optional):** Shows toast notifications for network status changes
     - `useConnectionToaster` - Enable/disable the feature (default: `false`)
     - `showConnectionToastOnInitialConnection` - Show toast during app startup/resume (default: `false`)
     - `connectionToastDelay` - Delay before showing toast (default: `Duration.zero`)
   - **Loading Overlays:** Manages full-screen loading overlays via `AppCubit.overlayLoadingStart/Finish()`
   - **Keyboard Dismissal:** Tapping anywhere on the screen dismisses the keyboard
   
   **AppState Status Handling:**
   - `AppStatus.loading` → Shows loading indicator
   - `AppStatus.updateRequired` → Shows `AppUpdateDialog` (blocks app usage)
   - `AppStatus.normal` → Shows your app content with optional update banner
   - `AppStatus.overlayLoading` → Shows overlay progress indicator
   - `AppStatus.networkError` → Shows `NetworkErrorWidget` (critical network failure during initial load)
   
   **Network Status Handling:**
   - `AppStatus.networkError` is for **critical network failures** during initial app load that prevent the app from starting
   - `ConnectionToaster` (when enabled) handles **transient network status changes** during normal app usage
   - These two mechanisms serve different purposes and work together:
     - Initial load network failure → Blocks app with `NetworkErrorWidget`
     - Connection loss during usage → Shows non-intrusive toast (if enabled)
   
   **Without AppRootWidget:**
   If you choose not to use `AppRootWidget`, you'll need to manually:
   - Provide `AppCubit` via `BlocProvider`
   - Call `appCubit.getInitialData()`
   - Handle version update UI based on `AppState.versionUpdateInfo`
   - Manage loading and error states
   - Show/hide loading overlays
   - Optionally wrap with `ConnectionToaster` for network status toasts

### Configuration

Set your app-specific defaults in `main.dart` **before initializing Firebase**:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // IMPORTANT: Set defaults FIRST, before any Firebase initialization
  AppConfigBase.appStoreAndroidUrlDefault = 'https://play.google.com/store/apps/details?id=com.yourapp';
  AppConfigBase.appStoreAppleUrlDefault = 'https://apps.apple.com/app/your-app/id123456789';
  AppConfigBase.backendEmulatorStartingPortDefault = 38005;
  AppConfigBase.backendRegionDefault = 'us-central1';
  AppConfigBase.minimumAppVersionRequiredAppleDefault = '1.0.0';
  AppConfigBase.logLevelDefault = 'info';
  AppConfigBase.retryAttemptsCountMaxDefault = 3;
  
  // Now initialize Firebase and other services
  final fbApp = await appInitFirebase(DefaultFirebaseOptions.currentPlatform);
  // ... rest of initialization
}
```

**Critical Initialization Order:**
1. `WidgetsFlutterBinding.ensureInitialized()`
2. Set `AppConfigBase` defaults
3. `appInitFirebase()` - Initialize Firebase
4. `appInitErrorHandling()` - Set up error handlers (or `configureErrorReporting()` for wrapper-based reporters)
5. `appInitRemoteConfig()` - Fetch remote config values
6. `appInitAppConfigsBase()` - Apply config values
7. `appInitConnectToFirebaseEmulatorIfNecessary()` - Connect to emulator if needed
8. Setup dependency injection (AuthService, repositories, cubits)
9. `appRunIfValidVersion()` - Start app with version checking

**Note:** If using a custom error reporter with a wrapper function (like `SentryFlutter.init`):
- Call `configureErrorReporting()` instead of `appInitErrorHandling()`
- Then call the wrapper function (e.g., `SentryFlutter.init`) which will call `runApp()`
- Skip step 9 (`appRunIfValidVersion()`) as the wrapper handles app launching

### Remote Config Setup

Set values in Firebase Console under Remote Config:

**Version Management Keys:**
- `minimumAppVersionRequiredApple` - Required version for iOS (blocks app if below)
- `minimumAppVersionRequiredGoogle` - Required version for Android (blocks app if below)
- `minimumAppVersionRequiredWeb` - Required version for Web (blocks app if below)
- `minimumAppVersionRecommendedApple` - Recommended version for iOS (shows banner)
- `minimumAppVersionRecommendedGoogle` - Recommended version for Android (shows banner)
- `minimumAppVersionRecommendedWeb` - Recommended version for Web (shows banner)

**Configuration Keys:**
- `logLevel` - Log level: 'debug', 'info', 'warn', 'error'
- `retryAttemptsCountMax` - Maximum retry attempts for network operations
- `connectionCheckerUrlOverride` - Custom URL for network connectivity checks
- `networkRequiredOverride` - Override network requirement: 'true', 'false', or 'null' (use app default)

**Custom Keys:**
Add any additional keys your app needs via the `additionalDefaultConfigs` parameter in `appInitRemoteConfig()`.

**Important Notes:**
- Version strings must be in format: `"1.0.0"` (major.minor.patch)
- Set version values higher than current app version to trigger updates
- Changes are published in real-time (no app restart needed on mobile)
- Web platform uses polling instead of real-time updates
- Firebase Remote Config has a fetch limit of 5 requests per hour per device

---

## Common Patterns

### Loading Data in a Cubit

```dart
class MyCubit extends CubitBase<MyState> {
  final MyRepoInt repo;
  
  MyCubit(this.repo) : super(MyState.initial());
  
  Future<void> loadData() async {
    emitSafe(state.copyWith(status: PageStatus.loading));
    
    final result = await callWithLoadingAfterTimeout(() async {
      return await repo.getData();
    });
    
    result.fold(
      (failure) => emitSafe(state.copyWith(
        status: PageStatus.error,
        errorMessage: _getErrorMessage(failure),
      )),
      (data) => emitSafe(state.copyWith(
        status: PageStatus.loaded,
        data: data,
      )),
    );
  }
}
```

### Handling Network-Dependent Operations

```dart
Future<void> saveData() async {
  // Check network first
  final isConnected = g<AppCubit>().state.networkStatus == NetworkStatus.connected;
  if (!isConnected) {
    emitSafe(state.copyWith(
      status: PageStatus.error,
      errorMessage: 'No internet connection',
    ));
    return;
  }
  
  // Proceed with save
  emitSafe(state.copyWith(status: PageStatus.processingAction));
  
  final result = await retryIt(() async {
    return await repo.saveData(state.data);
  }, maxAttempts: 3);
  
  // Handle result...
}
```

### Authentication Flow

```dart
Future<void> signIn(String email, String password) async {
  final result = await callWithLoadingAfterTimeout(() async {
    return await g<AuthServiceInt>().signInWithEmailAndPassword(
      email,
      password,
    );
  });
  
  result.fold(
    (failure) {
      // Show error
      if (failure == AuthServiceSignInFailure.wrongPassword) {
        showError('Invalid password');
      } else if (failure == AuthServiceSignInFailure.userNotFound) {
        showError('User not found');
      }
    },
    (_) {
      // Success - navigation handled by auth state listener
    },
  );
}
```

### Version Check Handling

**Note:** If you're using `AppRootWidget`, version checking is **automatically handled** for you. The widget will:
- Display a blocking dialog for required updates
- Show a dismissible banner at the bottom for recommended updates
- Automatically check for updates on app resume (after 5+ minute cooldown)

**If you need custom handling**, you can listen to version updates in your own widgets:

```dart
class MyCustomWidget extends StatefulWidget {
  @override
  State<MyCustomWidget> createState() => _MyCustomWidgetState();
}

class _MyCustomWidgetState extends State<MyCustomWidget> {
  StreamSubscription<VersionUpdateInfo>? _versionSubscription;
  
  @override
  void initState() {
    super.initState();
    
    // Only needed if NOT using AppRootWidget or if you need custom behavior
    _versionSubscription = AppVersionUpdateService().updateStream.listen((updateInfo) {
      if (updateInfo.isRequired) {
        // Show your custom blocking dialog
        _showCustomRequiredUpdateDialog(updateInfo);
      } else if (updateInfo.isRecommended) {
        // Show your custom update banner
        _showCustomRecommendedUpdateBanner(updateInfo);
      }
    });
  }
  
  @override
  void dispose() {
    _versionSubscription?.cancel();
    super.dispose();
  }
  
  // ... rest of widget
}
```

**Manual version check:**
```dart
// Trigger a manual check (uses cached values, respects Firebase fetch limits)
await AppVersionUpdateService().forceVersionCheck();

// Force fetch from Firebase (counts toward 5 fetches/hour limit)
await AppVersionUpdateService().forceVersionCheckWithFetch();
```

**Using AppCubit for version state:**
```dart
// Access version info from AppCubit state
BlocBuilder<AppCubit, AppState>(
  builder: (context, state) {
    if (state.versionUpdateInfo?.isRequired ?? false) {
      // App is in updateRequired status
      return UpdateRequiredScreen();
    }
    
    if (state.showVersionUpdateBanner) {
      // Recommended update banner should be shown
      // (AppRootWidget handles this automatically)
    }
    
    return YourNormalContent();
  },
)
```

---

## Troubleshooting

### Setup Issues

**Problem:** App crashes or shows errors during initialization
- **Solution:** Verify the initialization order in `main.dart`:
  1. Set `AppConfigBase` defaults first
  2. Call `appInitFirebase()` before any other init functions
  3. Call `appInitRemoteConfig()` before `appInitAppConfigsBase()`
  4. Setup dependency injection after all init functions
  5. Call `appRunIfValidVersion()` last to start the app

**Problem:** Remote Config values not loading
- **Solution:** 
  - Ensure `appInitRemoteConfig()` is called and completes successfully
  - Check Firebase Console to verify Remote Config keys are set
  - Use `AppConfigBase.doOverrideUseLiveRemoteConfig = true` if testing with emulator
  - Verify you're not hitting the 5 fetches/hour limit

### Authentication Issues

**Problem:** `isLoggedInAsync()` returns false even though user is logged in
- **Solution:** Wait for auth state to initialize: `await authService.waitForCanCheckLoginState()`

**Problem:** FCM not working on iOS simulator
- **Solution:** FCM doesn't work on iOS simulator. By default, `AppConfigBase.useFCM` automatically returns `false` on iOS simulators. For manual control, set `AppConfigBase.useFCMDefault = false` before initializing `NotificationService`. Test push notifications on a real device.

### Network Issues

**Problem:** App shows as offline even with internet
- **Solution:** Check `AppConfigBase.connectionCheckerUrlOverride` - you may need to set a custom check URL

**Problem:** Firebase emulator not found
- **Solution:** Ensure emulator is running and accessible. Check firewall settings. Try running `discoverFirebaseEmulatorHost()` with logging enabled

### Version Check Issues

**Problem:** Version updates not triggering
- **Solution:** Ensure Remote Config values are set and fetched. Check that `AppVersionUpdateService` is initialized after Remote Config

**Problem:** Web version checks not working
- **Solution:** Web uses polling instead of real-time updates. Wait for the polling interval or call `forceVersionCheck()`

### Loading State Issues

**Problem:** Loading overlay stuck on screen
- **Solution:** Call `resetLoadingState()` to clear the state. Ensure all loading operations are properly completing

---

## Complete Example

Here's a complete, production-ready `main.dart` setup:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:get_it/get_it.dart';
import 'package:dreamic/app/app_config_base.dart';
import 'package:dreamic/app/helpers/app_configs_init.dart';
import 'package:dreamic/app/helpers/app_errorhandling_init.dart';
import 'package:dreamic/app/helpers/app_firebase_init.dart';
import 'package:dreamic/app/helpers/app_version_handler.dart';
import 'package:dreamic/app/helpers/app_remote_config_init.dart';
import 'package:dreamic/data/repos/auth_service_impl.dart';
import 'package:dreamic/data/repos/auth_service_int.dart';
import 'package:dreamic/app/app_cubit.dart';
import 'package:dreamic/utils/get_it_utils.dart';
import 'firebase_options.dart';
import 'app/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Set AppConfigBase defaults FIRST
  AppConfigBase.appStoreAndroidUrlDefault = 'https://play.google.com/store/apps/details?id=com.yourapp';
  AppConfigBase.appStoreAppleUrlDefault = 'https://apps.apple.com/app/your-app/id123456789';
  AppConfigBase.backendEmulatorStartingPortDefault = 38005;
  AppConfigBase.backendRegionDefault = 'us-central1';

  // 2. Initialize Firebase
  final fbApp = await appInitFirebase(DefaultFirebaseOptions.currentPlatform);

  // 3. Set up error handling
  await appInitErrorHandling();

  // 4. Set up remote config
  await appInitRemoteConfig(
    additionalDefaultConfigs: {
      'yourCustomKey': 'defaultValue',
    },
  );

  // 5. Set up app configs
  await appInitAppConfigsBase();

  // 6. Connect to emulator if needed
  await appInitConnectToFirebaseEmulatorIfNecessary(fbApp);

  // 7. Setup dependency injection
  setupGetIt(fbApp);

  // 8. Run app with version checking
  appRunIfValidVersion(() {
    return MyApp();
  });
}

void setupGetIt(FirebaseApp fbApp) {
  // Auth Service
  GetIt.I.registerSingleton<AuthServiceInt>(
    AuthServiceImpl(
      firebaseApp: fbApp,
      onAuthenticated: (uid) async {
        // Initialize user-specific services
      },
      onLoggedOut: () async {
        // Clear caches
        g<UserRepoInt>().clearCache();
      },
    ),
  );

  // Repositories
  GetIt.I.registerLazySingleton<UserRepoInt>(() => UserRepoImpl());
  GetIt.I.registerLazySingleton<ContentRepoInt>(() => ContentRepoImpl());

  // App state
  GetIt.I.registerSingleton<AppCubit>(AppCubit(
    entranceUri: kIsWeb ? Uri.parse(getCurrentLocation()) : null,
  ));

  // Router
  final appRouter = AppRouter();
  GetIt.I.registerSingleton<AppRouter>(appRouter);
}
```

```dart
// app.dart
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final router = g<AppRouter>();
    
    return MaterialApp.router(
      builder: (context, child) {
        return AppRootWidget(
          child: child!,
        );
      },
      routerDelegate: AutoRouterDelegate(router),
      routeInformationParser: router.defaultRouteParser(),
      theme: ThemeData(...),
    );
  }
}
```

**Alternative: Using Sentry with SentryFlutter.init Wrapper**

If you're using a custom error reporter that provides a wrapper function (like Sentry's `SentryFlutter.init`), use this pattern instead:

```dart
// main.dart with Sentry wrapper
import 'package:sentry_flutter/sentry_flutter.dart';
import 'your_error_reporter.dart'; // Your SentryErrorReporter implementation

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Set AppConfigBase defaults
  AppConfigBase.appStoreAndroidUrlDefault = 'https://play.google.com/...';
  // ... other defaults

  // 2. Initialize Firebase
  final fbApp = await appInitFirebase(DefaultFirebaseOptions.currentPlatform);

  // 3. Configure error reporting (don't initialize handlers yet)
  await configureErrorReporting(
    ErrorReportingConfig.both(
      reporter: SentryErrorReporter(),
      customReporterManagesErrorHandlers: true, // Sentry will set up handlers
      enableInDebug: true,
    ),
  );

  // 4-6. Continue with rest of setup
  await appInitRemoteConfig();
  await appInitAppConfigsBase();
  await appInitConnectToFirebaseEmulatorIfNecessary(fbApp);
  
  // 7. Setup dependency injection
  setupGetIt(fbApp);

  // 8. Use Sentry's wrapper with version checking
  await SentryFlutter.init(
    (options) {
      options.dsn = 'your-sentry-dsn';
      options.environment = AppConfigBase.environmentType.value;
      options.release = await AppConfigBase.getAppRelease();
      options.tracesSampleRate = 1.0;
    },
    appRunner: () => appRunIfValidVersion(() => MyApp()),
  );
}
```

---

## Testing

### Testing Widgets with Dreamic Components

Location: `lib/test_utils/mock_app_cubit.dart`

Dreamic provides utilities to help you test widgets that use Dreamic components like `TappableAction`, `AppRootWidget`, and other features that depend on `AppCubit`.

#### Quick Start

**1. Initialize TappableAction for Testing**

Call this once at the start of test files that use TappableAction widgets:

```dart
void main() {
  setUpAll(() {
    initializeTappableActionForTesting();
  });

  group('MyWidget tests', () {
    // Your tests here
  });
}
```

**2. Wrap Widgets with MockAppCubit**

Use the `wrapWithMockAppCubit` helper to provide AppCubit context:

```dart
testWidgets('renders button correctly', (tester) async {
  await tester.pumpWidget(
    wrapWithMockAppCubit(
      MaterialApp(
        home: MyWidget(),
      ),
    ),
  );
  
  expect(find.byType(MyWidget), findsOneWidget);
});
```

#### Testing Different States

**Network States:**
```dart
testWidgets('disables button when network is disconnected', (tester) async {
  await tester.pumpWidget(
    wrapWithMockAppCubit(
      MaterialApp(home: MyButton()),
      networkStatus: NetworkStatus.none,
    ),
  );
  
  // Button should be disabled
  final button = find.byType(TappableAction);
  expect(button, findsOneWidget);
});
```

**Auth States:**
```dart
testWidgets('shows login prompt when not authenticated', (tester) async {
  await tester.pumpWidget(
    wrapWithMockAppCubit(
      MaterialApp(home: MyAuthWidget()),
      authStatus: AppAuthStatus.noauth,
    ),
  );
  
  expect(find.text('Please log in'), findsOneWidget);
});
```

**App States:**
```dart
testWidgets('shows loading indicator during app loading', (tester) async {
  await tester.pumpWidget(
    wrapWithMockAppCubit(
      MaterialApp(home: MyApp()),
      appStatus: AppStatus.loading,
    ),
  );
  
  expect(find.byType(CircularProgressIndicator), findsOneWidget);
});
```

#### MockAppCubit API

The `MockAppCubit` class provides methods to dynamically change state during tests:

```dart
testWidgets('responds to network status changes', (tester) async {
  final mockCubit = MockAppCubit();
  
  await tester.pumpWidget(
    BlocProvider<AppCubit>.value(
      value: mockCubit,
      child: MaterialApp(home: MyWidget()),
    ),
  );
  
  // Initially connected
  expect(mockCubit.state.networkStatus, NetworkStatus.connected);
  
  // Simulate network loss
  mockCubit.setNetworkStatus(NetworkStatus.none);
  await tester.pump();
  
  // Verify UI updated
  expect(find.text('No connection'), findsOneWidget);
  
  // Restore connection
  mockCubit.setNetworkStatus(NetworkStatus.connected);
  await tester.pump();
  
  expect(find.text('No connection'), findsNothing);
  
  await mockCubit.close();
});
```

**Available Setters:**
- `setNetworkStatus(NetworkStatus)` - Change network connectivity
- `setAuthStatus(AppAuthStatus)` - Change authentication state
- `setAppStatus(AppStatus)` - Change app loading state

#### Complete Example

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dreamic/dreamic.dart';

void main() {
  setUpAll(() {
    initializeTappableActionForTesting();
  });

  group('SaveButton', () {
    testWidgets('calls onSave when tapped', (tester) async {
      var tapped = false;
      
      await tester.pumpWidget(
        wrapWithMockAppCubit(
          MaterialApp(
            home: Scaffold(
              body: TappableAction(
                onTap: () => tapped = true,
                builder: (context, onTap) {
                  return ElevatedButton(
                    onPressed: onTap,
                    child: Text('Save'),
                  );
                },
              ),
            ),
          ),
        ),
      );
      
      await tester.tap(find.text('Save'));
      await tester.pump();
      
      expect(tapped, isTrue);
    });
    
    testWidgets('disables when network required but unavailable', (tester) async {
      await tester.pumpWidget(
        wrapWithMockAppCubit(
          MaterialApp(
            home: Scaffold(
              body: TappableAction(
                config: TappableActionConfig(requireNetwork: true),
                onTap: () {},
                builder: (context, onTap) {
                  return ElevatedButton(
                    onPressed: onTap,
                    child: Text('Save'),
                  );
                },
              ),
            ),
          ),
          networkStatus: NetworkStatus.none,
        ),
      );
      
      final button = tester.widget<ElevatedButton>(
        find.byType(ElevatedButton),
      );
      
      expect(button.onPressed, isNull);
    });
  });
}
```

#### Best Practices

1. **Always initialize TappableAction**: Call `initializeTappableActionForTesting()` in `setUpAll()` to prevent timer-related test failures
2. **Use wrapWithMockAppCubit for simplicity**: It handles the BlocProvider setup for you
3. **Clean up MockAppCubit instances**: If creating MockAppCubit directly, call `await mockCubit.close()` in tearDown or at end of test
4. **Test different states**: Use the provided parameters to test how your widgets behave in different network/auth/app states
5. **Avoid real network calls**: MockAppCubit doesn't initialize network checking or version update services

#### Additional Resources

See **[TESTING_GUIDE.md](TESTING_GUIDE.md)** for comprehensive testing patterns, examples, and advanced scenarios.

---

## Additional Resources

- See individual documentation files in `/docs` for specific features
- **Testing:**
  - **[TESTING_GUIDE.md](TESTING_GUIDE.md)** - Comprehensive widget testing guide with Dreamic components
- **Error Reporting:**
  - **[ERROR_REPORTING_GUIDE.md](ERROR_REPORTING_GUIDE.md)** - Complete error reporting integration guide (Firebase, Sentry, Bugsnag, custom services)
- **App Updates:**
  - `SETUP_APP_UPDATES.md` - Detailed app update setup guide
  - `APP_UPDATE_WEB_RELOADER_IMPLEMENTATION.md` - Web-specific update handling
- **UI Components:**
  - `TAPPABLE_ACTION_MIGRATION_GUIDE.md` - TappableAction usage guide
- **Configuration:**
  - `WEB_REMOTE_CONFIG_FIX.md` - Web-specific Remote Config issues and solutions

---

## Version History

This package is actively maintained. Check `CHANGELOG.md` for version history and updates.
