import 'package:dreamic/data/models/notification_action.dart';
import 'package:dreamic/data/models/notification_payload.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NotificationPayload', () {
    group('fromJson / toJson', () {
      test('serializes and deserializes correctly with all fields', () {
        final original = NotificationPayload(
          title: 'Test Title',
          body: 'Test Body',
          imageUrl: 'https://example.com/image.png',
          route: '/test-route',
          data: {'key1': 'value1', 'key2': 42},
          actions: [
            NotificationAction(
              id: 'action1',
              label: 'Action 1',
              icon: 'ic_action',
            ),
          ],
          id: 12345,
          channelId: 'test_channel',
          category: 'test_category',
          sound: 'default',
          badge: 5,
          ttl: 3600,
          priority: 'high',
        );

        final json = original.toJson();
        final deserialized = NotificationPayload.fromJson(json);

        expect(deserialized.title, equals(original.title));
        expect(deserialized.body, equals(original.body));
        expect(deserialized.imageUrl, equals(original.imageUrl));
        expect(deserialized.route, equals(original.route));
        expect(deserialized.data, equals(original.data));
        expect(deserialized.actions.length, equals(1));
        expect(deserialized.actions[0].id, equals('action1'));
        expect(deserialized.id, equals(original.id));
        expect(deserialized.channelId, equals(original.channelId));
        expect(deserialized.category, equals(original.category));
        expect(deserialized.sound, equals(original.sound));
        expect(deserialized.badge, equals(original.badge));
        expect(deserialized.ttl, equals(original.ttl));
        expect(deserialized.priority, equals(original.priority));
      });

      test('serializes and deserializes with minimal fields', () {
        final original = NotificationPayload(
          title: 'Minimal',
          body: 'Just basics',
        );

        final json = original.toJson();
        final deserialized = NotificationPayload.fromJson(json);

        expect(deserialized.title, equals('Minimal'));
        expect(deserialized.body, equals('Just basics'));
        expect(deserialized.imageUrl, isNull);
        expect(deserialized.route, isNull);
        expect(deserialized.data, isEmpty);
        expect(deserialized.actions, isEmpty);
        expect(deserialized.id, isNull);
        expect(deserialized.channelId, isNull);
      });

      test('handles null values correctly', () {
        final json = {
          'title': null,
          'body': null,
          'imageUrl': null,
          'route': null,
          'data': <String, dynamic>{},
          'actions': <Map<String, dynamic>>[],
        };

        final payload = NotificationPayload.fromJson(json);

        expect(payload.title, isNull);
        expect(payload.body, isNull);
        expect(payload.imageUrl, isNull);
        expect(payload.route, isNull);
        expect(payload.data, isEmpty);
        expect(payload.actions, isEmpty);
      });

      test('handles empty data and actions', () {
        final payload = NotificationPayload(
          title: 'Test',
          data: {},
          actions: [],
        );

        final json = payload.toJson();
        final deserialized = NotificationPayload.fromJson(json);

        expect(deserialized.data, isEmpty);
        expect(deserialized.actions, isEmpty);
      });

      test('preserves nested data structures', () {
        final payload = NotificationPayload(
          title: 'Test',
          data: {
            'nested': {'key': 'value'},
            'list': [1, 2, 3],
            'bool': true,
          },
        );

        final json = payload.toJson();
        final deserialized = NotificationPayload.fromJson(json);

        expect(deserialized.data['nested'], equals({'key': 'value'}));
        expect(deserialized.data['list'], equals([1, 2, 3]));
        expect(deserialized.data['bool'], equals(true));
      });
    });

    group('fromRemoteMessage', () {
      test('extracts data from RemoteMessage with notification', () {
        final message = RemoteMessage(
          notification: RemoteNotification(
            title: 'FCM Title',
            body: 'FCM Body',
            android: AndroidNotification(
              channelId: 'fcm_channel',
              imageUrl: 'https://example.com/android.png',
            ),
          ),
          data: {
            'route': '/fcm-route',
            'customKey': 'customValue',
          },
          ttl: 7200,
        );

        final payload = NotificationPayload.fromRemoteMessage(message);

        expect(payload.title, equals('FCM Title'));
        expect(payload.body, equals('FCM Body'));
        expect(payload.route, equals('/fcm-route'));
        expect(payload.imageUrl, equals('https://example.com/android.png'));
        expect(payload.channelId, equals('fcm_channel'));
        expect(payload.ttl, equals(7200));
        expect(payload.data['customKey'], equals('customValue'));
      });

      test('extracts data from RemoteMessage without notification object', () {
        final message = RemoteMessage(
          data: {
            'title': 'Data Title',
            'body': 'Data Body',
            'route': '/data-route',
            'imageUrl': 'https://example.com/data.png',
          },
        );

        final payload = NotificationPayload.fromRemoteMessage(message);

        expect(payload.title, equals('Data Title'));
        expect(payload.body, equals('Data Body'));
        expect(payload.route, equals('/data-route'));
        expect(payload.imageUrl, equals('https://example.com/data.png'));
      });

      test('prioritizes notification object over data fields', () {
        final message = RemoteMessage(
          notification: RemoteNotification(
            title: 'Notification Title',
            body: 'Notification Body',
          ),
          data: {
            'title': 'Data Title',
            'body': 'Data Body',
          },
        );

        final payload = NotificationPayload.fromRemoteMessage(message);

        expect(payload.title, equals('Notification Title'));
        expect(payload.body, equals('Notification Body'));
      });

      test('extracts route from multiple possible fields', () {
        final testCases = [
          {'route': '/route1'},
          {'screen': '/screen1'},
          {'deepLink': '/deeplink1'},
          {'url': '/url1'},
        ];

        for (final data in testCases) {
          final message = RemoteMessage(data: data);
          final payload = NotificationPayload.fromRemoteMessage(message);
          expect(payload.route, isNotNull);
        }
      });

      test('prioritizes route field order: route > screen > deepLink > url', () {
        final message = RemoteMessage(
          data: {
            'route': '/route',
            'screen': '/screen',
            'deepLink': '/deeplink',
            'url': '/url',
          },
        );

        final payload = NotificationPayload.fromRemoteMessage(message);
        expect(payload.route, equals('/route'));
      });

      test('extracts actions from data', () {
        final message = RemoteMessage(
          data: {
            'actions': [
              {'id': 'reply', 'label': 'Reply'},
              {'id': 'delete', 'label': 'Delete'},
            ],
          },
        );

        final payload = NotificationPayload.fromRemoteMessage(message);

        expect(payload.actions.length, equals(2));
        expect(payload.actions[0].id, equals('reply'));
        expect(payload.actions[1].id, equals('delete'));
      });

      test('handles iOS image URL', () {
        final message = RemoteMessage(
          notification: RemoteNotification(
            apple: AppleNotification(
              imageUrl: 'https://example.com/ios.png',
            ),
          ),
        );

        final payload = NotificationPayload.fromRemoteMessage(message);
        expect(payload.imageUrl, equals('https://example.com/ios.png'));
      });

      test('prioritizes Android imageUrl over iOS', () {
        final message = RemoteMessage(
          notification: RemoteNotification(
            android: AndroidNotification(
              imageUrl: 'https://example.com/android.png',
            ),
            apple: AppleNotification(
              imageUrl: 'https://example.com/ios.png',
            ),
          ),
        );

        final payload = NotificationPayload.fromRemoteMessage(message);
        expect(payload.imageUrl, equals('https://example.com/android.png'));
      });

      test('extracts iOS badge', () {
        final message = RemoteMessage(
          notification: RemoteNotification(
            apple: AppleNotification(
              badge: '5',
            ),
          ),
        );

        final payload = NotificationPayload.fromRemoteMessage(message);
        expect(payload.badge, equals(5));
      });

      test('extracts category and sound', () {
        final message = RemoteMessage(
          category: 'message_category',
          notification: RemoteNotification(
            android: AndroidNotification(
              sound: 'notification_sound',
            ),
          ),
        );

        final payload = NotificationPayload.fromRemoteMessage(message);
        expect(payload.category, equals('message_category'));
        expect(payload.sound, equals('notification_sound'));
      });

      test('handles empty RemoteMessage', () {
        final message = RemoteMessage();

        final payload = NotificationPayload.fromRemoteMessage(message);

        expect(payload.title, isNull);
        expect(payload.body, isNull);
        expect(payload.route, isNull);
        expect(payload.imageUrl, isNull);
        expect(payload.data, isNotNull); // Should have data map
        expect(payload.actions, isEmpty);
      });
    });

    group('copyWith', () {
      test('creates copy with replaced fields', () {
        final original = NotificationPayload(
          title: 'Original Title',
          body: 'Original Body',
          route: '/original',
        );

        final copy = original.copyWith(
          title: 'New Title',
          route: '/new',
        );

        expect(copy.title, equals('New Title'));
        expect(copy.body, equals('Original Body')); // Unchanged
        expect(copy.route, equals('/new'));
      });

      test('creates identical copy when no fields specified', () {
        final original = NotificationPayload(
          title: 'Test',
          body: 'Body',
        );

        final copy = original.copyWith();

        expect(copy.title, equals(original.title));
        expect(copy.body, equals(original.body));
      });
    });

    group('equality', () {
      test('equal payloads are equal', () {
        final payload1 = NotificationPayload(
          title: 'Test',
          body: 'Body',
          id: 123,
        );

        final payload2 = NotificationPayload(
          title: 'Test',
          body: 'Body',
          id: 123,
        );

        expect(payload1, equals(payload2));
        expect(payload1.hashCode, equals(payload2.hashCode));
      });

      test('different payloads are not equal', () {
        final payload1 = NotificationPayload(title: 'Test 1');
        final payload2 = NotificationPayload(title: 'Test 2');

        expect(payload1, isNot(equals(payload2)));
      });
    });

    group('toString', () {
      test('provides readable string representation', () {
        final payload = NotificationPayload(
          title: 'Test',
          body: 'Body',
          route: '/test',
          actions: [NotificationAction(id: 'a1', label: 'Action')],
          data: {'key': 'value'},
        );

        final str = payload.toString();

        expect(str, contains('Test'));
        expect(str, contains('Body'));
        expect(str, contains('/test'));
        expect(str, contains('actions: 1'));
        expect(str, contains('data: (key)')); // Uses parentheses not brackets
      });
    });
  });
}
