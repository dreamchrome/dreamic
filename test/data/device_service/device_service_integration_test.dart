import 'package:dartz/dartz.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dreamic/data/helpers/repository_failure.dart';
import 'package:dreamic/data/models/device_info.dart';
import 'package:dreamic/data/models/device_platform.dart';
import 'package:dreamic/data/repos/auth_service_int.dart';
import 'package:dreamic/data/repos/device_service_int.dart';

/// Integration tests for DeviceService lifecycle flows.
///
/// These tests verify the complete device lifecycle scenarios that are
/// critical for hospital-grade reliability:
///
/// 1. **First Login Flow** - New user, new device
/// 2. **Token Granted Later** - User grants notification permission after login
/// 3. **Token Rotation** - FCM token changes during session
/// 4. **Logout Offline** - User logs out while offline
/// 5. **Account Switch** - Different user logs in on same device
///
/// ## Running Integration Tests
///
/// These tests require a mock or stub implementation of DeviceService
/// that simulates backend behavior. For true integration testing with
/// Firebase, use the Firebase Emulator Suite.
///
/// ### With Firebase Emulator
///
/// 1. Start the Firebase Emulators:
///    ```bash
///    firebase emulators:start --only functions,firestore,auth
///    ```
///
/// 2. Run tests with emulator configuration:
///    ```bash
///    flutter test test/data/device_service/device_service_integration_test.dart
///    ```
///
/// ### With Mock Implementation
///
/// The tests in this file use [MockDeviceService] which simulates the
/// backend behavior without network calls.
void main() {
  late MockDeviceService deviceService;
  late MockAuthService authService;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    deviceService = MockDeviceService();
    authService = MockAuthService();
  });

  group('First Login Flow', () {
    test('registers device on first authentication', () async {
      // Simulate first login
      authService.currentUid = 'user-123';

      // Connect device service to auth
      await deviceService.connectToAuthService(authService: authService);

      // Simulate auth callback
      await deviceService.simulateOnAuthenticated('user-123');

      // Verify device was registered
      expect(deviceService.registeredDevices, hasLength(1));
      expect(
          deviceService.registeredDevices.first.timezone, isNotNull);
      expect(deviceService.registeredDevices.first.platform, isNotNull);
    });

    test('generates new device ID on first run', () async {
      final deviceId1 = await deviceService.getDeviceId();
      final deviceId2 = await deviceService.getDeviceId();

      // Should return same ID on subsequent calls
      expect(deviceId1, deviceId2);
      expect(deviceId1, isNotEmpty);
    });

    test('persists device ID across service instances', () async {
      final deviceId1 = await deviceService.getDeviceId();

      // Create new service instance (simulates app restart)
      final deviceService2 = MockDeviceService();
      final deviceId2 = await deviceService2.getDeviceId();

      expect(deviceId1, deviceId2);
    });
  });

  group('Token Granted Later Flow', () {
    test('updates token after initial registration', () async {
      authService.currentUid = 'user-123';
      await deviceService.connectToAuthService(authService: authService);

      // First: Register without token
      await deviceService.simulateOnAuthenticated('user-123');
      expect(deviceService.registeredDevices.first.fcmToken, isNull);

      // Later: User grants permission, token arrives
      await deviceService.persistFcmToken(fcmToken: 'new-fcm-token');

      // Verify token was updated
      final updatedDevice = deviceService.getDeviceById(
          await deviceService.getDeviceId());
      expect(updatedDevice?.fcmToken, 'new-fcm-token');
    });

    test('handles token update before registration completes', () async {
      // Token arrives before auth callback completes
      // (e.g., rapid app startup sequence)

      authService.currentUid = 'user-123';

      // Update token before registration
      await deviceService.persistFcmToken(fcmToken: 'early-token');

      // Then register
      await deviceService.connectToAuthService(authService: authService);
      await deviceService.simulateOnAuthenticated('user-123');

      // Token should be included in registration
      final device = deviceService.getDeviceById(
          await deviceService.getDeviceId());
      expect(device?.fcmToken, 'early-token');
    });
  });

  group('Token Rotation Flow', () {
    test('updates token when FCM rotates', () async {
      authService.currentUid = 'user-123';
      await deviceService.connectToAuthService(authService: authService);
      await deviceService.simulateOnAuthenticated('user-123');

      // Initial token
      await deviceService.persistFcmToken(fcmToken: 'token-v1');

      // FCM rotates token
      await deviceService.persistFcmToken(fcmToken: 'token-v2');

      final device = deviceService.getDeviceById(
          await deviceService.getDeviceId());
      expect(device?.fcmToken, 'token-v2');
    });

    test('handles null token (permission revoked)', () async {
      authService.currentUid = 'user-123';
      await deviceService.connectToAuthService(authService: authService);
      await deviceService.simulateOnAuthenticated('user-123');

      // Set initial token
      await deviceService.persistFcmToken(fcmToken: 'valid-token');

      // User revokes permission
      await deviceService.persistFcmToken(fcmToken: null);

      final device = deviceService.getDeviceById(
          await deviceService.getDeviceId());
      expect(device?.fcmToken, isNull);
    });
  });

  group('Logout Offline Scenario', () {
    test('stores unregister in pending when offline', () async {
      authService.currentUid = 'user-123';
      await deviceService.connectToAuthService(authService: authService);
      await deviceService.simulateOnAuthenticated('user-123');

      // Simulate offline
      deviceService.simulateOffline();

      // Logout attempt
      await deviceService.simulateOnAboutToLogOut();

      // Should have pending unregister
      expect(deviceService.hasPendingPayload, isTrue);
    });

    test('completes unregister when back online', () async {
      authService.currentUid = 'user-123';
      await deviceService.connectToAuthService(authService: authService);
      await deviceService.simulateOnAuthenticated('user-123');

      final deviceId = await deviceService.getDeviceId();
      expect(deviceService.getDeviceById(deviceId), isNotNull);

      // Go offline and logout
      deviceService.simulateOffline();
      await deviceService.simulateOnAboutToLogOut();

      // Come back online
      deviceService.simulateOnline();
      await deviceService.flushPendingPayload();

      // Device should be unregistered
      expect(deviceService.getDeviceById(deviceId), isNull);
    });
  });

  group('Account Switch Flow', () {
    test('unregisters old user and registers new user', () async {
      // First user logs in
      authService.currentUid = 'user-1';
      await deviceService.connectToAuthService(authService: authService);
      await deviceService.simulateOnAuthenticated('user-1');

      final deviceId = await deviceService.getDeviceId();
      expect(deviceService.getDevicesForUser('user-1'), hasLength(1));

      // First user logs out
      await deviceService.simulateOnAboutToLogOut();
      authService.currentUid = null;

      // Device should be unregistered for user-1
      expect(deviceService.getDevicesForUser('user-1'), isEmpty);

      // Second user logs in (same device)
      authService.currentUid = 'user-2';
      await deviceService.simulateOnAuthenticated('user-2');

      // Same device ID should now be registered for user-2
      expect(deviceService.getDevicesForUser('user-2'), hasLength(1));
      expect(
        deviceService.getDevicesForUser('user-2').first.deviceId,
        deviceId,
      );
    });
  });

  group('Timezone Update Scenarios', () {
    test('detects timezone change on app resume', () async {
      authService.currentUid = 'user-123';
      await deviceService.connectToAuthService(authService: authService);
      await deviceService.simulateOnAuthenticated('user-123');

      // Simulate travel: timezone changes
      deviceService.simulateTimezoneChange('Europe/London', 0);

      // App resumes
      final result = await deviceService.updateTimezoneOrOffsetIfChanged();

      result.fold(
        (failure) => fail('Should have succeeded'),
        (didUpdate) => expect(didUpdate, isTrue),
      );
    });

    test('detects DST offset change with same timezone', () async {
      authService.currentUid = 'user-123';
      await deviceService.connectToAuthService(authService: authService);
      await deviceService.simulateOnAuthenticated('user-123');

      // Register with EST
      deviceService.simulateTimezoneChange('America/New_York', -300);
      await deviceService.updateTimezoneOrOffsetIfChanged();

      // DST kicks in: same timezone, different offset
      deviceService.simulateTimezoneChange('America/New_York', -240);

      final result = await deviceService.updateTimezoneOrOffsetIfChanged();

      result.fold(
        (failure) => fail('Should have succeeded'),
        (didUpdate) => expect(didUpdate, isTrue),
      );
    });
  });

  group('Error Recovery', () {
    test('retries failed registration on next lifecycle event', () async {
      authService.currentUid = 'user-123';
      await deviceService.connectToAuthService(authService: authService);

      // First attempt fails
      deviceService.simulateBackendError();
      await deviceService.simulateOnAuthenticated('user-123');

      // Device not registered
      expect(deviceService.registeredDevices, isEmpty);
      expect(deviceService.hasPendingPayload, isTrue);

      // Backend recovers
      deviceService.clearBackendError();

      // Next lifecycle event triggers retry
      await deviceService.flushPendingPayload();

      // Now registered
      expect(deviceService.registeredDevices, hasLength(1));
    });

    test('handles concurrent flush attempts safely', () async {
      authService.currentUid = 'user-123';
      await deviceService.connectToAuthService(authService: authService);
      await deviceService.simulateOnAuthenticated('user-123');

      // Update token (creates pending payload)
      deviceService.simulateOffline();
      await deviceService.persistFcmToken(fcmToken: 'token');

      deviceService.simulateOnline();

      // Concurrent flush attempts
      final futures = [
        deviceService.flushPendingPayload(),
        deviceService.flushPendingPayload(),
        deviceService.flushPendingPayload(),
      ];

      await Future.wait(futures);

      // Should handle gracefully - no duplicates, no errors
      expect(deviceService.registeredDevices, hasLength(1));
    });
  });
}

