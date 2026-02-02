import 'package:dartz/dartz.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:dreamic/data/helpers/repository_failure.dart';
import 'package:dreamic/data/models/login_code_response.dart';

/// Callback with priority for ordered execution.
///
/// Higher priority callbacks execute first (e.g., priority 100 runs before priority 0).
/// Callbacks with the same priority execute in parallel via `Future.wait`.
/// Different priorities execute sequentially (all callbacks at priority N complete
/// before priority N-1 starts).
///
/// ## Default Priorities
///
/// | Service | Callback | Priority | Rationale |
/// |---------|----------|----------|-----------|
/// | DeviceService | onAuthenticated | 0 | Default |
/// | DeviceService | onAboutToLogOut | 0 | Default |
/// | NotificationService | onAuthenticated | 0 | Default, runs parallel with DeviceService |
/// | NotificationService | onAboutToLogOut | 0 | Default, defers to DeviceService when present |
///
/// ## Custom Priorities
///
/// - **Positive priorities (e.g., 100)** to run before default services
/// - **Negative priorities (e.g., -100)** to run after default services
///
/// ## Example
///
/// ```dart
/// final auth = AuthServiceImpl(
///   firebaseApp: app,
///   onAuthenticatedCallbacks: [
///     PrioritizedCallback(deviceService.handleAuthenticated, priority: 0),
///     PrioritizedCallback(notificationService.handleAuthenticated, priority: 0),
///     PrioritizedCallback(analyticsService.onLogin, priority: -10), // After core services
///   ],
/// );
/// ```
class PrioritizedCallback<T extends Function> {
  /// The callback function to execute.
  final T callback;

  /// The execution priority. Higher values execute first.
  ///
  /// Default is 0. Use positive values to run before defaults,
  /// negative values to run after defaults.
  final int priority;

  /// Creates a prioritized callback.
  ///
  /// [callback] is the function to execute.
  /// [priority] determines execution order (higher = earlier). Default is 0.
  const PrioritizedCallback(this.callback, {this.priority = 0});
}

abstract class AuthServiceInt {
  fb_auth.UserCredential? currentFbUserCredentials;
  fb_auth.User? currentFbUser;

  AuthServiceInt(Function(Future<void>) onAuthenticated);

  /// Stream that emits true when user is logged in, false when logged out
  Stream<bool> get isLoggedInStream;

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

  // Authentication lifecycle callbacks
  /// Add a callback to be invoked when user authenticates.
  ///
  /// The callback receives the user's UID (or null if unavailable).
  ///
  /// [priority] determines execution order:
  /// - Higher values execute first (priority 100 runs before priority 0)
  /// - Same priority callbacks execute in parallel
  /// - Default is 0
  void addOnAuthenticatedCallback(
    Future<void> Function(String? uid) callback, {
    int priority = 0,
  });

  /// Remove a previously added authenticated callback.
  /// Returns true if the callback was found and removed.
  bool removeOnAuthenticatedCallback(Future<void> Function(String? uid) callback);

  /// Add a callback to be invoked AFTER logout is complete.
  ///
  /// [priority] determines execution order:
  /// - Higher values execute first (priority 100 runs before priority 0)
  /// - Same priority callbacks execute in parallel
  /// - Default is 0
  void addOnLoggedOutCallback(
    Future<void> Function() callback, {
    int priority = 0,
  });

  /// Remove a previously added logged out callback.
  /// Returns true if the callback was found and removed.
  bool removeOnLoggedOutCallback(Future<void> Function() callback);

  // Pre-logout callbacks
  /// Add a callback to be invoked BEFORE logout while still authenticated.
  ///
  /// Use this for cleanup tasks that require auth (e.g., backend FCM unregistration).
  /// Callbacks are called with a timeout; failures won't block sign out.
  ///
  /// [priority] determines execution order:
  /// - Higher values execute first (priority 100 runs before priority 0)
  /// - Same priority callbacks execute in parallel
  /// - Default is 0
  ///
  /// **Best-effort semantics:** If callbacks exceed the global timeout, remaining
  /// callbacks are abandoned and logout proceeds. Design backend systems to handle
  /// orphaned records (e.g., device docs without unregister).
  void addOnAboutToLogOutCallback(
    Future<void> Function() callback, {
    int priority = 0,
  });

  /// Remove a previously added logout callback.
  /// Returns true if the callback was found and removed.
  bool removeOnAboutToLogOutCallback(Future<void> Function() callback);

  // Email verification
  /// Check if current user's email is verified
  bool get isEmailVerified;

  /// Send email verification to current user
  Future<Either<AuthServiceEmailVerificationFailure, Unit>> sendEmailVerification();

  /// Reload user data to get latest email verification status
  Future<Either<AuthServiceSignInFailure, Unit>> reloadUser();

  // Re-authentication
  /// Re-authenticate current user with password for sensitive operations
  ///
  /// Required before operations like changing email, password, or deleting account
  Future<Either<AuthServiceSignInFailure, Unit>> reauthenticateWithPassword(
    String password,
  );

  // Account linking
  /// Link anonymous account to email/password credentials
  ///
  /// Converts an anonymous user to a permanent account while preserving the UID.
  /// After linking, the user can sign in with email/password on other devices.
  ///
  /// Returns [AuthServiceLinkFailure.emailAlreadyInUse] if email is already registered.
  /// Returns [AuthServiceLinkFailure.weakPassword] if password is less than 6 characters.
  Future<Either<AuthServiceLinkFailure, Unit>> linkEmailPassword(
    String email,
    String password,
  );

  // Password management
  /// Update the current user's password
  ///
  /// Requires recent authentication - call [reauthenticateWithPassword] first.
  Future<Either<AuthServiceSignInFailure, Unit>> updatePassword(
    String newPassword,
  );

  Future<Either<AuthServiceSignInFailure, Unit>> signInWithDevOnly();
  Future<Either<AuthServiceSignInFailure, Unit>> signInWithCustomToken(String customToken);

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

enum AuthServiceEmailVerificationFailure {
  userNotLoggedIn,
  tooManyRequests,
  unexpected,
}

/// Failure cases for linking anonymous accounts to credentials
enum AuthServiceLinkFailure {
  /// User is not logged in or not anonymous
  userNotLoggedIn,

  /// The email is already in use by another account
  emailAlreadyInUse,

  /// Password is too weak (less than 6 characters)
  weakPassword,

  /// The email address is invalid
  invalidEmail,

  /// The credential is invalid or has expired
  invalidCredential,

  /// Account requires recent authentication before linking
  requiresRecentLogin,

  /// The credential is already associated with a different user account
  credentialAlreadyInUse,

  /// General unexpected error
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
