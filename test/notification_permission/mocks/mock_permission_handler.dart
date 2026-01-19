import 'package:dreamic/data/models/notification_permission_status.dart';

/// Mock permission handler for testing notification permission flows.
///
/// Allows tests to control the permission status and simulate various scenarios
/// like blocked requests, permanent denials, etc.
class MockPermissionHandler {
  NotificationPermissionStatus _status = NotificationPermissionStatus.notDetermined;
  bool _shouldShowRationale = false;
  bool _blockNextRequest = false;
  int _requestCount = 0;

  /// Sets the current permission status.
  void setStatus(NotificationPermissionStatus status) {
    _status = status;
  }

  /// Sets whether rationale should be shown (Android only).
  void setShouldShowRationale(bool value) {
    _shouldShowRationale = value;
  }

  /// Makes the next permission request appear blocked (no dialog shown).
  void blockNextRequest() {
    _blockNextRequest = true;
  }

  /// Returns the current permission status.
  Future<NotificationPermissionStatus> getStatus() async {
    return _status;
  }

  /// Simulates a permission request.
  ///
  /// If [blockNextRequest] was called, the status remains unchanged (simulating
  /// a blocked request). Otherwise, returns the current status.
  Future<NotificationPermissionStatus> request() async {
    _requestCount++;
    if (_blockNextRequest) {
      _blockNextRequest = false;
      return _status; // Status unchanged - request blocked
    }
    return _status;
  }

  /// Returns whether request rationale should be shown.
  bool shouldShowRequestRationale() {
    return _shouldShowRationale;
  }

  /// Returns the number of times [request] was called.
  int get requestCount => _requestCount;

  /// Resets the mock to initial state.
  void reset() {
    _status = NotificationPermissionStatus.notDetermined;
    _shouldShowRationale = false;
    _blockNextRequest = false;
    _requestCount = 0;
  }

  /// Simulates iOS denial behavior (always permanent after first denial).
  void simulateIosDenial() {
    _status = NotificationPermissionStatus.denied;
    _shouldShowRationale = false;
  }

  /// Simulates Android first denial (can still prompt again).
  void simulateAndroidFirstDenial() {
    _status = NotificationPermissionStatus.denied;
    _shouldShowRationale = true;
  }

  /// Simulates Android permanent denial (after second denial).
  void simulateAndroidPermanentDenial() {
    _status = NotificationPermissionStatus.denied;
    _shouldShowRationale = false;
  }

  /// Simulates permission being granted.
  void simulateGranted() {
    _status = NotificationPermissionStatus.authorized;
    _shouldShowRationale = false;
  }

  /// Simulates provisional permission (iOS).
  void simulateProvisional() {
    _status = NotificationPermissionStatus.provisional;
    _shouldShowRationale = false;
  }
}
