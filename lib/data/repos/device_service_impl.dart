import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../app/app_config_base.dart';
import '../../app/helpers/app_lifecycle_service.dart';
import '../../utils/get_it_utils.dart';
import '../../utils/logger.dart';
import '../helpers/repository_failure.dart';
import '../models/device_info.dart';
import '../models/device_platform.dart';
import 'auth_service_int.dart';
import 'device_service_int.dart';

/// SharedPreferences key for storing the device ID.
const String _kDeviceIdKey = 'dreamic_device_id';

/// SharedPreferences key for storing the pending payload.
const String _kPendingPayloadKey = 'dreamic_device_pending_payload';

/// Represents a pending device update payload that is persisted locally
/// and synced to the backend when connectivity is available.
///
/// This class implements the offline handling strategy described in the plan:
/// - Single merged payload (not a queue) with per-field last-write-wins
/// - Sticky `touch` flag (once true, stays true until successful flush)
/// - `fcmToken` can be null to represent explicit clearing
///
/// Used internally by [DeviceServiceImpl] to ensure eventual consistency
/// across flaky networks.
class _PendingDevicePayload {
  /// Required: The device ID this payload is for.
  final String deviceId;

  /// Optional: IANA timezone string to sync.
  final String? timezone;

  /// Optional: Timezone offset in minutes to sync.
  final int? timezoneOffsetMinutes;

  /// Optional: FCM token to sync. Use empty string sentinel to represent
  /// explicit null (clearing the token). Actual null means "don't update".
  ///
  /// Encoding:
  /// - `null` in this field = don't update fcmToken on server
  /// - empty string = explicitly set server fcmToken to null
  /// - non-empty string = set server fcmToken to this value
  final String? fcmToken;

  /// Whether to update lastActiveAt (touch the device).
  /// Sticky: once true, stays true until successful flush.
  final bool touch;

  /// Optional: Platform to include in registration.
  final String? platform;

  /// Optional: App version to include in registration.
  final String? appVersion;

  /// When this pending payload was last updated locally.
  final DateTime pendingUpdatedAt;

  /// When we last attempted to flush this payload (for backoff calculation).
  final DateTime? lastAttemptAt;

  /// Whether this payload was created due to a timezone/offset/token change
  /// (as opposed to just touch or initial registration).
  /// Used to determine if backoff should be bypassed.
  final bool hasChangedFields;

  const _PendingDevicePayload({
    required this.deviceId,
    this.timezone,
    this.timezoneOffsetMinutes,
    this.fcmToken,
    this.touch = false,
    this.platform,
    this.appVersion,
    required this.pendingUpdatedAt,
    this.lastAttemptAt,
    this.hasChangedFields = false,
  });

  /// Creates a payload from JSON data (for loading from storage).
  factory _PendingDevicePayload.fromJson(Map<String, dynamic> json) {
    return _PendingDevicePayload(
      deviceId: json['deviceId'] as String,
      timezone: json['timezone'] as String?,
      timezoneOffsetMinutes: json['timezoneOffsetMinutes'] as int?,
      fcmToken: json['fcmToken'] as String?,
      touch: json['touch'] as bool? ?? false,
      platform: json['platform'] as String?,
      appVersion: json['appVersion'] as String?,
      pendingUpdatedAt: json['pendingUpdatedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['pendingUpdatedAt'] as int)
          : DateTime.now(),
      lastAttemptAt: json['lastAttemptAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['lastAttemptAt'] as int)
          : null,
      hasChangedFields: json['hasChangedFields'] as bool? ?? false,
    );
  }

  /// Converts this payload to JSON for storage.
  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      if (timezone != null) 'timezone': timezone,
      if (timezoneOffsetMinutes != null) 'timezoneOffsetMinutes': timezoneOffsetMinutes,
      if (fcmToken != null) 'fcmToken': fcmToken,
      'touch': touch,
      if (platform != null) 'platform': platform,
      if (appVersion != null) 'appVersion': appVersion,
      'pendingUpdatedAt': pendingUpdatedAt.millisecondsSinceEpoch,
      if (lastAttemptAt != null) 'lastAttemptAt': lastAttemptAt!.millisecondsSinceEpoch,
      'hasChangedFields': hasChangedFields,
    };
  }

  /// Merges this payload with new values using per-field last-write-wins.
  ///
  /// - [touch] is sticky: once true, stays true until successful flush
  /// - [fcmToken] allows explicit null (empty string sentinel)
  /// - [hasChangedFields] is sticky if any changed fields are added
  _PendingDevicePayload merge({
    String? timezone,
    int? timezoneOffsetMinutes,
    String? fcmToken,
    bool touch = false,
    String? platform,
    String? appVersion,
    bool hasChangedFields = false,
  }) {
    return _PendingDevicePayload(
      deviceId: deviceId,
      timezone: timezone ?? this.timezone,
      timezoneOffsetMinutes: timezoneOffsetMinutes ?? this.timezoneOffsetMinutes,
      fcmToken: fcmToken ?? this.fcmToken,
      touch: this.touch || touch, // Sticky
      platform: platform ?? this.platform,
      appVersion: appVersion ?? this.appVersion,
      pendingUpdatedAt: DateTime.now(),
      lastAttemptAt: lastAttemptAt, // Preserved until flush attempt
      hasChangedFields: this.hasChangedFields || hasChangedFields, // Sticky
    );
  }

  /// Creates a copy with updated lastAttemptAt (called after flush attempt).
  _PendingDevicePayload withAttemptAt(DateTime attemptAt) {
    return _PendingDevicePayload(
      deviceId: deviceId,
      timezone: timezone,
      timezoneOffsetMinutes: timezoneOffsetMinutes,
      fcmToken: fcmToken,
      touch: touch,
      platform: platform,
      appVersion: appVersion,
      pendingUpdatedAt: pendingUpdatedAt,
      lastAttemptAt: attemptAt,
      hasChangedFields: hasChangedFields,
    );
  }

  /// Whether this payload has any data worth syncing.
  bool get hasDataToSync {
    return timezone != null ||
        timezoneOffsetMinutes != null ||
        fcmToken != null ||
        touch ||
        platform != null ||
        appVersion != null;
  }