// ============================================================================
// Mock Implementations for Testing
// ============================================================================

/// Mock implementation of DeviceServiceInt for testing lifecycle flows.
///
/// This mock simulates backend behavior without network calls, making
/// tests fast and deterministic.
class MockDeviceService implements DeviceServiceInt {
  final List<DeviceInfo> _devices = [];
  String? _deviceId;
  String _currentTimezone = 'America/New_York';
  int _currentOffset = -300;
  bool _isOnline = true;
  bool _hasBackendError = false;
  bool _hasPendingPayload = false;
  bool _isFlushingPayload = false;
  String? _pendingFcmToken;
  bool _pendingUnregister = false;
  MockAuthService? _authService;

  List<DeviceInfo> get registeredDevices => List.unmodifiable(_devices);
  bool get hasPendingPayload => _hasPendingPayload;

  void simulateOffline() => _isOnline = false;
  void simulateOnline() => _isOnline = true;
  void simulateBackendError() => _hasBackendError = true;
  void clearBackendError() => _hasBackendError = false;

  void simulateTimezoneChange(String timezone, int offset) {
    _currentTimezone = timezone;
    _currentOffset = offset;
  }

  DeviceInfo? getDeviceById(String deviceId) {
    try {
      return _devices.firstWhere((d) => d.deviceId == deviceId);
    } catch (_) {
      return null;
    }
  }

