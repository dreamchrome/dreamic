import 'package:dreamic/app/app_config_base.dart';
import 'package:dreamic/app/helpers/app_remote_config_init.dart';
import 'package:flutter_test/flutter_test.dart';

/// Validator tests for Lever 3's `buildValidatedRemoteConfigDefaults`
/// (Issue OQ-003 — reachable directly via @visibleForTesting, no Firebase/GetIt
/// harness needed). See plan `remote-config-default-hardening`.
void main() {
  group('buildValidatedRemoteConfigDefaults', () {
    test('null additionalDefaultConfigs merges only DreamIC defaults and passes',
        () {
      final merged = buildValidatedRemoteConfigDefaults(null);
      // DreamIC's own defaults are scalar-only (guarded elsewhere), so this
      // must not throw and must contain DreamIC's keys.
      expect(merged, isNotEmpty);
      expect(merged['notificationGoToSettingsMaxAskCount'],
          equals(AppConfigBase.notificationMaxAskCountUnlimited));
    });

    test('empty additionalDefaultConfigs merges only DreamIC defaults and passes',
        () {
      final merged = buildValidatedRemoteConfigDefaults(<String, dynamic>{});
      expect(merged.length, equals(AppConfigBase.defaultRemoteConfig.length));
    });

    test('valid scalar additionalDefaultConfigs values do not throw', () {
      final merged = buildValidatedRemoteConfigDefaults(<String, dynamic>{
        'consumerString': 'hello',
        'consumerInt': 42,
        'consumerDouble': 3.14,
        'consumerBool': true,
      });
      expect(merged['consumerString'], equals('hello'));
      expect(merged['consumerInt'], equals(42));
      expect(merged['consumerDouble'], equals(3.14));
      expect(merged['consumerBool'], isTrue);
    });

    test('consumer override of a DreamIC default with a scalar passes', () {
      final merged = buildValidatedRemoteConfigDefaults(<String, dynamic>{
        'notificationGoToSettingsMaxAskCount': 100,
      });
      // Consumer value wins over DreamIC's sentinel default.
      expect(merged['notificationGoToSettingsMaxAskCount'], equals(100));
    });

    test('a null value throws an ArgumentError naming the offending key', () {
      expect(
        () => buildValidatedRemoteConfigDefaults(<String, dynamic>{
          'badNullKey': null,
        }),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            allOf(contains("'badNullKey'"), contains('Null')),
          ),
        ),
      );
    });

    test('a non-scalar (List) value throws an ArgumentError naming the key', () {
      expect(
        () => buildValidatedRemoteConfigDefaults(<String, dynamic>{
          'badListKey': [1, 2, 3],
        }),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            contains("'badListKey'"),
          ),
        ),
      );
    });

    test('a non-scalar (Map) value throws an ArgumentError', () {
      expect(
        () => buildValidatedRemoteConfigDefaults(<String, dynamic>{
          'badMapKey': {'nested': 'value'},
        }),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('multiple offenders are all named in the message', () {
      expect(
        () => buildValidatedRemoteConfigDefaults(<String, dynamic>{
          'firstBad': null,
          'secondBad': <int>[],
        }),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            allOf(contains("'firstBad'"), contains("'secondBad'")),
          ),
        ),
      );
    });

    test('the error message states defaults must be bool, num, or String', () {
      expect(
        () => buildValidatedRemoteConfigDefaults(<String, dynamic>{
          'badNullKey': null,
        }),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            contains('bool, num, or String'),
          ),
        ),
      );
    });
  });
}
