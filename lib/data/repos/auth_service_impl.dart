import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:dartz/dartz.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:dreamic/data/helpers/repository_failure.dart';
import 'package:dreamic/utils/retry_it.dart';
import 'package:dreamic/data/helpers/repo_helpers.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:http/http.dart' as http;
import '../../app/app_config_base.dart';
import '../../utils/logger.dart';
import 'auth_service_int.dart';

// Note: this doesn't work with both anon auth and federated auth, but it could

class AuthServiceImpl implements AuthServiceInt {
  /// Callbacks invoked when user authenticates, grouped by priority.
  ///
  /// Higher priority values execute first. Callbacks at the same priority
  /// execute in parallel.
  final Map<int, List<Future<void> Function(String? uid)>>
      _onAuthenticatedByPriority = {};

  /// Callbacks invoked AFTER logout is complete, grouped by priority.
  ///
  /// Higher priority values execute first. Callbacks at the same priority
  /// execute in parallel.
  final Map<int, List<Future<void> Function()>> _onLoggedOutByPriority = {};

  /// Callbacks invoked BEFORE signing out, while still authenticated.
  ///
  /// Use [addOnAboutToLogOutCallback] to register callbacks for cleanup tasks
  /// that require authentication (e.g., unregistering FCM tokens from backend).
  /// Each callback is called with a timeout; failures won't block sign out.
  ///
  /// Higher priority values execute first. Callbacks at the same priority
  /// execute in parallel.
  final Map<int, List<Future<void> Function()>> _onAboutToLogOutByPriority = {};

  @override
  void addOnAuthenticatedCallback(
    Future<void> Function(String? uid) callback, {
    int priority = 0,
  }) {
    _onAuthenticatedByPriority.putIfAbsent(priority, () => []).add(callback);
  }

  @override
  bool removeOnAuthenticatedCallback(Future<void> Function(String? uid) callback) {
    for (final callbacks in _onAuthenticatedByPriority.values) {
      if (callbacks.remove(callback)) return true;
    }
    return false;
  }

  @override
  void addOnLoggedOutCallback(
    Future<void> Function() callback, {
    int priority = 0,
  }) {
    _onLoggedOutByPriority.putIfAbsent(priority, () => []).add(callback);
  }

  @override
  bool removeOnLoggedOutCallback(Future<void> Function() callback) {
    for (final callbacks in _onLoggedOutByPriority.values) {
      if (callbacks.remove(callback)) return true;
    }
    return false;
  }

  @override
  void addOnAboutToLogOutCallback(
    Future<void> Function() callback, {
    int priority = 0,
  }) {
    _onAboutToLogOutByPriority.putIfAbsent(priority, () => []).add(callback);
  }

  @override
  bool removeOnAboutToLogOutCallback(Future<void> Function() callback) {
    for (final callbacks in _onAboutToLogOutByPriority.values) {
      if (callbacks.remove(callback)) return true;
    }
    return false;
  }

  late HttpsCallable authCallable =
      AppConfigBase.firebaseFunctionCallable(AppConfigBase.authMainCallableFunction);

  @visibleForTesting
  Duration signInRetryDelay = const Duration(seconds: 1);

  late final fb_auth.FirebaseAuth _fbAuth;

  // Firebase auth listener subscriptions (for dispose/test teardown)
  StreamSubscription<fb_auth.User?>? _authStateSubscription;
  StreamSubscription<fb_auth.User?>? _idTokenSubscription;

  // bool _hasGottenUserPrivate = false;
  bool _hasAuthStateChangeListenerRunAtLeastOnce = false;
  String? _accessCodeCached;
  final StreamController<bool> _isLoggedInStreamController = StreamController<bool>.broadcast();

  @override
  Stream<bool> get isLoggedInStream => _isLoggedInStreamController.stream;

  // @override
  // /// Stream of [UserPrivate] which will emit the current user when
  // /// the authentication state changes.
  // ///
  // /// Emits [UserPrivate.empty] if the user is not authenticated.
  // Stream<UserPrivate> get user {
  //   return _fbAuth.authStateChanges().map((firebaseUser) {
  //     final user = firebaseUser == null ? UserPrivate.empty : firebaseUser.toUser;
  //     _cache.write(key: userCacheKey, value: user);
  //     return user;
  //   });
  // }

  // @override
  // UserPrivate currentUserPrivate = UserPrivate();

  // @override
  // Rx<UserPrivate> currentUserPrivate = Rx<UserPrivate>(UserPrivate());

  @override
  fb_auth.UserCredential? currentFbUserCredentials;

  //TODO: search for currentFbUser! everywhere because this is a potential issue if null
  @override
  fb_auth.User? get currentFbUser {
    return _fbAuth.currentUser;
  }

  //User currentUser;
  @override
  set currentFbUser(fb_auth.User? user) {
    // Note: This is done to appease the compiler...
    throw StateError('Cannot set this value programmatically');
  }

  AuthServiceImpl({
    FirebaseApp? firebaseApp,
    fb_auth.FirebaseAuth? firebaseAuthOverride, // @visibleForTesting
    // Single callback convenience (default priority 0)
    Future<void> Function(String? uid)? onAuthenticated,
    Future<void> Function()? onLoggedOut,
    Future<void> Function()? onAboutToLogOut,
    // List of callbacks (default priority 0)
    List<Future<void> Function(String? uid)>? onAuthenticatedCallbacks,
    List<Future<void> Function()>? onLoggedOutCallbacks,
    List<Future<void> Function()>? onAboutToLogOutCallbacks,
    // Prioritized callbacks for ordered execution
    List<PrioritizedCallback<Future<void> Function(String? uid)>>?
        onAuthenticatedPrioritized,
    List<PrioritizedCallback<Future<void> Function()>>? onLoggedOutPrioritized,
    List<PrioritizedCallback<Future<void> Function()>>?
        onAboutToLogOutPrioritized,
  }) : assert(firebaseApp != null || firebaseAuthOverride != null,
            'Provide firebaseApp or firebaseAuthOverride') {
    // This can be disabled for hardcoding
    logd('Instantiated AuthServiceImpl');
    _fbAuth = firebaseAuthOverride ?? fb_auth.FirebaseAuth.instanceFor(app: firebaseApp!);

    // IMPORTANT: Register ALL constructor-provided lifecycle callbacks BEFORE
    // attaching auth listeners.
    //
    // RATIONALE:
    // When a user is already logged in (warm start), Firebase can emit an auth
    // state event almost immediately after `authStateChanges().listen(...)`.
    // If callbacks are registered after listeners, the first auth event can be
    // missed by the consuming app (race condition).

    // Register prioritized callbacks first (explicit priority)
    if (onAuthenticatedPrioritized != null) {
      for (final pc in onAuthenticatedPrioritized) {
        addOnAuthenticatedCallback(pc.callback, priority: pc.priority);
      }
    }
    if (onLoggedOutPrioritized != null) {
      for (final pc in onLoggedOutPrioritized) {
        addOnLoggedOutCallback(pc.callback, priority: pc.priority);
      }
    }
    if (onAboutToLogOutPrioritized != null) {
      for (final pc in onAboutToLogOutPrioritized) {
        addOnAboutToLogOutCallback(pc.callback, priority: pc.priority);
      }
    }

    // Register list callbacks (default priority 0)
    if (onAuthenticatedCallbacks != null) {
      for (final callback in onAuthenticatedCallbacks) {
        addOnAuthenticatedCallback(callback);
      }
    }
    if (onLoggedOutCallbacks != null) {
      for (final callback in onLoggedOutCallbacks) {
        addOnLoggedOutCallback(callback);
      }
    }
    if (onAboutToLogOutCallbacks != null) {
      for (final callback in onAboutToLogOutCallbacks) {
        addOnAboutToLogOutCallback(callback);
      }
    }

    // Register single callbacks (default priority 0)
    if (onAuthenticated != null) {
      addOnAuthenticatedCallback(onAuthenticated);
    }
    if (onLoggedOut != null) {
      addOnLoggedOutCallback(onLoggedOut);
    }
    if (onAboutToLogOut != null) {
      addOnAboutToLogOutCallback(onAboutToLogOut);
    }

    // Attach listeners AFTER callbacks are registered.
    _authStateSubscription = _fbAuth.authStateChanges().listen(handleAuthStateChanges);
    _idTokenSubscription = _fbAuth.idTokenChanges().listen((event) => handleTokenChanges(event));

    // For debuggin
    if (AppConfigBase.signoutOnReload) {
      // _fbAuth.signOut();
      signOut();
    }
  }

