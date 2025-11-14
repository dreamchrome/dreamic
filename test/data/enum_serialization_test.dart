import 'package:flutter_test/flutter_test.dart';
import 'package:dreamic/data/models/enum_example.dart';

/// Integration tests proving that unknown enum values don't crash when using
/// the helper function pattern with @JsonKey annotations.
///
/// These tests verify the entire serialization pipeline including json_serializable
/// code generation, proving that the solution works in real-world scenarios.
void main() {
  group('Enum Serialization Integration Tests', () {
    group('UserProfileModel (Nullable Strategy)', () {
      test('deserializes known enum values correctly', () {
        final json = {
          'username': 'johndoe',
          'email': 'john@example.com',
          'role': 'admin',
          'createdAt': '2024-01-15T10:30:00Z',
        };

        final profile = UserProfileModel.fromJson(json);

        expect(profile.role, UserRole.admin);
        expect(profile.username, 'johndoe');
      });

      test('handles unknown enum value gracefully (NO CRASH)', () {
        final json = {
          'username': 'johndoe',
          'email': 'john@example.com',
          'role': 'future_role_that_does_not_exist', // Unknown value
          'createdAt': '2024-01-15T10:30:00Z',
        };

        // Should not throw - this is the critical test
        final profile = UserProfileModel.fromJson(json);

        // Nullable strategy: unknown → null
        expect(profile.role, isNull);
        expect(profile.username, 'johndoe');
      });

      test('handles null enum value correctly', () {
        final json = {
          'username': 'johndoe',
          'email': 'john@example.com',
          'role': null,
          'createdAt': '2024-01-15T10:30:00Z',
        };

        final profile = UserProfileModel.fromJson(json);

        expect(profile.role, isNull); // Nullable strategy
      });

      test('handles missing enum field correctly', () {
        final json = {
          'username': 'johndoe',
          'email': 'john@example.com',
          // 'role' field missing entirely
          'createdAt': '2024-01-15T10:30:00Z',
        };

        final profile = UserProfileModel.fromJson(json);

        expect(profile.role, isNull); // Nullable strategy
      });

      test('serializes enum values correctly', () {
        final profile = UserProfileModel(
          username: 'johndoe',
          email: 'john@example.com',
          role: UserRole.moderator,
        );

        final json = profile.toJson();

        expect(json['role'], 'moderator');
      });

      test('roundtrip with known value preserves data', () {
        final original = UserProfileModel(
          username: 'johndoe',
          email: 'john@example.com',
          role: UserRole.admin,
        );

        final json = original.toJson();
        final deserialized = UserProfileModel.fromJson(json);

        expect(deserialized.role, original.role);
        expect(deserialized.username, original.username);
      });
    });

    group('PostModel (Default Strategy)', () {
      test('deserializes known enum values correctly', () {
        final json = {
          'title': 'Test Post',
          'content': 'Content here',
          'authorId': 'author123',
          'status': 'published',
          'visibility': 'public',
          'createdAt': '2024-01-15T10:30:00Z',
          'updatedAt': '2024-01-15T10:30:00Z',
        };

        final post = PostModel.fromJson(json);

        expect(post.status, PostStatus.published);
        expect(post.visibility, PostVisibility.public);
      });

      test('handles unknown status value with default (NO CRASH)', () {
        final json = {
          'title': 'Test Post',
          'content': 'Content here',
          'authorId': 'author123',
          'status': 'future_status_unknown', // Unknown value
          'visibility': 'public',
          'createdAt': '2024-01-15T10:30:00Z',
          'updatedAt': '2024-01-15T10:30:00Z',
        };

        // Should not throw
        final post = PostModel.fromJson(json);

        // Default strategy: unknown → default value
        expect(post.status, PostStatus.draft);
        expect(post.visibility, PostVisibility.public);
      });

      test('handles unknown visibility value with default (NO CRASH)', () {
        final json = {
          'title': 'Test Post',
          'content': 'Content here',
          'authorId': 'author123',
          'status': 'published',
          'visibility': 'unknown_visibility', // Unknown value
          'createdAt': '2024-01-15T10:30:00Z',
          'updatedAt': '2024-01-15T10:30:00Z',
        };

        final post = PostModel.fromJson(json);

        expect(post.status, PostStatus.published);
        expect(post.visibility, PostVisibility.private); // Default for safety
      });

      test('handles multiple unknown enum values (NO CRASH)', () {
        final json = {
          'title': 'Test Post',
          'content': 'Content here',
          'authorId': 'author123',
          'status': 'unknown_status',
          'visibility': 'unknown_visibility',
          'createdAt': '2024-01-15T10:30:00Z',
          'updatedAt': '2024-01-15T10:30:00Z',
        };

        final post = PostModel.fromJson(json);

        expect(post.status, PostStatus.draft);
        expect(post.visibility, PostVisibility.private);
      });

      test('handles null values with defaults', () {
        final json = {
          'title': 'Test Post',
          'content': 'Content here',
          'authorId': 'author123',
          'status': null,
          'visibility': null,
          'createdAt': '2024-01-15T10:30:00Z',
          'updatedAt': '2024-01-15T10:30:00Z',
        };

        final post = PostModel.fromJson(json);

        expect(post.status, PostStatus.draft);
        expect(post.visibility, PostVisibility.private);
      });

      test('serializes enum values correctly', () {
        final post = PostModel(
          title: 'Test Post',
          content: 'Content here',
          authorId: 'author123',
          status: PostStatus.archived,
          visibility: PostVisibility.friendsOnly,
        );

        final json = post.toJson();

        expect(json['status'], 'archived');
        expect(json['visibility'], 'friendsOnly');
      });

      test('roundtrip with known values preserves data', () {
        final original = PostModel(
          title: 'Test Post',
          content: 'Content here',
          authorId: 'author123',
          status: PostStatus.published,
          visibility: PostVisibility.friendsOnly,
        );

        final json = original.toJson();
        final deserialized = PostModel.fromJson(json);

        expect(deserialized.status, original.status);
        expect(deserialized.visibility, original.visibility);
      });
    });

    group('NotificationModel (Logging Strategy)', () {
      test('deserializes known enum values correctly', () {
        final json = {
          'title': 'Test Notification',
          'message': 'This is a test',
          'userId': 'user123',
          'priority': 'high',
          'createdAt': '2024-01-15T10:30:00Z',
        };

        final notification = NotificationModel.fromJson(json);

        expect(notification.priority, NotificationPriority.high);
        expect(notification.title, 'Test Notification');
      });

      test('handles unknown priority with logging and default (NO CRASH)', () {
        final json = {
          'title': 'Test Notification',
          'message': 'This is a test',
          'userId': 'user123',
          'priority': 'ultra_mega_priority', // Unknown value
          'createdAt': '2024-01-15T10:30:00Z',
        };

        // Should not throw - should log and use default
        final notification = NotificationModel.fromJson(json);

        // Logging strategy: unknown → log + default
        expect(notification.priority, NotificationPriority.medium);
        expect(notification.title, 'Test Notification');
      });

      test('handles null priority with default', () {
        final json = {
          'title': 'Test Notification',
          'message': 'This is a test',
          'userId': 'user123',
          'priority': null,
          'createdAt': '2024-01-15T10:30:00Z',
        };

        final notification = NotificationModel.fromJson(json);

        expect(notification.priority, NotificationPriority.medium);
      });

      test('serializes enum values correctly', () {
        final notification = NotificationModel(
          title: 'Test Notification',
          message: 'This is a test',
          userId: 'user123',
          priority: NotificationPriority.high,
        );

        final json = notification.toJson();

        expect(json['priority'], 'high');
      });

      test('roundtrip with known value preserves data', () {
        final original = NotificationModel(
          title: 'Test Notification',
          message: 'This is a test',
          userId: 'user123',
          priority: NotificationPriority.low,
        );

        final json = original.toJson();
        final deserialized = NotificationModel.fromJson(json);

        expect(deserialized.priority, original.priority);
        expect(deserialized.title, original.title);
      });
    });

    group('Mixed Scenarios (Real-World)', () {
      test('batch deserialization with mix of known and unknown values', () {
        final jsonList = [
          {
            'title': 'Post 1',
            'content': 'Content 1',
            'authorId': 'author1',
            'status': 'published',
            'visibility': 'public',
            'createdAt': '2024-01-15T10:30:00Z',
            'updatedAt': '2024-01-15T10:30:00Z',
          },
          {
            'title': 'Post 2',
            'content': 'Content 2',
            'authorId': 'author1',
            'status': 'unknown_future_status', // Unknown
            'visibility': 'unknown_future_visibility', // Unknown
            'createdAt': '2024-01-15T10:30:00Z',
            'updatedAt': '2024-01-15T10:30:00Z',
          },
          {
            'title': 'Post 3',
            'content': 'Content 3',
            'authorId': 'author1',
            'status': 'draft',
            'visibility': 'private',
            'createdAt': '2024-01-15T10:30:00Z',
            'updatedAt': '2024-01-15T10:30:00Z',
          },
        ];

        // Should not throw on any item
        final posts = jsonList.map((json) => PostModel.fromJson(json)).toList();

        expect(posts, hasLength(3));
        expect(posts[0].status, PostStatus.published);
        expect(posts[1].status, PostStatus.draft); // Unknown → default (draft)
        expect(posts[1].visibility, PostVisibility.private); // Unknown → default (private)
        expect(posts[2].status, PostStatus.draft);
      });

      test('server response with new enum values does not crash app', () {
        // Simulates server adding new enum values in a future version
        final serverResponse = {
          'username': 'johndoe',
          'email': 'john@example.com',
          'role': 'superadmin', // New role added on server
          'createdAt': '2024-01-15T10:30:00Z',
        };

        // Old client should handle gracefully
        expect(
          () => UserProfileModel.fromJson(serverResponse),
          returnsNormally,
        );

        final profile = UserProfileModel.fromJson(serverResponse);
        expect(profile.role, isNull); // Nullable strategy: unknown → null
      });

      test('malformed data with unknown enum handles gracefully', () {
        final json = {
          'title': 'Test Post',
          'content': 'Content here',
          'authorId': 'author123',
          'status': 'this_is_totally_invalid', // Unknown string value
          'visibility': 'also_totally_invalid', // Unknown string value
          'createdAt': '2024-01-15T10:30:00Z',
          'updatedAt': '2024-01-15T10:30:00Z',
        };

        // Should not throw
        final post = PostModel.fromJson(json);

        // Both should fallback to defaults (default strategy)
        expect(post.status, PostStatus.draft);
        expect(post.visibility, PostVisibility.private);
      });
    });

    group('Performance and Stress Tests', () {
      test('handles large batch of unknown values efficiently', () {
        final jsonList = List.generate(
          1000,
          (i) => {
            'username': 'user$i',
            'email': 'user$i@example.com',
            'role': 'unknown_role_$i', // All unknown
            'createdAt': '2024-01-15T10:30:00Z',
          },
        );

        // Should handle efficiently without crashes
        final profiles = jsonList
            .map((json) => UserProfileModel.fromJson(json))
            .toList();

        expect(profiles, hasLength(1000));
        expect(profiles.every((p) => p.role == null), isTrue); // Nullable strategy
      });

      test('mixed valid and invalid in large batch', () {
        final jsonList = List.generate(
          500,
          (i) => {
            'title': 'Post $i',
            'content': 'Content $i',
            'authorId': 'author$i',
            'status': i % 2 == 0 ? 'published' : 'unknown_status_$i',
            'visibility': i % 3 == 0 ? 'public' : 'unknown_visibility_$i',
            'createdAt': '2024-01-15T10:30:00Z',
            'updatedAt': '2024-01-15T10:30:00Z',
          },
        );

        final posts = jsonList.map((json) => PostModel.fromJson(json)).toList();

        expect(posts, hasLength(500));
        // Verify mix of valid and default values
        expect(posts.where((p) => p.status == PostStatus.published).length,
            greaterThan(0));
        expect(posts.where((p) => p.status == PostStatus.draft).length, greaterThan(0));
      });
    });

    group('Edge Cases', () {
      test('empty string enum value', () {
        final json = {
          'username': 'johndoe',
          'email': 'john@example.com',
          'role': '', // Empty string
          'createdAt': '2024-01-15T10:30:00Z',
        };

        final profile = UserProfileModel.fromJson(json);
        expect(profile.role, isNull); // Nullable strategy
      });

      test('enum value with different casing', () {
        final json = {
          'username': 'johndoe',
          'email': 'john@example.com',
          'role': 'ADMIN', // Wrong case
          'createdAt': '2024-01-15T10:30:00Z',
        };

        final profile = UserProfileModel.fromJson(json);
        // Should fallback (case sensitive)
        expect(profile.role, isNull); // Nullable strategy
      });

      test('enum value with whitespace', () {
        final json = {
          'username': 'johndoe',
          'email': 'john@example.com',
          'role': ' admin ', // With spaces
          'createdAt': '2024-01-15T10:30:00Z',
        };

        final profile = UserProfileModel.fromJson(json);
        expect(profile.role, isNull); // Nullable strategy
      });

      test('special characters in enum value', () {
        final json = {
          'title': 'Test Post',
          'content': 'Content here',
          'authorId': 'author123',
          'status': r'publi$hed!@#', // Special chars with raw string
          'visibility': 'public',
          'createdAt': '2024-01-15T10:30:00Z',
          'updatedAt': '2024-01-15T10:30:00Z',
        };

        final post = PostModel.fromJson(json);
        expect(post.status, PostStatus.draft); // Default strategy
      });
    });
  });
}