  /// Whether the backoff should be applied before attempting flush.
  ///
  /// Backoff is enforced when:
  /// - There was a previous attempt
  /// - The time since last attempt is less than backoff interval
  /// - AND no changed fields require immediate sync (timezone/offset/token)
  bool shouldBackoff(int backoffMinutes) {
    if (lastAttemptAt == null) {
      return false; // No previous attempt, don't backoff
    }

    final timeSinceAttempt = DateTime.now().difference(lastAttemptAt!);
    final withinBackoff = timeSinceAttempt < Duration(minutes: backoffMinutes);

    // Bypass backoff if we have changed fields that need prompt sync
    if (hasChangedFields) {
      return false;
    }

    return withinBackoff;
  }

  @override
  String toString() {
    return '_PendingDevicePayload{'
        'deviceId: $deviceId, '
        'timezone: $timezone, '
        'offset: $timezoneOffsetMinutes, '
        'touch: $touch, '
        'hasToken: ${fcmToken != null}, '
        'hasChangedFields: $hasChangedFields'
        '}';
  }
}

/// Implementation of [DeviceServiceInt] for device registration and timezone tracking.
///
/// This implementation provides production-ready device tracking with:
/// - **Device Identity**: Generates and persists a UUIDv4 per app install
/// - **Timezone Tracking**: Syncs IANA timezone and offset with DST awareness
/// - **Activity Tracking**: Updates `lastActiveAt` on app resume (throttled)
/// - **Offline Resilience**: Pending payload system for eventual consistency
/// - **Lifecycle Integration**: Automatic auth and app lifecycle wiring
///
/// ## Quick Start
///
/// ```dart
/// // 1. Create and register the service
/// final deviceService = DeviceServiceImpl();
/// GetIt.instance.registerSingleton<DeviceServiceInt>(deviceService);
///
/// // 2. Connect to auth service (enables automatic lifecycle management)
/// await deviceService.connectToAuthService();
///
/// // That's it! Device registration, timezone updates, and activity
/// // tracking are now automatic based on auth and app lifecycle events.
/// ```
///
/// ## Integration with NotificationService
///
/// For apps using push notifications, NotificationService auto-detects
/// DeviceService in GetIt and forwards token changes:
///
/// ```dart
/// await deviceService.connectToAuthService();
/// await notificationService.connectToAuthService(); // Auto-forwards tokens
/// ```
///
/// ## Internal State Management
///
/// The service maintains several pieces of in-memory state:
/// - `_deviceId`: Cached device ID (loaded from SharedPreferences)
/// - `_cachedTimezone`: Last synced timezone (for change detection)
/// - `_cachedOffsetMinutes`: Last synced offset (for DST detection)
/// - `_lastServerSyncAt`: Timestamp of last successful timezone sync
/// - `_lastTouchAt`: Timestamp of last successful touch operation
/// - `_pendingPayload`: Pending updates awaiting sync (offline resilience)
///
/// ## Offline Handling
///
/// When backend calls fail (network errors, server issues), updates are
/// stored in a [_PendingDevicePayload] that persists to SharedPreferences:
///
/// - **Merge semantics**: Per-field last-write-wins
/// - **Sticky flags**: `touch` stays true until successful flush
/// - **Backoff**: 15 minutes between retry attempts (bypassed for changes)
/// - **Auto-flush**: Pending data is flushed on auth events and app resume
///
/// ## Throttling Configuration
///
/// All throttle values can be configured via [AppConfigBase] or Remote Config:
/// - Timezone unchanged: 48 hours (avoids resume spam)
/// - Timezone changed: 10 min debounce (prevents flapping)
/// - Touch throttle: 60 minutes (limits activity updates)
/// - Pending backoff: 15 minutes (retry interval)
///
/// ## Thread Safety
///
/// The service is designed for single-isolate use (main isolate). Concurrent
/// calls are handled via:
/// - `_isFlushingPayload` flag prevents concurrent pending payload flushes
/// - Callback idempotency in `connectToAuthService()`
///
/// ## Backend Requirements
///
/// This implementation requires the Firebase Functions scaffolding deployed
/// to your project. The callable function name is configured via
/// [AppConfigBase.deviceActionFunction] (default: `"deviceAction"`).
///
/// See `scaffolding/firebase_functions/device/README.md` for setup.
///
/// ## See Also
///
/// - [DeviceServiceInt] for the interface contract and method documentation
/// - [DeviceInfo] for the device document model
/// - [_PendingDevicePayload] for offline handling internals
class DeviceServiceImpl implements DeviceServiceInt {
  /// UUID generator for device IDs.
  static const Uuid _uuid = Uuid();

  /// Cached device ID (loaded from SharedPreferences on first access).
  String? _deviceId;

  /// Cached timezone string from last successful sync.
  String? _cachedTimezone;

  /// Cached timezone offset in minutes from last successful sync.
  int? _cachedOffsetMinutes;

  /// Timestamp of last successful server sync for timezone/offset.
  DateTime? _lastServerSyncAt;

  /// Timestamp of last successful touch operation.
  DateTime? _lastTouchAt;

  /// Registered authenticated callback for cleanup during disconnect.
  Future<void> Function(String? uid)? _registeredOnAuthenticatedCallback;

  /// Registered about-to-logout callback for cleanup during disconnect.
  Future<void> Function()? _registeredOnAboutToLogOutCallback;

  /// Reference to the auth service (set via connectToAuthService).
  AuthServiceInt? _authService;

  /// Whether the service has been connected to auth service.
  bool _isConnectedToAuthService = false;

  /// Subscription to app lifecycle events for timezone/touch updates on resume.
  StreamSubscription<AppLifecycleState>? _lifecycleSubscription;

  /// Whether lifecycle integration is active.
  bool _isLifecycleConnected = false;

  /// In-memory pending payload for offline handling.
  /// This is synced to persistent storage on changes.
  _PendingDevicePayload? _pendingPayload;

  /// Whether there's a flush operation currently in progress.
  /// Used to prevent concurrent flushes.
  bool _isFlushingPayload = false;

  /// Firebase callable for device operations.
  HttpsCallable get _deviceCallable =>
      AppConfigBase.firebaseFunctionCallable(AppConfigBase.deviceActionFunction);

  /// Creates a new [DeviceServiceImpl] instance.
  ///
  /// The service is not connected to auth service by default.
  /// Call [connectToAuthService] to enable automatic lifecycle management.
  DeviceServiceImpl();

  // ============================================================
  // Pending Payload Persistence (Phase 5)
  // ============================================================

