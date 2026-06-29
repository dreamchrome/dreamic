import 'dart:async';

import 'package:dreamic/app/app_config_base.dart';
import 'package:dreamic/data/repos/remote_config_repo_int.dart';
import 'package:dreamic/error_reporting/error_reporter_interface.dart';
import 'package:dreamic/utils/logger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

/// Mutable RemoteConfig mock — returns Firebase-RC-like defaults for unset keys
/// (empty string / 0 / false) and allows per-test string overrides.
class _MutableRemoteConfigMock implements RemoteConfigRepoInt {
  final Map<String, dynamic> _values = {};

  void setString(String key, String value) => _values[key] = value;
  void clear() => _values.clear();

  @override
  String getString(String key) => _values[key] as String? ?? '';
  @override
  bool getBool(String key) => _values[key] as bool? ?? false;
  @override
  int getInt(String key) => _values[key] as int? ?? 0;
  @override
  double getDouble(String key) => _values[key] as double? ?? 0.0;
}

/// Reporter that records every breadcrumb (message + category + data) it
/// receives. `extends ErrorReporter` to inherit the default no-op members.
class _RecordingBreadcrumbReporter extends ErrorReporter {
  final List<({String message, String? category, Map<String, dynamic>? data})> crumbs =
      [];

  @override
  void recordError(Object error, StackTrace? stackTrace) {}

  @override
  void addBreadcrumb(String message, {String? category, Map<String, dynamic>? data}) {
    crumbs.add((message: message, category: category, data: data));
  }
}

