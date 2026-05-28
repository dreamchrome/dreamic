import 'dart:convert';

import 'package:dreamic/app/app_config_base.dart';
import 'package:dreamic/data/models/notification_permission_status.dart';
import 'package:dreamic/data/repos/remote_config_repo_int.dart';
import 'package:dreamic/notifications/notification_permission_helper.dart';
import 'package:dreamic/notifications/notification_service.dart';
import 'package:dreamic/notifications/notification_types.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mocks/mock_shared_preferences.dart';

/// Returns sensible defaults for unset RC keys (Firebase RC's actual behavior).
class _StubRemoteConfig implements RemoteConfigRepoInt {
  final Map<String, dynamic> _values = {};

  void setInt(String key, int value) => _values[key] = value;

  @override
  String getString(String key) => _values[key] as String? ?? '';
  @override
  bool getBool(String key) => _values[key] as bool? ?? false;
  @override
  int getInt(String key) => _values[key] as int? ?? 0;
  @override
  double getDouble(String key) => _values[key] as double? ?? 0.0;
}

/// Seeds [ValuePropDeclineInfo] into the mock SharedPreferences.
void _seedValuePropDeclineInfo({
  required DateTime lastDeclineTime,
  required int declineCount,
}) {
  final info = ValuePropDeclineInfo(
    lastDeclineTime: lastDeclineTime,
    declineCount: declineCount,
  );
  SharedPreferences.setMockInitialValues({
    MockSharedPreferencesHelper.keyMigrationComplete: true,
    'dreamic_notification_value_prop_decline_info': jsonEncode(info.toJson()),
  });
}

