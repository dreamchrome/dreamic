import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../app/app_cubit.dart';
import '../presentation/elements/tappable_action.dart';

/// Mock timer factory for testing that doesn't create real timers
class _TestTimerFactory extends TimerFactory {
  const _TestTimerFactory();

  @override
  Timer createTimer(Duration duration, VoidCallback callback) {
    // Return a fake timer that never fires
    // This prevents pending timer assertions in tests
    return Timer(Duration.zero, () {
      // No-op - prevents timer from actually executing
    });
  }
}

/// Initialize TappableActionGroupManager for testing
///
/// Call this at the start of test files that use TappableAction widgets.
/// This prevents timer-related test failures.
///
/// Example:
/// ```dart
/// void main() {
///   setUpAll(() {
///     initializeTappableActionForTesting();
///   });
///
///   group('MyWidget', () { ... });
/// }
/// ```
void initializeTappableActionForTesting() {
  // Initialize singleton with test config that doesn't create background timers
  TappableActionGroupManager(
    const TappableActionGroupConfig(
      autoResetDelay: Duration.zero,
      enableAutoReset: false,
      resetOnAppResume: false,
      timerFactory: _TestTimerFactory(),
      maxGroupLifetime: Duration.zero,
    ),
  );
}

/// Mock AppCubit for widget testing
///
/// Provides minimal AppState for widgets that depend on AppCubit context.
/// Use [wrapWithMockAppCubit] helper for easy test setup.
///
/// Example:
/// ```dart
/// await tester.pumpWidget(
///   wrapWithMockAppCubit(
///     MaterialApp(
///       home: MyWidget(),
///     ),
///   ),
/// );
/// ```
class MockAppCubit extends AppCubit {
  MockAppCubit({
    NetworkStatus networkStatus = NetworkStatus.connected,
    AppAuthStatus authStatus = AppAuthStatus.noauth,
    AppStatus appStatus = AppStatus.normal,
  }) : super(networkRequired: false) {
    // Emit initial state with provided values using regular emit
    // (emitSafe checks isClosed which may not be set yet in constructor)
    emit(AppState(
      networkStatus: networkStatus,
      appAuthStatus: authStatus,
      appStatus: appStatus,
    ));
  }

  /// Update network status for testing different scenarios
  void setNetworkStatus(NetworkStatus status) {
    emit(state.copyWith(networkStatus: status));
  }

  /// Update auth status for testing
  void setAuthStatus(AppAuthStatus status) {
    emit(state.copyWith(appAuthStatus: status));
  }

  /// Update app status for testing
  void setAppStatus(AppStatus status) {
    emit(state.copyWith(appStatus: status));
  }

  @override
  Future<void> getInitialData() async {
    // Override to prevent network checking and version update service initialization
    // Tests should explicitly set states via setter methods above
  }

  @override
  Future<void> close() async {
    // Ensure we don't try to dispose services that weren't initialized
    // Don't call super.close() to avoid disposing services
    return super.close();
  }
}

/// Helper to wrap widgets with MockAppCubit provider
///
/// This provides the AppCubit context required by widgets that use
/// TappableAction or other components that depend on AppCubit.
///
/// Usage in tests:
/// ```dart
/// Widget createTestWidget() {
///   return wrapWithMockAppCubit(
///     MaterialApp(
///       home: MyWidget(),
///     ),
///   );
/// }
/// ```
///
/// To test different network states:
/// ```dart
/// await tester.pumpWidget(
///   wrapWithMockAppCubit(
///     MaterialApp(home: MyWidget()),
///     networkStatus: NetworkStatus.none,
///   ),
/// );
/// ```
Widget wrapWithMockAppCubit(
  Widget child, {
  NetworkStatus networkStatus = NetworkStatus.connected,
  AppAuthStatus authStatus = AppAuthStatus.noauth,
  AppStatus appStatus = AppStatus.normal,
}) {
  return BlocProvider<AppCubit>(
    create: (_) => MockAppCubit(
      networkStatus: networkStatus,
      authStatus: authStatus,
      appStatus: appStatus,
    ),
    child: child,
  );
}