  List<DeviceInfo> getDevicesForUser(String uid) {
    // In real impl, devices are scoped by uid in Firestore path
    // For mock, we just return all devices (single user assumption)
    return _devices.toList();
  }

  Future<void> simulateOnAuthenticated(String uid) async {
    if (!_isOnline || _hasBackendError) {
      _hasPendingPayload = true;
      return;
    }

    final deviceId = await getDeviceId();
    _devices.add(DeviceInfo(
      deviceId: deviceId,
      timezone: _currentTimezone,
      timezoneOffsetMinutes: _currentOffset,
      platform: DevicePlatform.ios,
      appVersion: '1.0.0',
      fcmToken: _pendingFcmToken,
    ));
    _pendingFcmToken = null;
    _hasPendingPayload = false;
  }

  Future<void> simulateOnAboutToLogOut() async {
    if (!_isOnline || _hasBackendError) {
      _hasPendingPayload = true;
      _pendingUnregister = true;
      return;
    }

    final deviceId = await getDeviceId();
    _devices.removeWhere((d) => d.deviceId == deviceId);
    _hasPendingPayload = false;
    _pendingUnregister = false;
  }

  Future<void> flushPendingPayload() async {
    if (_isFlushingPayload) return;
    if (!_hasPendingPayload) return;
    if (!_isOnline || _hasBackendError) return;

    _isFlushingPayload = true;
    try {
      final deviceId = await getDeviceId();

      // Handle pending unregister first
      if (_pendingUnregister) {
        _devices.removeWhere((d) => d.deviceId == deviceId);
        _pendingUnregister = false;
        _hasPendingPayload = false;
        return;
      }

      // Simulate flush - register/update
      if (_devices.every((d) => d.deviceId != deviceId)) {
        _devices.add(DeviceInfo(
          deviceId: deviceId,
          timezone: _currentTimezone,
          timezoneOffsetMinutes: _currentOffset,
          platform: DevicePlatform.ios,
          appVersion: '1.0.0',
          fcmToken: _pendingFcmToken,
        ));
      } else {
        // Update existing
        final index = _devices.indexWhere((d) => d.deviceId == deviceId);
        if (index >= 0 && _pendingFcmToken != null) {
          _devices[index] = _devices[index].copyWith(fcmToken: _pendingFcmToken);
        }
      }
      _pendingFcmToken = null;
      _hasPendingPayload = false;
    } finally {
      _isFlushingPayload = false;
    }
  }

  @override
  Future<String> getDeviceId() async {
    if (_deviceId != null) return _deviceId!;

    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('dreamic_device_id');
    if (id == null) {
      id = 'mock-device-${DateTime.now().millisecondsSinceEpoch}';
      await prefs.setString('dreamic_device_id', id);
    }
    _deviceId = id;
    return _deviceId!;
  }

  @override
  Future<String> getCurrentTimezone() async => _currentTimezone;

