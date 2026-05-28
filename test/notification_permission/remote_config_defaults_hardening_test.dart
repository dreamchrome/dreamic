import 'package:dreamic/app/app_config_base.dart';
import 'package:dreamic/data/repos/remote_config_repo_int.dart';
import 'package:dreamic/data/repos/remote_config_repo_mockimpl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

/// Hardening tests for the Remote Config default map (Levers 1 & 2 + the
/// Companion CI guard). See plan `remote-config-default-hardening`.
void main() {
  group('CI scalar-only guard for AppConfigBase.defaultRemoteConfig', () {
    test('every default value is bool, num, or String', () {
      // Mirrors Firebase RC's _checkIsSupportedType. Defense in depth alongside
      // the Map<String, Object> compile guard: catches a regression even if the
      // field type were ever loosened back to dynamic.
      final offenders = <String>[];
      AppConfigBase.defaultRemoteConfig.forEach((key, value) {
        if (value is! bool && value is! num && value is! String) {
          offenders.add("'$key' = ${value.runtimeType}");
        }
      });

      expect(
        offenders,
        isEmpty,
        reason: 'Unsupported default value type(s): ${offenders.join(', ')}',
      );
    });
  });

  group('Sentinel representation (Lever 2)', () {
    // The getters read the in-memory programmatic default via a GetIt-resolved
    // RemoteConfigRepoInt; register a stub returning 0 (= "unset") so resolution
    // falls through to the programmatic default.
    late _UnsetRemoteConfigStub stubRC;
    late int origGoToSettingsMaxAskCount;
    late int origValuePropReminderMaxAskCount;

    setUp(() {
      origGoToSettingsMaxAskCount =
          AppConfigBase.defaultRemoteConfig['notificationGoToSettingsMaxAskCount'] as int;
      origValuePropReminderMaxAskCount = AppConfigBase
          .defaultRemoteConfig['notificationValuePropReminderMaxAskCount'] as int;

      stubRC = _UnsetRemoteConfigStub();
      if (GetIt.I.isRegistered<RemoteConfigRepoInt>()) {
        GetIt.I.unregister<RemoteConfigRepoInt>();
      }
      GetIt.I.registerSingleton<RemoteConfigRepoInt>(stubRC);
    });

    tearDown(() {
      AppConfigBase.defaultRemoteConfig['notificationGoToSettingsMaxAskCount'] =
          origGoToSettingsMaxAskCount;
      AppConfigBase.defaultRemoteConfig['notificationValuePropReminderMaxAskCount'] =
          origValuePropReminderMaxAskCount;

      if (GetIt.I.isRegistered<RemoteConfigRepoInt>()) {
        GetIt.I.unregister<RemoteConfigRepoInt>();
      }
    });

    test('stored default for the two keys equals the unlimited sentinel', () {
      expect(
        AppConfigBase.defaultRemoteConfig['notificationGoToSettingsMaxAskCount'],
        equals(AppConfigBase.notificationMaxAskCountUnlimited),
      );
      expect(
        AppConfigBase.defaultRemoteConfig['notificationValuePropReminderMaxAskCount'],
        equals(AppConfigBase.notificationMaxAskCountUnlimited),
      );
    });

    test('the unlimited sentinel value is -1', () {
      expect(AppConfigBase.notificationMaxAskCountUnlimited, equals(-1));
    });

    test('getter maps the stored sentinel back to null (unlimited)', () {
      expect(AppConfigBase.notificationGoToSettingsMaxAskCount, isNull);
      expect(AppConfigBase.notificationValuePropReminderMaxAskCount, isNull);
    });

    test('programmatic default = 0 resolves to 0 (not null) — 0 passes through',
        () {
      AppConfigBase.notificationGoToSettingsMaxAskCountDefault = 0;
      AppConfigBase.notificationValuePropReminderMaxAskCountDefault = 0;
      expect(AppConfigBase.notificationGoToSettingsMaxAskCount, equals(0));
      expect(AppConfigBase.notificationValuePropReminderMaxAskCount, equals(0));
    });

    test('setter translates null to the sentinel in the stored map', () {
      AppConfigBase.notificationGoToSettingsMaxAskCountDefault = null;
      AppConfigBase.notificationValuePropReminderMaxAskCountDefault = null;
      expect(
        AppConfigBase.defaultRemoteConfig['notificationGoToSettingsMaxAskCount'],
        equals(AppConfigBase.notificationMaxAskCountUnlimited),
      );
      expect(
        AppConfigBase.defaultRemoteConfig['notificationValuePropReminderMaxAskCount'],
        equals(AppConfigBase.notificationMaxAskCountUnlimited),
      );
    });
  });

  group('Production mock read (behavior E1, Issue OQ-010)', () {
    test(
        'RemoteConfigRepoMockImpl.getInt on the two notification keys returns the '
        'sentinel without throwing a CastError', () {
      // Constructs the production mock with the real defaults (not the inline
      // stubs the notification tests use, whose getInt returns `?? 0`). Before
      // the sentinel change these keys held null, so `defaultValues[key] as int`
      // CastError'd; now they hold the -1 sentinel and read cleanly.
      final mock = RemoteConfigRepoMockImpl({...AppConfigBase.defaultRemoteConfig});

      expect(
        mock.getInt('notificationGoToSettingsMaxAskCount'),
        equals(AppConfigBase.notificationMaxAskCountUnlimited),
      );
      expect(
        mock.getInt('notificationValuePropReminderMaxAskCount'),
        equals(AppConfigBase.notificationMaxAskCountUnlimited),
      );
    });
  });
}

/// RemoteConfigRepoInt stub whose int reads return 0 ("unset"), so getter
/// resolution falls through to the in-memory programmatic default.
class _UnsetRemoteConfigStub implements RemoteConfigRepoInt {
  @override
  String getString(String key) => '';
  @override
  bool getBool(String key) => false;
  @override
  int getInt(String key) => 0;
  @override
  double getDouble(String key) => 0.0;
}
