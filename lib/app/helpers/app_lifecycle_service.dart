import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dreamic/versioning/app_version_update_service.dart';
import 'package:dreamic/utils/logger.dart';

/// Service to handle app lifecycle events and trigger appropriate actions
/// like version checking when the app resumes from background
class AppLifecycleService with WidgetsBindingObserver {
  static final AppLifecycleService _instance = AppLifecycleService._internal();
  factory AppLifecycleService() => _instance;
  AppLifecycleService._internal();

  StreamController<AppLifecycleState>? _lifecycleController;
  bool _isInitialized = false;
  DateTime? _lastPausedTime;

  /// Minimum time in seconds that must pass before triggering a version check
  static const Duration _versionCheckCooldown = Duration(minutes: 5);

  /// Stream of app lifecycle state changes
  Stream<AppLifecycleState> get lifecycleStream =>
      _lifecycleController?.stream ?? const Stream.empty();

  /// Initialize the service and start listening to lifecycle events
  void initialize() {
    if (_isInitialized) return;

    logv('Initializing AppLifecycleService');
    _lifecycleController = StreamController<AppLifecycleState>.broadcast();
    WidgetsBinding.instance.addObserver(this);
    _isInitialized = true;
  }

  /// Dispose of the service and clean up resources
  void dispose() {
    if (!_isInitialized) return;

    logv('Disposing AppLifecycleService');
    WidgetsBinding.instance.removeObserver(this);
    _lifecycleController?.close();
    _lifecycleController = null;
    _isInitialized = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    logv('App lifecycle state changed: $state');
    _lifecycleController?.add(state);

    switch (state) {
      case AppLifecycleState.resumed:
        _handleAppResumed();
        break;
      case AppLifecycleState.paused:
        _handleAppPaused();
        break;
      case AppLifecycleState.detached:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        // No specific action needed for these states
        break;
    }
  }

  void _handleAppResumed() {
    logv('App resumed from background');

    // Check if enough time has passed since last pause to trigger version check
    if (_lastPausedTime != null) {
      final timeSincePause = DateTime.now().difference(_lastPausedTime!);

      if (timeSincePause >= _versionCheckCooldown) {
        logv(
            'Triggering version check after app resume (paused for ${timeSincePause.inMinutes} minutes)');
        _triggerVersionCheck();
      } else {
        logv('Skipping version check, app was paused for only ${timeSincePause.inMinutes} minutes');
      }
    } else {
      // First time resuming, trigger version check
      logv('First app resume, triggering version check');
      _triggerVersionCheck();
    }
  }

  void _handleAppPaused() {
    logv('App paused/backgrounded');
    _lastPausedTime = DateTime.now();
  }

  void _triggerVersionCheck() {
    try {
      AppVersionUpdateService().forceVersionCheck().catchError((error) {
        loge('Error during lifecycle version check: $error');
      });
    } catch (e) {
      loge('Error triggering version check: $e');
    }
  }

  /// Manually trigger a version check (useful for testing or manual refresh)
  Future<void> checkForUpdates() async {
    logv('Manual version check triggered');
    _triggerVersionCheck();
  }

  /// Check if the service is initialized
  bool get isInitialized => _isInitialized;
}