  @override
  Future<Either<RepositoryFailure, Unit>> registerDevice() async {
    if (!_isOnline || _hasBackendError) {
      _hasPendingPayload = true;
      return const Left(RepositoryFailure.networkError);
    }
    await simulateOnAuthenticated(_authService?.currentUid ?? '');
    return const Right(unit);
  }

  @override
  Future<Either<RepositoryFailure, bool>> updateTimezoneOrOffsetIfChanged() async {
    if (!_isOnline || _hasBackendError) {
      _hasPendingPayload = true;
      return const Left(RepositoryFailure.networkError);
    }

    final deviceId = await getDeviceId();
    final existingIndex = _devices.indexWhere((d) => d.deviceId == deviceId);

    if (existingIndex < 0) {
      return const Right(false);
    }

    final existing = _devices[existingIndex];
    final changed = existing.timezone != _currentTimezone ||
        existing.timezoneOffsetMinutes != _currentOffset;

    if (changed) {
      _devices[existingIndex] = existing.copyWith(
        timezone: _currentTimezone,
        timezoneOffsetMinutes: _currentOffset,
      );
    }

    return Right(changed);
  }

  @override
  Future<Either<RepositoryFailure, Unit>> touchDevice() async {
    if (!_isOnline || _hasBackendError) {
      return const Left(RepositoryFailure.networkError);
    }
    return const Right(unit);
  }

  @override
  Future<Either<RepositoryFailure, Unit>> persistFcmToken({
    required String? fcmToken,
  }) async {
    if (!_isOnline || _hasBackendError) {
      _pendingFcmToken = fcmToken;
      _hasPendingPayload = true;
      return const Left(RepositoryFailure.networkError);
    }

    final deviceId = await getDeviceId();
    final existingIndex = _devices.indexWhere((d) => d.deviceId == deviceId);

    if (existingIndex >= 0) {
      // Create new DeviceInfo with updated token
      // Note: copyWith can't set fcmToken to null, so we recreate the object
      final existing = _devices[existingIndex];
      _devices[existingIndex] = DeviceInfo(
        deviceId: existing.deviceId,
        timezone: existing.timezone,
        timezoneOffsetMinutes: existing.timezoneOffsetMinutes,
        lastActiveAt: existing.lastActiveAt,
        fcmToken: fcmToken, // Explicitly set, including null
        fcmTokenUpdatedAt: existing.fcmTokenUpdatedAt,
        createdAt: existing.createdAt,
        updatedAt: existing.updatedAt,
        platform: existing.platform,
        appVersion: existing.appVersion,
        deviceInfo: existing.deviceInfo,
      );
    } else {
      // Store for later registration
      _pendingFcmToken = fcmToken;
    }

    return const Right(unit);
  }

  @override
  Future<Either<RepositoryFailure, Unit>> unregisterDevice() async {
    if (!_isOnline || _hasBackendError) {
      _hasPendingPayload = true;
      return const Left(RepositoryFailure.networkError);
    }
    await simulateOnAboutToLogOut();
    return const Right(unit);
  }

  @override
  Future<Either<RepositoryFailure, List<DeviceInfo>>> getMyDevices() async {
    if (!_isOnline || _hasBackendError) {
      return const Left(RepositoryFailure.networkError);
    }
    return Right(_devices.toList());
  }

  @override
  Future<void> connectToAuthService({
    AuthServiceInt? authService,
    Future<void> Function(String? uid)? onAuthenticated,
    Future<void> Function()? onAboutToLogOut,
  }) async {
    if (authService is MockAuthService) {
      _authService = authService;
    }
  }

  // Phase 1 methods - required by DeviceServiceInt interface
  @override
  Future<void> handleAuthenticated(String? uid) async {
    await simulateOnAuthenticated(uid ?? '');
  }

  @override
  Future<void> handleAboutToLogOut() async {
    await simulateOnAboutToLogOut();
  }

  @override
  Future<void> initialize({required AuthServiceInt authService}) async {
    if (authService is MockAuthService) {
      _authService = authService;
    }
  }

  @override
  bool get isConnectedToAuth => _authService != null;
}

/// Mock implementation of AuthServiceInt for testing.
///
/// This minimal mock provides just enough functionality for DeviceService
/// integration tests. It uses `noSuchMethod` to provide default implementations
/// for all other interface methods.
class MockAuthService implements AuthServiceInt {
  String? currentUid;

  // We can't easily mock fb_auth.User, so we use the fact that
  // DeviceServiceImpl only checks if currentFbUser != null
  fb_auth.User? _mockUser;

  @override
  fb_auth.User? get currentFbUser => currentUid != null ? _mockUser : null;

  @override
  set currentFbUser(fb_auth.User? user) => _mockUser = user;

  @override
  fb_auth.UserCredential? currentFbUserCredentials;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
