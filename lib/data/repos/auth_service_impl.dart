import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:dartz/dartz.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:dreamic/data/helpers/repository_failure.dart';
import 'package:dreamic/utils/retry_it.dart';
import 'package:dreamic/data/helpers/repo_helpers.dart';
import 'package:dreamic/data/models/login_code_request.dart';
import 'package:dreamic/data/models/login_code_response.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
// import 'package:http/browser_client.dart';

// import '../../common/bloc_exception.dart';
import '../../app/app_config_base.dart';
import '../../utils/logger.dart';
import 'auth_service_int.dart';

const String sharedPrefKeyFcmToken = 'commonSharedKeyFcmToken';
//TODO: use this to update the server when it changes
const String sharedPrefKeyTimezone = 'commonSharedKeyTimezone';

//TODO: this doesn't work with both anon auth and federated auth, but it could

class AuthServiceImpl implements AuthServiceInt {
  Future<void> Function(String? uid)? onAuthenticated;
  Future<void> Function()? onRefreshed;
  Future<void> Function()? onLoggedOut;

  /// Whether to use Firebase FCM for push notifications
  /// This is the general setting, which can be disabled by the app config setting, but not overridden to enable FCM by the app config.
  bool useFirebaseFCM;
  HttpsCallable authCallable =
      AppConfigBase.firebaseFunctionCallable(AppConfigBase.authMainCallableFunction);
  late final fb_auth.FirebaseAuth _fbAuth;