  // Add dispose method to clean up the stream controller
  void dispose() {
    _authStateSubscription?.cancel();
    _idTokenSubscription?.cancel();
    _isLoggedInStreamController.close();
  }

  /// Executes callbacks grouped by priority.
  ///
  /// Higher priority values execute first. Callbacks at the same priority
  /// execute in parallel via `Future.wait`. Different priorities execute
  /// sequentially.
  ///
  /// [callbacksByPriority] is the map of priority -> callbacks.
  /// [argument] is passed to each callback.
  /// [timeout] is the global timeout for all callbacks (not per-priority).
  /// [callbackType] is used for logging (e.g., "onAuthenticated").
  Future<void> _executeCallbacksByPriority<T>(
    Map<int, List<Future<void> Function(T)>> callbacksByPriority,
    T argument,
    Duration timeout,
    String callbackType,
  ) async {
    if (callbacksByPriority.isEmpty) return;

    // Sort priorities descending (higher runs first)
    final priorities = callbacksByPriority.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    final stopwatch = Stopwatch()..start();

    for (final priority in priorities) {
      // Check if global timeout exceeded
      if (stopwatch.elapsed >= timeout) {
        // Log as ERROR - timeout means cleanup may be incomplete
        loge('$callbackType callbacks: global timeout exceeded after '
            '${stopwatch.elapsed}, skipping remaining priorities. '
            'Backend cleanup may be required.');
        break;
      }

      final callbacks = callbacksByPriority[priority] ?? [];
      if (callbacks.isEmpty) continue;

      final remainingTime = timeout - stopwatch.elapsed;

      // Execute all callbacks at this priority level in parallel
      try {
        await Future.wait(
          callbacks.map((cb) => cb(argument).catchError((e) {
                logw('$callbackType callback (priority $priority) failed: $e');
              })),
        ).timeout(remainingTime, onTimeout: () {
          // Log as ERROR - timeout means cleanup may be incomplete
          loge('$callbackType callbacks (priority $priority) timed out after '
              '$remainingTime. Backend cleanup may be required.');
          return [];
        });
      } catch (e) {
        logw('$callbackType callbacks (priority $priority) error: $e');
      }
    }
  }

  /// Executes void callbacks grouped by priority (no argument version).
  ///
  /// Higher priority values execute first. Callbacks at the same priority
  /// execute in parallel via `Future.wait`. Different priorities execute
  /// sequentially.
  Future<void> _executeVoidCallbacksByPriority(
    Map<int, List<Future<void> Function()>> callbacksByPriority,
    Duration timeout,
    String callbackType,
  ) async {
    if (callbacksByPriority.isEmpty) return;

    // Sort priorities descending (higher runs first)
    final priorities = callbacksByPriority.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    final stopwatch = Stopwatch()..start();

    for (final priority in priorities) {
      // Check if global timeout exceeded
      if (stopwatch.elapsed >= timeout) {
        // Log as ERROR - timeout means cleanup may be incomplete
        loge('$callbackType callbacks: global timeout exceeded after '
            '${stopwatch.elapsed}, skipping remaining priorities. '
            'Backend cleanup may be required.');
        break;
      }

      final callbacks = callbacksByPriority[priority] ?? [];
      if (callbacks.isEmpty) continue;

      final remainingTime = timeout - stopwatch.elapsed;

      // Execute all callbacks at this priority level in parallel
      try {
        await Future.wait(
          callbacks.map((cb) => cb().catchError((e) {
                logw('$callbackType callback (priority $priority) failed: $e');
              })),
        ).timeout(remainingTime, onTimeout: () {
          // Log as ERROR - timeout means cleanup may be incomplete
          loge('$callbackType callbacks (priority $priority) timed out after '
              '$remainingTime. Backend cleanup may be required.');
          return [];
        });
      } catch (e) {
        logw('$callbackType callbacks (priority $priority) error: $e');
      }
    }
  }

  // Update auth state change handler to complete the completer
  Future<void> handleAuthStateChanges(fb_auth.User? fbUser) async {
    logd('handleAuthStateChanges called');

    // final wasAuthenticated = fbUser != null;

    if (fbUser == null) {
      logd('fbUser is null during handleAuthStateChanges');
      _updateCachedState(false);
      _hasAuthStateChangeListenerRunAtLeastOnce = true;

      // Emit to the stream
      _isLoggedInStreamController.add(false);

      // Complete the auth state completer if it's waiting
      if (_authStateCompleter != null && !_authStateCompleter!.isCompleted) {
        _authStateCompleter!.complete(false);
      }

      signOut(useFbAuthAlso: false);
    } else {
      logd('fbUser is NOT null during handleAuthStateChanges');
      _updateCachedState(true);
      _hasAuthStateChangeListenerRunAtLeastOnce = true;

      // Emit to the stream
      _isLoggedInStreamController.add(true);

      // Complete the auth state completer if it's waiting
      if (_authStateCompleter != null && !_authStateCompleter!.isCompleted) {
        _authStateCompleter!.complete(true);
      }

      // Call all onAuthenticated callbacks by priority
      // Using a generous timeout for auth callbacks since they may need to make
      // network calls (e.g., device registration)
      await _executeCallbacksByPriority<String?>(
        _onAuthenticatedByPriority,
        fbUser.uid,
        const Duration(seconds: 30),
        'onAuthenticated',
      );
    }
  }

  Future<void> handleTokenChanges(fb_auth.User? fbUser) async {
    logd('handleTokenChanges called');

    // Call the function to get the cookie set
    // final token = await _fbAuth.currentUser!.getIdToken();
    if (fbUser == null) {
      logd('fbUser is null during handleTokenChanges');
      return;
    } else {
      logd('fbUser is NOT null during handleTokenChanges');
      // Note: refreshCurrentUser was here but is no longer needed.

      // Note: FCM token management has been moved to NotificationService.
      // Apps should subscribe to isLoggedInStream and call
      // NotificationService.initializeFcmToken() when user logs in.
    }

    //
    // Set the cookie for multi-domain auth
    //
    if (AppConfigBase.doUseBackendEmulator == false &&
        AppConfigBase.useCookieFederatedAuth == true) {
      final url = RepoHelpers.getFunctionUrl(_fbAuth.app, 'authfunctions-onsignin');
      final token = await fbUser.getIdToken();

      logd('onSignIn url: $url');
      // logd('token: $token');

      final http.Client client = http.Client();
      try {
        final response = await client.post(Uri.parse(url), body: {
          // 'Accept': '*/*',
          // 'User-Agent': 'Thunder Client (https://www.thunderclient.com)',
          // 'Authorization': 'Bearer $token',
          'token': token,
        });

        if (response.statusCode == 200) {
          logd('Cookie set successfully!!');
        } else {
          loge('Failed to set cookie!!');
        }
      } finally {
        client.close();
      }
    }
  }

