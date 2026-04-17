import 'dart:io';
import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Classifies whether an error is transient (worth retrying) or permanent (fail fast).
///
/// Transient errors are network/availability issues that may resolve on retry.
/// Permanent errors are logic/auth issues that require user action or code fixes.
/// Unknown/unrecognized exceptions default to retryable (safe fallback).
bool isTransientError(Object error) {
  if (error is FirebaseFunctionsException) {
    return _isTransientFunctionsCode(error.code);
  }

  if (error is FirebaseAuthException) {
    return _isTransientAuthCode(error.code);
  }

  if (error is FirebaseException) {
    return _isTransientFirebaseCode(error.code);
  }

  // Network/timeout errors are always transient
  if (error is SocketException ||
      error is TimeoutException ||
      error is HttpException) {
    return true;
  }

  // Programming errors — never retry
  if (error is ArgumentError ||
      error is FormatException ||
      error is StateError) {
    return false;
  }

  // Unknown exceptions default to retryable
  return true;
}

bool _isTransientFunctionsCode(String code) {
  switch (code) {
    case 'unavailable':
    case 'deadline-exceeded':
    case 'internal':
    case 'unknown':
    case 'resource-exhausted':
      return true;
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
      return false;
    default:
      return true; // Unknown code — default to retryable
  }
}

bool _isTransientAuthCode(String code) {
  switch (code) {
    case 'too-many-requests':
      return true;
    case 'invalid-email':
    case 'user-not-found':
    case 'wrong-password':
    case 'invalid-credential':
    case 'user-disabled':
    case 'email-already-in-use':
    case 'weak-password':
    case 'credential-already-in-use':
    case 'requires-recent-login':
    case 'invalid-phone-number':
    case 'invalid-verification-code':
    case 'invalid-action-code':
    case 'expired-action-code':
    case 'captcha-check-failed':
      return false;
    default:
      return true; // Unknown code — default to retryable
  }
}

bool _isTransientFirebaseCode(String code) {
  switch (code) {
    case 'throttled':
    case 'fetch-failed':
      return true;
    default:
      return true; // Unknown code — default to retryable
  }
}
