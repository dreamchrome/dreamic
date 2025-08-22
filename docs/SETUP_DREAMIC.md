# Dreamic Developer Setup Guide

This guide provides instructions for setting up the Dreamic package for development, including environment configuration, dependency setup, and troubleshooting common issues.

## 1. Prerequisites

Before you begin, ensure you have the following tools installed and configured.

### Firebase CLI

Install the Firebase CLI globally using npm:

```bash
npm install -g firebase-tools
```

### FlutterFire CLI

Activate the FlutterFire CLI, which is used to configure Firebase for your Flutter projects. This is especially important after upgrading the Firebase CLI.

```bash
dart pub global activate flutterfire_cli
```

## 2. Firebase Project Setup

### 2.1. Configure Firebase for your Project

Run `flutterfire configure` to link your Flutter app with your Firebase project.

```bash
flutterfire configure -p your-project-name --account your-email@email.com
```

### 2.2. Platform-Specific Configuration

#### Android

To allow your app to connect to the Firebase emulator (which uses insecure HTTP), you need to enable cleartext traffic for debug builds.

In `android/app/src/main/AndroidManifest.xml`, add `android:usesCleartextTraffic="true"` to the `<application>` tag:

```xml
<!-- File: android/app/src/main/AndroidManifest.xml -->
<application
    android:label="My App"
    android:icon="@mipmap/ic_launcher"
    android:usesCleartextTraffic="true">
    <!-- ... existing configuration ... -->
</application>
```

#### iOS

**Emulator Connection:**

To allow connections to the Firebase emulator on iOS, add the following to your `ios/Runner/Info.plist` file to allow arbitrary loads for `localhost`.

```xml
<!-- File: ios/Runner/Info.plist -->
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
    <key>NSExceptionDomains</key>
    <dict>
        <key>localhost</key>
        <dict>
            <key>NSExceptionAllowsInsecureHTTPLoads</key>
            <true/>
            <key>NSIncludesSubdomains</key>
            <true/>
        </dict>
    </dict>
</dict>
```

**URL Schemes:**

Make sure to change the "URL schemes" in Xcode to the correct value for your Firebase server. This is crucial for features like deep linking and authentication.

**AdMob IDs:**

Configure your AdMob application IDs as described in the official documentation: [Google AdMob Flutter Quick Start](https://developers.google.com/admob/flutter/quick-start).

## 3. Dependencies Setup

### `internet_connection_checker`

This package requires platform-specific permissions to check network status.

**Android:**

Add the following permissions to `android/app/src/main/AndroidManifest.xml`:

```xml
<!-- File: android/app/src/main/AndroidManifest.xml -->
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
    <application ...>
        ...
    </application>
</manifest>
```

**macOS:**

Add the network server entitlement to `macos/Runner/DebugProfile.entitlements` and `macos/Runner/Release.entitlements`.

```xml
<!-- File: macos/Runner/DebugProfile.entitlements and Release.entitlements -->
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
```

### `flutter_local_notifications`

For local notifications on iOS, refer to the setup instructions in the example `AppDelegate.swift` from the plugin's repository: [flutter_local_notifications example](https://github.com/MaikuB/flutter_local_notifications/blob/master/flutter_local_notifications/example/ios/Runner/AppDelegate.swift).

## 4. Building and Running

### Building for iOS (TestFlight)

Use the following commands to build an IPA for TestFlight.

**Standard Build:**
```bash
flutter build ipa --dart-define BACKEND_REGION=us-east4
```

**Obfuscated Build:**
```bash
flutter build ipa --obfuscate --split-debug-info
```

### Deep Link Testing

**iOS:**
```bash
xcrun simctl openurl booted https://yourDomain.com/path
```

**Android:**
```bash
adb shell am start -W -a android.intent.action.VIEW -d "https://app.yourDomain/path"
```

## 5. Troubleshooting

### iOS Pod Errors

If you encounter CocoaPods dependency errors, follow these steps:

1.  **Clean Project:**
    ```bash
    flutter clean && flutter pub get
    ```
2.  **Reset Pods:**
    ```bash
    cd ios
    rm -rf Podfile.lock Pods
    pod install --repo-update
    cd ..
    ```
3.  **Deintegrate and Reinstall (if issues persist):**
    ```bash
    cd ios
    pod deintegrate
    pod install --repo-update
    cd ..
    ```
4.  **Update CocoaPods:**
    ```bash
    sudo gem install cocoapods
    pod repo update
    ```

### Updating Firebase SDK for iOS

If you need to use a specific version of the Firebase iOS SDK, you can specify it in your `ios/Podfile`.

```ruby
# File: ios/Podfile
target 'Runner' do
  use_frameworks!
  use_modular_headers!

  # Example: Pinning the Firestore SDK version
  pod 'FirebaseFirestore', :git => 'https://github.com/invertase/firestore-ios-sdk-frameworks.git', :tag => '9.5.0'

  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
end
```

### macOS Binary Issues

If macOS complains about binaries, try clearing Flutter's artifact cache:

1.  Delete the `flutter/bin/cache/artifacts` directory.
2.  Run `flutter doctor`.

### iOS Simulator Data

**Find Simulator App Folder:**
The data for your app on the iOS simulator is located in a path similar to this:
`/Users/your-user/Library/Developer/CoreSimulator/Devices/{DEVICE_UUID}/data/Containers/Data/Application/{APP_UUID}`

**Delete All App Data:**
To clear all data for a specific simulator, you can run:
```bash
# Replace with the correct path for your simulator
rm -r /Users/mike/Library/Developer/CoreSimulator/Devices/EF629263-CFFC-4FAF-9E6A-B352013366D8/data/Containers/Data/Application/22663F53-E005-4F56-9B92-65D10495CD25/*
```

## 6. Development Notes

### Listing Simulator Devices and Apps

**List all devices:**
```bash
xcrun simctl list devices
```

**List booted devices only:**
```bash
xcrun simctl list devices booted
```

**List installed apps on a specific simulator:**
```bash
xcrun simctl listapps {DEVICE_UUID}
```

### Internationalization

When adding new localizations, update the supported locales in your iOS project configuration. See the Flutter documentation for details: [Flutter Internationalization](https://docs.flutter.dev/ui/accessibility-and-internationalization/internationalization).