  // Add method to force refresh auth state
  Future<bool> forceRefreshAuthState() async {
    _lastTokenValidation = null;
    _lastKnownAuthState = null;
    // Don't reuse any existing completer for forced refresh
    _loginCheckCompleter = null;
    return await isLoggedInAsync();
  }

  // Update sign out to clear cached state
  @override
  Future<Either<AuthServiceSignOutFailure, Unit>> signOut({bool useFbAuthAlso = true}) async {
    // Clear cached auth state immediately
    _updateCachedState(false);

    // Cancel any pending completers
    if (_loginCheckCompleter != null && !_loginCheckCompleter!.isCompleted) {
      _safeCompleteLoginCheckWithError('User signed out');
    }

    // ...existing signOut code...
    try {
      // Call all onAboutToLogOut callbacks while still authenticated (before Firebase signOut)
      // This allows cleanup tasks like FCM token unregistration that require auth
      if (useFbAuthAlso && _onAboutToLogOutByPriority.isNotEmpty) {
        final timeout = Duration(milliseconds: AppConfigBase.timeoutForAboutToLogOutCallbackMill);
        await _executeVoidCallbacksByPriority(
          _onAboutToLogOutByPriority,
          timeout,
          'onAboutToLogOut',
        );
      }

      if (useFbAuthAlso) {
        await _fbAuth.signOut();
      }

      // Call all onLoggedOut callbacks (after sign out is complete)
      // Using a generous timeout for post-logout callbacks
      await _executeVoidCallbacksByPriority(
        _onLoggedOutByPriority,
        const Duration(seconds: 30),
        'onLoggedOut',
      );

      // Clear the cookie on the server if using federated auth
      if (AppConfigBase.useCookieFederatedAuth) {
        final http.Client client = http.Client();
        try {
          final response = await client
              .get(Uri.parse(RepoHelpers.getFunctionUrl(_fbAuth.app, 'authfunctions-signout')));

          if (response.statusCode == 204) {
            logd('Cleared cookie successfully');
          } else {
            logd('Failed to clear cookie!!');
            // Don't return error for cookie clear failure
          }
        } finally {
          client.close();
        }
      }

      // Note: FCM token cleanup has been moved to NotificationService.clearFcmToken()
      // Apps should call NotificationService.clearFcmToken() before signing out.

      _accessCodeCached = null;
    } on fb_auth.FirebaseAuthException catch (e) {
      loge(e);
      return left(AuthServiceSignOutFailure.unexpected);
    } catch (e) {
      loge(e);
      return left(AuthServiceSignOutFailure.unexpected);
    }

    return right(unit);
  }

  // Email verification
  @override
  bool get isEmailVerified {
    return _fbAuth.currentUser?.emailVerified ?? false;
  }

  @override
  Future<Either<AuthServiceEmailVerificationFailure, Unit>> sendEmailVerification() async {
    try {
      final user = _fbAuth.currentUser;
      if (user == null) {
        logw('sendEmailVerification: No user logged in');
        return left(AuthServiceEmailVerificationFailure.userNotLoggedIn);
      }

      logd('sendEmailVerification: Sending verification email to ${user.email}');
      await user.sendEmailVerification();
      logd('sendEmailVerification: Email sent successfully');

      return right(unit);
    } on fb_auth.FirebaseAuthException catch (e) {
      loge(e, 'sendEmailVerification failed');
      if (e.code == 'too-many-requests') {
        return left(AuthServiceEmailVerificationFailure.tooManyRequests);
      }
      return left(AuthServiceEmailVerificationFailure.unexpected);
    } catch (e) {
      loge(e, 'sendEmailVerification failed');
      return left(AuthServiceEmailVerificationFailure.unexpected);
    }
  }

  @override
  Future<Either<AuthServiceSignInFailure, Unit>> reloadUser() async {
    try {
      final user = _fbAuth.currentUser;
      if (user == null) {
        logw('reloadUser: No user logged in');
        return left(AuthServiceSignInFailure.userNotFound);
      }

      logd('reloadUser: Reloading user data');
      await user.reload();
      logd('reloadUser: User data reloaded, emailVerified=${_fbAuth.currentUser?.emailVerified}');

      return right(unit);
    } on fb_auth.FirebaseAuthException catch (e) {
      loge(e, 'reloadUser failed');
      return left(AuthServiceSignInFailure.unexpected);
    } catch (e) {
      loge(e, 'reloadUser failed');
      return left(AuthServiceSignInFailure.unexpected);
    }
  }

  @override
  Future<Either<AuthServiceSignInFailure, Unit>> reauthenticateWithPassword(
    String password,
  ) async {
    try {
      final user = _fbAuth.currentUser;
      if (user == null) {
        logw('reauthenticateWithPassword: No user logged in');
        return left(AuthServiceSignInFailure.userNotFound);
      }

      final email = user.email;
      if (email == null) {
        logw('reauthenticateWithPassword: User has no email');
        return left(AuthServiceSignInFailure.invalidEmail);
      }

      logd('reauthenticateWithPassword: Re-authenticating user');

      // Create credential and re-authenticate
      final credential = fb_auth.EmailAuthProvider.credential(
        email: email,
        password: password,
      );

      await user.reauthenticateWithCredential(credential);
      logd('reauthenticateWithPassword: Re-authentication successful');

      return right(unit);
    } on fb_auth.FirebaseAuthException catch (e) {
      loge(e, 'reauthenticateWithPassword failed');
      switch (e.code) {
        case 'wrong-password':
          return left(AuthServiceSignInFailure.wrongPassword);
        case 'invalid-credential':
          return left(AuthServiceSignInFailure.invalidCredential);
        case 'user-disabled':
          return left(AuthServiceSignInFailure.userDisabled);
        case 'too-many-requests':
          return left(AuthServiceSignInFailure.tooManyRequests);
        default:
          return left(AuthServiceSignInFailure.unexpected);
      }
    } catch (e) {
      loge(e, 'reauthenticateWithPassword failed');
      return left(AuthServiceSignInFailure.unexpected);
    }
  }

