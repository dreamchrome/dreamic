# App Update Notification System

This system provides automatic app update notifications for Flutter apps using Firebase Remote Config. It supports both required updates (blocking app usage) and recommended updates (dismissible notifications).

## Features

- **Firebase Remote Config Integration**: Version numbers are managed in Firebase Remote Config for real-time updates
- **Platform-Specific Versions**: Supports different version requirements for iOS, Android, and Web
- **Required vs Recommended Updates**: Handles critical updates that block app usage and optional updates with dismissible notifications
- **App Lifecycle Management**: Automatically checks for updates when the app resumes from background
- **Reusable UI Components**: Provides banner, toast, and dialog widgets for displaying update notifications
- **Stream-Based Architecture**: Uses reactive streams for real-time update notifications

## Setup

### 1. Firebase Remote Config Keys

Add these keys to your Firebase Remote Config (values should be version strings like "1.2.3"):

**Required Version Keys:**
- `minimumAppVersionRequiredApple` - iOS required version
- `minimumAppVersionRequiredGoogle` - Android required version  
- `minimumAppVersionRequiredWeb` - Web required version

**Recommended Version Keys:**
- `minimumAppVersionRecommendedApple` - iOS recommended version
- `minimumAppVersionRecommendedGoogle` - Android recommended version
- `minimumAppVersionRecommendedWeb` - Web recommended version

### 2. AppConfigBase Configuration

The `AppConfigBase` class in flutter_base already includes the required getters with proper dependency injection and fallback logic. The getters automatically:

1. Check for environment variable overrides first
2. Use Remote Config values when available  
3. Fall back to default values when Remote Config is empty
4. Support both real Firebase and mock implementations for testing

**Key getters provided:**

```dart
// Required versions
AppConfigBase.minimumAppVersionRequiredApple
AppConfigBase.minimumAppVersionRequiredGoogle  
AppConfigBase.minimumAppVersionRequiredWeb

// Recommended versions
AppConfigBase.minimumAppVersionRecommendedApple
AppConfigBase.minimumAppVersionRecommendedGoogle
AppConfigBase.minimumAppVersionRecommendedWeb

// App store URL (platform-specific)
AppConfigBase.appStoreUrl
```

**Setting default values (if needed):**

```dart
void main() {
  // Set defaults before initializing Firebase
  AppConfigBase.minimumAppVersionRequiredAppleDefault = '1.0.0';
  AppConfigBase.minimumAppVersionRecommendedAppleDefault = '1.1.0';
  // ... other defaults
  
  runApp(MyApp());
}
```

### 3. Emulator Mode Configuration

The system supports both real Firebase Remote Config and mock implementations:

```dart
// Use real Firebase Remote Config (production/staging)
AppConfigBase.doUseBackendEmulator = false;

// Use mock Remote Config (local development)  
AppConfigBase.doUseBackendEmulator = true;
AppConfigBase.doOverrideUseLiveRemoteConfig = false;

// Force real Firebase even in emulator mode (testing)
AppConfigBase.doUseBackendEmulator = true;
AppConfigBase.doOverrideUseLiveRemoteConfig = true;
```

**Important**: The Remote Config implementation is automatically selected during initialization in `appInitRemoteConfig()` based on these settings. The dependency injection system will register either:
- `RemoteConfigRepoLiveImpl` for real Firebase
- `RemoteConfigRepoMockImpl` for local development

**Real-time listeners are automatically disabled when using mock Remote Config** to prevent unnecessary setup attempts.

## Usage

### Automatic Integration

The system is automatically integrated if you're using the flutter_base `AppCubit` and `AppRootWidget`:

1. **AppCubit**: Automatically initializes the version update service and lifecycle service
2. **AppRootWidget**: Automatically displays update banners and handles required updates

### Manual Integration

If not using the base classes, you can integrate manually:

```dart
import 'package:dreamic/app/helpers/app_version_update_service.dart';
import 'package:dreamic/app/helpers/app_lifecycle_service.dart';

class MyAppState extends State<MyApp> {
  StreamSubscription<VersionUpdateInfo>? _updateSubscription;

  @override
  void initState() {
    super.initState();
    _initializeUpdateSystem();
  }

  void _initializeUpdateSystem() async {
    // Initialize services
    await AppVersionUpdateService().initialize();
    AppLifecycleService().initialize();

    // Listen to update notifications
    _updateSubscription = AppVersionUpdateService().updateStream.listen(
      (updateInfo) {
        if (updateInfo.hasUpdate) {
          _handleUpdate(updateInfo);
        }
      },
    );
  }

  void _handleUpdate(VersionUpdateInfo updateInfo) {
    if (updateInfo.isRequired) {
      // Show blocking dialog for required updates
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AppUpdateDialog(updateInfo: updateInfo),
      );
    } else if (updateInfo.isRecommended) {
      // Show dismissible banner for recommended updates
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppUpdateBanner(
            updateInfo: updateInfo,
            onDismiss: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
          ),
          duration: const Duration(seconds: 10),
        ),
      );
    }
  }
}
```