void main() {
  late _MutableRemoteConfigMock mockRC;

  setUp(() {
    mockRC = _MutableRemoteConfigMock();
    if (GetIt.I.isRegistered<RemoteConfigRepoInt>()) {
      GetIt.I.unregister<RemoteConfigRepoInt>();
    }
    GetIt.I.registerSingleton<RemoteConfigRepoInt>(mockRC);
    Logger.setCustomErrorReporter(null);
    Logger.resetEarlyBreadcrumbBufferForTest();
    AppConfigBase.resetBreadcrumbLevelWarnedForTest();
  });

  tearDown(() {
    Logger.setCustomErrorReporter(null);
    Logger.resetEarlyBreadcrumbBufferForTest();
    AppConfigBase.resetBreadcrumbLevelWarnedForTest();
    if (GetIt.I.isRegistered<RemoteConfigRepoInt>()) {
      GetIt.I.unregister<RemoteConfigRepoInt>();
    }
  });

  group('AppConfigBase.breadcrumbLevel', () {
    test('defaults to info when env + RC are unset', () {
      expect(AppConfigBase.breadcrumbLevel, LogLevel.info);
    });

    test('reads a valid RC value', () {
      mockRC.setString('breadcrumbLevel', 'debug');
      expect(AppConfigBase.breadcrumbLevel, LogLevel.debug);
      mockRC.setString('breadcrumbLevel', 'warn');
      expect(AppConfigBase.breadcrumbLevel, LogLevel.warn);
      mockRC.setString('breadcrumbLevel', 'error');
      expect(AppConfigBase.breadcrumbLevel, LogLevel.error);
    });

    test('an invalid RC string falls back to info', () {
      mockRC.setString('breadcrumbLevel', 'bogus');
      expect(AppConfigBase.breadcrumbLevel, LogLevel.info);
    });

    test('debugVerbose is out-of-domain and falls back to info', () {
      // debugVerbose has no backend equivalent → excluded from the domain.
      mockRC.setString('breadcrumbLevel', 'debugVerbose');
      expect(AppConfigBase.breadcrumbLevel, LogLevel.info);
    });

    test('repeated invalid reads stay info and the one-time guard does not '
        'throw or change the result', () {
      // The warning is emitted via print() (one-time, guarded by
      // _breadcrumbLevelWarned). We assert the observable behavior: every read
      // of an invalid value returns info and never throws, on first and
      // subsequent reads (the guard only suppresses the duplicate console line).
      mockRC.setString('breadcrumbLevel', 'nope');
      expect(AppConfigBase.breadcrumbLevel, LogLevel.info);
      expect(AppConfigBase.breadcrumbLevel, LogLevel.info);
      expect(AppConfigBase.breadcrumbLevel, LogLevel.info);
    });

    test('the invalid-value warning is emitted exactly once (one-time guard), '
        'and re-arms after the reset seam', () {
      // The getter warns via print() guarded by _breadcrumbLevelWarned. Capture
      // print() through a Zone and assert the warning line fires exactly once
      // across multiple invalid reads (not on every breadcrumb-emit read).
      mockRC.setString('breadcrumbLevel', 'bogus');

      final printed = <String>[];
      final results = <LogLevel>[];
      runZoned(
        () {
          for (var i = 0; i < 3; i++) {
            results.add(AppConfigBase.breadcrumbLevel);
          }
        },
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => printed.add(line),
        ),
      );

      expect(results, everyElement(LogLevel.info));
      expect(
        printed.where((l) => l.contains('invalid breadcrumbLevel')),
        hasLength(1),
        reason: 'warning must be emitted exactly once, not per read',
      );

      // The reset seam re-arms the guard so a later misconfiguration warns again.
      AppConfigBase.resetBreadcrumbLevelWarnedForTest();
      final printedAfterReset = <String>[];
      runZoned(
        () => AppConfigBase.breadcrumbLevel,
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => printedAfterReset.add(line),
        ),
      );
      expect(
        printedAfterReset.where((l) => l.contains('invalid breadcrumbLevel')),
        hasLength(1),
        reason: 'guard must re-arm after reset',
      );
    });

    test('never throws when GetIt is not ready (RC unregistered)', () {
      GetIt.I.unregister<RemoteConfigRepoInt>();
      expect(() => AppConfigBase.breadcrumbLevel, returnsNormally);
      expect(AppConfigBase.breadcrumbLevel, LogLevel.info);
      // Re-register so tearDown's unregister doesn't fail.
      GetIt.I.registerSingleton<RemoteConfigRepoInt>(mockRC);
    });
  });

  group('Logger.breadcrumb — emit-time level gating (LogLevel-only)', () {
    test('drops a breadcrumb below the threshold', () {
      mockRC.setString('breadcrumbLevel', 'warn');
      final reporter = _RecordingBreadcrumbReporter();
      Logger.setCustomErrorReporter(reporter);

      logBreadcrumb('an info crumb', level: LogLevel.info);
      logBreadcrumb('a debug crumb', level: LogLevel.debug);

      expect(reporter.crumbs, isEmpty);
    });

    test('forwards a breadcrumb at/above the threshold', () {
      mockRC.setString('breadcrumbLevel', 'warn');
      final reporter = _RecordingBreadcrumbReporter();
      Logger.setCustomErrorReporter(reporter);

      logBreadcrumb('a warn crumb', level: LogLevel.warn);
      logBreadcrumb('an error crumb', level: LogLevel.error);

      expect(reporter.crumbs.map((c) => c.message),
          ['a warn crumb', 'an error crumb']);
    });

    test('default omitted level is info', () {
      mockRC.setString('breadcrumbLevel', 'info');
      final reporter = _RecordingBreadcrumbReporter();
      Logger.setCustomErrorReporter(reporter);

      logBreadcrumb('no explicit level'); // defaults to info → forwarded
      expect(reporter.crumbs.map((c) => c.message), ['no explicit level']);

      // Raise the threshold above info; the same default-level crumb is dropped.
      reporter.crumbs.clear();
      mockRC.setString('breadcrumbLevel', 'error');
      logBreadcrumb('no explicit level again');
      expect(reporter.crumbs, isEmpty);
    });

    test('logd-equivalent (debug) breadcrumb is gated purely by breadcrumbLevel',
        () {
      final reporter = _RecordingBreadcrumbReporter();
      Logger.setCustomErrorReporter(reporter);

      // breadcrumbLevel=info (default) → debug crumb dropped.
      logBreadcrumb('debug detail', level: LogLevel.debug);
      expect(reporter.crumbs, isEmpty);

      // Lower the threshold to debug → the same crumb is forwarded.
      mockRC.setString('breadcrumbLevel', 'debug');
      logBreadcrumb('debug detail', level: LogLevel.debug);
      expect(reporter.crumbs.map((c) => c.message), ['debug detail']);
    });
  });

  group('Logger.breadcrumb — redaction', () {
    test('redacts oobCode in the message', () {
      final reporter = _RecordingBreadcrumbReporter();
      Logger.setCustomErrorReporter(reporter);

      logBreadcrumb('navigated to /confirm?oobCode=SECRET123&mode=signIn');
      expect(reporter.crumbs.single.message, isNot(contains('SECRET123')));
      expect(reporter.crumbs.single.message, contains('oobCode=[redacted]'));
    });

    test('redacts a Bearer token in the message', () {
      final reporter = _RecordingBreadcrumbReporter();
      Logger.setCustomErrorReporter(reporter);

      logBreadcrumb('Authorization: Bearer eyJhbGSECRET.payload.sig');
      expect(reporter.crumbs.single.message, isNot(contains('eyJhbGSECRET')));
      expect(reporter.crumbs.single.message, contains('Bearer [redacted]'));
    });

    test('redacts email embedded in a URL', () {
      final reporter = _RecordingBreadcrumbReporter();
      Logger.setCustomErrorReporter(reporter);

      logBreadcrumb('opened https://x.com/p?email=secret@user.com&a=b');
      expect(reporter.crumbs.single.message, isNot(contains('secret@user.com')));
      expect(reporter.crumbs.single.message, contains('[redacted]'));
    });

    test('redacts string values in the data map; leaves non-strings intact', () {
      final reporter = _RecordingBreadcrumbReporter();
      Logger.setCustomErrorReporter(reporter);

      logBreadcrumb('login', data: {
        'url': '/confirm?oobCode=SECRET',
        'attempt': 3,
        'flag': true,
      });
      final data = reporter.crumbs.single.data!;
      expect(data['url'], isNot(contains('SECRET')));
      expect(data['url'], contains('oobCode=[redacted]'));
      expect(data['attempt'], 3);
      expect(data['flag'], true);
    });

    test('fail-closed: a thrown redaction replaces message + EVERY data value '
        'with a class-preserving placeholder (never toString)', () {
      final reporter = _RecordingBreadcrumbReporter();
      Logger.setCustomErrorReporter(reporter);

      // A data value whose toString() throws forces a redaction failure when the
      // map is iterated. (String values are redacted; this is a non-string whose
      // stringification — were it ever attempted — would throw; we use a key
      // that itself throws when iterated by injecting a throwing Map.)
      logBreadcrumb('secret oobCode=ABC', data: _ThrowingMap());

      final crumb = reporter.crumbs.single;
      // The class-preserving placeholder, NOT the secret, NOT toString().
      expect(crumb.message, startsWith('[redaction-error:'));
      expect(crumb.message, isNot(contains('ABC')));
      // Every data value replaced with the same placeholder.
      for (final v in (crumb.data ?? {}).values) {
        expect(v, startsWith('[redaction-error:'));
      }
    });
  });

  group('Logger.breadcrumb — early buffer (unattached)', () {
    test('buffers when no reporter is attached, then drains on demand', () {
      Logger.setCustomErrorReporter(null);
      expect(Logger.earlyBreadcrumbBufferLengthForTest, 0);

      logBreadcrumb('early one', level: LogLevel.info);
      logBreadcrumb('early two', level: LogLevel.warn);
      expect(Logger.earlyBreadcrumbBufferLengthForTest, 2);

      final drained = Logger.drainEarlyBreadcrumbs();
      expect(drained.map((c) => c.message), ['early one', 'early two']);
      // Drain clears the buffer (no re-flush).
      expect(Logger.earlyBreadcrumbBufferLengthForTest, 0);
      expect(Logger.drainEarlyBreadcrumbs(), isEmpty);
    });

    test('a gated-out breadcrumb is NOT buffered', () {
      mockRC.setString('breadcrumbLevel', 'error');
      Logger.setCustomErrorReporter(null);

      logBreadcrumb('below threshold', level: LogLevel.info);
      expect(Logger.earlyBreadcrumbBufferLengthForTest, 0);
    });

    test('buffered breadcrumbs are redacted at emit time (no re-redaction on '
        'drain)', () {
      Logger.setCustomErrorReporter(null);
      logBreadcrumb('oobCode=SECRET in early buffer');

      final drained = Logger.drainEarlyBreadcrumbs();
      expect(drained.single.message, isNot(contains('SECRET')));
      expect(drained.single.message, contains('oobCode=[redacted]'));
    });

    test('buffer is bounded (drop-oldest beyond 50)', () {
      Logger.setCustomErrorReporter(null);
      for (var i = 0; i < 60; i++) {
        logBreadcrumb('crumb $i');
      }
      expect(Logger.earlyBreadcrumbBufferLengthForTest, 50);
      final drained = Logger.drainEarlyBreadcrumbs();
      // Oldest 10 dropped → first retained is crumb 10, last is crumb 59.
      expect(drained.first.message, 'crumb 10');
      expect(drained.last.message, 'crumb 59');
    });
  });
}

/// A Map whose entry iteration throws, to force the redaction try/catch into its
/// fail-closed path. `keys` is used by the fail-closed placeholder branch, so it
/// must return a real iterable (we expose a single key) while `entries` (used by
/// the happy path) throws.
class _ThrowingMap implements Map<String, dynamic> {
  @override
  Iterable<MapEntry<String, dynamic>> get entries =>
      throw StateError('boom-during-redaction');

  @override
  Iterable<String> get keys => ['payload'];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