  @override
  Future<Either<AuthServiceLinkFailure, Unit>> linkEmailPassword(
    String email,
    String password,
  ) async {
    try {
      final user = _fbAuth.currentUser;
      if (user == null) {
        logw('linkEmailPassword: No user logged in');
        return left(AuthServiceLinkFailure.userNotLoggedIn);
      }

      // Check if user already has email/password credential linked.
      // We check for email provider instead of isAnonymous because users
      // signed in with custom tokens (e.g., server-created anonymous users)
      // have isAnonymous=false but should still be able to link email/password.
      final hasEmailProvider = user.providerData.any(
        (provider) => provider.providerId == 'password',
      );
      if (hasEmailProvider) {
        logw('linkEmailPassword: User already has email/password linked');
        return left(AuthServiceLinkFailure.credentialAlreadyInUse);
      }

      logd('linkEmailPassword: Linking account to email: $email');

      // Create email/password credential
      final credential = fb_auth.EmailAuthProvider.credential(
        email: email,
        password: password,
      );

      // Link the credential to the anonymous account
      await user.linkWithCredential(credential);
      logd('linkEmailPassword: Successfully linked account');

      return right(unit);
    } on fb_auth.FirebaseAuthException catch (e) {
      loge(e, 'linkEmailPassword failed');
      switch (e.code) {
        case 'email-already-in-use':
          return left(AuthServiceLinkFailure.emailAlreadyInUse);
        case 'weak-password':
          return left(AuthServiceLinkFailure.weakPassword);
        case 'invalid-email':
          return left(AuthServiceLinkFailure.invalidEmail);
        case 'invalid-credential':
          return left(AuthServiceLinkFailure.invalidCredential);
        case 'credential-already-in-use':
          return left(AuthServiceLinkFailure.credentialAlreadyInUse);
        case 'requires-recent-login':
          return left(AuthServiceLinkFailure.requiresRecentLogin);
        default:
          return left(AuthServiceLinkFailure.unexpected);
      }
    } catch (e) {
      loge(e, 'linkEmailPassword failed');
      return left(AuthServiceLinkFailure.unexpected);
    }
  }

  @override
  Future<Either<AuthServiceSignInFailure, Unit>> updatePassword(
    String newPassword,
  ) async {
    try {
      final user = _fbAuth.currentUser;
      if (user == null) {
        logw('updatePassword: No user logged in');
        return left(AuthServiceSignInFailure.userNotFound);
      }

      logd('updatePassword: Updating password');
      await user.updatePassword(newPassword);
      logd('updatePassword: Password updated successfully');

      return right(unit);
    } on fb_auth.FirebaseAuthException catch (e) {
      loge(e, 'updatePassword failed');
      switch (e.code) {
        case 'weak-password':
          return left(AuthServiceSignInFailure.weakPassword);
        case 'requires-recent-login':
          return left(AuthServiceSignInFailure.invalidCredential);
        default:
          return left(AuthServiceSignInFailure.unexpected);
      }
    } catch (e) {
      loge(e, 'updatePassword failed');
      return left(AuthServiceSignInFailure.unexpected);
    }
  }

  // @override
  // bool isLoggedIn() {
  //   return _fbAuth.currentUser != null;
  // }

  // Completer
  Completer<bool>? _loginCheckCompleter;

  /// Safely completes the login check completer if it exists and hasn't been completed yet
  void _safeCompleteLoginCheck(bool result) {
    if (_loginCheckCompleter != null && !_loginCheckCompleter!.isCompleted) {
      _loginCheckCompleter!.complete(result);
    }
  }

  /// Safely completes the login check completer with an error if it exists and hasn't been completed yet
  void _safeCompleteLoginCheckWithError(Object error) {
    if (_loginCheckCompleter != null && !_loginCheckCompleter!.isCompleted) {
      _loginCheckCompleter!.completeError(error);
    }
  }

  // For caching and state management
  DateTime? _lastTokenValidation;
  bool? _lastKnownAuthState;
  static const Duration _tokenValidationInterval = Duration(minutes: 5);
  static const Duration _quickCheckInterval = Duration(seconds: 30);

  @override
  Future<bool> isLoggedInAsync() async {
    // Check if another check is in progress
    if (_loginCheckCompleter != null && !_loginCheckCompleter!.isCompleted) {
      logd('isLoggedInAsync: Already checking login state, waiting for completion...');
      try {
        // Wait for the existing check to complete and return its result
        return await _loginCheckCompleter!.future;
      } catch (e) {
        logd('isLoggedInAsync: Error waiting for existing check: $e');
        // If the existing check failed, fall through to perform our own check
      }
    }

    // Create a new completer for this check
    _loginCheckCompleter = Completer<bool>();

    try {
      // Use cached state for very frequent calls (within 30 seconds)
      if (_shouldUseQuickCache()) {
        logd('isLoggedInAsync: Using quick cached auth state');
        _safeCompleteLoginCheck(_lastKnownAuthState!);
        return _lastKnownAuthState!;
      }

      await waitForCanCheckLoginState();

      // Quick check if no user
      if (_fbAuth.currentUser == null) {
        final result = await _handleUnauthenticatedState();
        _updateCachedState(result);
        _safeCompleteLoginCheck(result);
        return result;
      }

      // For less frequent calls, do a lightweight check
      if (_shouldUseLightweightCheck()) {
        logd('isLoggedInAsync: Performing lightweight token check');
        bool isValid = await _performLightweightTokenCheck();
        if (isValid) {
          _updateCachedState(true);
          _safeCompleteLoginCheck(true);
          return true;
        }
      }

      // Full validation with network check
      bool isTokenValid = await _performFullTokenValidation();

      if (isTokenValid) {
        _updateCachedState(true);
        _safeCompleteLoginCheck(true);
        return true;
      } else {
        // Token is invalid, try alternative auth methods
        final result = await _handleInvalidToken();
        _updateCachedState(result);
        _safeCompleteLoginCheck(result);
        return result;
      }
    } catch (e) {
      logd('isLoggedInAsync: Unexpected error: $e');

      // On error, trust Firebase's auth state
      bool fbAuthState = _fbAuth.currentUser != null;
      if (fbAuthState && _lastKnownAuthState == true) {
        // If Firebase says we're logged in and we were logged in before, trust it
        _safeCompleteLoginCheck(true);
        return true;
      }

      _safeCompleteLoginCheckWithError(e);
      return fbAuthState;
    } finally {
      // Clean up the completer after a short delay
      Future.delayed(const Duration(milliseconds: 100), () {
        _loginCheckCompleter = null;
      });
    }
  }

  bool _shouldUseQuickCache() {
    if (_lastTokenValidation == null || _lastKnownAuthState != true) {
      return false;
    }

    final timeSinceLastValidation = DateTime.now().difference(_lastTokenValidation!);
    return timeSinceLastValidation < _quickCheckInterval;
  }

  bool _shouldUseLightweightCheck() {
    if (_lastTokenValidation == null) {
      return true;
    }

    final timeSinceLastValidation = DateTime.now().difference(_lastTokenValidation!);
    return timeSinceLastValidation < _tokenValidationInterval;
  }

  void _updateCachedState(bool isAuthenticated) {
    _lastKnownAuthState = isAuthenticated;
    _lastTokenValidation = DateTime.now();

    // Also emit to the stream
    if (!_isLoggedInStreamController.isClosed) {
      _isLoggedInStreamController.add(isAuthenticated);
    }
  }

  Future<bool> _performLightweightTokenCheck() async {
    try {
      final user = _fbAuth.currentUser;
      if (user == null) {
        logw('_performLightweightTokenCheck: currentUser is null');
        return false;
      }
      // Get token without forcing refresh - uses cached token if valid
      final token = await user.getIdToken(false);
      return token != null;
    } catch (e) {
      logd('_performLightweightTokenCheck failed: $e');
      return false;
    }
  }