## UI Components

### AppUpdateBanner
A banner widget for displaying update notifications:

```dart
AppUpdateBanner(
  updateInfo: versionUpdateInfo,
  onDismiss: () {
    // Handle dismissal
  },
)
```

### AppUpdateToast
An animated toast notification:

```dart
AppUpdateToast(
  updateInfo: versionUpdateInfo,
  displayDuration: Duration(seconds: 5),
  onDismiss: () {
    // Handle dismissal
  },
)
```

### AppUpdateDialog
A modal dialog for updates:

```dart
AppUpdateDialog(
  updateInfo: versionUpdateInfo,
)
```

## Version Update Types

### VersionUpdateType.none
No update is needed. Current version meets all requirements.

### VersionUpdateType.recommended
A newer version is available but not required. Users can dismiss the notification and continue using the app.

### VersionUpdateType.required
A critical update is required. Users cannot continue using the app without updating.

## Testing

### Quick Test Guide
📋 **For detailed testing instructions and troubleshooting, see: [REMOTE_CONFIG_LISTENER_TEST_GUIDE.md](REMOTE_CONFIG_LISTENER_TEST_GUIDE.md)**

### Debug Widget

Use the `AppUpdateDebugWidget` for testing:

```dart
import 'package:dreamic/presentation/debug/app_update_debug_widget.dart';

// In your debug builds:
child.withUpdateDebugControls()
```

**Key debug buttons:**
- **"Test RC Listener"**: Verifies real-time Remote Config listener setup and provides testing instructions. **Note**: This button only works when using real Firebase Remote Config, not mock implementation.
- **"Force Version Check"**: Manually triggers version checking with the current Remote Config values (no fetch to avoid rate limits)
- **"Force Refresh Config"**: Forces a fresh fetch from Firebase Remote Config (use sparingly due to 5 fetches/hour limit)

### Manual Testing Steps

1. **Set up test versions in Firebase Remote Config:**
   - Set required version higher than current app version
   - Set recommended version higher than current app version

2. **Test required updates:**
   - App should show blocking dialog
   - User cannot dismiss or continue without updating

3. **Test recommended updates:**
   - App should show dismissible banner
   - User can continue using app after dismissing

4. **Test app lifecycle:**
   - Background the app for 5+ minutes
   - Resume the app
   - Version check should trigger automatically (with cooldown to avoid excessive checking)

### Firebase Remote Config Testing