  /// Loads the pending payload from persistent storage.
  ///
  /// Returns null if no pending payload exists or if loading fails.
  /// On web, falls back gracefully if storage is unavailable.
  Future<_PendingDevicePayload?> _loadPendingPayload() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_kPendingPayloadKey);

      if (jsonString == null || jsonString.isEmpty) {
        return null;
      }

      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      final payload = _PendingDevicePayload.fromJson(json);

      logd('DeviceService: Loaded pending payload: $payload');
      return payload;
    } catch (e) {
      logw('DeviceService: Failed to load pending payload: $e');
      return null;
    }
  }

  /// Saves the pending payload to persistent storage.
  ///
  /// On web, this is best-effort; storage may be unavailable or blocked.
  /// Returns true if save succeeded, false otherwise.
  Future<bool> _savePendingPayload(_PendingDevicePayload? payload) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (payload == null) {
        // Clear the pending payload
        final removed = await prefs.remove(_kPendingPayloadKey);
        logd('DeviceService: Cleared pending payload');
        return removed;
      }

      final jsonString = jsonEncode(payload.toJson());
      final saved = await prefs.setString(_kPendingPayloadKey, jsonString);

      if (saved) {
        logd('DeviceService: Saved pending payload: $payload');
      } else {
        logw('DeviceService: Failed to save pending payload to SharedPreferences');
      }

      return saved;
    } catch (e) {
      logw('DeviceService: Error saving pending payload: $e');
      return false;
    }
  }

  /// Ensures the pending payload is loaded into memory.
  ///
  /// Call this at the start of operations that need to merge with or
  /// check the pending payload state.
  Future<void> _ensurePendingPayloadLoaded() async {
    _pendingPayload ??= await _loadPendingPayload();
  }

  /// Updates the pending payload with new data using merge semantics.
  ///
  /// - Per-field last-write-wins
  /// - [touch] is sticky (once true, stays true until flush)
  /// - [hasChangedFields] is sticky
  ///
  /// Persists the updated payload to storage.
  Future<void> _updatePendingPayload({
    required String deviceId,
    String? timezone,
    int? timezoneOffsetMinutes,
    String? fcmToken,
    bool touch = false,
    String? platform,
    String? appVersion,
    bool hasChangedFields = false,
  }) async {
    await _ensurePendingPayloadLoaded();

    if (_pendingPayload == null) {
      // Create new payload
      _pendingPayload = _PendingDevicePayload(
        deviceId: deviceId,
        timezone: timezone,
        timezoneOffsetMinutes: timezoneOffsetMinutes,
        fcmToken: fcmToken,
        touch: touch,
        platform: platform,
        appVersion: appVersion,
        pendingUpdatedAt: DateTime.now(),
        hasChangedFields: hasChangedFields,
      );
    } else {
      // Merge with existing payload
      _pendingPayload = _pendingPayload!.merge(
        timezone: timezone,
        timezoneOffsetMinutes: timezoneOffsetMinutes,
        fcmToken: fcmToken,
        touch: touch,
        platform: platform,
        appVersion: appVersion,
        hasChangedFields: hasChangedFields,
      );
    }

    // Persist to storage
    await _savePendingPayload(_pendingPayload);
  }

  /// Clears the pending payload from memory and storage.
  ///
  /// Called after successful backend sync to indicate no pending data.
  Future<void> _clearPendingPayload() async {
    _pendingPayload = null;
    await _savePendingPayload(null);
    logd('DeviceService: Pending payload cleared after successful sync');
  }

  /// Attempts to flush the pending payload to the backend.
  ///
  /// This method:
  /// 1. Checks if there's a pending payload with data to sync
  /// 2. Applies backoff logic (unless changed fields bypass it)
  /// 3. Calls the backend with appropriate action
  /// 4. Clears pending payload on success, updates lastAttemptAt on failure
  ///
  /// Returns true if sync succeeded or no sync was needed, false on error.
  ///
  /// [bypassBackoff] forces immediate sync regardless of backoff (use for
  /// explicit user actions or important changes).
  Future<bool> _flushPendingPayload({bool bypassBackoff = false}) async {
    // Prevent concurrent flushes
    if (_isFlushingPayload) {
      logd('DeviceService: Flush already in progress, skipping');
      return true;
    }

    await _ensurePendingPayloadLoaded();

    if (_pendingPayload == null || !_pendingPayload!.hasDataToSync) {
      logd('DeviceService: No pending payload to flush');
      return true;
    }

    // Check backoff unless bypassed
    if (!bypassBackoff) {
      final backoffMinutes = AppConfigBase.devicePendingBackoffMinutes;
      if (_pendingPayload!.shouldBackoff(backoffMinutes)) {
        logd('DeviceService: Flush backoff active, skipping (last attempt: ${_pendingPayload!.lastAttemptAt})');
        return true; // Not an error, just throttled
      }
    }

    _isFlushingPayload = true;

    try {
      logd('DeviceService: Flushing pending payload: $_pendingPayload');

      final payload = _pendingPayload!;

      // Determine the action based on what data we have
      // If we have timezone/platform/appVersion, use 'register' action
      // Otherwise, use the most specific action for the data we have
      String action;
      final Map<String, dynamic> callData = {
        'deviceId': payload.deviceId,
      };

      if (payload.timezone != null && payload.platform != null) {
        // Full registration data available
        action = 'register';
        callData['timezone'] = payload.timezone;
        callData['timezoneOffsetMinutes'] = payload.timezoneOffsetMinutes;
        callData['platform'] = payload.platform;
        callData['appVersion'] = payload.appVersion;

        // Include token if available
        if (payload.fcmToken != null) {
          // Empty string sentinel means explicit null
          callData['fcmToken'] = payload.fcmToken!.isEmpty ? null : payload.fcmToken;
        }
      } else if (payload.fcmToken != null) {
        // Token update only
        action = 'updateToken';
        // Empty string sentinel means explicit null
        callData['fcmToken'] = payload.fcmToken!.isEmpty ? null : payload.fcmToken;
      } else if (payload.touch) {
        // Touch only
        action = 'touch';
      } else {
        // Nothing to sync after all
        logd('DeviceService: Pending payload has no actionable data');
        await _clearPendingPayload();
        return true;
      }

      callData['action'] = action;

      final result = await _deviceCallable.call(callData);
      final data = Map<String, dynamic>.from(result.data as Map);

      if (data['success'] == true) {
        logd('DeviceService: Pending payload flushed successfully with action: $action');

        // Update cache based on what was synced
        if (payload.timezone != null) {
          _cachedTimezone = payload.timezone;
          _cachedOffsetMinutes = payload.timezoneOffsetMinutes;
          _lastServerSyncAt = DateTime.now();
        }
        if (payload.touch || action == 'register') {
          _lastTouchAt = DateTime.now();
        }

        // Clear the pending payload
        await _clearPendingPayload();
        return true;
      } else {
        logw('DeviceService: Pending payload flush failed: ${data['error'] ?? 'unknown error'}');
        // Update attempt timestamp for backoff
        _pendingPayload = _pendingPayload!.withAttemptAt(DateTime.now());
        await _savePendingPayload(_pendingPayload);
        return false;
      }
    } on FirebaseFunctionsException catch (e) {
      loge(e, 'DeviceService: Firebase error during pending payload flush');
      // Update attempt timestamp for backoff
      _pendingPayload = _pendingPayload!.withAttemptAt(DateTime.now());
      await _savePendingPayload(_pendingPayload);
      return false;
    } catch (e) {
      loge(e, 'DeviceService: Unexpected error during pending payload flush');
      // Update attempt timestamp for backoff
      _pendingPayload = _pendingPayload!.withAttemptAt(DateTime.now());
      await _savePendingPayload(_pendingPayload);
      return false;
    } finally {
      _isFlushingPayload = false;
    }
  }

  /// Checks if the user is currently authenticated.
  ///
  /// Returns true if:
  /// - We're connected to auth service AND
  /// - The auth service reports a current user
  ///
  /// This is used to determine if backend calls should be attempted
  /// or if data should be stored in the pending payload.
  bool _isUserAuthenticated() {
    if (!_isConnectedToAuthService || _authService == null) {
      return false;
    }
    return _authService!.currentFbUser != null;
  }

  // ============================================================
  // Core Service Implementation
  // ============================================================

  @override
  Future<String> getDeviceId() async {
    // Return cached value if available
    if (_deviceId != null) {
      return _deviceId!;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final storedId = prefs.getString(_kDeviceIdKey);

      if (storedId != null && storedId.isNotEmpty) {
        _deviceId = storedId;
        logd('DeviceService: Loaded existing device ID: $_deviceId');
        return _deviceId!;
      }

      // Generate new UUID
      _deviceId = _uuid.v4();
      logd('DeviceService: Generated new device ID: $_deviceId');

      // Persist the new ID
      final saved = await prefs.setString(_kDeviceIdKey, _deviceId!);
      if (!saved) {
        logw('DeviceService: Failed to persist device ID to SharedPreferences');
      }

      return _deviceId!;
    } catch (e) {
      // Fallback: generate ephemeral ID if storage fails (e.g., web with blocked storage)
      logw('DeviceService: Storage unavailable, using ephemeral device ID: $e');
      _deviceId ??= _uuid.v4();
      return _deviceId!;
    }
  }

  @override
  Future<String> getCurrentTimezone() async {
    try {
      final timezoneInfo = await FlutterTimezone.getLocalTimezone();
      return timezoneInfo.identifier;
    } catch (e) {
      loge(e, 'DeviceService: Failed to get timezone');
      // Return UTC as fallback - this is a safe default
      return 'UTC';
    }
  }

  /// Gets the current timezone offset in minutes.
  ///
  /// This uses [DateTime.now().timeZoneOffset] which correctly handles
  /// DST transitions and half-hour/45-minute offsets.
  int _getCurrentOffsetMinutes() {
    return DateTime.now().timeZoneOffset.inMinutes;
  }

  /// Gets the current device platform.
  DevicePlatform _getCurrentPlatform() {
    if (kIsWeb) {
      return DevicePlatform.web;
    }
    if (Platform.isIOS) {
      return DevicePlatform.ios;
    }
    if (Platform.isAndroid) {
      return DevicePlatform.android;
    }
    if (Platform.isMacOS) {
      return DevicePlatform.macos;
    }
    if (Platform.isWindows) {
      return DevicePlatform.windows;
    }
    if (Platform.isLinux) {
      return DevicePlatform.linux;
    }
    // Fallback - should never reach here
    return DevicePlatform.web;
  }

  @override
  Future<Either<RepositoryFailure, Unit>> registerDevice() async {
    logd('DeviceService: registerDevice called');

    try {
      final deviceId = await getDeviceId();
      final timezone = await getCurrentTimezone();
      final offsetMinutes = _getCurrentOffsetMinutes();
      final platform = _getCurrentPlatform();
      final platformString = DevicePlatformSerialization.serialize(platform);
      final packageInfo = await PackageInfo.fromPlatform();

      // Check authentication - if not authenticated, store pending and return
      if (!_isUserAuthenticated()) {
        logd('DeviceService: User not authenticated, storing pending registration');
        await _updatePendingPayload(
          deviceId: deviceId,
          timezone: timezone,
          timezoneOffsetMinutes: offsetMinutes,
          platform: platformString,
          appVersion: packageInfo.version,
          touch: true,
          hasChangedFields: true,
        );
        // Return success since we've stored it for later - this is best-effort
        return const Right(unit);
      }

      logd('DeviceService: Registering device $deviceId with timezone $timezone');

      // First, try to flush any existing pending payload
      // This ensures we don't lose pending changes when registering
      await _flushPendingPayload();

      final result = await _deviceCallable.call({
        'action': 'register',
        'deviceId': deviceId,
        'timezone': timezone,
        'timezoneOffsetMinutes': offsetMinutes,
        'platform': platformString,
        'appVersion': packageInfo.version,
      });

      // Check for success
      final data = Map<String, dynamic>.from(result.data as Map);
      if (data['success'] != true) {
        logw('DeviceService: Registration response indicated failure');
        // Store in pending payload for retry
        await _updatePendingPayload(
          deviceId: deviceId,
          timezone: timezone,
          timezoneOffsetMinutes: offsetMinutes,
          platform: platformString,
          appVersion: packageInfo.version,
          touch: true,
          hasChangedFields: true,
        );
        return const Left(RepositoryFailure.unexpected);
      }

      // Update cached values on success
      _cachedTimezone = timezone;
      _cachedOffsetMinutes = offsetMinutes;
      _lastServerSyncAt = DateTime.now();
      _lastTouchAt = DateTime.now(); // registerDevice also updates lastActiveAt

      // Clear any pending payload since we just synced
      await _clearPendingPayload();

      // Log if timezone changed
      if (data['timezoneChanged'] == true) {
        logd('DeviceService: Timezone changed from ${data['previousTimezone']} to $timezone');
      }

      logd('DeviceService: Device registered successfully');
      return const Right(unit);
    } on FirebaseFunctionsException catch (e) {
      loge(e, 'DeviceService: Firebase Functions error during registration');

      // Store in pending payload for retry on network/transient errors
      if (_shouldStorePendingOnError(e)) {
        await _storePendingRegistration();
      }

      return _mapFirebaseFunctionsException(e);
    } catch (e) {
      loge(e, 'DeviceService: Unexpected error during registration');

      // Store in pending payload for retry
      await _storePendingRegistration();

      return const Left(RepositoryFailure.unexpected);
    }
  }

  /// Stores the current device state as a pending registration.
  ///
  /// Helper method used when registration fails to ensure eventual sync.
  Future<void> _storePendingRegistration() async {
    try {
      final deviceId = await getDeviceId();
      final timezone = await getCurrentTimezone();
      final offsetMinutes = _getCurrentOffsetMinutes();
      final platform = _getCurrentPlatform();
      final platformString = DevicePlatformSerialization.serialize(platform);
      final packageInfo = await PackageInfo.fromPlatform();

      await _updatePendingPayload(
        deviceId: deviceId,
        timezone: timezone,
        timezoneOffsetMinutes: offsetMinutes,
        platform: platformString,
        appVersion: packageInfo.version,
        touch: true,
        hasChangedFields: true,
      );
    } catch (e) {
      logw('DeviceService: Failed to store pending registration: $e');
    }
  }

  /// Determines if a Firebase Functions error should trigger pending storage.
  ///
  /// Returns true for transient/network errors that may succeed on retry.
  /// Returns false for permanent errors (auth, permission) that won't benefit
  /// from retry without user action.
  bool _shouldStorePendingOnError(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'unavailable':
      case 'deadline-exceeded':
      case 'internal':
      case 'unknown':
      case 'resource-exhausted':
        return true; // Transient errors - store for retry
      case 'unauthenticated':
      case 'permission-denied':
      case 'invalid-argument':
      case 'not-found':
      case 'already-exists':
      case 'failed-precondition':
      case 'aborted':
      case 'out-of-range':
      case 'unimplemented':
      case 'cancelled':
      case 'data-loss':
        return false; // Permanent or user-actionable errors
      default:
        return true; // Default to storing for unknown errors
    }
  }

  @override
  Future<Either<RepositoryFailure, bool>> updateTimezoneOrOffsetIfChanged() async {
    logd('DeviceService: updateTimezoneOrOffsetIfChanged called');

    try {
      // Fast local checks (no network)
      final currentTimezone = await getCurrentTimezone();
      final currentOffsetMinutes = _getCurrentOffsetMinutes();
      final now = DateTime.now();

      // Check if values actually changed
      final timezoneChanged = _cachedTimezone != currentTimezone;
      final offsetChanged = _cachedOffsetMinutes != currentOffsetMinutes;
      final didChange = timezoneChanged || offsetChanged;

      // Get throttle configuration
      final changeDebounceMinutes = AppConfigBase.deviceTimezoneChangeDebounceMinutes;
      final unchangedSyncMinMinutes = AppConfigBase.deviceTimezoneUnchangedSyncMinMinutes;
      final unchangedSyncMaxMinutes = AppConfigBase.deviceTimezoneUnchangedSyncMaxMinutes;

      // Clamp max to be at least min (defensive against misconfiguration)
      final effectiveMax = unchangedSyncMaxMinutes < unchangedSyncMinMinutes
          ? unchangedSyncMinMinutes
          : unchangedSyncMaxMinutes;

      // Check throttle conditions
      final withinChangeDebounce = _lastServerSyncAt != null &&
          now.difference(_lastServerSyncAt!) < Duration(minutes: changeDebounceMinutes);

      final recentlySyncedUnchanged = _lastServerSyncAt != null &&
          now.difference(_lastServerSyncAt!) < Duration(minutes: unchangedSyncMinMinutes);

      // Safety net: Force sync if max interval exceeded, even if within min interval.
      // In normal operation this never triggers (min < max means recentlySyncedUnchanged
      // is already false when we'd exceed max), but provides self-healing if
      // _lastServerSyncAt becomes stale due to bugs or unexpected state.
      final exceededMaxInterval = _lastServerSyncAt != null &&
          now.difference(_lastServerSyncAt!) >= Duration(minutes: effectiveMax);

      // Apply throttling logic
      if (didChange && withinChangeDebounce) {
        logd(
            'DeviceService: Timezone/offset changed but within debounce window, skipping sync');
        return const Right(false);
      }

      if (!didChange && recentlySyncedUnchanged && !exceededMaxInterval) {
        logd(
            'DeviceService: Timezone/offset unchanged and recently synced, skipping sync');
        // Try to flush any pending payload on this lifecycle event (if authenticated)
        if (_isUserAuthenticated()) {
          await _flushPendingPayload();
        }
        return const Right(false);
      }

      // Check authentication - if not authenticated, store pending and return
      if (!_isUserAuthenticated()) {
        logd('DeviceService: User not authenticated, storing pending timezone update');
        final deviceId = await getDeviceId();
        final platform = _getCurrentPlatform();
        final platformString = DevicePlatformSerialization.serialize(platform);
        final packageInfo = await PackageInfo.fromPlatform();

        await _updatePendingPayload(
          deviceId: deviceId,
          timezone: currentTimezone,
          timezoneOffsetMinutes: currentOffsetMinutes,
          platform: platformString,
          appVersion: packageInfo.version,
          touch: true,
          hasChangedFields: didChange,
        );
        // Return false since no server sync occurred - but data is saved
        return const Right(false);
      }

      // Log when max interval forces a sync (self-healing scenario)
      if (!didChange && exceededMaxInterval) {
        logd(
            'DeviceService: Forcing sync due to max interval ceiling ($effectiveMax min)');
      }

      // Perform server sync
      logd(
          'DeviceService: Syncing timezone/offset - changed: $didChange, timezone: $currentTimezone, offset: $currentOffsetMinutes');

      final deviceId = await getDeviceId();
      final platform = _getCurrentPlatform();
      final platformString = DevicePlatformSerialization.serialize(platform);
      final packageInfo = await PackageInfo.fromPlatform();

      final result = await _deviceCallable.call({
        'action': 'register', // Use register action which handles updates
        'deviceId': deviceId,
        'timezone': currentTimezone,
        'timezoneOffsetMinutes': currentOffsetMinutes,
        'platform': platformString,
        'appVersion': packageInfo.version,
      });

      final data = Map<String, dynamic>.from(result.data as Map);
      if (data['success'] != true) {
        logw('DeviceService: Timezone sync response indicated failure');
        // Store in pending payload for retry
        await _updatePendingPayload(
          deviceId: deviceId,
          timezone: currentTimezone,
          timezoneOffsetMinutes: currentOffsetMinutes,
          platform: platformString,
          appVersion: packageInfo.version,
          touch: true,
          hasChangedFields: didChange,
        );
        return const Left(RepositoryFailure.unexpected);
      }

      // Update cached values on success
      _cachedTimezone = currentTimezone;
      _cachedOffsetMinutes = currentOffsetMinutes;
      _lastServerSyncAt = now;
      _lastTouchAt = now; // register also updates lastActiveAt

      // Clear any pending payload since we just synced
      await _clearPendingPayload();

      logd('DeviceService: Timezone/offset sync completed successfully');
      return const Right(true);
    } on FirebaseFunctionsException catch (e) {
      loge(e, 'DeviceService: Firebase Functions error during timezone sync');

      // Store in pending payload for retry on transient errors
      if (_shouldStorePendingOnError(e)) {
        await _storePendingTimezoneUpdate();
      }

      return _mapFirebaseFunctionsException(e);
    } catch (e) {
      loge(e, 'DeviceService: Unexpected error during timezone sync');

      // Store in pending payload for retry
      await _storePendingTimezoneUpdate();

      return const Left(RepositoryFailure.unexpected);
    }
  }

  /// Stores the current timezone/offset as a pending update.
  Future<void> _storePendingTimezoneUpdate() async {
    try {
      final deviceId = await getDeviceId();
      final timezone = await getCurrentTimezone();
      final offsetMinutes = _getCurrentOffsetMinutes();
      final platform = _getCurrentPlatform();
      final platformString = DevicePlatformSerialization.serialize(platform);
      final packageInfo = await PackageInfo.fromPlatform();

      // Check if this is a change from cached values
      final hasChangedFields =
          _cachedTimezone != timezone || _cachedOffsetMinutes != offsetMinutes;

      await _updatePendingPayload(
        deviceId: deviceId,
        timezone: timezone,
        timezoneOffsetMinutes: offsetMinutes,
        platform: platformString,
        appVersion: packageInfo.version,
        touch: true,
        hasChangedFields: hasChangedFields,
      );
    } catch (e) {
      logw('DeviceService: Failed to store pending timezone update: $e');
    }
  }

  @override
  Future<Either<RepositoryFailure, Unit>> touchDevice() async {
    logd('DeviceService: touchDevice called');

    try {
      final now = DateTime.now();
      final throttleMinutes = AppConfigBase.deviceTouchThrottleMinutes;

      // Apply throttle
      if (_lastTouchAt != null &&
          now.difference(_lastTouchAt!) < Duration(minutes: throttleMinutes)) {
        logd('DeviceService: Touch throttled, last touch was ${now.difference(_lastTouchAt!).inMinutes} minutes ago');
        // Try to flush any pending payload on this lifecycle event (if authenticated)
        if (_isUserAuthenticated()) {
          await _flushPendingPayload();
        }
        return const Right(unit);
      }

      final deviceId = await getDeviceId();

      // Check authentication - if not authenticated, store pending and return
      if (!_isUserAuthenticated()) {
        logd('DeviceService: User not authenticated, storing pending touch');
        await _updatePendingPayload(
          deviceId: deviceId,
          touch: true,
        );
        // Return success since we've stored it for later
        return const Right(unit);
      }

      logd('DeviceService: Touching device $deviceId');

      final result = await _deviceCallable.call({
        'action': 'touch',
        'deviceId': deviceId,
      });

      final data = Map<String, dynamic>.from(result.data as Map);
      if (data['success'] != true) {
        logw('DeviceService: Touch response indicated failure');
        // Store touch in pending payload for retry
        await _updatePendingPayload(
          deviceId: deviceId,
          touch: true,
        );
        return const Left(RepositoryFailure.unexpected);
      }

      _lastTouchAt = now;

      // Try to flush any other pending data now that we have connectivity
      await _flushPendingPayload();

      logd('DeviceService: Device touched successfully');
      return const Right(unit);
    } on FirebaseFunctionsException catch (e) {
      loge(e, 'DeviceService: Firebase Functions error during touch');

      // Store touch in pending payload for retry on transient errors
      if (_shouldStorePendingOnError(e)) {
        final deviceId = await getDeviceId();
        await _updatePendingPayload(
          deviceId: deviceId,
          touch: true,
        );
      }

      return _mapFirebaseFunctionsException(e);
    } catch (e) {
      loge(e, 'DeviceService: Unexpected error during touch');

      // Store touch in pending payload for retry
      final deviceId = await getDeviceId();
      await _updatePendingPayload(
        deviceId: deviceId,
        touch: true,
      );

      return const Left(RepositoryFailure.unexpected);
    }
  }

  @override
  Future<Either<RepositoryFailure, Unit>> persistFcmToken({
    required String? fcmToken,
  }) async {
    logd('DeviceService: persistFcmToken called with token: ${fcmToken != null ? '***' : 'null'}');

    try {
      final deviceId = await getDeviceId();

      // Check authentication - if not authenticated, store pending and return
      if (!_isUserAuthenticated()) {
        logd('DeviceService: User not authenticated, storing pending token update');
        await _updatePendingPayload(
          deviceId: deviceId,
          fcmToken: fcmToken ?? '', // Empty string = explicit null
          hasChangedFields: true,
        );
        // Return success since we've stored it for later
        return const Right(unit);
      }

      final result = await _deviceCallable.call({
        'action': 'updateToken',
        'deviceId': deviceId,
        'fcmToken': fcmToken,
      });

      final data = Map<String, dynamic>.from(result.data as Map);
      if (data['success'] != true) {
        logw('DeviceService: persistFcmToken response indicated failure');
        // Store token update in pending payload
        // Use empty string as sentinel for explicit null
        await _updatePendingPayload(
          deviceId: deviceId,
          fcmToken: fcmToken ?? '', // Empty string = explicit null
          hasChangedFields: true,
        );
        return const Left(RepositoryFailure.unexpected);
      }

      // Clear any pending token update since we just synced
      // Note: We don't clear the entire pending payload, just mark that
      // token updates don't need to be re-sent. However, since our merge
      // is last-write-wins, a successful sync here is good enough - the
      // next flush will use the most recent token value anyway.

      logd('DeviceService: FCM token updated successfully');
      return const Right(unit);
    } on FirebaseFunctionsException catch (e) {
      loge(e, 'DeviceService: Firebase Functions error during token update');

      // Store token update in pending payload for retry on transient errors
      if (_shouldStorePendingOnError(e)) {
        final deviceId = await getDeviceId();
        await _updatePendingPayload(
          deviceId: deviceId,
          fcmToken: fcmToken ?? '', // Empty string = explicit null
          hasChangedFields: true,
        );
      }

      return _mapFirebaseFunctionsException(e);
    } catch (e) {
      loge(e, 'DeviceService: Unexpected error during token update');

      // Store token update in pending payload for retry
      final deviceId = await getDeviceId();
      await _updatePendingPayload(
        deviceId: deviceId,
        fcmToken: fcmToken ?? '', // Empty string = explicit null
        hasChangedFields: true,
      );

      return const Left(RepositoryFailure.unexpected);
    }
  }

  @override
  Future<Either<RepositoryFailure, Unit>> unregisterDevice() async {
    logd('DeviceService: unregisterDevice called');

    try {
      final deviceId = await getDeviceId();

      logd('DeviceService: Unregistering device $deviceId');

      final result = await _deviceCallable.call({
        'action': 'unregister',
        'deviceId': deviceId,
      });

      final data = Map<String, dynamic>.from(result.data as Map);
      if (data['success'] != true) {
        logw('DeviceService: Unregister response indicated failure');
        return const Left(RepositoryFailure.unexpected);
      }

      logd('DeviceService: Device unregistered successfully');
      return const Right(unit);
    } on FirebaseFunctionsException catch (e) {
      loge(e, 'DeviceService: Firebase Functions error during unregistration');
      return _mapFirebaseFunctionsException(e);
    } catch (e) {
      loge(e, 'DeviceService: Unexpected error during unregistration');
      return const Left(RepositoryFailure.unexpected);
    }
  }

  @override
  Future<Either<RepositoryFailure, List<DeviceInfo>>> getMyDevices() async {
    logd('DeviceService: getMyDevices called');

    try {
      final deviceId = await getDeviceId();

      final result = await _deviceCallable.call({
        'action': 'getMyDevices',
        'deviceId': deviceId, // Required for callable validation
      });

      final data = Map<String, dynamic>.from(result.data as Map);
      if (data['success'] != true) {
        logw('DeviceService: getMyDevices response indicated failure');
        return const Left(RepositoryFailure.unexpected);
      }

      final devicesData = data['devices'] as List<dynamic>? ?? [];
      final devices = devicesData.map((deviceData) {
        final deviceMap = Map<String, dynamic>.from(deviceData as Map);
        // The server returns 'id' as the document ID, map it to deviceId
        if (deviceMap.containsKey('id') && !deviceMap.containsKey('deviceId')) {
          deviceMap['deviceId'] = deviceMap['id'];
        }
        return DeviceInfo.fromJson(deviceMap);
      }).toList();

      logd('DeviceService: Retrieved ${devices.length} devices');
      return Right(devices);
    } on FirebaseFunctionsException catch (e) {
      loge(e, 'DeviceService: Firebase Functions error during getMyDevices');
      return _mapFirebaseFunctionsException(e);
    } catch (e) {
      loge(e, 'DeviceService: Unexpected error during getMyDevices');
      return const Left(RepositoryFailure.unexpected);
    }
  }

  @override
  Future<void> connectToAuthService({
    AuthServiceInt? authService,
    Future<void> Function(String? uid)? onAuthenticated,
    Future<void> Function()? onAboutToLogOut,
  }) async {
    logd('DeviceService: connectToAuthService called');

    // Resolve auth service if not provided
    AuthServiceInt? resolvedAuthService = authService;
    if (resolvedAuthService == null) {
      try {
        resolvedAuthService = g<AuthServiceInt>();
      } catch (e) {
        logw('DeviceService: AuthServiceInt not registered in GetIt, cannot connect: $e');
        return;
      }
    }

    // Remove old callbacks if already connected (idempotency)
    if (_isConnectedToAuthService && _authService != null) {
      logd('DeviceService: Removing existing callbacks before reconnecting');
      _disconnectFromAuthService();
    }

    _authService = resolvedAuthService;

    // Create callback wrappers with default behavior
    _registeredOnAuthenticatedCallback = onAuthenticated ?? _defaultOnAuthenticated;
    _registeredOnAboutToLogOutCallback = onAboutToLogOut ?? _defaultOnAboutToLogOut;

    // Register callbacks
    _authService!.addOnAuthenticatedCallback(_registeredOnAuthenticatedCallback!);
    _authService!.addOnAboutToLogOutCallback(_registeredOnAboutToLogOutCallback!);

    _isConnectedToAuthService = true;

    // Also connect to lifecycle service for automatic resume updates
    _connectToLifecycleService();

    logd('DeviceService: Connected to AuthService and lifecycle');
  }

  /// Disconnects from auth service by removing registered callbacks.
  ///
  /// Also disconnects from lifecycle service since lifecycle updates
  /// require an authenticated user.
  void _disconnectFromAuthService() {
    if (_authService == null) return;

    if (_registeredOnAuthenticatedCallback != null) {
      _authService!.removeOnAuthenticatedCallback(_registeredOnAuthenticatedCallback!);
    }
    if (_registeredOnAboutToLogOutCallback != null) {
      _authService!.removeOnAboutToLogOutCallback(_registeredOnAboutToLogOutCallback!);
    }

    _registeredOnAuthenticatedCallback = null;
    _registeredOnAboutToLogOutCallback = null;
    _authService = null;
    _isConnectedToAuthService = false;

    // Also disconnect from lifecycle service
    // Note: Using unawaited since this is a synchronous method
    // The cancellation is fire-and-forget
    _disconnectFromLifecycleService();
  }

  /// Connects to app lifecycle service for automatic timezone/activity updates.
  ///
  /// This method wires the service to receive app resume events and automatically:
  /// - Calls [updateTimezoneOrOffsetIfChanged] to sync timezone/offset changes
  /// - Calls [touchDevice] to update lastActiveAt (with throttling)
  ///
  /// This is called automatically by [connectToAuthService] and should not need
  /// to be called manually by consuming apps.
  ///
  /// The lifecycle wiring is automatic and requires no consuming-app setup.
  void _connectToLifecycleService() {
    if (_isLifecycleConnected) {
      logd('DeviceService: Already connected to lifecycle service');
      return;
    }

    // Ensure AppLifecycleService is initialized
    final lifecycleService = AppLifecycleService();
    if (!lifecycleService.isInitialized) {
      lifecycleService.initialize();
    }

    // Subscribe to lifecycle events
    _lifecycleSubscription = lifecycleService.lifecycleStream.listen(
      _handleLifecycleStateChange,
      onError: (Object error) {
        loge(error, 'DeviceService: Error in lifecycle stream');
      },
    );

    _isLifecycleConnected = true;
    logd('DeviceService: Connected to lifecycle service');
  }

  /// Disconnects from app lifecycle service.
  Future<void> _disconnectFromLifecycleService() async {
    await _lifecycleSubscription?.cancel();
    _lifecycleSubscription = null;
    _isLifecycleConnected = false;
    logd('DeviceService: Disconnected from lifecycle service');
  }

  /// Handles app lifecycle state changes.
  ///
  /// On resume from background:
  /// - Updates timezone/offset if changed (with throttling)
  /// - Touches device to update lastActiveAt (with throttling)
  ///
  /// These operations are best-effort and failures do not propagate.
  Future<void> _handleLifecycleStateChange(AppLifecycleState state) async {
    if (state != AppLifecycleState.resumed) {
      return;
    }

    logd('DeviceService: App resumed, checking for timezone/offset changes');

    // Only perform updates if connected to auth (user is logged in)
    if (!_isConnectedToAuthService) {
      logd('DeviceService: Not connected to auth service, skipping resume updates');
      return;
    }

    // Update timezone/offset if changed (has its own throttling)
    // This is best-effort; failures are logged but not propagated
    try {
      final timezoneResult = await updateTimezoneOrOffsetIfChanged();
      timezoneResult.fold(
        (failure) => logw('DeviceService: Timezone update on resume failed: $failure'),
        (didUpdate) {
          if (didUpdate) {
            logd('DeviceService: Timezone/offset synced on resume');
          }
        },
      );
    } catch (e) {
      logw('DeviceService: Unexpected error during timezone update on resume: $e');
    }

    // Touch device to update lastActiveAt (has its own throttling)
    // This is best-effort; failures are logged but not propagated
    try {
      final touchResult = await touchDevice();
      touchResult.fold(
        (failure) => logw('DeviceService: Touch on resume failed: $failure'),
        (_) => logd('DeviceService: Device touched on resume'),
      );
    } catch (e) {
      logw('DeviceService: Unexpected error during touch on resume: $e');
    }
  }

  // ============================================================
  // Race-Free Initialization API (plan.auth-race.md)
  // ============================================================

  @override
  Future<void> handleAuthenticated(String? uid) async {
    // Defensive check - uid should never be null when called from AuthService,
    // but guard against unexpected edge cases.
    if (uid == null) {
      logw('DeviceService: handleAuthenticated called with null uid, skipping');
      return;
    }

    // Defensive check - warn if called before initialize().
    // This can happen if initialize() awaits are executed sequentially rather than
    // in parallel, allowing the auth callback to fire before all services are ready.
    // The pending payload system provides graceful degradation, but this indicates
    // an initialization ordering bug that should be fixed.
    if (_authService == null) {
      logw('DeviceService: handleAuthenticated called before initialize(). '
          'Device registration will use pending payload fallback. '
          'This indicates an initialization ordering issue - see Constraint 2 in plan.auth-race.md');
    }

    logd('DeviceService: handleAuthenticated called, uid=$uid');
    await _flushPendingPayload(bypassBackoff: true);
    await registerDevice();
  }

  @override
  Future<void> handleAboutToLogOut() async {
    logd('DeviceService: handleAboutToLogOut called');
    await unregisterDevice();
  }

  @override
  Future<void> initialize({required AuthServiceInt authService}) async {
    // CRITICAL: Set _authService FIRST, before any await statements.
    //
    // The auth callback (handleAuthenticated) may fire immediately after
    // AuthService construction via a microtask. If we await anything before
    // setting _authService, the callback could execute while _authService
    // is still null, breaking dependent operations.
    //
    // See: "Critical implementation constraints" section in plan.auth-race.md
    _authService = authService;
    _isConnectedToAuthService = true;

    // Connect to lifecycle service for automatic resume updates.
    // This is synchronous and does not await.
    _connectToLifecycleService();

    logd('DeviceService: Initialized with auth service');
  }

  @override
  bool get isConnectedToAuth => _isConnectedToAuthService;

  /// Default callback for authenticated event.
  Future<void> _defaultOnAuthenticated(String? uid) async {
    logd('DeviceService: onAuthenticated triggered for uid: $uid');
    if (uid != null) {
      // First, try to flush any pending payload from before authentication
      await _flushPendingPayload(bypassBackoff: true);

      // Register device on login
      final result = await registerDevice();
      result.fold(
        (failure) => logw('DeviceService: registerDevice failed on auth: $failure'),
        (_) => logd('DeviceService: registerDevice succeeded on auth'),
      );
    }
  }

  /// Default callback for about-to-logout event.
  Future<void> _defaultOnAboutToLogOut() async {
    logd('DeviceService: onAboutToLogOut triggered');
    // Unregister device on logout (best-effort)
    final result = await unregisterDevice();
    result.fold(
      (failure) => logw('DeviceService: unregisterDevice failed on logout: $failure'),
      (_) => logd('DeviceService: unregisterDevice succeeded on logout'),
    );
  }

  /// Maps Firebase Functions exceptions to [RepositoryFailure].
  Left<RepositoryFailure, T> _mapFirebaseFunctionsException<T>(
      FirebaseFunctionsException e) {
    switch (e.code) {
      case 'unauthenticated':
        return const Left(RepositoryFailure.notAuthorizedToRead);
      case 'permission-denied':
        return const Left(RepositoryFailure.notAuthorizedToWrite);
      case 'not-found':
        return const Left(RepositoryFailure.expectedRecordNotFound);
      case 'invalid-argument':
        return const Left(RepositoryFailure.unexpected);
      case 'unavailable':
      case 'deadline-exceeded':
        return const Left(RepositoryFailure.networkError);
      default:
        return const Left(RepositoryFailure.unexpected);
    }
  }
}