  Future<bool> _performFullTokenValidation() async {
    try {
      // Only force refresh if we haven't validated recently
      final shouldForceRefresh = _lastTokenValidation == null ||
          DateTime.now().difference(_lastTokenValidation!) > _tokenValidationInterval;

      logd('_performFullTokenValidation: forceRefresh=$shouldForceRefresh');

      final user = _fbAuth.currentUser;
      if (user == null) {
        logw('_performFullTokenValidation: currentUser is null');
        return false;
      }

      // This will use Firebase's automatic token management
      final token = await user
          .getIdToken(shouldForceRefresh)
          .timeout(const Duration(seconds: 10));

      if (token != null) {
        logd('isLoggedInAsync: Token validated successfully');
        return true;
      }
      return false;
    } on TimeoutException {
      logd('_performFullTokenValidation: Timeout - assuming valid if was valid before');
      // On timeout, trust last known state
      return _lastKnownAuthState ?? false;
    } catch (e) {
      logd('_performFullTokenValidation failed: $e');

      // Check if it's a network error
      if (_isNetworkError(e)) {
        logd('Network error detected, trusting Firebase auth state');
        // For network errors, trust Firebase's local auth state
        return _fbAuth.currentUser != null;
      }

      return false;
    }
  }

  bool _isNetworkError(dynamic error) {
    final errorString = error.toString().toLowerCase();
    return errorString.contains('network') ||
        errorString.contains('timeout') ||
        errorString.contains('connection') ||
        errorString.contains('unavailable') ||
        errorString.contains('fetch') ||
        errorString.contains('xmlhttprequest');
  }

  Future<bool> _handleInvalidToken() async {
    logd('isLoggedInAsync: Handling invalid token');

    // Try cookie auth first
    if (AppConfigBase.doUseBackendEmulator == false &&
        AppConfigBase.useCookieFederatedAuth == true) {
      try {
        final cookieAuthResult = await _attemptCookieAuth();
        if (cookieAuthResult) {
          return true;
        }
      } catch (e) {
        logd('Cookie auth failed: $e');
      }
    }

    // Only sign out if we're certain the session is invalid
    logd('isLoggedInAsync: Session confirmed invalid, signing out');
    await signOut(useFbAuthAlso: true);
    return false;
  }

  Future<bool> _handleUnauthenticatedState() async {
    // Try DevOnly login if configured
    if (AppConfigBase.devOnlyUid.isNotEmpty || AppConfigBase.devOnlyAutoGenerateNewUser == true) {
      try {
        await signInWithDevOnly();
        return true;
      } catch (e) {
        logd('DevOnly sign in failed: $e');
      }
    }

    // Try cookie auth
    if (AppConfigBase.doUseBackendEmulator == false &&
        AppConfigBase.useCookieFederatedAuth == true) {
      try {
        final cookieAuthResult = await _attemptCookieAuth();
        if (cookieAuthResult) {
          return true;
        }
      } catch (e) {
        logd('Cookie auth failed: $e');
      }
    }

    return false;
  }

