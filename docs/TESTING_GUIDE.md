# Dreamic Package - Testing Guide

A comprehensive guide to testing widgets and components that use the Dreamic package.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Testing TappableAction Widgets](#testing-tappableaction-widgets)
- [Testing with AppCubit](#testing-with-appcubit)
- [Testing Network-Dependent Features](#testing-network-dependent-features)
- [Testing Authentication-Dependent Features](#testing-authentication-dependent-features)
- [Testing Loading States](#testing-loading-states)
- [Advanced Testing Patterns](#advanced-testing-patterns)
- [Common Issues & Solutions](#common-issues--solutions)
- [Complete Examples](#complete-examples)

---

## Overview

The Dreamic package provides testing utilities in `lib/test_utils/mock_app_cubit.dart` to help you test widgets that depend on Dreamic components like:

- `TappableAction` and `TappableActionInkedWell`
- `AppRootWidget`
- `BlocBuilder<AppCubit, AppState>`
- Network connectivity checks
- Authentication state
- App loading states

### Key Testing Utilities

1. **`initializeTappableActionForTesting()`** - Prevents timer-related test failures
2. **`wrapWithMockAppCubit()`** - Provides AppCubit context for widgets
3. **`MockAppCubit`** - Mock implementation with state setters for testing

---

## Quick Start

### Minimal Test Setup

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dreamic/dreamic.dart';

void main() {
  // 1. Initialize TappableAction testing utilities
  setUpAll(() {
    initializeTappableActionForTesting();
  });

  // 2. Write tests using wrapWithMockAppCubit
  testWidgets('my widget renders correctly', (tester) async {
    await tester.pumpWidget(
      wrapWithMockAppCubit(
        MaterialApp(
          home: MyWidget(),
        ),
      ),
    );
    
    expect(find.byType(MyWidget), findsOneWidget);
  });
}
```

### Why These Steps Are Needed

**`initializeTappableActionForTesting()`**
- Prevents "Timer still pending" assertions in tests
- Configures `TappableActionGroupManager` to not create background timers
- Should be called once in `setUpAll()` for any test file using `TappableAction`

**`wrapWithMockAppCubit()`**
- Provides `AppCubit` context via `BlocProvider`
- Widgets using `BlocBuilder<AppCubit, AppState>` need this context
- `TappableAction` checks network status via `AppCubit`

---

## Testing TappableAction Widgets

### Basic TappableAction Test

```dart
testWidgets('button triggers callback when tapped', (tester) async {
  var callbackInvoked = false;
  
  await tester.pumpWidget(
    wrapWithMockAppCubit(
      MaterialApp(
        home: Scaffold(
          body: TappableAction(
            onTap: () => callbackInvoked = true,
            builder: (context, onTap) {
              return ElevatedButton(
                onPressed: onTap,
                child: Text('Tap Me'),
              );
            },
          ),
        ),
      ),
    ),
  );
  
  await tester.tap(find.text('Tap Me'));
  await tester.pump();
  
  expect(callbackInvoked, isTrue);
});
```

### Testing TappableAction with Config

```dart
testWidgets('button requires network when configured', (tester) async {
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
                child: Text('Submit'),
              );
            },
          ),
        ),
      ),
      // Network is disconnected
      networkStatus: NetworkStatus.none,
    ),
  );
  
  // Button should be disabled
  final button = tester.widget<ElevatedButton>(
    find.byType(ElevatedButton),
  );
  expect(button.onPressed, isNull);
});
```

### Testing TappableActionInkedWell

```dart
testWidgets('InkedWell shows ripple effect', (tester) async {
  var tapped = false;
  
  await tester.pumpWidget(
    wrapWithMockAppCubit(
      MaterialApp(
        home: Scaffold(
          body: TappableActionInkedWell(
            onTap: () => tapped = true,
            child: Container(
              width: 100,
              height: 100,
              child: Text('Tap'),
            ),
          ),
        ),
      ),
    ),
  );
  
  await tester.tap(find.text('Tap'));
  await tester.pump();
  
  expect(tapped, isTrue);
  expect(find.byType(InkWell), findsOneWidget);
});
```

### Testing TappableAction Groups

```dart
testWidgets('buttons in same group disable together', (tester) async {
  const groupId = 'test-group';
  var button1Taps = 0;
  var button2Taps = 0;
  
  await tester.pumpWidget(
    wrapWithMockAppCubit(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TappableAction(
                config: TappableActionConfig(
                  groupId: groupId,
                  minDisabledDuration: Duration(milliseconds: 100),
                ),
                onTap: () => button1Taps++,
                builder: (context, onTap) {
                  return ElevatedButton(
                    onPressed: onTap,
                    child: Text('Button 1'),
                  );
                },
              ),
              TappableAction(
                config: TappableActionConfig(
                  groupId: groupId,
                  minDisabledDuration: Duration(milliseconds: 100),
                ),
                onTap: () => button2Taps++,
                builder: (context, onTap) {
                  return ElevatedButton(
                    onPressed: onTap,
                    child: Text('Button 2'),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
  
  // Tap button 1
  await tester.tap(find.text('Button 1'));
  await tester.pump();
  
  expect(button1Taps, 1);
  
  // Try to tap button 2 immediately - should be disabled
  await tester.tap(find.text('Button 2'));
  await tester.pump();
  
  expect(button2Taps, 0); // Group is disabled
  
  // Wait for group to re-enable
  await tester.pump(Duration(milliseconds: 150));
  
  // Now button 2 should work
  await tester.tap(find.text('Button 2'));
  await tester.pump();
  
  expect(button2Taps, 1);
});
```

---

## Testing with AppCubit

### Using wrapWithMockAppCubit Helper

The simplest way to provide AppCubit context:

```dart
testWidgets('widget accesses AppCubit state', (tester) async {
  await tester.pumpWidget(
    wrapWithMockAppCubit(
      MaterialApp(home: MyWidget()),
      networkStatus: NetworkStatus.connected,
      authStatus: AppAuthStatus.authenticated,
      appStatus: AppStatus.normal,
    ),
  );
  
  // Your assertions
});
```

### Creating MockAppCubit Directly

For more control over state changes:

```dart
testWidgets('widget responds to AppCubit state changes', (tester) async {
  final mockCubit = MockAppCubit(
    networkStatus: NetworkStatus.connected,
    authStatus: AppAuthStatus.noauth,
  );
  
  await tester.pumpWidget(
    BlocProvider<AppCubit>.value(
      value: mockCubit,
      child: MaterialApp(
        home: MyAuthWidget(),
      ),
    ),
  );
  
  // Initially not authenticated
  expect(find.text('Please log in'), findsOneWidget);
  
  // Simulate login
  mockCubit.setAuthStatus(AppAuthStatus.authenticated);
  await tester.pump();
  
  // Should show authenticated content
  expect(find.text('Welcome!'), findsOneWidget);
  
  // Clean up
  await mockCubit.close();
});
```

### MockAppCubit State Setters

```dart
final mockCubit = MockAppCubit();

// Change network status
mockCubit.setNetworkStatus(NetworkStatus.connected);
mockCubit.setNetworkStatus(NetworkStatus.connecting);
mockCubit.setNetworkStatus(NetworkStatus.none);

// Change auth status
mockCubit.setAuthStatus(AppAuthStatus.noauth);
mockCubit.setAuthStatus(AppAuthStatus.authenticating);
mockCubit.setAuthStatus(AppAuthStatus.authenticated);

// Change app status
mockCubit.setAppStatus(AppStatus.loading);
mockCubit.setAppStatus(AppStatus.normal);
mockCubit.setAppStatus(AppStatus.error);
```

---

## Testing Network-Dependent Features

### Testing Offline Behavior

```dart
testWidgets('shows offline message when disconnected', (tester) async {
  await tester.pumpWidget(
    wrapWithMockAppCubit(
      MaterialApp(home: MyNetworkWidget()),
      networkStatus: NetworkStatus.none,
    ),
  );
  
  expect(find.text('You are offline'), findsOneWidget);
});
```

### Testing Network State Transitions

```dart
testWidgets('handles network reconnection', (tester) async {
  final mockCubit = MockAppCubit(
    networkStatus: NetworkStatus.none,
  );
  
  await tester.pumpWidget(
    BlocProvider<AppCubit>.value(
      value: mockCubit,
      child: MaterialApp(home: MyNetworkWidget()),
    ),
  );
  
  // Initially offline
  expect(find.text('No connection'), findsOneWidget);
  
  // Simulate reconnecting
  mockCubit.setNetworkStatus(NetworkStatus.connecting);
  await tester.pump();
  
  expect(find.text('Connecting...'), findsOneWidget);
  
  // Simulate connected
  mockCubit.setNetworkStatus(NetworkStatus.connected);
  await tester.pump();
  
  expect(find.text('Online'), findsOneWidget);
  
  await mockCubit.close();
});
```

### Testing Network-Required Actions

```dart
testWidgets('disables submit when offline', (tester) async {
  var submitCalled = false;
  
  await tester.pumpWidget(
    wrapWithMockAppCubit(
      MaterialApp(
        home: Scaffold(
          body: TappableAction(
            config: TappableActionConfig(requireNetwork: true),
            onTap: () => submitCalled = true,
            builder: (context, onTap) {
              return ElevatedButton(
                onPressed: onTap,
                child: Text('Submit'),
              );
            },
          ),
        ),
      ),
      networkStatus: NetworkStatus.none,
    ),
  );
  
  // Try to tap - should be disabled
  await tester.tap(find.text('Submit'));
  await tester.pump();
  
  expect(submitCalled, isFalse);
  
  final button = tester.widget<ElevatedButton>(
    find.byType(ElevatedButton),
  );
  expect(button.onPressed, isNull);
});
```

---

## Testing Authentication-Dependent Features

### Testing Login Flow

```dart
testWidgets('shows login screen when not authenticated', (tester) async {
  await tester.pumpWidget(
    wrapWithMockAppCubit(
      MaterialApp(home: MyApp()),
      authStatus: AppAuthStatus.noauth,
    ),
  );
  
  expect(find.byType(LoginPage), findsOneWidget);
  expect(find.byType(HomePage), findsNothing);
});
```

### Testing Auth State Transitions

```dart
testWidgets('navigates to home after authentication', (tester) async {
  final mockCubit = MockAppCubit(
    authStatus: AppAuthStatus.noauth,
  );
  
  await tester.pumpWidget(
    BlocProvider<AppCubit>.value(
      value: mockCubit,
      child: MaterialApp(
        home: MyAuthenticatedApp(),
      ),
    ),
  );
  
  // Initially shows login
  expect(find.text('Login'), findsOneWidget);
  
  // Simulate authentication
  mockCubit.setAuthStatus(AppAuthStatus.authenticated);
  await tester.pumpAndSettle();
  
  // Should navigate to home
  expect(find.text('Home'), findsOneWidget);
  
  await mockCubit.close();
});
```

### Testing Protected Content

```dart
testWidgets('hides protected content when not authenticated', (tester) async {
  await tester.pumpWidget(
    wrapWithMockAppCubit(
      MaterialApp(
        home: BlocBuilder<AppCubit, AppState>(
          builder: (context, state) {
            if (state.appAuthStatus == AppAuthStatus.authenticated) {
              return Text('Secret Content');
            }
            return Text('Please log in');
          },
        ),
      ),
      authStatus: AppAuthStatus.noauth,
    ),
  );
  
  expect(find.text('Secret Content'), findsNothing);
  expect(find.text('Please log in'), findsOneWidget);
});
```

---

## Testing Loading States

### Testing Initial App Loading

```dart
testWidgets('shows splash screen during app loading', (tester) async {
  await tester.pumpWidget(
    wrapWithMockAppCubit(
      MaterialApp(home: MyApp()),
      appStatus: AppStatus.loading,
    ),
  );
  
  expect(find.byType(SplashScreen), findsOneWidget);
  expect(find.byType(HomePage), findsNothing);
});
```

### Testing Loading to Loaded Transition

```dart
testWidgets('transitions from loading to loaded', (tester) async {
  final mockCubit = MockAppCubit(
    appStatus: AppStatus.loading,
  );
  
  await tester.pumpWidget(
    BlocProvider<AppCubit>.value(
      value: mockCubit,
      child: MaterialApp(
        home: BlocBuilder<AppCubit, AppState>(
          builder: (context, state) {
            if (state.appStatus == AppStatus.loading) {
              return CircularProgressIndicator();
            }
            return Text('Loaded');
          },
        ),
      ),
    ),
  );
  
  expect(find.byType(CircularProgressIndicator), findsOneWidget);
  
  // Simulate loading complete
  mockCubit.setAppStatus(AppStatus.normal);
  await tester.pump();
  
  expect(find.text('Loaded'), findsOneWidget);
  
  await mockCubit.close();
});
```

### Testing Error States

```dart
testWidgets('shows error message when app fails to load', (tester) async {
  await tester.pumpWidget(
    wrapWithMockAppCubit(
      MaterialApp(home: MyApp()),
      appStatus: AppStatus.error,
    ),
  );
  
  expect(find.text('Error loading app'), findsOneWidget);
  expect(find.text('Retry'), findsOneWidget);
});
```

---

## Advanced Testing Patterns

### Testing Complex State Combinations

```dart
testWidgets('handles all state combinations correctly', (tester) async {
  final scenarios = [
    {
      'network': NetworkStatus.connected,
      'auth': AppAuthStatus.authenticated,
      'app': AppStatus.normal,
      'expected': 'Full Access',
    },
    {
      'network': NetworkStatus.none,
      'auth': AppAuthStatus.authenticated,
      'app': AppStatus.normal,
      'expected': 'Offline Mode',
    },
    {
      'network': NetworkStatus.connected,
      'auth': AppAuthStatus.noauth,
      'app': AppStatus.normal,
      'expected': 'Login Required',
    },
  ];
  
  for (final scenario in scenarios) {
    await tester.pumpWidget(
      wrapWithMockAppCubit(
        MaterialApp(home: MyComplexWidget()),
        networkStatus: scenario['network'] as NetworkStatus,
        authStatus: scenario['auth'] as AppAuthStatus,
        appStatus: scenario['app'] as AppStatus,
      ),
    );
    
    expect(
      find.text(scenario['expected'] as String),
      findsOneWidget,
      reason: 'Failed scenario: $scenario',
    );
  }
});
```

### Testing with Custom Cubit

```dart
class CustomMockAppCubit extends MockAppCubit {
  bool loadingOverlayVisible = false;
  
  @override
  void overlayLoadingStart() {
    loadingOverlayVisible = true;
    super.overlayLoadingStart();
  }
  
  @override
  void overlayLoadingFinish() {
    loadingOverlayVisible = false;
    super.overlayLoadingFinish();
  }
}

testWidgets('tracks loading overlay calls', (tester) async {
  final customCubit = CustomMockAppCubit();
  
  await tester.pumpWidget(
    BlocProvider<AppCubit>.value(
      value: customCubit,
      child: MaterialApp(home: MyWidget()),
    ),
  );
  
  // Trigger action that shows loading
  await tester.tap(find.text('Load Data'));
  await tester.pump();
  
  expect(customCubit.loadingOverlayVisible, isTrue);
  
  await customCubit.close();
});
```

### Testing Async Operations

```dart
testWidgets('handles async tap operations', (tester) async {
  final completer = Completer<void>();
  var completed = false;
  
  await tester.pumpWidget(
    wrapWithMockAppCubit(
      MaterialApp(
        home: Scaffold(
          body: TappableAction(
            onTap: () async {
              await completer.future;
              completed = true;
            },
            builder: (context, onTap) {
              return ElevatedButton(
                onPressed: onTap,
                child: Text('Async Action'),
              );
            },
          ),
        ),
      ),
    ),
  );
  
  // Tap button
  await tester.tap(find.text('Async Action'));
  await tester.pump();
  
  // Operation not complete yet
  expect(completed, isFalse);
  
  // Complete the operation
  completer.complete();
  await tester.pump();
  
  // Now it should be complete
  expect(completed, isTrue);
});
```

### Testing with Golden Files

```dart
testWidgets('matches golden file in all states', (tester) async {
  await tester.pumpWidget(
    wrapWithMockAppCubit(
      MaterialApp(home: MyWidget()),
      networkStatus: NetworkStatus.connected,
    ),
  );
  
  await expectLater(
    find.byType(MyWidget),
    matchesGoldenFile('goldens/my_widget_connected.png'),
  );
  
  // Test offline state
  await tester.pumpWidget(
    wrapWithMockAppCubit(
      MaterialApp(home: MyWidget()),
      networkStatus: NetworkStatus.none,
    ),
  );
  
  await expectLater(
    find.byType(MyWidget),
    matchesGoldenFile('goldens/my_widget_offline.png'),
  );
});
```

---

## Common Issues & Solutions

### Issue: "Timer still pending after test"

**Problem:** Tests fail with pending timer assertions.

**Solution:** Call `initializeTappableActionForTesting()` in `setUpAll()`:

```dart
void main() {
  setUpAll(() {
    initializeTappableActionForTesting();
  });
  
  testWidgets('...', (tester) async {
    // Your test
  });
}
```

### Issue: "BlocProvider not found in context"

**Problem:** Widget tries to access AppCubit but it's not provided.

**Solution:** Wrap your widget with `wrapWithMockAppCubit()`:

```dart
testWidgets('test', (tester) async {
  await tester.pumpWidget(
    wrapWithMockAppCubit(
      MaterialApp(home: MyWidget()),
    ),
  );
});
```

### Issue: State changes not reflected in UI

**Problem:** Called state setter but UI didn't update.

**Solution:** Call `await tester.pump()` or `await tester.pumpAndSettle()` after state changes:

```dart
mockCubit.setNetworkStatus(NetworkStatus.none);
await tester.pump(); // Forces widget rebuild

// Or for animations:
await tester.pumpAndSettle();
```

### Issue: Memory leaks in tests

**Problem:** MockAppCubit instances not disposed.

**Solution:** Close cubit instances when using them directly:

```dart
testWidgets('test', (tester) async {
  final mockCubit = MockAppCubit();
  
  await tester.pumpWidget(
    BlocProvider<AppCubit>.value(
      value: mockCubit,
      child: MaterialApp(home: MyWidget()),
    ),
  );
  
  // Test code...
  
  await mockCubit.close(); // Clean up
});
```

**Note:** When using `wrapWithMockAppCubit()`, the cubit is automatically managed.

### Issue: Testing TappableAction with real timers

**Problem:** Need to test actual debouncing/cooldown behavior.

**Solution:** Use `tester.pump(Duration)` to advance time:

```dart
testWidgets('respects cooldown duration', (tester) async {
  var tapCount = 0;
  
  await tester.pumpWidget(
    wrapWithMockAppCubit(
      MaterialApp(
        home: Scaffold(
          body: TappableAction(
            config: TappableActionConfig(
              coolDownDuration: Duration(seconds: 1),
            ),
            onTap: () => tapCount++,
            builder: (context, onTap) {
              return ElevatedButton(
                onPressed: onTap,
                child: Text('Tap'),
              );
            },
          ),
        ),
      ),
    ),
  );
  
  // First tap
  await tester.tap(find.text('Tap'));
  await tester.pump();
  expect(tapCount, 1);
  
  // Immediate second tap - should be ignored
  await tester.tap(find.text('Tap'));
  await tester.pump();
  expect(tapCount, 1);
  
  // Wait for cooldown
  await tester.pump(Duration(seconds: 1, milliseconds: 100));
  
  // Third tap - should work
  await tester.tap(find.text('Tap'));
  await tester.pump();
  expect(tapCount, 2);
});
```

---

## Complete Examples

### Example 1: Login Form Test

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dreamic/dreamic.dart';

class LoginForm extends StatelessWidget {
  final VoidCallback onLogin;
  
  const LoginForm({required this.onLogin});
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(key: Key('email')),
        TextField(key: Key('password')),
        TappableAction(
          config: TappableActionConfig(requireNetwork: true),
          onTap: onLogin,
          builder: (context, onTap) {
            return ElevatedButton(
              onPressed: onTap,
              child: Text('Login'),
            );
          },
        ),
      ],
    );
  }
}

void main() {
  setUpAll(() {
    initializeTappableActionForTesting();
  });

  group('LoginForm', () {
    testWidgets('allows login when online', (tester) async {
      var loginCalled = false;
      
      await tester.pumpWidget(
        wrapWithMockAppCubit(
          MaterialApp(
            home: Scaffold(
              body: LoginForm(onLogin: () => loginCalled = true),
            ),
          ),
          networkStatus: NetworkStatus.connected,
        ),
      );
      
      await tester.tap(find.text('Login'));
      await tester.pump();
      
      expect(loginCalled, isTrue);
    });
    
    testWidgets('disables login when offline', (tester) async {
      var loginCalled = false;
      
      await tester.pumpWidget(
        wrapWithMockAppCubit(
          MaterialApp(
            home: Scaffold(
              body: LoginForm(onLogin: () => loginCalled = true),
            ),
          ),
          networkStatus: NetworkStatus.none,
        ),
      );
      
      final button = tester.widget<ElevatedButton>(
        find.byType(ElevatedButton),
      );
      
      expect(button.onPressed, isNull);
      expect(loginCalled, isFalse);
    });
  });
}
```

### Example 2: Dashboard with Multiple States

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dreamic/dreamic.dart';

class Dashboard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppCubit, AppState>(
      builder: (context, state) {
        if (state.appStatus == AppStatus.loading) {
          return CircularProgressIndicator();
        }
        
        if (state.appAuthStatus != AppAuthStatus.authenticated) {
          return Text('Please log in');
        }
        
        if (state.networkStatus == NetworkStatus.none) {
          return Text('Offline - Limited functionality');
        }
        
        return Column(
          children: [
            Text('Welcome to Dashboard'),
            TappableAction(
              onTap: () {},
              builder: (context, onTap) {
                return ElevatedButton(
                  onPressed: onTap,
                  child: Text('Refresh'),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

void main() {
  setUpAll(() {
    initializeTappableActionForTesting();
  });

  group('Dashboard', () {
    testWidgets('shows loading during app initialization', (tester) async {
      await tester.pumpWidget(
        wrapWithMockAppCubit(
          MaterialApp(home: Dashboard()),
          appStatus: AppStatus.loading,
        ),
      );
      
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Welcome to Dashboard'), findsNothing);
    });
    
    testWidgets('requires authentication', (tester) async {
      await tester.pumpWidget(
        wrapWithMockAppCubit(
          MaterialApp(home: Dashboard()),
          authStatus: AppAuthStatus.noauth,
        ),
      );
      
      expect(find.text('Please log in'), findsOneWidget);
    });
    
    testWidgets('shows offline message when disconnected', (tester) async {
      await tester.pumpWidget(
        wrapWithMockAppCubit(
          MaterialApp(home: Dashboard()),
          authStatus: AppAuthStatus.authenticated,
          networkStatus: NetworkStatus.none,
        ),
      );
      
      expect(find.text('Offline - Limited functionality'), findsOneWidget);
    });
    
    testWidgets('shows full dashboard when authenticated and online', 
      (tester) async {
      await tester.pumpWidget(
        wrapWithMockAppCubit(
          MaterialApp(home: Dashboard()),
          authStatus: AppAuthStatus.authenticated,
          networkStatus: NetworkStatus.connected,
        ),
      );
      
      expect(find.text('Welcome to Dashboard'), findsOneWidget);
      expect(find.text('Refresh'), findsOneWidget);
    });
    
    testWidgets('handles state transitions', (tester) async {
      final mockCubit = MockAppCubit(
        appStatus: AppStatus.loading,
        authStatus: AppAuthStatus.noauth,
        networkStatus: NetworkStatus.none,
      );
      
      await tester.pumpWidget(
        BlocProvider<AppCubit>.value(
          value: mockCubit,
          child: MaterialApp(home: Dashboard()),
        ),
      );
      
      // Initially loading
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      
      // App loads but user not authenticated
      mockCubit.setAppStatus(AppStatus.normal);
      await tester.pump();
      expect(find.text('Please log in'), findsOneWidget);
      
      // User authenticates but still offline
      mockCubit.setAuthStatus(AppAuthStatus.authenticated);
      await tester.pump();
      expect(find.text('Offline - Limited functionality'), findsOneWidget);
      
      // Network comes online
      mockCubit.setNetworkStatus(NetworkStatus.connected);
      await tester.pump();
      expect(find.text('Welcome to Dashboard'), findsOneWidget);
      
      await mockCubit.close();
    });
  });
}
```

### Example 3: Testing Group Behavior

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dreamic/dreamic.dart';

class FormWithMultipleButtons extends StatelessWidget {
  final VoidCallback onSave;
  final VoidCallback onCancel;
  
  const FormWithMultipleButtons({
    required this.onSave,
    required this.onCancel,
  });
  
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        TappableAction(
          config: TappableActionConfig(
            groupId: 'form-actions',
            minDisabledDuration: Duration(milliseconds: 500),
          ),
          onTap: onSave,
          builder: (context, onTap) {
            return ElevatedButton(
              onPressed: onTap,
              child: Text('Save'),
            );
          },
        ),
        TappableAction(
          config: TappableActionConfig(
            groupId: 'form-actions',
            minDisabledDuration: Duration(milliseconds: 500),
          ),
          onTap: onCancel,
          builder: (context, onTap) {
            return ElevatedButton(
              onPressed: onTap,
              child: Text('Cancel'),
            );
          },
        ),
      ],
    );
  }
}

void main() {
  setUpAll(() {
    initializeTappableActionForTesting();
  });

  group('FormWithMultipleButtons', () {
    testWidgets('disables both buttons when one is tapped', (tester) async {
      var saveTaps = 0;
      var cancelTaps = 0;
      
      await tester.pumpWidget(
        wrapWithMockAppCubit(
          MaterialApp(
            home: Scaffold(
              body: FormWithMultipleButtons(
                onSave: () => saveTaps++,
                onCancel: () => cancelTaps++,
              ),
            ),
          ),
        ),
      );
      
      // Tap Save
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(saveTaps, 1);
      
      // Try to tap Cancel immediately - should be disabled
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(cancelTaps, 0); // Still 0 due to group disabled
      
      // Wait for group to re-enable
      await tester.pump(Duration(milliseconds: 600));
      
      // Now Cancel should work
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(cancelTaps, 1);
    });
  });
}
```

---

## Best Practices Summary

1. **Always call `initializeTappableActionForTesting()` in `setUpAll()`** for test files using TappableAction
2. **Use `wrapWithMockAppCubit()` for simple cases** - it handles BlocProvider setup
3. **Create `MockAppCubit` directly for dynamic state testing** - but remember to call `close()`
4. **Call `await tester.pump()` after state changes** to ensure UI updates
5. **Test different state combinations** using the provided parameters (network, auth, app status)
6. **Clean up resources** - close cubit instances when created directly
7. **Use `pumpAndSettle()` for animations** and navigation transitions
8. **Test error cases and edge cases** in addition to happy paths
9. **Leverage golden tests** for visual regression testing
10. **Use semantic finders** (`find.text()`, `find.byType()`) over complex widget traversal

---

## Additional Resources

- [Flutter Testing Documentation](https://docs.flutter.dev/testing)
- [Bloc Testing Library](https://pub.dev/packages/bloc_test)
- [DREAMIC_FEATURES_GUIDE.md](DREAMIC_FEATURES_GUIDE.md) - Main features documentation
- [TappableAction Source](../lib/presentation/elements/tappable_action.dart) - Implementation details
- [MockAppCubit Source](../lib/test_utils/mock_app_cubit.dart) - Testing utilities source

---

**Questions or Issues?**

If you encounter testing scenarios not covered in this guide, please open an issue in the repository with your use case and we'll expand the documentation.
