import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:dartz/dartz.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:dreamic/data/repos/auth_service_impl.dart';
import 'package:dreamic/data/repos/auth_service_int.dart';

// --- Mocks ---

class MockFirebaseAuth extends Mock implements fb_auth.FirebaseAuth {}

class MockUserCredential extends Mock implements fb_auth.UserCredential {}

class MockHttpsCallable extends Mock implements HttpsCallable {}

class MockHttpsCallableResult extends Mock implements HttpsCallableResult<dynamic> {}

// --- Fake for registerFallbackValue ---

class FakeAuthCredential extends Fake implements fb_auth.AuthCredential {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AuthServiceImpl authService;
  late MockFirebaseAuth mockFirebaseAuth;
  late MockHttpsCallable mockCallable;
  late MockHttpsCallableResult mockCallableResult;

  setUpAll(() {
    registerFallbackValue(FakeAuthCredential());

    // Stub package_info_plus platform channel for AppConfigBase.getPackageInfo()
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/package_info'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getAll') {
          return <String, dynamic>{
            'appName': 'dreamic_test',
            'packageName': 'com.test.dreamic',
            'version': '1.0.0',
            'buildNumber': '1',
          };
        }
        return null;
      },
    );
  });

  setUp(() {
    mockFirebaseAuth = MockFirebaseAuth();
    mockCallable = MockHttpsCallable();
    mockCallableResult = MockHttpsCallableResult();

    // Stub streams to prevent constructor side effects.
    // Stream.empty() emits no events — handleAuthStateChanges/handleTokenChanges
    // never fire, avoiding signOut() side effects.
    when(() => mockFirebaseAuth.authStateChanges())
        .thenAnswer((_) => Stream.empty());
    when(() => mockFirebaseAuth.idTokenChanges())
        .thenAnswer((_) => Stream.empty());

    // Construct with override only — no FirebaseApp, no AppConfigBase needed.
    authService = AuthServiceImpl(firebaseAuthOverride: mockFirebaseAuth);

    // Replace lazy authCallable before first read (initializer never runs).
    authService.authCallable = mockCallable;

    // Stub callable result for register methods.
    // HttpsCallableResult has a private constructor — must be mocked.
    when(() => mockCallableResult.data)
        .thenReturn({'password': 'testpass', 'result': 'created'});
    when(() => mockCallable.call(any())).thenAnswer((_) async => mockCallableResult);

    // Eliminate real delays in retry loops.
    authService.signInRetryDelay = Duration.zero;
  });

  group('loginWithPhoneVerifyCode', () {
    test('returns smsCodeExpired when Firebase throws session-expired', () async {
      when(() => mockFirebaseAuth.signInWithCredential(any()))
          .thenThrow(fb_auth.FirebaseAuthException(
        code: 'session-expired',
        message: 'SMS code has expired',
      ));

      final result = await authService.loginWithPhoneVerifyCode('123456');

      expect(result, left(PhoneAuthError.smsCodeExpired));
    });

    test('returns sessionExpired when Firebase throws invalid-verification-id', () async {
      when(() => mockFirebaseAuth.signInWithCredential(any()))
          .thenThrow(fb_auth.FirebaseAuthException(
        code: 'invalid-verification-id',
        message: 'Verification ID is invalid',
      ));

      final result = await authService.loginWithPhoneVerifyCode('123456');

      expect(result, left(PhoneAuthError.sessionExpired));
    });

    test('returns wrongSmsCode when Firebase throws invalid-verification-code', () async {
      when(() => mockFirebaseAuth.signInWithCredential(any()))
          .thenThrow(fb_auth.FirebaseAuthException(
        code: 'invalid-verification-code',
        message: 'SMS code is invalid',
      ));

      final result = await authService.loginWithPhoneVerifyCode('123456');

      expect(result, left(PhoneAuthError.wrongSmsCode));
    });
  });

  group('registerUserWithJustEmail', () {
    test('returns signInTimedOut after 8 failed retries', () async {
      when(() => mockFirebaseAuth.signInWithEmailAndPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          )).thenThrow(fb_auth.FirebaseAuthException(
        code: 'user-not-found',
        message: 'User not found',
      ));

      final result = await authService.registerUserWithJustEmail('test@example.com');

      expect(result, left(AuthServiceSignInFailure.signInTimedOut));
      verify(() => mockFirebaseAuth.signInWithEmailAndPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          )).called(8);
    });

    test('returns Right(unit) when sign-in succeeds after retries', () async {
      int callCount = 0;
      when(() => mockFirebaseAuth.signInWithEmailAndPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          )).thenAnswer((_) {
        callCount++;
        if (callCount <= 3) {
          throw fb_auth.FirebaseAuthException(
            code: 'user-not-found',
            message: 'User not found',
          );
        }
        return Future.value(MockUserCredential());
      });

      final result = await authService.registerUserWithJustEmail('test@example.com');

      expect(result, right(unit));
      verify(() => mockFirebaseAuth.signInWithEmailAndPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          )).called(4); // 3 failures + 1 success
    });

    test('returns unexpected immediately on non-retryable error', () async {
      when(() => mockFirebaseAuth.signInWithEmailAndPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          )).thenThrow(fb_auth.FirebaseAuthException(
        code: 'email-already-in-use',
        message: 'Email already in use',
      ));

      final result = await authService.registerUserWithJustEmail('test@example.com');

      expect(result, left(AuthServiceSignInFailure.unexpected));
      verify(() => mockFirebaseAuth.signInWithEmailAndPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          )).called(1); // No retry
    });
  });

  group('registerUserWithEmailAndPassword', () {
    test('returns signInTimedOut after 5 failed retries', () async {
      when(() => mockFirebaseAuth.signInWithEmailAndPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          )).thenThrow(fb_auth.FirebaseAuthException(
        code: 'user-not-found',
        message: 'User not found',
      ));

      final result = await authService.registerUserWithEmailAndPassword(
          'test@example.com', 'password123');

      expect(result, left(AuthServiceSignInFailure.signInTimedOut));
      verify(() => mockFirebaseAuth.signInWithEmailAndPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          )).called(5);
    });

    test('returns unexpected immediately on non-retryable error', () async {
      when(() => mockFirebaseAuth.signInWithEmailAndPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          )).thenThrow(fb_auth.FirebaseAuthException(
        code: 'email-already-in-use',
        message: 'Email already in use',
      ));

      final result = await authService.registerUserWithEmailAndPassword(
          'test@example.com', 'password123');

      expect(result, left(AuthServiceSignInFailure.unexpected));
      verify(() => mockFirebaseAuth.signInWithEmailAndPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          )).called(1); // No retry
    });
  });
}
