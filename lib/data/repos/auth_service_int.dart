import 'package:dartz/dartz.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:dreamic/data/helpers/repository_failure.dart';
import 'package:dreamic/data/models/login_code_response.dart';

abstract class AuthServiceInt {
  fb_auth.UserCredential? currentFbUserCredentials;
  fb_auth.User? currentFbUser;

  AuthServiceInt(Function(Future<void>) onAuthenticated, Function(Future<void>) onRefreshed);

  // Stream<AuthenticationStatus> get user async* {}

  // Future<Either<RepositoryFailure, UserPrivate>> getCurrentUserPrivate();

  Future<Either<AuthServiceSignInFailure, Unit>> checkIfSignedInAndLoginAnonymouslyIfNot();

  Future<Either<AuthServiceSignInFailure, LoginCodeResponse>> loginWithCode(String code);

  Future<Either<PhoneAuthError, Unit>> loginWithPhone(
    String phoneNumber, {
    required Function verificationCompleted,
    required Function(PhoneAuthError) verificationFailed,
    required Function codeSent,
    required Function codeAutoRetrievalTimeout,
    required bool codeResend,
  });
  Future<Either<PhoneAuthError, bool>> loginWithPhoneVerifyCode(String smsCode);

  Future<Either<AuthServiceSignInFailure, Unit>> registerUserWithJustEmail(String email);
  Future<Either<AuthServiceSignInFailure, Unit>> sendLoginEmail(String email);
  Future<Either<AuthServiceSignInFailure, Unit>> signInWithEmail(String email);
  Future<Either<AuthServiceSignInFailure, Unit>> signInWithEmailAndPassword(
      String email, String password);
  Future<Either<AuthServiceSignInFailure, Unit>> registerUserWithEmailAndPassword(
      String email, String password);
  Future<Either<AuthServiceEmailLinkFailure, Unit>> validateEmailLink(String link, {String? email});
  // Future<Either<AuthServiceSignInFailure, Unit>> refreshCurrentUser();
  Future<Either<AuthServiceSignInFailure, Unit>> resetPassword(String email);
  Future<Either<AuthServiceSignInFailure, Unit>> setPassword(String newPassword);
  Future<Either<AuthServiceSignInFailure, bool>> isEmailUser(String email);
  Future<Either<AuthServiceSignOutFailure, Unit>> signOut();
  Future<Either<AuthServiceSignInFailure, Unit>> signInWithDevOnly();

  // Access codes
  Future<Either<RepositoryFailure, (AccessCodeCheckReturn validity, String welcomeMessage)>>
      accessCodeCheckIfValid(
    String code,
  );
  Future<Either<RepositoryFailure, bool>> accessCodeIsValidCached();
  Future<Either<AuthServiceSignInFailure, Unit>> accessCodeRegisterWithEmailAndPassword(
    String email,
    String password,
  );

  // bool isLoggedIn();
  Future<bool> isLoggedInAsync();
  // bool canCheckLoginState();
  Future<bool> waitForCanCheckLoginState();
  // Future<bool> waitForUserPrivateRefreshed();
  /// Pass the UserClaims type to get the claims for that user
  Future<Map<T, bool>> getUserClaims<T extends Enum>({
    required List<T> enumValues,
    bool forceRefresh = false,
  });
}

enum PhoneAuthError {
  invalidPhoneNumber,
  userDisabled,
  captchaCheckFailed,
  tooManyRequests,
  wrongSmsCode,
  invalidPhone,
  unexpected,
}

enum AuthServiceSignInFailure {
  invalidEmail,
  userNotFound,
  wrongPassword,
  weakPassword,
  userDisabled,
  userAlreadyExists,
  databaseError,
  unexpected,
  tooManyRequests,
  invalidCredential,
}

enum AuthServiceEmailLinkFailure {
  noEmailRemembered,
  invalidLink,
  invalidEmail,
  expiredCode,
  userDisabled,
  databaseError,
  unexpected,
  invalidCode,
}

enum AuthServiceSignOutFailure {
  unexpected,
}

enum AuthenticationStatus {
  unknown,
  authenticatedAnonymous,
  authenticatedLogin,
  unauthenticated,
}

//TODO: should return this instead of just bool
enum AccessCodeCheckReturn {
  valid,
  invalidCode,
  expired,
  notYetValid,
  maxUsed,
  maxAttempts,
  unexpected,
}