1. Go to Firebase Console > Remote Config
2. Create test values for version keys
3. Set conditions for different user segments if needed
4. Publish changes (don't just save - must publish to activate)
5. **Real-time listener will automatically pick up changes** (10-30 seconds delay)
6. Alternatively, use "Force Refresh Config" in debug widget for immediate testing

## Firebase Remote Config Limitations

### Fetch Limits
Firebase Remote Config has important limitations to be aware of:

- **Fetch Limit**: 5 fetches per hour per app instance
- **minimumFetchInterval**: Prevents fetches more frequent than the configured interval
  - Debug mode: 10 seconds
  - Release mode: 1 hour
- **Throttling**: Exceeding limits results in `FirebaseException` with throttling errors

### How Our System Stays Under Limits
The version update system is designed to minimize Remote Config fetches:

1. **App Startup**: 1 fetch during initialization (in `appInitRemoteConfig`)
2. **App Resume**: Maximum 1 fetch per app session (with 5+ minute cooldown in `AppLifecycleService`)
3. **Real-time Updates**: Uses `onConfigUpdated` listener (doesn't count toward fetch limit)
4. **Cached Values**: Uses cached values when fetch fails or is throttled
5. **Debug Force Refresh**: Only used during development testing (bypasses cooldown)

**Total Normal Usage**: 1-2 fetches per hour maximum during typical usage

### Real-time Updates
The system uses Firebase's `onConfigUpdated` listener for instant updates when you publish changes in Firebase Console. This listener:
- Doesn't count toward the 5 fetches/hour limit
- Provides real-time updates without explicit fetching
- Works even when fetch is throttled
- Automatically activates new values

### Version Check Cooldown

App lifecycle version checks have a 5-minute cooldown to avoid excessive checking:

```dart
// In AppLifecycleService
static const Duration _versionCheckCooldown = Duration(minutes: 5);
```

### App Store URLs

Configure platform-specific app store URLs in `AppConfigBase.appStoreUrl`.

## Architecture

### Recent Improvements (Latest Version)

The app update system has been completely refactored to use proper dependency injection and eliminate circular dependencies:

1. **Circular Dependency Resolution**: Fixed infinite loop between `AppConfigBase.logLevel` → Remote Config → Logger by using `debugPrint` in Remote Config repository
2. **Complete Dependency Injection**: All components now use `g<RemoteConfigRepoInt>()` instead of direct Firebase calls
3. **Enhanced Fallback Logic**: AppConfigBase getters check environment variables first, then Remote Config, then defaults
4. **Smart Listener Management**: Listeners automatically skip setup on web platforms and in emulator mode
5. **Platform Compatibility**: Full support for iOS, Android, and Web with appropriate limitations

### Dependency Injection System

The app update system uses a sophisticated dependency injection architecture that supports both production and testing scenarios:

```dart
// Real Firebase Remote Config (production)
g<RemoteConfigRepoInt>() // Returns RemoteConfigRepoLiveImple

// Mock Remote Config (testing/emulator)
g<RemoteConfigRepoInt>() // Returns RemoteConfigRepoFakeImple
```

The correct implementation is automatically selected during app initialization based on your `AppConfigBase` settings:

- **Live Firebase**: When `doUseBackendEmulator = false` OR `doOverrideUseLiveRemoteConfig = true`
- **Mock Implementation**: When `doUseBackendEmulator = true` AND `doOverrideUseLiveRemoteConfig = false`

### Smart Fallback Logic

All `AppConfigBase` getters implement a three-tier fallback system:

1. **Environment Variables**: Highest priority (compile-time overrides)
2. **Remote Config Values**: Medium priority (Firebase or mock values)
3. **Default Values**: Lowest priority (built-in fallbacks)

This ensures the app always has valid configuration values, even when Firebase is unavailable.

### Real-time Listener System

The system includes an intelligent listener that:

- **Skips setup on web platforms** (where `onConfigUpdated` is not supported)
- **Skips setup in emulator mode** (when using mock Remote Config)
- **Uses exponential backoff** for connection retry attempts  
- **Includes health checks** every 5 minutes to verify listener connectivity
- **Activates values automatically** when updates are received
- **Filters updates by relevance** (only triggers version checks for version-related keys)

## Best Practices

1. **Test thoroughly**: Always test version updates before releasing to production
2. **Gradual rollouts**: Use Firebase Remote Config conditions for gradual version requirement rollouts
3. **Clear messaging**: Provide clear update messages explaining why updates are needed
4. **Monitor usage**: Track update adoption rates through analytics
5. **Emergency updates**: Have a process for pushing critical security updates quickly
6. **Respect Firebase limits**: The system is designed to stay under Firebase's 5 fetches/hour limit by only fetching on:
   - App startup (1 fetch)
   - App resume after 5+ minute background (1 fetch per session)
   - Real-time listener updates (doesn't count toward limit)
   - Debug force refresh (testing only)
7. **Use emulator mode**: Test with mock Remote Config during development to avoid Firebase API calls and rate limits
8. **Monitor logs**: Use the debug widget and logger output to troubleshoot issues
9. **Understand platform limitations**: Real-time listeners don't work on web platform or with mock Remote Config

## Troubleshooting

### Updates not showing
- **Check Firebase Remote Config values are published** in Firebase Console
- **Verify app has internet connection** and can reach Firebase
- **Check console logs** for version comparison results and Remote Config values
- **Ensure Remote Config has been fetched and activated** (look for initialization logs)
- **Verify emulator mode settings** if testing with mock values

### App crashes on update check
- **Check that `appIsVersionValid()` function is implemented correctly**
- **Verify Firebase Remote Config is properly initialized** before version checks
- **Check app store URLs are valid** and accessible
- **Look for circular dependency errors** in logger output
- **Verify dependency injection is working** (check for GetIt registration errors)

### Updates showing incorrectly
- **Verify version string format** (should be semantic versioning like "1.2.3")
- **Check platform-specific version keys in Remote Config** match the implementation
- **Test version comparison logic with debug logs** to see actual vs expected versions
- **Ensure proper fallback behavior** when Remote Config values are empty
- **Check for environment variable overrides** that might be affecting values

### Remote Config not updating in real-time
- **Verify you're not in emulator mode** (real-time listeners are disabled for mock Remote Config)
- **Check web platform limitations** (`onConfigUpdated` not supported on web)
- **Look for listener setup errors** in the logs during initialization
- **Verify network connectivity** and Firebase project configuration
- **Check listener health status** using the debug widget's "Test RC Listener" button
- **Ensure you published changes** in Firebase Console (not just saved)
- **Wait 10-30 seconds** for listener updates to propagate after publishing

### Stack overflow or circular dependency errors
- **Check for infinite loops** between `AppConfigBase.logLevel` and logging systems
- **Verify proper separation** between Remote Config reading and logging
- **Look for `_logForRemoteConfig` usage** in Remote Config repository implementation
- **Ensure logger dependency isn't circular** when reading configuration values

### Emulator mode not working correctly
- **Verify `doUseBackendEmulator` and `doOverrideUseLiveRemoteConfig` settings**
- **Check that mock Remote Config is properly registered** in dependency injection
- **Look for Firebase calls that bypass** the dependency injection system
- **Verify listener setup is skipped** when using mock implementation
