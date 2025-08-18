## Firebase

For Android devices running API level 28 and above, cleartext (insecure) HTTP traffic is blocked by default. To allow connections to the Firebase emulator (which uses HTTP), add the following attribute to the <application> tag in your AndroidManifest.xml:
<application
    android:label="My App"
    android:icon="@mipmap/ic_launcher"
    android:usesCleartextTraffic="true">
    <!-- ... existing configuration ... -->
</application>

For iOS
<!-- filepath: ios/Runner/Info.plist -->
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


## Firebase CLI
npm install -g firebase-tools

## Enable flutterfire, especially after upgrading firebase cli
dart pub global activate flutterfire_cli

## Connection Checker

https://github.com/RounakTadvi/internet_connection_checker

Android Configuration
On Android, for correct working in release mode, you must add INTERNET & ACCESS_NETWORK_STATE permissions to AndroidManifest.xml, follow the next lines:

    <manifest xmlns:android="http://schemas.android.com/apk/res/android">
    
    <!-- Permissions for internet_connection_checker -->
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
    
    <application
        ...
Mac OS Configuration
On MacOS, you'll need to add the following entry to your DebugProfile.entitlements and Release.entitlements (located under macos/Runner) to allow access to internet.

  <key>com.apple.security.network.server</key>
  <true/>
Example:

  <plist version="1.0">
    <dict>
	    <key>com.apple.security.app-sandbox</key>
	    <true/>
    </dict>
  </plist>







Build APK for TestFlight:
flutter build ipa --dart-define BACKEND_REGION=us-east4

future obfusicate etc....
flutter build ipa --obfuscate --split-debug-info

-----------------------------------------

To configure for each environment:
(dev)
1.) flutterfire configure -p projectname --account email@email.com
2.) Change the Info.plist URLScheme to the correct "Encoded App ID"
3.) Admob IDs
https://developers.google.com/admob/flutter/quick-start

Troubleshooting:

Pod errors:
pod update Firebase/Firestore
pod update
pod repo update
pod install --repo-update

or...

Clean your Flutter project: flutter clean && flutter pub get
Remove Pods directory inside the iOS directory: rm Podfile.lock && rm -rf Pods/
Install and update pods: pod install && pod update
Build and test your app on an iOS device: flutter run. Or build within your Xcode.

or to deintegrate first...

flutter clean flutter pub get cd ios pod deintegrate pod install --repo-update cd ..

# Fixing the dependency errors on iOS:
How to fix:

Delete Podfile.lock and Pods directory
This will force CocoaPods to resolve dependencies fresh.

Pods
Reinstall pods with repo update
This ensures you get the latest podspecs and versions.

pod install --repo-update
pod install --repo-update
If you still see the error, try updating CocoaPods itself:

sudo gem install cocoapods
pod repo update
pod install
If you use precompiled Firestore binaries (see your commented-out pod 'FirebaseFirestore', ...), make sure the version/tag matches the Firebase SDK version your plugins require.
For your current setup, you can leave it commented out unless you specifically want to use the precompiled binary.


# To fix macOS complaining about binaries:
Delete /flutter/bin/cache/artifacts directory and run flutter doctor in terminal


Iphone 11 simulator app folder:
/Users/mike/Library/Developer/CoreSimulator/Devices/EF629263-CFFC-4FAF-9E6A-B352013366D8/data/Containers/Data/Application/22663F53-E005-4F56-9B92-65D10495CD25

delete all data:
rm -r /Users/mike/Library/Developer/CoreSimulator/Devices/EF629263-CFFC-4FAF-9E6A-B352013366D8/data/Containers/Data/Application/22663F53-E005-4F56-9B92-65D10495CD25/*


!!!!!!!!!!!!
Update the Firebase version for iOS when it changes:

target 'Runner' do
  use_frameworks!
  use_modular_headers!
  #This line. The tag depends on what Firebase SDK you have installed.
  pod 'FirebaseFirestore', :git => 'https://github.com/invertase/firestore-ios-sdk-frameworks.git', :tag => '9.5.0'
  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
end
!!!!!!!!!!!!!






Make sure to change the "URL schemes" in XCode to the correct value for the Firebase server.

These were added to AppDelegate.swift for local notifications:
https://github.com/MaikuB/flutter_local_notifications/blob/master/flutter_local_notifications/example/ios/Runner/AppDelegate.swift





==========================================

Notes: 

xcrun simctl list devices

To list booted devices only use:

xcrun simctl list devices booted

To list installed apps on single simulator, use:

xcrun simctl listapps {DEVICE_UUID}

or to list apps on booted simulator only:

xcrun simctl listapps booted




Later:

When more localizations are added, they'll need to be updated in the iOS file here:
https://docs.flutter.dev/ui/accessibility-and-internationalization/internationalization


# Deep links

test iOS:
xcrun simctl openurl booted https://yourDomain.com/path

test Android:
adb shell am start -W -a android.intent.action.VIEW -d "https://app.yourDomain/path"