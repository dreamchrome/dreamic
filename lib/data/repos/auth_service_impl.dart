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
  bool useFirebaseFCM;
  HttpsCallable mainCallable = AppConfigBase.firebaseFunctionCallable('mainCallable');
  HttpsCallable authCallable = AppConfigBase.firebaseFunctionCallable('authMainCallable');
  late final fb_auth.FirebaseAuth _fbAuth;
  late final FirebaseFunctions _fbFunctions;

  // bool _hasGottenUserPrivate = false;
  bool _hasAuthStateChangeListenerRunAtLeastOnce = false;
  bool _hasInitializedFCM = false;
  String? _accessCodeCached;

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
    _fbFunctions = FirebaseFunctions.instanceFor(
      app: firebaseApp,
      region: AppConfigBase.backendRegion,
    );

    // For debuggin
    if (AppConfigBase.signoutOnReload) {
      // _fbAuth.signOut();
      signOut();
    }
  }

  Future<void> handleAuthStateChanges(fb_auth.User? fbUser) async {
    logd('handleAuthStateChanges called');

    // currentFbUser = fbUser;

    if (fbUser == null) {
      logd('fbUser is null during handleAuthStateChanges');
      // _hasGottenUserPrivate = false;
      // currentUserPrivate = UserPrivate();
      // GetIt.I.get<InputRepoInt>().clearCache();
      _hasAuthStateChangeListenerRunAtLeastOnce = true;
      signOut(useFbAuthAlso: false);
    } else {
      logd('fbUser is NOT null during handleAuthStateChanges');
      // await refreshCurrentUser();
      //TODO: added this here but not sure it needs to do this again...
      _hasAuthStateChangeListenerRunAtLeastOnce = true;
      await onAuthenticated?.call(fbUser.uid);
    }

    // Well, I moved this up because it needs to run at a very exact time
    // _hasAuthStateChangeListenerRunAtLeastOnce = true;
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
        // Initialize FCM
        await initFCM();
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

  // @override
  // bool isLoggedIn() {
  //   return _fbAuth.currentUser != null;
  // }

  @override
  Future<bool> isLoggedInAsync() async {
    await waitForCanCheckLoginState();

    var isAuthed = _fbAuth.currentUser != null;
    // logd('isLoggedInAsync isAuthed: $isAuthed');

    // DevOnly login if provided, on here if in preview mode!!
    //TODO: This is a hack, but it works for now
    if (isAuthed == false &&
        (AppConfigBase.devOnlyUid.isNotEmpty || AppConfigBase.devOnlyAutoGenerateNewUser == true)) {
      // && AppConfigBase.editorPreviewMode) {
      await signInWithDevOnly();
      // await refreshCurrentUser();
      isAuthed = true;
    }

    // See if we have a valid cookie to use for auth from a different subdomain
    if (isAuthed == false &&
        AppConfigBase.doUseBackendEmulator == false &&
        AppConfigBase.useCookieFederatedAuth == true) {
      // Create the client
      final http.Client client = http.Client();
      //TODO: temp disabled
      // if (client is BrowserClient) {
      //   client.withCredentials = true;
      // }

      // Make the request
      final response = await client
          .get(Uri.parse(RepoHelpers.getFunctionUrl(_fbAuth.app, 'authfunctions-checkstatus')));

      // Check the response
      if (response.statusCode == 200) {
        logd('isLoggedInAsync: Cookie is valid, logging in...');
        await _fbAuth.signInWithCustomToken(jsonDecode(response.body)['customToken']);
        isAuthed = true;
      } else {
        loge('isLoggedInAsync: Cookie is NOT valid or not present');
      }
    }

    return isAuthed;
  }

  // @override
  // bool canCheckLoginState() {
  //   logd('canCheckLoginState() called...and it is: $_hasGottenUserPrivate');
  //   return _hasGottenUserPrivate;
  // }

  @override
  Future<bool> waitForCanCheckLoginState() async {
    logd('waitForCanCheckLoginState called');

    const maxMilliseconds = 5000;
    int currentMilliseconds = 0;

    // while (_hasTriedToGetCurrentUserPrivate == false) {
    while (_hasAuthStateChangeListenerRunAtLeastOnce == false &&
        currentMilliseconds < maxMilliseconds) {
      if (currentMilliseconds >= maxMilliseconds) {
        debugPrint('waitForCanCheckLoginState timed out');

        // signOut();
        // return false;
        final currentUser = _fbAuth.currentUser;

        if (currentUser != null) {
          // Reload the current user to force authStateChanges to trigger
          await currentUser.reload();
        } else {
          // Sign out to force authStateChanges to trigger
          //TODO: I guess we sign out here because we can't get the user???
          signOut();
          return false;
        }
      }
      debugPrint('waitForCanCheckLoginState loop');
      await Future.delayed(const Duration(milliseconds: 50));
      currentMilliseconds += 50;
    }

    // logd('waitForCanCheckLoginState FINISHED');

    return _fbAuth.currentUser != null;
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
      var result = await mainCallable.call(LoginCodeRequest(loginCode: code).toJson());

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
          Logr.le('verificationFaild: $fe');

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
      Logr.le(fe);
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

        HttpsCallable callable = _fbFunctions.httpsCallable('authLoginAnonymously');
        // HttpsCallable callable = _fbFunctions.httpsCallable('authLoginAnonymouslyV1');

        // HttpsCallable callable =
        //     FirebaseFunctions.instanceFor(region: AppConfigBase.backendRegion)
        //         .httpsCallable('authLoginAnonymouslyV1');

        var result = await retryIt(() async {
          return await callable.call(
            <String, dynamic>{'timezone': await FlutterTimezone.getLocalTimezone()},
          );
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
          Logr.le(f);
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
      _fbAuth.sendPasswordResetEmail(email: email);
      return right(unit);
    } catch (e) {
      loge(e);
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
        Logr.le(e);
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
              'timezone': await FlutterTimezone.getLocalTimezone()
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

  @override
  Future<Either<AuthServiceSignOutFailure, Unit>> signOut({bool useFbAuthAlso = true}) async {
    try {
      if (useFbAuthAlso) {
        await _fbAuth.signOut();
      }

      // Call the optional callback
      await onLoggedOut?.call();

      // Clear the cookie on the server if using federated auth
      if (AppConfigBase.useCookieFederatedAuth) {
        final http.Client client = http.Client();
        //TODO: temp disabled
        // if (client is BrowserClient) {
        //   client.withCredentials = true;
        // }

        //TODO: not sure if this should be open to the public
        final response = await client
            .get(Uri.parse(RepoHelpers.getFunctionUrl(_fbAuth.app, 'authfunctions-signout')));

        if (response.statusCode == 204) {
          logd('Cleared cookie successfully');
        } else {
          logd('Faild to clear cookie!!');
          return left(AuthServiceSignOutFailure.unexpected);
        }
      }

      // Clear the stored user info
      SharedPreferences prefs = await SharedPreferences.getInstance();

      await prefs.remove(sharedPrefKeyFcmToken);
      await prefs.remove(sharedPrefKeyTimezone);

      _hasInitializedFCM = false;
      _accessCodeCached = null;
      //TODO: do we do this here? Or will the listeners take care of it?
      // currentFbUserCredentials = null;
      // currentFbUser = null;
    } on fb_auth.FirebaseAuthException catch (e) {
      loge(e);
      return left(AuthServiceSignOutFailure.unexpected);
    } catch (e) {
      loge(e);
      return left(AuthServiceSignOutFailure.unexpected);
    }

    return right(unit);
  }

  //
  // Dev Only
  //

  @override
  Future<Either<AuthServiceSignInFailure, Unit>> signInWithDevOnly() async {
    FirebaseAuth.instance.signOut();

    HttpsCallable devOnlyCallable = AppConfigBase.firebaseFunctionCallable('devOnlyDevSignIn');

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

  //
  //
  // FCM
  //
  //

  initFCM() async {
    logd('Initializing FCM with _hasInitializedFCM = $_hasInitializedFCM');

    FirebaseMessaging messaging = FirebaseMessaging.instance;

    // Request permission for iOS devices
    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

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
        Logr.le('APNS token was not set after waiting.');
        // Optionally: return or throw here
      }
    }

    SharedPreferences prefs = await SharedPreferences.getInstance();

    String? oldToken = prefs.getString(sharedPrefKeyFcmToken);
    String? newToken = await messaging.getToken();

    if (newToken != null && (newToken != oldToken || !_hasInitializedFCM)) {
      try {
        logd('Updating FCM token on server: $newToken');
        await _updateTokenOnServer(newToken, oldToken ?? "");
        await prefs.setString(sharedPrefKeyFcmToken, newToken);
      } catch (e) {
        Logr.le('Error updating FCM token on server: $e');
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
          Logr.le('Error updating FCM token on server: $e');
        }
      });
    }

    _hasInitializedFCM = true;
  }

  Future<void> _updateTokenOnServer(String newToken, String oldToken) async {
    // Call a Firebase function to update the token on the server.
    await AppConfigBase.firebaseFunctionCallable('notificationsUpdateFcmToken')
        .call(<String, dynamic>{
      'newToken': newToken,
      'oldToken': oldToken,
      'timezone': await FlutterTimezone.getLocalTimezone(),
    });
  }
}
