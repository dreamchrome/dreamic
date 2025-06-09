# App Update Web Reloader Implementation

## Summary
Updated the `AppUpdateBanner` and `AppUpdateDialog` widgets to use the `reloadApp()` function from `appreloader.dart` for web platforms instead of launching app store URLs.

## Changes Made

### File: `/lib/presentation/elements/app_update_widgets.dart`

#### 1. **Added Imports**
- Added `import 'package:flutter/foundation.dart' show kIsWeb;`
- Added `import 'package:dreamic/presentation/helpers/app_reloader/appreloader.dart';`

#### 2. **AppUpdateBanner Changes**
- **Button Action**: Modified the "Update" button to call `reloadApp()` for web platforms and `_launchAppStore()` for mobile platforms
- **Button Text**: Changed button text to "Refresh" for web and "Update" for mobile
- **Message Text**: Updated banner message to use "refresh" terminology for web platforms

#### 3. **AppUpdateDialog Changes**
- **Dialog Title**: Updated title to show "Refresh Required/Available" for web and "Update Required/Available" for mobile
- **Dialog Content**: Modified content text to use "refresh" terminology for web platforms
- **Button Action**: Modified the action button to call `reloadApp()` for web and `_launchAppStore()` for mobile
- **Button Text**: Changed button text to "Refresh Now" for web and "Update Now" for mobile

## Platform-Specific Behavior

### Web Platforms (`kIsWeb == true`)
- **Banner**: Shows "Refresh" button that calls `reloadApp()`
- **Dialog**: Shows "Refresh Required/Available" with "Refresh Now" button
- **Action**: Reloads the web page using `web.window.location.reload()`
- **Text**: Uses "refresh" terminology throughout

### Mobile Platforms (`kIsWeb == false`)
- **Banner**: Shows "Update" button that launches app store
- **Dialog**: Shows "Update Required/Available" with "Update Now" button  
- **Action**: Opens app store URL using `url_launcher`
- **Text**: Uses "update" terminology throughout

## Benefits

1. **Consistent User Experience**: Web users now get an appropriate "refresh" action instead of being directed to app stores
2. **Immediate Updates**: Web users can immediately get the latest version by refreshing the page
3. **Platform Appropriate**: Each platform gets the most appropriate update mechanism
4. **Follows Existing Pattern**: Matches the implementation already used in `outdated_app_page.dart`

## Testing

The changes maintain backward compatibility for mobile platforms while providing proper web support. The widgets will:

- Show "Refresh" actions on web platforms that reload the page
- Show "Update" actions on mobile platforms that open app stores
- Use appropriate terminology for each platform in all UI text
- Maintain all existing functionality for dismissal, required vs. recommended updates, etc.

## Integration

This implementation works seamlessly with the existing Remote Config update detection system and the web-specific refresh service that was previously implemented. When Remote Config detects an update on web platforms, users will now see appropriate refresh options instead of app store links.
