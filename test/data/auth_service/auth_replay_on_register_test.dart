import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:dreamic/data/repos/auth_service_impl.dart';

/// Tests for `AuthServiceImpl.addOnAuthenticatedCallback` **replay-on-register**
/// (Issue 99).
///
/// When the cold-start init chain moved behind the app-init gate, a callback
/// registered AFTER `DreamicServices.initialize` (because its target services
/// are constructed post-init) could miss the warm-start `authStateChanges`
/// event, which is delivered DURING `initialize`'s await. The fix gives
/// `addOnAuthenticatedCallback` BehaviorSubject semantics: a callback added
/// after the initial event has been delivered AND while a user is authenticated
/// is replayed once (via `scheduleMicrotask`) with the current uid.
///
/// Cases (Testing Strategy → "dreamic auth warm-start replay-on-register"):
/// (a) a callback added AFTER the initial event → replayed once with the uid;
/// (b) a callback registered BEFORE the listener delivers the initial event
///     fires once via the listener and is NOT double-invoked by the replay
///     (the gate is the stream-event flag, not the synchronously-populated
///     `currentUser`);
/// (c) `addOnLoggedOutCallback` is NOT replayed while logged out;
/// (d) the replay dispatches via microtask and is safe (no throw) for an async
///     callback.
class MockFirebaseAuth extends Mock implements fb_auth.FirebaseAuth {}

class MockUser extends Mock implements fb_auth.User {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // Stub package_info_plus platform channel for AppConfigBase.getPackageInfo()
    // (read lazily by AuthServiceImpl).
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

  late MockFirebaseAuth mockFirebaseAuth;
  // A controllable auth-state stream so the test drives WHEN the initial event
  // is delivered.
  late StreamController<fb_auth.User?> authStateController;

  setUp(() {
    mockFirebaseAuth = MockFirebaseAuth();
    authStateController = StreamController<fb_auth.User?>.broadcast();

    when(() => mockFirebaseAuth.authStateChanges())
        .thenAnswer((_) => authStateController.stream);
    // idToken stream emits nothing (handleTokenChanges does network work we
    // don't want to exercise here).
    when(() => mockFirebaseAuth.idTokenChanges())
        .thenAnswer((_) => const Stream.empty());
  });

  tearDown(() async {
    await authStateController.close();
  });

  /// Drives an authenticated `authStateChanges` event for [uid] and awaits its
  /// async handler completion.
  Future<void> deliverAuthEvent(
    AuthServiceImpl auth,
    MockFirebaseAuth fb,
    String uid,
  ) async {
    final user = MockUser();
    when(() => user.uid).thenReturn(uid);
    // currentUser is synchronously populated by Firebase before the stream's
    // first event — model that so the test catches a wrong gate on currentUser.
    when(() => fb.currentUser).thenReturn(user);

    // Invoke the handler directly (the same callback the listener invokes) and
    // await it, so the delivered-event state is set deterministically.
    await auth.handleAuthStateChanges(user);
  }

  test(
      '(a) a callback added AFTER the initial event is replayed once with the uid',
      () async {
    final auth = AuthServiceImpl(firebaseAuthOverride: mockFirebaseAuth);
    addTearDown(auth.dispose);

    // Deliver the warm-start auth event BEFORE the late callback registers.
    await deliverAuthEvent(auth, mockFirebaseAuth, 'warm-user');

    final replayed = <String?>[];
    auth.addOnAuthenticatedCallback((uid) async => replayed.add(uid));

    // The replay is dispatched via scheduleMicrotask — flush it.
    await Future<void>.delayed(Duration.zero);

    expect(replayed, ['warm-user'],
        reason: 'late callback replayed exactly once with the delivered uid');
  });

  test(
      '(b) a callback registered BEFORE the initial event fires once via the '
      'listener and is NOT double-invoked by the replay', () async {
    final invocations = <String?>[];
    final auth = AuthServiceImpl(
      firebaseAuthOverride: mockFirebaseAuth,
      onAuthenticatedCallbacks: [
        (uid) async => invocations.add(uid),
      ],
    );
    addTearDown(auth.dispose);

    // Now deliver the initial event — the constructor-registered callback fires
    // via the listener path. The replay must NOT also fire it (the gate is the
    // stream-event flag, not currentUser which is synchronously populated).
    await deliverAuthEvent(auth, mockFirebaseAuth, 'first-user');

    // Flush any (incorrect) replay microtask.
    await Future<void>.delayed(Duration.zero);

    expect(invocations, ['first-user'],
        reason: 'constructor-path callback fires exactly once (no double-fire)');
  });

  test('(c) addOnLoggedOutCallback is NOT replayed on registration while '
      'logged out', () async {
    final auth = AuthServiceImpl(firebaseAuthOverride: mockFirebaseAuth);
    addTearDown(auth.dispose);

    // Deliver a logout event (null user) so the listener has run at least once
    // but the user is NOT authenticated.
    when(() => mockFirebaseAuth.currentUser).thenReturn(null);
    await auth.handleAuthStateChanges(null);

    final loggedOutReplayed = <String>[];
    auth.addOnLoggedOutCallback(() async => loggedOutReplayed.add('logout'));
    // Also confirm onAuthenticated is not replayed while logged out.
    final authReplayed = <String?>[];
    auth.addOnAuthenticatedCallback((uid) async => authReplayed.add(uid));

    await Future<void>.delayed(Duration.zero);

    expect(loggedOutReplayed, isEmpty,
        reason: 'onLoggedOut is never replayed on register');
    expect(authReplayed, isEmpty,
        reason: 'onAuthenticated is not replayed while logged out '
            '(_lastDeliveredAuthUid is null after logout)');
  });

  test('(d) the replay dispatch is safe (no throw) for an async callback',
      () async {
    final auth = AuthServiceImpl(firebaseAuthOverride: mockFirebaseAuth);
    addTearDown(auth.dispose);

    await deliverAuthEvent(auth, mockFirebaseAuth, 'async-user');

    final completer = Completer<String?>();
    // An async callback that yields before completing — the microtask dispatch
    // must await it without throwing.
    auth.addOnAuthenticatedCallback((uid) async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      completer.complete(uid);
    });

    final result = await completer.future
        .timeout(const Duration(seconds: 1), onTimeout: () => '__timeout__');

    expect(result, 'async-user');
  });

  test('a throwing replay callback does not escape the microtask (no '
      'unhandled exception)', () async {
    final auth = AuthServiceImpl(firebaseAuthOverride: mockFirebaseAuth);
    addTearDown(auth.dispose);

    await deliverAuthEvent(auth, mockFirebaseAuth, 'throw-user');

    // A throwing replay callback must be caught (loge) inside the microtask so
    // it does not surface as an unhandled async error.
    auth.addOnAuthenticatedCallback((uid) async {
      throw StateError('replay callback blew up');
    });

    // Reaching here after the microtask flush without the test failing on an
    // unhandled exception is the assertion.
    await Future<void>.delayed(Duration.zero);
  });
}