void main() {
  late NotificationService service;
  late NotificationPermissionHelper helper;
  late _StubRemoteConfig stubRC;

  // Snapshot of programmatic defaults so each test starts/ends clean (OQ-010).
  late int origCooldownDays;
  late int origMaxAskCount;

  setUp(() {
    origCooldownDays = AppConfigBase
        .defaultRemoteConfig['notificationValuePropReminderCooldownDays'] as int;
    origMaxAskCount = AppConfigBase
        .defaultRemoteConfig['notificationValuePropReminderMaxAskCount'] as int;

    stubRC = _StubRemoteConfig();
    if (GetIt.I.isRegistered<RemoteConfigRepoInt>()) {
      GetIt.I.unregister<RemoteConfigRepoInt>();
    }
    GetIt.I.registerSingleton<RemoteConfigRepoInt>(stubRC);

    NotificationService.resetForTesting();
    service = NotificationService();
    helper = NotificationPermissionHelper(notificationService: service);

    // Default to no decline info (empty SP). Individual tests override.
    MockSharedPreferencesHelper.setupEmpty();
  });

  tearDown(() {
    service.testGetPermissionStatusOverride = null;
    NotificationService.resetForTesting();

    AppConfigBase.defaultRemoteConfig['notificationValuePropReminderCooldownDays'] =
        origCooldownDays;
    AppConfigBase.defaultRemoteConfig['notificationValuePropReminderMaxAskCount'] =
        origMaxAskCount;

    if (GetIt.I.isRegistered<RemoteConfigRepoInt>()) {
      GetIt.I.unregister<RemoteConfigRepoInt>();
    }
  });

  group('shouldShowValuePropReminder — permission status gating', () {
    test('returns false when status is denied (handled by go-to-settings flow)',
        () async {
      _seedValuePropDeclineInfo(
        lastDeclineTime: DateTime.now().subtract(const Duration(days: 365)),
        declineCount: 1,
      );
      service.testGetPermissionStatusOverride =
          () async => NotificationPermissionStatus.denied;

      expect(await helper.shouldShowValuePropReminder(), isFalse);
    });

    test('returns false when status is authorized', () async {
      _seedValuePropDeclineInfo(
        lastDeclineTime: DateTime.now().subtract(const Duration(days: 365)),
        declineCount: 1,
      );
      service.testGetPermissionStatusOverride =
          () async => NotificationPermissionStatus.authorized;

      expect(await helper.shouldShowValuePropReminder(), isFalse);
    });

    test('returns false when status is provisional', () async {
      _seedValuePropDeclineInfo(
        lastDeclineTime: DateTime.now().subtract(const Duration(days: 365)),
        declineCount: 1,
      );
      service.testGetPermissionStatusOverride =
          () async => NotificationPermissionStatus.provisional;

      expect(await helper.shouldShowValuePropReminder(), isFalse);
    });
  });

  group('shouldShowValuePropReminder — no decline info', () {
    test('returns false when no decline info exists (never declined)', () async {
      // SP empty, status notDetermined.
      service.testGetPermissionStatusOverride =
          () async => NotificationPermissionStatus.notDetermined;

      expect(await helper.shouldShowValuePropReminder(), isFalse);
    });
  });

  group('shouldShowValuePropReminder — cooldown gating', () {
    test('returns false when timeSinceDecline < cooldown', () async {
      _seedValuePropDeclineInfo(
        lastDeclineTime: DateTime.now().subtract(const Duration(days: 5)),
        declineCount: 1,
      );
      service.testGetPermissionStatusOverride =
          () async => NotificationPermissionStatus.notDetermined;

      expect(
        await helper.shouldShowValuePropReminder(
          cooldown: const Duration(days: 30),
        ),
        isFalse,
      );
    });

    test('returns true when timeSinceDecline >= cooldown', () async {
      _seedValuePropDeclineInfo(
        lastDeclineTime: DateTime.now().subtract(const Duration(days: 31)),
        declineCount: 1,
      );
      service.testGetPermissionStatusOverride =
          () async => NotificationPermissionStatus.notDetermined;

      expect(
        await helper.shouldShowValuePropReminder(
          cooldown: const Duration(days: 30),
        ),
        isTrue,
      );
    });

    test('cooldown: Duration.zero always passes timing gate', () async {
      // Even a decline that just happened passes the timing gate.
      _seedValuePropDeclineInfo(
        lastDeclineTime: DateTime.now(),
        declineCount: 1,
      );
      service.testGetPermissionStatusOverride =
          () async => NotificationPermissionStatus.notDetermined;

      expect(
        await helper.shouldShowValuePropReminder(
          cooldown: Duration.zero,
        ),
        isTrue,
      );
    });
  });

  group('shouldShowValuePropReminder — maxAskCount gating', () {
    test('maxAskCount: 1 returns true once then false after second decline',
        () async {
      // After first decline (declineCount=1): 1 < 1+1, cap allows; cooldown ok → true.
      _seedValuePropDeclineInfo(
        lastDeclineTime: DateTime.now().subtract(const Duration(days: 60)),
        declineCount: 1,
      );
      service.testGetPermissionStatusOverride =
          () async => NotificationPermissionStatus.notDetermined;

      expect(
        await helper.shouldShowValuePropReminder(
          cooldown: const Duration(days: 30),
          maxAskCount: 1,
        ),
        isTrue,
      );

      // After second decline (declineCount=2): 2 >= 1+1, cap blocks → false.
      _seedValuePropDeclineInfo(
        lastDeclineTime: DateTime.now().subtract(const Duration(days: 60)),
        declineCount: 2,
      );
      // Recreate helper so the seeded SP is read fresh.
      helper = NotificationPermissionHelper(notificationService: service);

      expect(
        await helper.shouldShowValuePropReminder(
          cooldown: const Duration(days: 30),
          maxAskCount: 1,
        ),
        isFalse,
      );
    });

    test('maxAskCount: 0 returns false after first decline', () async {
      _seedValuePropDeclineInfo(
        lastDeclineTime: DateTime.now().subtract(const Duration(days: 365)),
        declineCount: 1,
      );
      service.testGetPermissionStatusOverride =
          () async => NotificationPermissionStatus.notDetermined;

      // 1 >= 0+1 → cap blocks → false (even though cooldown elapsed).
      expect(
        await helper.shouldShowValuePropReminder(
          cooldown: const Duration(days: 30),
          maxAskCount: 0,
        ),
        isFalse,
      );
    });

    test('maxAskCount: -5 inline same as 0 (never re-prompt)', () async {
      _seedValuePropDeclineInfo(
        lastDeclineTime: DateTime.now().subtract(const Duration(days: 365)),
        declineCount: 1,
      );
      service.testGetPermissionStatusOverride =
          () async => NotificationPermissionStatus.notDetermined;

      // 1 >= -5+1=-4 → cap blocks → false.
      expect(
        await helper.shouldShowValuePropReminder(
          cooldown: const Duration(days: 30),
          maxAskCount: -5,
        ),
        isFalse,
      );
    });

    test('maxAskCount: null with AppConfigBase null default = unlimited', () async {
      _seedValuePropDeclineInfo(
        lastDeclineTime: DateTime.now().subtract(const Duration(days: 365)),
        declineCount: 100, // arbitrarily large count
      );
      service.testGetPermissionStatusOverride =
          () async => NotificationPermissionStatus.notDetermined;
      // AppConfigBase default is null; cap is skipped; cooldown gates.

      expect(
        await helper.shouldShowValuePropReminder(
          cooldown: const Duration(days: 30),
        ),
        isTrue,
      );
    });
  });

  group('shouldShowValuePropReminder — AppConfigBase fall-through', () {
    test('cooldown: null falls through to AppConfigBase cooldownDays default '
        '(30 days)', () async {
      // Decline 25 days ago — still within default 30-day cooldown.
      _seedValuePropDeclineInfo(
        lastDeclineTime: DateTime.now().subtract(const Duration(days: 25)),
        declineCount: 1,
      );
      service.testGetPermissionStatusOverride =
          () async => NotificationPermissionStatus.notDetermined;

      expect(await helper.shouldShowValuePropReminder(), isFalse);

      // Decline 35 days ago — past default 30-day cooldown.
      _seedValuePropDeclineInfo(
        lastDeclineTime: DateTime.now().subtract(const Duration(days: 35)),
        declineCount: 1,
      );
      helper = NotificationPermissionHelper(notificationService: service);

      expect(await helper.shouldShowValuePropReminder(), isTrue);
    });

    test('cooldown: null with overridden AppConfigBase default (14 days)',
        () async {
      AppConfigBase.notificationValuePropReminderCooldownDaysDefault = 14;

      _seedValuePropDeclineInfo(
        lastDeclineTime: DateTime.now().subtract(const Duration(days: 15)),
        declineCount: 1,
      );
      service.testGetPermissionStatusOverride =
          () async => NotificationPermissionStatus.notDetermined;

      // 15 days >= 14 day cooldown → true.
      expect(await helper.shouldShowValuePropReminder(), isTrue);

      // 13 days < 14 day cooldown → false.
      _seedValuePropDeclineInfo(
        lastDeclineTime: DateTime.now().subtract(const Duration(days: 13)),
        declineCount: 1,
      );
      helper = NotificationPermissionHelper(notificationService: service);

      expect(await helper.shouldShowValuePropReminder(), isFalse);
    });

    test('maxAskCount: null falls through to AppConfigBase maxAskCount default',
        () async {
      AppConfigBase.notificationValuePropReminderMaxAskCountDefault = 2;

      _seedValuePropDeclineInfo(
        lastDeclineTime: DateTime.now().subtract(const Duration(days: 365)),
        declineCount: 3, // 3 >= 2+1, cap blocks
      );
      service.testGetPermissionStatusOverride =
          () async => NotificationPermissionStatus.notDetermined;

      expect(
        await helper.shouldShowValuePropReminder(
          cooldown: const Duration(days: 30),
        ),
        isFalse,
      );

      // declineCount=2: 2 < 2+1, cap allows; cooldown elapsed → true.
      _seedValuePropDeclineInfo(
        lastDeclineTime: DateTime.now().subtract(const Duration(days: 365)),
        declineCount: 2,
      );
      helper = NotificationPermissionHelper(notificationService: service);

      expect(
        await helper.shouldShowValuePropReminder(
          cooldown: const Duration(days: 30),
        ),
        isTrue,
      );
    });

    test('inline cooldown overrides AppConfigBase cooldownDays default',
        () async {
      AppConfigBase.notificationValuePropReminderCooldownDaysDefault = 14;

      _seedValuePropDeclineInfo(
        lastDeclineTime: DateTime.now().subtract(const Duration(days: 20)),
        declineCount: 1,
      );
      service.testGetPermissionStatusOverride =
          () async => NotificationPermissionStatus.notDetermined;

      // Inline 60-day cooldown overrides the 14-day AppConfigBase default;
      // 20 days < 60 day inline cooldown → false.
      expect(
        await helper.shouldShowValuePropReminder(
          cooldown: const Duration(days: 60),
        ),
        isFalse,
      );
    });

    test('inline maxAskCount overrides AppConfigBase maxAskCount default',
        () async {
      AppConfigBase.notificationValuePropReminderMaxAskCountDefault = 10;

      _seedValuePropDeclineInfo(
        lastDeclineTime: DateTime.now().subtract(const Duration(days: 365)),
        declineCount: 1,
      );
      service.testGetPermissionStatusOverride =
          () async => NotificationPermissionStatus.notDetermined;

      // Inline maxAskCount: 0 overrides AppConfigBase default of 10;
      // 1 >= 0+1 → cap blocks → false.
      expect(
        await helper.shouldShowValuePropReminder(
          cooldown: const Duration(days: 30),
          maxAskCount: 0,
        ),
        isFalse,
      );
    });
  });

  group('shouldShowValuePropReminder — error handling', () {
    test('returns false when getPermissionStatus throws', () async {
      _seedValuePropDeclineInfo(
        lastDeclineTime: DateTime.now().subtract(const Duration(days: 365)),
        declineCount: 1,
      );
      service.testGetPermissionStatusOverride = () async {
        throw Exception('simulated permission status failure');
      };

      expect(await helper.shouldShowValuePropReminder(), isFalse);
    });
  });
}