  Future<bool> _attemptCookieAuth() async {
    final http.Client client = http.Client();

    try {
      final response = await client
          .get(Uri.parse(RepoHelpers.getFunctionUrl(_fbAuth.app, 'authfunctions-checkstatus')))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        logd('_attemptCookieAuth: Cookie is valid, logging in...');
        await _fbAuth.signInWithCustomToken(jsonDecode(response.body)['customToken']);
        return true;
      } else {
        logd('_attemptCookieAuth: Cookie is NOT valid or not present');
        return false;
      }
    } catch (e) {
      logd('_attemptCookieAuth: Cookie auth failed: $e');
      return false;
    } finally {
      client.close();
    }
  }

  // Update waitForCanCheckLoginState to also use a Completer
  Completer<bool>? _authStateCompleter;

  @override
  Future<bool> waitForCanCheckLoginState() async {
    logd('waitForCanCheckLoginState called');

    // If we already have auth state, return immediately
    if (_hasAuthStateChangeListenerRunAtLeastOnce) {
      return _fbAuth.currentUser != null;
    }

    // Check if we're already waiting
    if (_authStateCompleter != null && !_authStateCompleter!.isCompleted) {
      logd('waitForCanCheckLoginState: Already waiting, reusing existing completer');
      return await _authStateCompleter!.future;
    }

    // Create a new completer
    _authStateCompleter = Completer<bool>();

    // Set up a timeout
    Timer? timeoutTimer;
    timeoutTimer = Timer(const Duration(seconds: 5), () async {
      if (_authStateCompleter != null && !_authStateCompleter!.isCompleted) {
        logw('waitForCanCheckLoginState timed out');

        try {
          final currentUser = _fbAuth.currentUser;

          if (currentUser != null) {
            // Reload the current user to force authStateChanges to trigger
            await currentUser.reload();
            _hasAuthStateChangeListenerRunAtLeastOnce = true;
            if (!_authStateCompleter!.isCompleted) {
              // Add this check
              _authStateCompleter!.complete(true);
            }
          } else {
            // Sign out to force authStateChanges to trigger
            await signOut();
            _hasAuthStateChangeListenerRunAtLeastOnce = true;
            if (!_authStateCompleter!.isCompleted) {
              // Add this check
              _authStateCompleter!.complete(false);
            }
          }
        } catch (e) {
          logd('waitForCanCheckLoginState: Error during timeout handling: $e');
          _hasAuthStateChangeListenerRunAtLeastOnce = true;
          if (!_authStateCompleter!.isCompleted) {
            // Add this check
            _authStateCompleter!.complete(false);
          }
        }
      }
    });

    // Wait for auth state to be ready
    final result = await _authStateCompleter!.future;
    timeoutTimer.cancel();
    return result;
  }

  @override
  Future<Map<T, bool>> getUserClaims<T extends Enum>({
    required List<T> enumValues,
    bool forceRefresh = false,
  }) async {
    // Handle if they are not logged in
    final user = _fbAuth.currentUser;
    if (user == null) {
      logd('AuthService: Current user is null! (getUserClaims()');
      return <T, bool>{};
    }

    var userClaims = <T, bool>{};
    var tokenResult = await user.getIdTokenResult(forceRefresh);

    // For each tokenResult.claims, add it to the userClaims list if it matches an enum value
    for (var entry in (tokenResult.claims?.entries ?? <MapEntry<String, dynamic>>[])) {
      var key = entry.key;
      var value = entry.value;

      for (var enumValue in enumValues) {
        if (enumValue.name == key) {
          userClaims[enumValue] = value as bool;
        }
      }
    }

    return userClaims;
  }

  String _lastUsedPhoneNumberForLogin = '';
  String _phoneVerificationId = '';
  int? _resendToken;

  @override
  Future<Either<PhoneAuthError, Unit>> loginWithPhone(
    String phoneNumber, {
    required Function verificationCompleted,
    required Function(PhoneAuthError) verificationFailed,
    required Function codeSent,
    required Function codeAutoRetrievalTimeout,
    // Note: this is unused right now because the code kind of handles either case
    required bool codeResend,
  }) async {
    assert(phoneNumber.isNotEmpty);

    // Normalize the phone number

    if (_lastUsedPhoneNumberForLogin != phoneNumber) {
      logd('AuthService: Phone number changed, clearing resend token');
      _resendToken = null;
    }

    try {
      await _fbAuth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        forceResendingToken: _resendToken,
        verificationCompleted: (PhoneAuthCredential credential) async {
          // Only on Android
          // This callback will be here for instant verification and auto-retrieval. For those cases, we can sign in the user directly
          await _fbAuth.signInWithCredential(credential);
          verificationCompleted();
        },
        verificationFailed: (FirebaseAuthException fe) {
          // Handle failed verification
          loge(fe, 'verificationFaild');

          if (fe.code == 'invalid-phone-number') {
            verificationFailed(PhoneAuthError.invalidPhoneNumber);
          } else if (fe.code == 'user-disabled') {
            verificationFailed(PhoneAuthError.userDisabled);
          } else if (fe.code == 'captcha-check-failed') {
            verificationFailed(PhoneAuthError.captchaCheckFailed);
          } else if (fe.code == 'too-many-requests') {
            verificationFailed(PhoneAuthError.tooManyRequests);
          } else {
            verificationFailed(PhoneAuthError.unexpected);
          }
        },
        codeSent: (String verificationId, int? resendToken) {
          _lastUsedPhoneNumberForLogin = phoneNumber;
          _phoneVerificationId = verificationId;
          _resendToken = resendToken;
          codeSent();
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          // Auto-retrieval timeout
          codeAutoRetrievalTimeout();
        },
      );
    } on FirebaseException catch (fe) {
      loge(fe);
      if (fe.code == 'invalid-phone-number') {
        return left(PhoneAuthError.invalidPhoneNumber);
      } else if (fe.code == 'user-disabled') {
        return left(PhoneAuthError.userDisabled);
      } else if (fe.code == 'captcha-check-failed') {
        return left(PhoneAuthError.captchaCheckFailed);
      } else if (fe.code == 'too-many-requests') {
        return left(PhoneAuthError.tooManyRequests);
      } else {
        return left(PhoneAuthError.unexpected);
      }
    } catch (e) {
      loge(e);
      return left(PhoneAuthError.unexpected);
    }

    return right(unit);
  }

  @override
  Future<Either<PhoneAuthError, bool>> loginWithPhoneVerifyCode(String smsCode) async {
    try {
      // Create a PhoneAuthCredential with the verification ID and the SMS code
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: _phoneVerificationId,
        smsCode: smsCode,
      );

      // Sign in the user with the credential
      await _fbAuth.signInWithCredential(credential);

      return right(true);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'invalid-verification-code') {
        return left(PhoneAuthError.wrongSmsCode);
      } else if (e.code == 'session-expired') {
        return left(PhoneAuthError.smsCodeExpired);
      } else if (e.code == 'invalid-verification-id') {
        return left(PhoneAuthError.sessionExpired);
      } else if (e.code == 'user-not-found') {
        return left(PhoneAuthError.invalidPhone);
      } else {
        logd(
            'e.code was something unhandled in loginWithPhoneVerifyCode:${e.message ?? 'no message'}');
        return left(PhoneAuthError.unexpected);
      }
    } catch (e) {
      loge(e);
      return left(PhoneAuthError.unexpected);
    }
  }

  @override
  Future<Either<AuthServiceSignInFailure, Unit>> checkIfSignedInAndLoginAnonymouslyIfNot() async {
    try {
      if (AppConfigBase.devOnlyUid.isNotEmpty || AppConfigBase.devOnlyAutoGenerateNewUser) {
        await signInWithDevOnly();
        // await refreshCurrentUser();
        return right(unit);
      }

      // Login anonymously if not
      if (_fbAuth.currentUser == null) {
        logd('AuthService: LOGGING IN ANONYMOUSLY');

        // logd('AuthService: ${AppConfigBase.backendRegion}');
        // logd('AuthService: ${AppConfigBase.doUseBackendEmulator}');
        // logd('AuthService: ${AppConfigBase.backendEmulatorRemoteAddress}');
        // logd('AuthService: ${_fbFunctions.app.options.asMap}');
        // logd('AuthService: ${_fbFunctions.app.options.appId}');
        // logd('AuthService: ${_fbFunctions.app.name}');

        // await _fbAuth.signInAnonymously();

        var result = await retryIt(() async {
          return await authCallable.call({
            'action': 'loginAnonymously',
            'timezone': (await FlutterTimezone.getLocalTimezone()).identifier,
          });
        }, maxAttempts: 8);

        final String token = result.data['token'];

        await retryIt(
          () async => await _fbAuth.signInWithCustomToken(token),
          maxAttempts: 8,
        );
      }
      return right(unit);
    } catch (e) {
      loge(e);
      return left(AuthServiceSignInFailure.unexpected);
    }
  }

  @override
  Future<Either<AuthServiceSignInFailure, Unit>> registerUserWithJustEmail(String email) async {
    try {
      // Call the function to register the user with a random password

      final packageInfo = await AppConfigBase.getPackageInfo();
      var result = await authCallable.call({
        'action': 'registerWithJustEmail',
        'email': email,
        'isForApp': true, // deprecated: use bundleId
        'bundleId': packageInfo.packageName,
      });

      if (result.data['result'] == 'exists') {
        return left(AuthServiceSignInFailure.userAlreadyExists);
      }

      // logd('registerUserWithJustEmail result: ${result.data}');

      // Sometimes we can't sign in right away after creating the account
      const int maxRetries = 8;
      int i = 0;
      for (i; i < maxRetries; i++) {
        try {
          await _fbAuth.signInWithEmailAndPassword(
            email: email,
            password: result.data['password'],
          );
        } on fb_auth.FirebaseAuthException catch (f) {
          if (f.code == 'user-not-found') {
            logd('AUTH SIGN IN FAILED. Waiting a second then trying again');
            await Future.delayed(signInRetryDelay);
            continue;
          } else {
            loge(f);
            return left(AuthServiceSignInFailure.unexpected);
          }
        }
        break;
      }

      if (i >= maxRetries) {
        return left(AuthServiceSignInFailure.signInTimedOut);
      }

      logd('Signed in with one time password');

      return right(unit);
    } on FirebaseFunctionsException catch (e) {
      logd('registerUserWithJustEmail FirebaseFunctionsException: ${e.message}');
      switch (e.message) {
        case 'email-already-in-use':
          return left(AuthServiceSignInFailure.userAlreadyExists);
        case 'weak-password':
          return left(AuthServiceSignInFailure.weakPassword);
        case 'invalid-email':
          return left(AuthServiceSignInFailure.invalidEmail);
        default:
          return left(AuthServiceSignInFailure.unexpected);
      }
    } catch (e) {
      logd('registerUserWithJustEmail other exception');
      loge(e);
      return left(AuthServiceSignInFailure.unexpected);
    }
  }

  @override
  Future<Either<AuthServiceSignInFailure, Unit>> sendLoginEmail(String email) async {
    try {
      final packageInfo = await AppConfigBase.getPackageInfo();
      await authCallable.call({
        'action': 'emailLoginLink',
        'email': email,
        'isForApp': !kIsWeb, // deprecated: use bundleId
        'bundleId': packageInfo.packageName,
      });

      // if (result.data['result'] == 'exists') {
      //   return left(AuthServiceSignInFailure.userAlreadyExists);
      // }

      // logd('sendLoginEmail result: ${result.data}');

      return right(unit);
    } catch (e) {
      return left(AuthServiceSignInFailure.unexpected);
    }
  }

  @override
  Future<Either<AuthServiceSignInFailure, Unit>> signInWithEmailAndPassword(
      String email, String password) async {
    try {
      var userCred = await _fbAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (userCred.user == null) {
        return left(AuthServiceSignInFailure.userNotFound);
      }

      await waitForCanCheckLoginState();

      return right(unit);

      //return right(currentUser.value);
    } on fb_auth.FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'invalid-email':
          logd('signInWithEmailAndPassword invalid-email');
          return left(AuthServiceSignInFailure.invalidEmail);
        case 'user-not-found':
          logd('signInWithEmailAndPassword user-not-found');
          return left(AuthServiceSignInFailure.userNotFound);
        case 'wrong-password':
          logd('signInWithEmailAndPassword wrong-password');
          return left(AuthServiceSignInFailure.wrongPassword);
        case 'invalid-credential':
          logd('signInWithEmailAndPassword invalid-credential');
          return left(AuthServiceSignInFailure.wrongPassword);
        case 'user-disabled':
          logd('signInWithEmailAndPassword user-disabled');
          return left(AuthServiceSignInFailure.userDisabled);
        default:
          logd('signInWithEmailAndPassword default exception');
          return left(AuthServiceSignInFailure.unexpected);
      }
    } catch (e) {
      loge(e);
      return left(AuthServiceSignInFailure.unexpected);
    }
  }

  @override
  Future<Either<AuthServiceSignInFailure, Unit>> registerUserWithEmailAndPassword(
      String email, String password) async {
    try {
      // Call the function to create the auth user and db user
      var result = await authCallable.call({
        'action': 'authRegisterWithEmailAndPassword',
        'email': email,
        'password': password,
      });

      logd('Register result: ${result.data}');

      // // Create the auth user
      // fb_auth.UserCredential userCred =
      //     await _auth.createUserWithEmailAndPassword(email: email, password: password);

      // if (userCred.user == null) {
      //   return left(AuthServiceSignInFailure.unexpected);
      // }

      // // Create, Get the firebase user and return
      // var dbCreateResult = await Get.find<UserRepositoryInt>().createUserIfNotExist(User(
      //   id: userCred.user!.uid,
      //   email: email,
      // ));

      // // Determine outcome
      // Either<AuthServiceSignInFailure, User> returnVal = dbCreateResult.fold(
      //   (failure) {
      //     return failure.maybeWhen(
      //       orElse: () => left(AuthServiceSignInFailure.databaseError()),
      //     );
      //   },
      //   (success) {
      //     currentUser.value = success;
      //     return right(success);
      //   },
      // );

      // // Finally return
      // return returnVal;

      // Sometimes we can't sign in right away after creating the account
      const int maxRetries = 5;
      int i = 0;
      for (i; i < maxRetries; i++) {
        try {
          await _fbAuth.signInWithEmailAndPassword(email: email, password: password);
        } on fb_auth.FirebaseAuthException catch (f) {
          if (f.code == 'user-not-found') {
            logd('AUTH SIGN IN FAILED. Waiting a second then trying again');
            await Future.delayed(signInRetryDelay);
            continue;
          } else {
            loge(f);
            return left(AuthServiceSignInFailure.unexpected);
          }
        }
        break;
      }
      if (i >= maxRetries) {
        return left(AuthServiceSignInFailure.signInTimedOut);
      }

      return right(unit);
    } on FirebaseFunctionsException catch (e) {
      logd('registerUserWithEmailAndPassword FirebaseFunctionsException: ${e.message}');
      switch (e.message) {
        case 'email-already-in-use':
          return left(AuthServiceSignInFailure.userAlreadyExists);
        case 'weak-password':
          return left(AuthServiceSignInFailure.weakPassword);
        case 'invalid-email':
          return left(AuthServiceSignInFailure.invalidEmail);
        default:
          return left(AuthServiceSignInFailure.unexpected);
      }
    } catch (e) {
      logd('registerUserWithEmailAndPassword other exception');
      loge(e);
      return left(AuthServiceSignInFailure.unexpected);
    }
  }

  @override
  Future<Either<AuthServiceSignInFailure, Unit>> resetPassword(String email) async {
    try {
      logd('resetPassword: Sending password reset email to $email');
      await _fbAuth.sendPasswordResetEmail(email: email);
      logd('resetPassword: Password reset email sent successfully');
      return right(unit);
    } on fb_auth.FirebaseAuthException catch (e) {
      loge(e, 'resetPassword failed');
      switch (e.code) {
        case 'invalid-email':
          return left(AuthServiceSignInFailure.invalidEmail);
        case 'user-not-found':
          return left(AuthServiceSignInFailure.userNotFound);
        default:
          return left(AuthServiceSignInFailure.unexpected);
      }
    } catch (e) {
      loge(e, 'resetPassword failed');
      return left(AuthServiceSignInFailure.unexpected);
    }
  }

  @override
  Future<Either<AuthServiceSignInFailure, Unit>> setPassword(String newPassword) async {
    try {
      await authCallable.call({
        'action': 'authSetPassword',
        'password': newPassword,
      });

      return right(unit);
    } catch (e) {
      loge(e);
      return left(AuthServiceSignInFailure.unexpected);
    }
  }

  @override
  Future<Either<AuthServiceSignInFailure, Unit>> signInWithEmail(String email) async {
    try {
      // Save the email for later
      // GetStorage().write(Constants.boxKeyUserSignInWithLinkEmail, email);
      // Send the email
      await _fbAuth.sendSignInLinkToEmail(
        email: email,
        actionCodeSettings: await _createActionCodeSettingsAsync(),
      );
      // For UI
      await Future.delayed(const Duration(seconds: 1));
      return right(unit);
    } on fb_auth.FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'invalid-email':
          return left(AuthServiceSignInFailure.invalidEmail);
        default:
          return left(AuthServiceSignInFailure.unexpected);
      }
    } catch (e) {
      loge(e);
      return left(AuthServiceSignInFailure.unexpected);
    }
  }

  @override
  Future<Either<AuthServiceEmailLinkFailure, Unit>> validateEmailLink(String link,
      {String? email}) async {
    String? storedEmail;

    var uriLink = Uri.parse(link);

    if (uriLink.host != 'localhost' && (!_fbAuth.isSignInWithEmailLink(link))) {
      logd('isSignInWithEmailLink failed');
      return left(AuthServiceEmailLinkFailure.invalidLink);
    } else {
      // The email is embedded in the link URL by the server (sendLoginEmail.ts)
      // and validated by Firebase against the oobCode — client-side email
      // validation is unnecessary.
      storedEmail = email;

      if (storedEmail == null) {
        return left(AuthServiceEmailLinkFailure.noEmailRemembered);
      }

      logd('storedEmail: $storedEmail');
      logd('link: $link');

      try {
        // Do the signin
        var signInResult = await _fbAuth.signInWithEmailLink(
          email: storedEmail,
          emailLink: link,
        );

        assert(signInResult.user != null);
        currentFbUserCredentials = signInResult;

        return right(unit);
      } on fb_auth.FirebaseAuthException catch (e) {
        loge(e);
        switch (e.code) {
          case 'invalid-action-code':
            return left(AuthServiceEmailLinkFailure.invalidCode);
          case 'invalid-email':
            return left(AuthServiceEmailLinkFailure.invalidEmail);
          case 'expired-action-code':
            return left(AuthServiceEmailLinkFailure.expiredCode);
          case 'user-disabled':
            return left(AuthServiceEmailLinkFailure.userDisabled);
          default:
            return left(AuthServiceEmailLinkFailure.unexpected);
        }
      } catch (e) {
        loge(e);
        return left(AuthServiceEmailLinkFailure.unexpected);
      }
    }
  }

  /// The email-confirm route. Must match all of:
  ///  - server-side `sendLoginEmail.ts` path component
  ///  - consuming app's web router route
  ///  - AndroidManifest.xml intent-filter `pathPrefix`
  ///  - iOS associated domains `paths` entry
  static const String _emailConfirmPath = '/emailconfirm';

  Future<fb_auth.ActionCodeSettings> _createActionCodeSettingsAsync() async {
    if (kIsWeb) {
      // Web: derive from the running page. Zero config — works in dev,
      // staging, and prod. Constructs from components (not Uri.base.replace)
      // to avoid leaking query params or fragment from the current page URL.
      // Use hasPort to avoid redundant :443/:80 in production URLs
      // while preserving explicit dev ports (e.g., localhost:5000).
      return fb_auth.ActionCodeSettings(
        url: Uri(
          scheme: Uri.base.scheme,
          host: Uri.base.host,
          port: Uri.base.hasPort ? Uri.base.port : null,
          path: _emailConfirmPath,
        ).toString(),
        handleCodeInApp: true,
      );
    }

    // Mobile: escape hatch first — consuming app fully owns construction
    // for FDL / linkDomain / Branch / AppsFlyer / etc.
    final builder = AppConfigBase.mobileEmailLinkActionCodeSettingsBuilder;
    if (builder != null) {
      return await builder();
    }

    // Default: plain App Links / Universal Links pattern.
    final origin = AppConfigBase.emailConfirmMobileOrigin;
    if (origin.isEmpty) {
      throw StateError(
        'Mobile email-link auth requires one of:\n'
        '  (1) AppConfigBase.emailConfirmMobileOriginDefault = '
        '"https://yourapp.com" — for plain App Links / Universal Links, OR\n'
        '  (2) AppConfigBase.mobileEmailLinkActionCodeSettingsBuilder = '
        '() async { ... } — for Firebase Dynamic Links, linkDomain, '
        'Branch, AppsFlyer, or other deferred-deep-link services.',
      );
    }

    final packageInfo = await AppConfigBase.getPackageInfo();
    return fb_auth.ActionCodeSettings(
      url: '$origin$_emailConfirmPath',
      handleCodeInApp: true,
      androidPackageName: packageInfo.packageName,
      iOSBundleId: packageInfo.packageName,
    );
  }

  @override
  Future<Either<AuthServiceSignInFailure, bool>> isEmailUser(String email) async {
    try {
      var result = await authCallable.call({
        'action': 'authIsEmailUser',
        'email': email,
      });

      return right(result.data['exists'] as bool);
    } catch (e) {
      loge(StackTrace.current, 'Error checking if email exists in auth: $e');
      return left(AuthServiceSignInFailure.unexpected);
    }
  }

  @override
  Future<Either<RepositoryFailure, (AccessCodeCheckReturn validity, String welcomeMessage)>>
      accessCodeCheckIfValid(
    String code,
  ) async {
    logd('accessCodeCheckIfValid: $code');
    try {
      // Submit the code
      var result = await retryIt(() async => await authCallable.call(
            {
              'action': 'accessCodeCheck',
              'accessCode': code,
              'timezone': (await FlutterTimezone.getLocalTimezone()).identifier,
            },
          ));

      // HttpsCallableResult.data returns Map<Object?, Object?>, not Map<String, dynamic>
      final data = safeResultData(result);

      // Check if the code is valid
      if (data['result'] != 'valid') {
        logd('checkAccessCode: invalid code');
        return right((AccessCodeCheckReturn.invalidCode, ''));
      }

      // Save the access code
      logd('checkAccessCode: valid code');
      _accessCodeCached = code;

      return right((AccessCodeCheckReturn.valid, data['welcomeMessage']));
    } catch (e) {
      loge(StackTrace.current, e.toString());
      return const Left(RepositoryFailure.unexpected);
    }
  }

  @override
  Future<Either<RepositoryFailure, bool>> accessCodeIsValidCached() {
    if (_accessCodeCached == null || _accessCodeCached!.isEmpty) {
      return Future.value(right(false));
    } else {
      return Future.value(right(true));
    }
  }

  @override
  Future<Either<AuthServiceSignInFailure, Unit>> accessCodeRegisterWithEmailAndPassword(
    String email,
    String password,
  ) async {
    try {
      var result = await authCallable.call({
        'action': 'authRegisterWithEmailAndPasswordAndCode',
        'email': email,
        'password': password,
        'accessCode': _accessCodeCached,
      });

      String token = result.data['token'];

      logd('registerWithEmailAndPassword token: $token');

      await retryIt(
        () async => await _fbAuth.signInWithCustomToken(token),
        maxAttempts: 8,
      );

      return right(unit);

      // if (result.data['result'] == 'exists') {
      //   return left(const AuthServiceSignInFailure.userAlreadyExists());
      // }
      // Note: the function may not actually return any of these
    } on FirebaseFunctionsException catch (e) {
      logd('registerUserWithEmailAndPassword FirebaseFunctionsException: ${e.message}');
      switch (e.message) {
        case 'email-already-in-use':
          return left(AuthServiceSignInFailure.userAlreadyExists);
        case 'weak-password':
          return left(AuthServiceSignInFailure.weakPassword);
        case 'invalid-email':
          return left(AuthServiceSignInFailure.invalidEmail);
        default:
          return left(AuthServiceSignInFailure.unexpected);
      }
    } catch (e) {
      logd('registerUserWithEmailAndPassword other exception');
      loge(e);
      return left(AuthServiceSignInFailure.unexpected);
    }
  }

  //
  // Dev Only
  //

  @override
  Future<Either<AuthServiceSignInFailure, Unit>> signInWithDevOnly() async {
    _fbAuth.signOut();

    HttpsCallable devActionsCallable =
        AppConfigBase.firebaseFunctionCallable(AppConfigBase.devActionsFunction);

    var result = await devActionsCallable.call({
      'action': 'signInWithUserId',
      'uid': AppConfigBase.devOnlyUid,
      'autoGenerateNewUser': AppConfigBase.devOnlyAutoGenerateNewUser,
      'autoGenerateNewUserAccessLevel': AppConfigBase.devOnlyAutoGenerateNewUserAccessLevel,
    });
    logd('result.data: ${result.data}');

    // var customToken = jsonDecode(result.data)['customToken'];
    var customToken = result.data['customToken'];
    logd('customToken: $customToken');

    // await Future.delayed(Duration(seconds: 2));

    await _fbAuth.signInWithCustomToken(customToken);

    return right(unit);
  }

  @override
  Future<Either<AuthServiceSignInFailure, Unit>> signInWithCustomToken(String customToken) async {
    try {
      await retryIt(
        () async => await _fbAuth.signInWithCustomToken(customToken),
        maxAttempts: 3,
      );

      return right(unit);
    } catch (e) {
      loge(e);
      return left(AuthServiceSignInFailure.unexpected);
    }
  }
}
