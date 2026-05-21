import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dreamic/data/helpers/repository_failure.dart';
import 'package:dreamic/data/models/device_info.dart';
import 'package:dreamic/data/repos/auth_service_int.dart';
import 'package:dreamic/data/repos/device_service_int.dart';
import 'package:dreamic/data/repos/dreamic_services.dart';

/// Tests for [DreamicServices.defaultTokenChangedCallback].
///
/// This callback is the bridge between [NotificationService]'s FCM token
/// lifecycle and [DeviceServiceInt.persistFcmToken]. When
/// [DreamicServices.initialize] is called with both `enableDeviceService:
/// true` and `enableNotifications: true` and no explicit `onTokenChanged`,
/// it wires the returned callback into `notificationService.initialize`
/// so the silent FCM token capture path
/// (`NotificationService._handleLogin` when permission is already granted
/// and `fcmAutoInitialize` is false) actually persists the token to the
/// device document.
///
/// These tests verify the callback's delegation contract end-to-end:
/// invoking the callback with a token results in
/// [DeviceServiceInt.persistFcmToken] being called with the same token.
/// Failures and exceptions from persistence are absorbed — token sync
/// must not block other operations.
void main() {
  group('DreamicServices.defaultTokenChangedCallback', () {
    test('delegates non-null token to DeviceService.persistFcmToken',
        () async {
      final mockDevice = _RecordingDeviceService();
      final callback = DreamicServices.defaultTokenChangedCallback(mockDevice);

      await callback('new-fcm-token', null);

      expect(mockDevice.persistFcmTokenCalls, ['new-fcm-token']);
    });

    test('delegates null token (clear) to DeviceService.persistFcmToken',
        () async {
      final mockDevice = _RecordingDeviceService();
      final callback = DreamicServices.defaultTokenChangedCallback(mockDevice);

      await callback(null, 'old-fcm-token');

      expect(mockDevice.persistFcmTokenCalls, [null]);
    });

    test('passes token rotation through (old token ignored, new persisted)',
        () async {
      final mockDevice = _RecordingDeviceService();
      final callback = DreamicServices.defaultTokenChangedCallback(mockDevice);

      await callback('token-v2', 'token-v1');

      expect(mockDevice.persistFcmTokenCalls, ['token-v2']);
    });

    test('swallows exceptions thrown by persistFcmToken (does not rethrow)',
        () async {
      final mockDevice = _RecordingDeviceService(throwOnPersist: true);
      final callback = DreamicServices.defaultTokenChangedCallback(mockDevice);

      // Must not throw — token sync failures cannot block other operations.
      await callback('some-token', null);

      expect(mockDevice.persistFcmTokenCalls, ['some-token']);
    });

    test('handles Left(RepositoryFailure) without throwing', () async {
      final mockDevice = _RecordingDeviceService(
        persistResult: const Left(RepositoryFailure.networkError),
      );
      final callback = DreamicServices.defaultTokenChangedCallback(mockDevice);

      // Must not throw — DeviceService returning a Left is a soft failure.
      await callback('token', null);

      expect(mockDevice.persistFcmTokenCalls, ['token']);
    });
  });
}

/// Minimal DeviceServiceInt that records [persistFcmToken] invocations.
///
/// Only the fields/methods exercised by [DreamicServices.defaultTokenChangedCallback]
/// are implemented meaningfully — the rest throw if touched, which signals an
/// over-broad test.
class _RecordingDeviceService implements DeviceServiceInt {
  _RecordingDeviceService({
    this.throwOnPersist = false,
    this.persistResult = const Right(unit),
  });

  final bool throwOnPersist;
  final Either<RepositoryFailure, Unit> persistResult;

  final List<String?> persistFcmTokenCalls = [];

  @override
  Future<Either<RepositoryFailure, Unit>> persistFcmToken({
    required String? fcmToken,
  }) async {
    persistFcmTokenCalls.add(fcmToken);
    if (throwOnPersist) {
      throw StateError('simulated persistFcmToken failure');
    }
    return persistResult;
  }

  // ─── Unused interface members ─────────────────────────────────────────────

  @override
  Future<String> getDeviceId() async => throw UnimplementedError();

  @override
  Future<String> getCurrentTimezone() async => throw UnimplementedError();

  @override
  Future<Either<RepositoryFailure, Unit>> registerDevice() async =>
      throw UnimplementedError();

  @override
  Future<Either<RepositoryFailure, Unit>> unregisterDevice() async =>
      throw UnimplementedError();

  @override
  Future<Either<RepositoryFailure, Unit>> touchDevice() async =>
      throw UnimplementedError();

  @override
  Future<Either<RepositoryFailure, bool>>
      updateTimezoneOrOffsetIfChanged() async => throw UnimplementedError();

  @override
  Future<Either<RepositoryFailure, List<DeviceInfo>>> getMyDevices() async =>
      throw UnimplementedError();

  @override
  Future<void> connectToAuthService({
    AuthServiceInt? authService,
    Future<void> Function(String? uid)? onAuthenticated,
    Future<void> Function()? onAboutToLogOut,
  }) async => throw UnimplementedError();

  @override
  Future<void> handleAuthenticated(String? uid) async =>
      throw UnimplementedError();

  @override
  Future<void> handleAboutToLogOut() async => throw UnimplementedError();

  @override
  Future<void> initialize({required AuthServiceInt authService}) async =>
      throw UnimplementedError();

  @override
  bool get isConnectedToAuth => throw UnimplementedError();
}
