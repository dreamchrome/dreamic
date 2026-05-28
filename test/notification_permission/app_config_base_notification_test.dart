import 'package:dreamic/app/app_config_base.dart';
import 'package:dreamic/data/repos/remote_config_repo_int.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

/// Mutable RemoteConfig mock for tests. Returns sensible defaults (0, '', false)
/// for unset keys, mirroring Firebase RC's behavior, but allows per-test
/// overrides via [setInt].
class _MutableRemoteConfigMock implements RemoteConfigRepoInt {
  final Map<String, dynamic> _values = {};

  void setInt(String key, int value) => _values[key] = value;
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

void main() {
  late _MutableRemoteConfigMock mockRC;

  // Snapshot of programmatic defaults so each test starts/ends clean.
  // Per OQ-010: defaultRemoteConfig is static; mutations persist across tests.
  late int origGoToSettingsAskAgainDays;
  late int origGoToSettingsMaxAskCount;
  late int origValuePropReminderCooldownDays;
  late int origValuePropReminderMaxAskCount;

  setUp(() {
    origGoToSettingsAskAgainDays =
        AppConfigBase.defaultRemoteConfig['notificationGoToSettingsAskAgainDays'] as int;
    origGoToSettingsMaxAskCount =
        AppConfigBase.defaultRemoteConfig['notificationGoToSettingsMaxAskCount'] as int;
    origValuePropReminderCooldownDays = AppConfigBase
        .defaultRemoteConfig['notificationValuePropReminderCooldownDays'] as int;
    origValuePropReminderMaxAskCount = AppConfigBase
        .defaultRemoteConfig['notificationValuePropReminderMaxAskCount'] as int;

    mockRC = _MutableRemoteConfigMock();
    if (GetIt.I.isRegistered<RemoteConfigRepoInt>()) {
      GetIt.I.unregister<RemoteConfigRepoInt>();
    }
    GetIt.I.registerSingleton<RemoteConfigRepoInt>(mockRC);
  });

  tearDown(() {
    AppConfigBase.defaultRemoteConfig['notificationGoToSettingsAskAgainDays'] =
        origGoToSettingsAskAgainDays;
    AppConfigBase.defaultRemoteConfig['notificationGoToSettingsMaxAskCount'] =
        origGoToSettingsMaxAskCount;
    AppConfigBase.defaultRemoteConfig['notificationValuePropReminderCooldownDays'] =
        origValuePropReminderCooldownDays;
    AppConfigBase.defaultRemoteConfig['notificationValuePropReminderMaxAskCount'] =
        origValuePropReminderMaxAskCount;

    if (GetIt.I.isRegistered<RemoteConfigRepoInt>()) {
      GetIt.I.unregister<RemoteConfigRepoInt>();
    }
  });

  group('AppConfigBase.notificationGoToSettingsAskAgainDays', () {
    test('falls through to programmatic default when env unset and RC unset', () {
      // RC unset → mock returns 0 → falls through to programmatic default (30).
      expect(AppConfigBase.notificationGoToSettingsAskAgainDays, equals(30));
    });

    test('reads from Remote Config when set to a positive value', () {
      mockRC.setInt('notificationGoToSettingsAskAgainDays', 14);
      expect(AppConfigBase.notificationGoToSettingsAskAgainDays, equals(14));
    });

    test('clamps Remote Config value to upper bound (365)', () {
      mockRC.setInt('notificationGoToSettingsAskAgainDays', 1000);
      expect(AppConfigBase.notificationGoToSettingsAskAgainDays, equals(365));
    });

    test('falls through to default when Remote Config value is 0', () {
      mockRC.setInt('notificationGoToSettingsAskAgainDays', 0);
      expect(AppConfigBase.notificationGoToSettingsAskAgainDays, equals(30));
    });

    test('honors programmatic default override', () {
      AppConfigBase.notificationGoToSettingsAskAgainDaysDefault = 90;
      expect(AppConfigBase.notificationGoToSettingsAskAgainDays, equals(90));
    });

    // Env-override path: `int.fromEnvironment` is a compile-time constant. When
    // tests are run without `--dart-define notificationGoToSettingsAskAgainDays=N`,
    // envValue resolves to -1 and the code falls through to RC/default. The
    // behavior of "env != -1 returns envValue" is locked in by the source-level
    // pattern match with `notificationMaxAskCount`'s tested env override.
  });

  group('AppConfigBase.notificationGoToSettingsMaxAskCount', () {
    test('falls through to null when env unset, RC unset, default null', () {
      expect(AppConfigBase.notificationGoToSettingsMaxAskCount, isNull);
    });

    test('reads from Remote Config when set to a positive value', () {
      mockRC.setInt('notificationGoToSettingsMaxAskCount', 5);
      expect(AppConfigBase.notificationGoToSettingsMaxAskCount, equals(5));
    });

    test('clamps Remote Config value to upper bound (100)', () {
      mockRC.setInt('notificationGoToSettingsMaxAskCount', 500);
      expect(AppConfigBase.notificationGoToSettingsMaxAskCount, equals(100));
    });

    test('RC value 0 falls through to programmatic default', () {
      mockRC.setInt('notificationGoToSettingsMaxAskCount', 0);
      // Default is null
      expect(AppConfigBase.notificationGoToSettingsMaxAskCount, isNull);
    });

    test('RC value -1 falls through to programmatic default', () {
      mockRC.setInt('notificationGoToSettingsMaxAskCount', -1);
      expect(AppConfigBase.notificationGoToSettingsMaxAskCount, isNull);
    });

    test('RC value -100 falls through to programmatic default', () {
      mockRC.setInt('notificationGoToSettingsMaxAskCount', -100);
      expect(AppConfigBase.notificationGoToSettingsMaxAskCount, isNull);
    });

    test('programmatic default = 5 returns 5 when RC unset', () {
      AppConfigBase.notificationGoToSettingsMaxAskCountDefault = 5;
      expect(AppConfigBase.notificationGoToSettingsMaxAskCount, equals(5));
    });

    test('programmatic default = null returns null', () {
      AppConfigBase.notificationGoToSettingsMaxAskCountDefault = null;
      expect(AppConfigBase.notificationGoToSettingsMaxAskCount, isNull);
    });

    test('RC = 0 with programmatic default = 5 returns 5 (RC = 0 means unset)', () {
      AppConfigBase.notificationGoToSettingsMaxAskCountDefault = 5;
      mockRC.setInt('notificationGoToSettingsMaxAskCount', 0);
      expect(AppConfigBase.notificationGoToSettingsMaxAskCount, equals(5));
    });

    // Env-override path note: see comment above. The convention `--dart-define
    // notificationGoToSettingsMaxAskCount=0 returns 0` (per OQ-007) is encoded
    // by the source pattern `if (envValue != -1) return envValue;`. Verifying
    // env = 0 explicitly requires running the test binary with that define.
  });

  group('AppConfigBase.notificationValuePropReminderCooldownDays', () {
    test('falls through to programmatic default (30) when env and RC unset', () {
      expect(AppConfigBase.notificationValuePropReminderCooldownDays, equals(30));
    });

    test('reads from Remote Config when set to a positive value', () {
      mockRC.setInt('notificationValuePropReminderCooldownDays', 14);
      expect(AppConfigBase.notificationValuePropReminderCooldownDays, equals(14));
    });

    test('clamps Remote Config value to upper bound (365)', () {
      mockRC.setInt('notificationValuePropReminderCooldownDays', 1000);
      expect(AppConfigBase.notificationValuePropReminderCooldownDays, equals(365));
    });

    test('falls through to default when Remote Config value is 0', () {
      mockRC.setInt('notificationValuePropReminderCooldownDays', 0);
      expect(AppConfigBase.notificationValuePropReminderCooldownDays, equals(30));
    });

    test('honors programmatic default override', () {
      AppConfigBase.notificationValuePropReminderCooldownDaysDefault = 60;
      expect(AppConfigBase.notificationValuePropReminderCooldownDays, equals(60));
    });
  });

  group('AppConfigBase.notificationValuePropReminderMaxAskCount', () {
    test('falls through to null when env unset, RC unset, default null', () {
      expect(AppConfigBase.notificationValuePropReminderMaxAskCount, isNull);
    });

    test('reads from Remote Config when set to a positive value', () {
      mockRC.setInt('notificationValuePropReminderMaxAskCount', 3);
      expect(AppConfigBase.notificationValuePropReminderMaxAskCount, equals(3));
    });

    test('clamps Remote Config value to upper bound (100)', () {
      mockRC.setInt('notificationValuePropReminderMaxAskCount', 500);
      expect(AppConfigBase.notificationValuePropReminderMaxAskCount, equals(100));
    });

    test('RC value 0 falls through to programmatic default', () {
      mockRC.setInt('notificationValuePropReminderMaxAskCount', 0);
      expect(AppConfigBase.notificationValuePropReminderMaxAskCount, isNull);
    });

    test('RC value -1 falls through to programmatic default', () {
      mockRC.setInt('notificationValuePropReminderMaxAskCount', -1);
      expect(AppConfigBase.notificationValuePropReminderMaxAskCount, isNull);
    });

    test('RC value -100 falls through to programmatic default', () {
      mockRC.setInt('notificationValuePropReminderMaxAskCount', -100);
      expect(AppConfigBase.notificationValuePropReminderMaxAskCount, isNull);
    });

    test('programmatic default = 2 returns 2 when RC unset', () {
      AppConfigBase.notificationValuePropReminderMaxAskCountDefault = 2;
      expect(AppConfigBase.notificationValuePropReminderMaxAskCount, equals(2));
    });

    test('programmatic default = null returns null', () {
      AppConfigBase.notificationValuePropReminderMaxAskCountDefault = null;
      expect(AppConfigBase.notificationValuePropReminderMaxAskCount, isNull);
    });

    test('RC = -1 with programmatic default = 2 returns 2 (RC <= 0 means unset)',
        () {
      AppConfigBase.notificationValuePropReminderMaxAskCountDefault = 2;
      mockRC.setInt('notificationValuePropReminderMaxAskCount', -1);
      expect(AppConfigBase.notificationValuePropReminderMaxAskCount, equals(2));
    });
  });

  group('configBounds entries exist for all four new keys', () {
    test('notificationGoToSettingsAskAgainDays bounds (1, 365)', () {
      final bounds = AppConfigBase.configBounds['notificationGoToSettingsAskAgainDays'];
      expect(bounds, isNotNull);
      expect(bounds!.min, equals(1));
      expect(bounds.max, equals(365));
    });

    test('notificationGoToSettingsMaxAskCount bounds (1, 100)', () {
      final bounds = AppConfigBase.configBounds['notificationGoToSettingsMaxAskCount'];
      expect(bounds, isNotNull);
      expect(bounds!.min, equals(1));
      expect(bounds.max, equals(100));
    });

    test('notificationValuePropReminderCooldownDays bounds (1, 365)', () {
      final bounds =
          AppConfigBase.configBounds['notificationValuePropReminderCooldownDays'];
      expect(bounds, isNotNull);
      expect(bounds!.min, equals(1));
      expect(bounds.max, equals(365));
    });

    test('notificationValuePropReminderMaxAskCount bounds (1, 100)', () {
      final bounds =
          AppConfigBase.configBounds['notificationValuePropReminderMaxAskCount'];
      expect(bounds, isNotNull);
      expect(bounds!.min, equals(1));
      expect(bounds.max, equals(100));
    });
  });
}
