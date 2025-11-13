import 'package:dreamic/data/models/notification_action.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NotificationAction', () {
    group('fromJson / toJson', () {
      test('serializes and deserializes with all fields', () {
        final original = NotificationAction(
          id: 'reply',
          label: 'Reply',
          icon: 'ic_reply',
          requiresAuth: true,
          launchesApp: false,
        );

        final json = original.toJson();
        final deserialized = NotificationAction.fromJson(json);

        expect(deserialized.id, equals(original.id));
        expect(deserialized.label, equals(original.label));
        expect(deserialized.icon, equals(original.icon));
        expect(deserialized.requiresAuth, equals(original.requiresAuth));
        expect(deserialized.launchesApp, equals(original.launchesApp));
      });

      test('serializes and deserializes with minimal fields', () {
        final original = NotificationAction(
          id: 'view',
          label: 'View',
        );

        final json = original.toJson();
        final deserialized = NotificationAction.fromJson(json);

        expect(deserialized.id, equals('view'));
        expect(deserialized.label, equals('View'));
        expect(deserialized.icon, isNull);
        expect(deserialized.requiresAuth, isFalse);
        expect(deserialized.launchesApp, isTrue);
      });

      test('handles default values correctly', () {
        final json = {
          'id': 'action1',
          'label': 'Action 1',
        };

        final action = NotificationAction.fromJson(json);

        expect(action.requiresAuth, isFalse);
        expect(action.launchesApp, isTrue);
      });

      test('handles explicit false values', () {
        final json = {
          'id': 'action1',
          'label': 'Action 1',
          'requiresAuth': false,
          'launchesApp': false,
        };

        final action = NotificationAction.fromJson(json);

        expect(action.requiresAuth, isFalse);
        expect(action.launchesApp, isFalse);
      });

      test('handles null icon', () {
        final action = NotificationAction(
          id: 'delete',
          label: 'Delete',
          icon: null,
        );

        final json = action.toJson();
        final deserialized = NotificationAction.fromJson(json);

        expect(deserialized.icon, isNull);
      });

      test('round-trip preserves all values', () {
        final original = NotificationAction(
          id: 'mark_read',
          label: 'Mark as Read',
          icon: 'ic_check',
          requiresAuth: false,
          launchesApp: true,
        );

        final json = original.toJson();
        final roundTrip = NotificationAction.fromJson(json);
        final json2 = roundTrip.toJson();

        expect(json, equals(json2));
      });
    });

    group('constructor', () {
      test('creates action with required fields', () {
        final action = NotificationAction(
          id: 'test',
          label: 'Test Action',
        );

        expect(action.id, equals('test'));
        expect(action.label, equals('Test Action'));
        expect(action.icon, isNull);
        expect(action.requiresAuth, isFalse);
        expect(action.launchesApp, isTrue);
      });

      test('creates action with all fields', () {
        final action = NotificationAction(
          id: 'secure_action',
          label: 'Secure Action',
          icon: 'ic_lock',
          requiresAuth: true,
          launchesApp: false,
        );

        expect(action.id, equals('secure_action'));
        expect(action.label, equals('Secure Action'));
        expect(action.icon, equals('ic_lock'));
        expect(action.requiresAuth, isTrue);
        expect(action.launchesApp, isFalse);
      });

      test('creates const action', () {
        const action = NotificationAction(
          id: 'const_action',
          label: 'Const Action',
        );

        expect(action.id, equals('const_action'));
        expect(action.label, equals('Const Action'));
      });
    });

    group('equality', () {
      test('equal actions are equal', () {
        final action1 = NotificationAction(
          id: 'test',
          label: 'Test',
          icon: 'ic_test',
          requiresAuth: true,
          launchesApp: false,
        );

        final action2 = NotificationAction(
          id: 'test',
          label: 'Test',
          icon: 'ic_test',
          requiresAuth: true,
          launchesApp: false,
        );

        expect(action1, equals(action2));
        expect(action1.hashCode, equals(action2.hashCode));
      });

      test('actions with different ids are not equal', () {
        final action1 = NotificationAction(id: 'action1', label: 'Action');
        final action2 = NotificationAction(id: 'action2', label: 'Action');

        expect(action1, isNot(equals(action2)));
      });

      test('actions with different labels are not equal', () {
        final action1 = NotificationAction(id: 'test', label: 'Label 1');
        final action2 = NotificationAction(id: 'test', label: 'Label 2');

        expect(action1, isNot(equals(action2)));
      });

      test('actions with different icons are not equal', () {
        final action1 = NotificationAction(
          id: 'test',
          label: 'Test',
          icon: 'ic_one',
        );
        final action2 = NotificationAction(
          id: 'test',
          label: 'Test',
          icon: 'ic_two',
        );

        expect(action1, isNot(equals(action2)));
      });

      test('actions with different requiresAuth are not equal', () {
        final action1 = NotificationAction(
          id: 'test',
          label: 'Test',
          requiresAuth: true,
        );
        final action2 = NotificationAction(
          id: 'test',
          label: 'Test',
          requiresAuth: false,
        );

        expect(action1, isNot(equals(action2)));
      });

      test('actions with different launchesApp are not equal', () {
        final action1 = NotificationAction(
          id: 'test',
          label: 'Test',
          launchesApp: true,
        );
        final action2 = NotificationAction(
          id: 'test',
          label: 'Test',
          launchesApp: false,
        );

        expect(action1, isNot(equals(action2)));
      });

      test('identical actions are the same object', () {
        final action = NotificationAction(id: 'test', label: 'Test');

        expect(identical(action, action), isTrue);
        expect(action == action, isTrue);
      });
    });

    group('toString', () {
      test('provides readable string representation', () {
        final action = NotificationAction(
          id: 'reply',
          label: 'Reply',
          icon: 'ic_reply',
          requiresAuth: true,
          launchesApp: false,
        );

        final str = action.toString();

        expect(str, contains('reply'));
        expect(str, contains('Reply'));
        expect(str, contains('ic_reply'));
        expect(str, contains('requiresAuth: true'));
        expect(str, contains('launchesApp: false'));
      });

      test('includes null icon in string', () {
        final action = NotificationAction(
          id: 'test',
          label: 'Test',
        );

        final str = action.toString();

        expect(str, contains('icon: null'));
      });
    });

    group('use cases', () {
      test('creates typical reply action', () {
        final action = NotificationAction(
          id: 'reply',
          label: 'Reply',
          icon: 'ic_reply',
          requiresAuth: false,
          launchesApp: true,
        );

        expect(action.id, equals('reply'));
        expect(action.launchesApp, isTrue);
      });

      test('creates secure action requiring authentication', () {
        final action = NotificationAction(
          id: 'delete',
          label: 'Delete',
          icon: 'ic_delete',
          requiresAuth: true,
          launchesApp: false,
        );

        expect(action.requiresAuth, isTrue);
        expect(action.launchesApp, isFalse);
      });

      test('creates background action', () {
        final action = NotificationAction(
          id: 'mark_read',
          label: 'Mark as Read',
          requiresAuth: false,
          launchesApp: false,
        );

        expect(action.launchesApp, isFalse);
      });
    });

    group('JSON edge cases', () {
      test('handles extra fields in JSON', () {
        final json = {
          'id': 'test',
          'label': 'Test',
          'extraField': 'ignored',
          'anotherField': 123,
        };

        final action = NotificationAction.fromJson(json);

        expect(action.id, equals('test'));
        expect(action.label, equals('Test'));
      });

      test('serializes to JSON with expected fields', () {
        final action = NotificationAction(
          id: 'test',
          label: 'Test',
          icon: 'ic_test',
          requiresAuth: true,
          launchesApp: false,
        );

        final json = action.toJson();

        expect(json, containsPair('id', 'test'));
        expect(json, containsPair('label', 'Test'));
        expect(json, containsPair('icon', 'ic_test'));
        expect(json, containsPair('requiresAuth', true));
        expect(json, containsPair('launchesApp', false));
      });
    });
  });
}
