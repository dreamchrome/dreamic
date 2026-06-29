// BEH-4 integration test (automated proxy) — lowering `breadcrumbLevel` to
// `debug` via Remote Config causes `logd`-equivalent breadcrumbs to be captured
// WITHOUT a rebuild/redeploy.
//
// The LIVE end of BEH-4 — actually seeding the `breadcrumbLevel` Remote Config
// key per environment (ERH-044) and flipping it to `debug` against a running app
// — is DEFERRED-LIVE (see the tasklist's `## Deferred Concerns`). This test is
// the AUTOMATABLE proxy: it drives the SAME code path BEH-4 exercises at runtime
// — `AppConfigBase.breadcrumbLevel` reads the RC value (here a mutable mock), and
// `Logger.breadcrumb()` gates at EMIT time against that value — and flips the RC
// value within one process (no rebuild) to prove a `logd`-level breadcrumb that
// was dropped at the default `info` is captured once the threshold is lowered to
// `debug`. The gate reads RC live (per emit), so a real production RC flip behaves
// the same; the only thing this proxy cannot exercise is the real Firebase RC
// fetch/propagation (the DEFERRED-LIVE piece).

import 'package:dreamic/app/app_config_base.dart';
import 'package:dreamic/data/repos/remote_config_repo_int.dart';
import 'package:dreamic/error_reporting/error_reporter_interface.dart';
import 'package:dreamic/utils/logger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

/// Mutable RemoteConfig mock — stands in for Firebase Remote Config so the
/// `breadcrumbLevel` value can be flipped at runtime (as a real RC publish would,
/// without a rebuild).
class _MutableRemoteConfigMock implements RemoteConfigRepoInt {
  final Map<String, dynamic> _values = {};
  void setString(String key, String value) => _values[key] = value;

  @override
  String getString(String key) => _values[key] as String? ?? '';
  @override
  bool getBool(String key) => _values[key] as bool? ?? false;
  @override
  int getInt(String key) => _values[key] as int? ?? 0;
  @override
  double getDouble(String key) => _values[key] as double? ?? 0.0;
}

/// Records every breadcrumb forwarded to the reporter.
class _RecordingBreadcrumbReporter extends ErrorReporter {
  final List<String> messages = [];

  @override
  void recordError(Object error, StackTrace? stackTrace) {}

  @override
  void addBreadcrumb(String message, {String? category, Map<String, dynamic>? data}) {
    messages.add(message);
  }
}

void main() {
  late _MutableRemoteConfigMock mockRC;
  late _RecordingBreadcrumbReporter reporter;

  setUp(() {
    mockRC = _MutableRemoteConfigMock();
    if (GetIt.I.isRegistered<RemoteConfigRepoInt>()) {
      GetIt.I.unregister<RemoteConfigRepoInt>();
    }
    GetIt.I.registerSingleton<RemoteConfigRepoInt>(mockRC);
    reporter = _RecordingBreadcrumbReporter();
    Logger.setCustomErrorReporter(reporter);
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

  group('BEH-4 — RC breadcrumbLevel flip captures logd crumbs without rebuild',
      () {
    test(
        'a debug (logd-equivalent) breadcrumb is dropped at the default info, '
        'then captured after RC lowers breadcrumbLevel to debug — same process, '
        'no rebuild', () {
      // (1) No RC key set ⇒ getter falls back to the seeded default `info`
      //     (ERH-044: until the key is seeded the app runs on the default). A
      //     debug-level breadcrumb (the breadcrumb form of a `logd`) is below the
      //     info threshold → dropped.
      expect(AppConfigBase.breadcrumbLevel, LogLevel.info);
      logBreadcrumb('logd-shaped detail', level: LogLevel.debug);
      expect(reporter.messages, isEmpty);

      // (2) Lower the threshold to `debug` via RC — the runtime flip BEH-4
      //     describes (a production RC publish, no redeploy). The getter reads RC
      //     live, so no rebuild is needed.
      mockRC.setString('breadcrumbLevel', 'debug');
      expect(AppConfigBase.breadcrumbLevel, LogLevel.debug);

      // (3) The SAME debug-level breadcrumb now passes the (emit-time) gate and
      //     is forwarded — captured without a rebuild.
      logBreadcrumb('logd-shaped detail', level: LogLevel.debug);
      expect(reporter.messages, ['logd-shaped detail']);
    });

    test('raising breadcrumbLevel back to info via RC re-drops debug crumbs '
        '(the gate re-reads RC each emit)', () {
      mockRC.setString('breadcrumbLevel', 'debug');
      logBreadcrumb('captured', level: LogLevel.debug);
      expect(reporter.messages, ['captured']);

      // Raise the threshold back to info (another runtime RC flip).
      mockRC.setString('breadcrumbLevel', 'info');
      reporter.messages.clear();
      logBreadcrumb('dropped again', level: LogLevel.debug);
      expect(reporter.messages, isEmpty);
    });
  });
}