  // bool _hasGottenUserPrivate = false;
  bool _hasAuthStateChangeListenerRunAtLeastOnce = false;
  bool _hasInitializedFCM = false;
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
    //TODO: This is done to appease the compiler...
    throw StateError('Cannot set this value programmatically');
  }

  AuthServiceImpl({
    required FirebaseApp firebaseApp,
    required this.useFirebaseFCM,
    this.onAuthenticated,
    this.onRefreshed,
    this.onLoggedOut,
  }) {
    // This can be disabled for hardcoding
    logd('Instantiated AuthServiceImpl');
    _fbAuth = fb_auth.FirebaseAuth.instanceFor(app: firebaseApp);
    _fbAuth.authStateChanges().listen(handleAuthStateChanges);
    _fbAuth.idTokenChanges().listen((event) => handleTokenChanges(event));

    // For debuggin
    if (AppConfigBase.signoutOnReload) {
      // _fbAuth.signOut();
      signOut();
    }
  }

  // Add dispose method to clean up the stream controller
  void dispose() {
    _isLoggedInStreamController.close();
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

      await onAuthenticated?.call(fbUser.uid);
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
      //TODO: added this here but not sure it needs to do this again...
      // await refreshCurrentUser();

      if (useFirebaseFCM) {
        // Initialize FCM if app config allows it
        if (AppConfigBase.useFCM) {
          await initFCM();
        } else {
          logd('FCM is disabled in AppConfigBase, not initializing FCM');
        }
      }
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
      //TODO: temp disabled
      // if (client is BrowserClient) {
      //   client.withCredentials = true;
      // }

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
      if (useFbAuthAlso) {
        await _fbAuth.signOut();
      }

      // Call the optional callback
      await onLoggedOut?.call();

      // Clear the cookie on the server if using federated auth
      if (AppConfigBase.useCookieFederatedAuth) {
        final http.Client client = http.Client();

        final response = await client
            .get(Uri.parse(RepoHelpers.getFunctionUrl(_fbAuth.app, 'authfunctions-signout')));

        if (response.statusCode == 204) {
          logd('Cleared cookie successfully');
        } else {
          logd('Failed to clear cookie!!');
          // Don't return error for cookie clear failure
        }
      }

      // Clear the stored user info
      SharedPreferences prefs = await SharedPreferences.getInstance();

      await prefs.remove(sharedPrefKeyFcmToken);
      await prefs.remove(sharedPrefKeyTimezone);

      _hasInitializedFCM = false;
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
      // Get token without forcing refresh - uses cached token if valid
      final token = await _fbAuth.currentUser!.getIdToken(false);
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

      // This will use Firebase's automatic token management
      final token = await _fbAuth.currentUser!
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
        return false; // Add this line
      }
    } catch (e) {
      logd('_attemptCookieAuth: Cookie auth failed: $e');
      return false; // Add this line
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

  // @override
  // Future<bool> waitForUserPrivateRefreshed() async {
  //   // logd('waitForCanCheckLoginState called');

  //   // while (_hasTriedToGetCurrentUserPrivate == false) {

  //   //TODO: set a
  //   while (_hasGottenUserPrivate == false) {
  //     logd('waitForUserPrivateRefreshed loop');
  //     await Future.delayed(const Duration(milliseconds: 50));
  //   }

  //   // logd('waitForCanCheckLoginState FINISHED');

  //   return _hasGottenUserPrivate;
  // }

  // @override
  // Future<Either<RepositoryFailure, UserPrivate>> getCurrentUserPrivate() {

  // }

  @override
  Future<Map<T, bool>> getUserClaims<T extends Enum>({
    required List<T> enumValues,
    bool forceRefresh = false,
  }) async {
    // Handle if they are not logged in
    if (_fbAuth.currentUser == null) {
      logd('AuthService: Current user is null! (getUserClaims()');
      return <T, bool>{};
    }

    var userClaims = <T, bool>{};
    var tokenResult = await _fbAuth.currentUser!.getIdTokenResult(forceRefresh);

    // For each tokenResult.claims, add it to the userClaims list if it matches an enum value
    for (var entry in tokenResult.claims!.entries) {
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

  // @override
  // Future<Either<AuthServiceSignInFailure, UserPrivate>> refreshCurrentUser() async {
  //   logd('REFRESHING CURRENT USER');

  //   // if (_fbAuth.currentUser != null) {
  //   //   if (_fbAuth.currentUser!.isAnonymous) {
  //   //     // Create a standard anonymous profile
  //   //     logd('AuthService: Current user is anonymous!');
  //   //     currentUser = UserPrivate(
  //   //       firstName: 'Anonymous',
  //   //       lastName: 'User',
  //   //       userType: UserType.anonymous,
  //   //     );
  //   //     // if (kDebugMode)
  //   //     // {
  //   //     //   _auth.app
  //   //     // }
  //   //   } else {
  //   // Get database user
  //   (await Get.find<UserRepoInt>().getMyUserPrivate()).fold(
  //     (failure) {
  //       failure.maybeWhen(
  //         expectedRecordNotFound: () {
  //           logd('AuthService: Couldnt find database user for auth user. Signing out...');
  //           _hasGottenUserPrivate = false;
  //           _fbAuth.signOut();
  //         },
  //         orElse: () {
  //           logd('AuthService: Unknown failure getting db user for auth user');
  //           //TODO: Which error should we throw here?
  //           throw BlocRetryableException();
  //         },
  //       );
  //     },
  //     (success) {
  //       // logd('AuthService: Sucessfully found db user for auth user');
  //       logd('AuthService: Sucessfully found db user for auth user: ${success.id}');
  //       currentUserPrivate = success;
  //       _hasGottenUserPrivate = true;
  //     },
  //   );

  //   //TODO: need more logic around this. SHould we clear cache when refreshing??????????????
  //   if (_hasGottenUserPrivate) {
  //     // await GetIt.I.get<InputRepoInt>().getMyInputCached();
  //     await onRefreshed?.call();
  //   }
  //   //   }
  //   // } else {
  //   //   logd('AuthService: fbUser is null. Must be signed out');
  //   //   currentUser = UserPrivate();
  //   // }

  //   logd('REFRESHING CURRENT USER FINISHED');

  //   return right(unit);
  // }

  // Future<Either<AuthServiceSignInFailure, Unit>> signInOrUpFirstStep(String email, String password) {

  // }

  // Future<Either<AuthServiceSignInFailure, Unit>> signInOrUpFirstStep(String email, String password) {

  // }

  @override
  Future<Either<AuthServiceSignInFailure, LoginCodeResponse>> loginWithCode(String code) async {
    try {
      var result = await authCallable.call(LoginCodeRequest(loginCode: code).toJson());

      return right(LoginCodeResponse.fromJson(result.data));
    } catch (e) {
      loge(e);
      return left(AuthServiceSignInFailure.wrongPassword);
    }
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
    //TODO: this is unused right now because the code kind of handles either case
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

      //TODO: handle the Firebase Errors to see if the code was wrong
      return right(true);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'invalid-verification-code') {
        // print('The provided verification code is invalid.');
        return left(PhoneAuthError.wrongSmsCode);
        // Handle invalid verification code
      } else if (e.code == 'user-not-found') {
        // print('No user found with this phone number.');
        return left(PhoneAuthError.invalidPhone);
        // Handle no user found
      } else {
        logd(
            'e.code was something unhandled in loginWithPhoneVerifyCode:${e.message ?? 'no message'}');
        // Handle other Firebase auth errors
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

      var result = await authCallable.call({
        'action': 'registerWithJustEmail',
        'email': email,
        //TODO: pass the bundle ID or something like that to know whihc app is calling. Using isForApp is legacy and should be removed after the existing functions are updated
        'isForApp': true,
      });

      if (result.data['result'] == 'exists') {
        return left(AuthServiceSignInFailure.userAlreadyExists);
      }

      // logd('registerUserWithJustEmail result: ${result.data}');

      // Sometimes we can't sign in right away after creating the account
      const int maxRetries = 8;
      int i = 0;
      for (i; i < maxRetries; i++) {
        bool hadError = false;

        try {
          await _fbAuth.signInWithEmailAndPassword(
            email: email,
            password: result.data['password'],
          );
        } on fb_auth.FirebaseAuthException catch (f) {
          hadError = true;
          //TODO: should this be "firebase_auth/user-not-found" now?
          // if (f.message == 'user-not-found') {
          // Delay
          loge(f);
          // } else {
          // rethrow;
          // }
        }

        if (hadError) {
          logd('AUTH SIGN IN FAILED. Waiting a second then trying again');
          await Future.delayed(const Duration(seconds: 1));
          continue;
        }
        // Got here so there's no error
        break;
      }

      if (i >= maxRetries) {
        //TODO: a better error?

        return left(AuthServiceSignInFailure.unexpected);
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
      await authCallable.call({
        'action': 'emailLoginLink',
        'email': email,
        //TODO: pass the bundle ID or something like that to know whihc app is calling. Using isForApp is legacy and should be removed after the existing functions are updated
        'isForApp': !kIsWeb,
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
      // _hasGottenUserPrivate = false;

      var userCred = await _fbAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Have to get this here so we'll know if the user finished setup yet
      // (await Get.find<UserRepositoryInt>().getUserById(credential.user!.uid)).fold(
      //   (failure) => currentUser.value = User(),
      //   (success) => currentUser.value = success,
      // );

      //TODO: duplicate code because the user could quit right after login

      // Create, Get the firebase user and return
      // var dbCreateResult = await Get.find<UserRepoInt>().createUserIfNotExist(User(
      //   id: userCred.user!.uid,
      //   email: email,
      // ));

      // Determine outcome
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

      // Finally return

      if (userCred.user == null) {
        return left(AuthServiceSignInFailure.userNotFound);
      }

      await waitForCanCheckLoginState();

      // UserPrivate returnValUser =
      //     (await Get.find<UserRepoInt>().getUserPrivateById(userCred.user!.uid)).fold(
      //   (failure) => throw Exception(),
      //   (success) => success,
      // );

      //await refreshCurrentUser();

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
          if (f.message == 'user-not-found') {
            // Delay
            logd('AUTH SIGN IN FAILED. Waiting a second then trying again');
            await Future.delayed(const Duration(seconds: 1));
            continue;
          } else {
            rethrow;
          }
        }
        break;
      }
      if (i >= maxRetries) {
        //TODO: a better error?
        return left(AuthServiceSignInFailure.unexpected);
      }

//TODO: is this redundant? Because I'm not sure it gets it in tiem without it
      //await refreshCurrentUser();

      return right(unit);
      // } on fb_auth.FirebaseAuthException catch (e) {
      //   switch (e.code) {
      //     case 'invalid-email':
      //       logd('registerUserWithEmailAndPassword invalid-email');
      //       return left(AuthServiceSignInFailure.invalidEmail);
      //     case 'email-already-in-use':
      //       logd('registerUserWithEmailAndPassword email-already-in-use');
      //       return left(AuthServiceSignInFailure.userAlreadyExists);
      //     case 'weak-password':
      //       logd('registerUserWithEmailAndPassword weak-password');
      //       return left(AuthServiceSignInFailure.weakPassword);
      //     default:
      //       logd('registerUserWithEmailAndPassword default');
      //       return left(AuthServiceSignInFailure.unexpected);
      //   }
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
        actionCodeSettings: _createActionCodeSettings(),
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
      // Get the email from storage if we can
      // if (email == null) {
      //   storedEmail = GetStorage().read(Constants.boxKeyUserSignInWithLinkEmail);
      // } else {
      //   storedEmail = email;
      // }

      // If email is still null, we need to ask the user
      // if (storedEmail == null) {
      //   return left(AuthServiceEmailLinkFailure.noEmailRemembered());
      // }

      //TODO: sure we want to rely on this email being passed?
      storedEmail = email;

      logd('storedEmail: $storedEmail');
      logd('link: $link');

      try {
        // Do the signin
        var signInResult = await _fbAuth.signInWithEmailLink(
          email: storedEmail!,
          emailLink: link,
        );

        assert(signInResult.user != null);
        currentFbUserCredentials = signInResult;

        // Don't need the temp storage anymore
        // GetStorage().remove(Constants.boxKeyUserSignInWithLinkEmail);

        // Create, Get the firebase user and return
        //TODO: broken due to separating private data
        // var dbCreateResult = await Get.find<UserRepoInt>().createUserIfNotExist(User(
        //   id: currentFbUserCredentials!.user!.uid,
        //email: currentFbUserCredentials!.user!.email!,
        // ));

        // Determine outcome
        // Either<AuthServiceEmailLinkFailure, Unit> returnVal = dbCreateResult.fold(
        //   (failure) {
        //     return failure.maybeWhen(
        //       orElse: () => left(AuthServiceEmailLinkFailure.databaseError()),
        //     );
        //   },
        //   (success) {
        //     currentUser.value = success;
        //     return right(unit);
        //   },
        // );

        // Finally return
        // return returnVal;

        //TODO: make sure this doesn't return before getting the user info loaded
        await isLoggedInAsync();

        // final response = await http.get(Uri.parse(url), headers: {
        //   'Authorization': 'Bearer $token',
        // });

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

  fb_auth.ActionCodeSettings _createActionCodeSettings() {
    if (kIsWeb) {
      return fb_auth.ActionCodeSettings(
        //TODO: localhost url
        url: 'http://localhost:${Uri.base.port}/emailconfirm',
        handleCodeInApp: true,
      );
    } else {
      //final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      return fb_auth.ActionCodeSettings(
        url: 'https://xyz.page.link/emailconfirm}',
        handleCodeInApp: true,
        androidPackageName: 'family.milestone.milestone_app',
        iOSBundleId: 'family.milestone.milestoneApp',
      );
    }
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

      final data = result.data as Map<String, dynamic>;

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
      //TODO: I don' think the function actually returns any of these
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

    HttpsCallable devOnlyCallable =
        AppConfigBase.firebaseFunctionCallable(AppConfigBase.devOnlyDevSignInFunction);

    var result = await devOnlyCallable.call({
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

  //
  //
  // FCM
  //
  //

  Future<void> initFCM() async {
    logd('Initializing FCM with _hasInitializedFCM = $_hasInitializedFCM');

    try {
      FirebaseMessaging messaging = FirebaseMessaging.instance;

      // Request permission for iOS devices
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      //TODO: do we need to do something with the settings?
      // NotificationSettings settings = await messaging.requestPermission(
      //   alert: true,
      //   badge: true,
      //   sound: true,
      // );

      // For apple platforms, ensure the APNS token is available before making any FCM plugin API calls
      String? apnsToken;
      if (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS) {
        // Wait for APNS token to be available
        int retries = 0;
        while (apnsToken == null && retries < 30) {
          apnsToken = await messaging.getAPNSToken();
          if (apnsToken == null) {
            logd('APNS token not available yet, waiting...');
            await Future.delayed(const Duration(milliseconds: 250));
            retries++;
          }
        }
        if (apnsToken == null) {
          loge('APNS token was not set after waiting.');
          // Optionally: return or throw here
        }
      }

      SharedPreferences prefs = await SharedPreferences.getInstance();

      String? oldToken = prefs.getString(sharedPrefKeyFcmToken);
      String? newToken;

      try {
        newToken = await messaging.getToken();
      } catch (e) {
        loge('Failed to get FCM token (Firebase Installations Service may be unavailable): $e');
        // Don't propagate the error - FCM is not critical for app functionality
        return;
      }

      if (newToken != null && (newToken != oldToken || !_hasInitializedFCM)) {
        try {
          logd('Updating FCM token on server: $newToken');
          await _updateTokenOnServer(newToken, oldToken ?? "");
          await prefs.setString(sharedPrefKeyFcmToken, newToken);
        } catch (e) {
          loge('Error updating FCM token on server: $e');
        }
      }

      if (!_hasInitializedFCM) {
        messaging.onTokenRefresh.listen((newToken) async {
          SharedPreferences prefs = await SharedPreferences.getInstance();
          String? oldToken = prefs.getString(sharedPrefKeyFcmToken);
          try {
            await _updateTokenOnServer(newToken, oldToken ?? "");
            await prefs.setString(sharedPrefKeyFcmToken, newToken);
          } catch (e) {
            loge('Error updating FCM token on server: $e');
          }
        });
      }

      _hasInitializedFCM = true;
    } catch (e) {
      loge('FCM initialization failed: $e');
      // Don't set _hasInitializedFCM to true if initialization failed
      // This allows retry on next auth state change
    }
  }

  Future<void> _updateTokenOnServer(String newToken, String oldToken) async {
    // Call a Firebase function to update the token on the server.
    final data = <String, dynamic>{
      'newToken': newToken,
      'oldToken': oldToken,
      'timezone': (await FlutterTimezone.getLocalTimezone()).identifier,
    };

    if (AppConfigBase.notificationsUpdateFcmTokenUseGrouped) {
      // Grouped style: call group function with action parameter
      await AppConfigBase.firebaseFunctionCallable(
              AppConfigBase.notificationsUpdateFcmTokenGroupFunction!)
          .call(<String, dynamic>{
        'action': AppConfigBase.notificationsUpdateFcmTokenAction,
        ...data,
      });
    } else {
      // Standalone style: call function directly
      await AppConfigBase.firebaseFunctionCallable(
              AppConfigBase.notificationsUpdateFcmTokenFunction)
          .call(data);
    }
  }
}
