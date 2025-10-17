import 'package:cloud_firestore/cloud_firestore.dart';

/// Serialization context to determine how to handle special fields
enum SerializationContext {
  /// Direct Firestore read/write operations
  firestore,

  /// Firebase callable functions
  callable,

  /// Local storage or caching
  local,
}

/// Base class for all Firestore models with enhanced serialization capabilities.
///
/// This base class provides intelligent serialization methods that handle
/// different contexts (Firestore, Cloud Functions, local storage) and
/// automatically manages timestamp fields.
///
/// ## Key Features:
/// - Automatic server timestamp handling for create/update operations
/// - Support for data migration with explicit timestamps
/// - Separate handling of creation vs update timestamps
/// - Cloud Functions compatible serialization
/// - Flexible field exclusion
///
/// ## Usage:
///
/// ```dart
/// @JsonSerializable(explicitToJson: true)
/// class PostModel extends BaseFirestoreModel {
///   final String id;
///   final String title;
///
///   @SmartTimestampConverter()
///   final DateTime? createdAt;
///
///   @SmartTimestampConverter()
///   final DateTime? updatedAt;
///
///   PostModel({
///     this.id = '',
///     required this.title,
///     this.createdAt,
///     this.updatedAt,
///   });
///
///   factory PostModel.fromJson(Map<String, dynamic> json) => _$PostModelFromJson(json);
///
///   @override
///   Map<String, dynamic> toJson() => _$PostModelToJson(this);
/// }
/// ```
///
/// ## Creating Documents:
///
/// ```dart
/// // Standard create with server timestamps
/// await firestore.collection('posts')
///   .add(newPost.toFirestoreCreate());
///
/// // Import with specific timestamps
/// await firestore.collection('posts')
///   .add(historicalPost.toFirestoreCreate(useServerTimestamp: false));
/// ```
///
/// ## Updating Documents:
///
/// ```dart
/// // Update (preserves createdAt, updates updatedAt)
/// await firestore.collection('posts')
///   .doc(postId)
///   .update(updatedPost.toFirestoreUpdate());
/// ```
///
/// ## Cloud Functions:
///
/// ```dart
/// // Callable function (removes timestamp fields)
/// final callable = FirebaseFunctions.instance.httpsCallable('createPost');
/// await callable.call(post.toCallable());
/// ```
abstract class BaseFirestoreModel {
  /// The single generated toJson method from json_serializable.
  /// This should be implemented by the generated code.
  Map<String, dynamic> toJson();

  /// Convert to Firestore document for CREATE operations.
  ///
  /// By default, uses server timestamps for fields returned by
  /// [getCreateTimestampFields] and [getUpdateTimestampFields].
  ///
  /// Parameters:
  /// - [useServerTimestamp]: If true, uses FieldValue.serverTimestamp() for
  ///   timestamp fields. If false, preserves DateTime values as Timestamps
  ///   (useful for data migration/import).
  /// - [fieldsToExclude]: List of field names to exclude from the output.
  ///
  /// Example:
  /// ```dart
  /// // Standard create
  /// await firestore.collection('posts').add(post.toFirestoreCreate());
  ///
  /// // Import with specific timestamps
  /// await firestore.collection('posts')
  ///   .add(historicalPost.toFirestoreCreate(useServerTimestamp: false));
  /// ```
  Map<String, dynamic> toFirestoreCreate({
    bool useServerTimestamp = true,
    List<String>? fieldsToExclude,
  }) {
    final json = toJson();
    return _processForContext(
      json,
      SerializationContext.firestore,
      isCreate: true,
      useServerTimestamp: useServerTimestamp,
      fieldsToExclude: fieldsToExclude,
    );
  }

  /// Convert to Firestore document for UPDATE operations.
  ///
  /// Only updates fields returned by [getUpdateTimestampFields], and completely
  /// removes fields from [getCreateTimestampFields] to preserve original values.
  ///
  /// Parameters:
  /// - [fieldsToExclude]: List of field names to exclude from the output.
  ///
  /// Example:
  /// ```dart
  /// await firestore.collection('posts')
  ///   .doc(postId)
  ///   .update(post.toFirestoreUpdate());
  /// ```
  Map<String, dynamic> toFirestoreUpdate({
    List<String>? fieldsToExclude,
  }) {
    final json = toJson();
    return _processForContext(
      json,
      SerializationContext.firestore,
      isUpdate: true,
      fieldsToExclude: fieldsToExclude,
    );
  }

  /// Convert to Firestore with explicit control (advanced use).
  ///
  /// Allows setting documents with specific timestamps without using
  /// FieldValue.serverTimestamp(). Useful for data migrations or when you
  /// need full control over all field values.
  ///
  /// Parameters:
  /// - [fieldsToExclude]: List of field names to exclude from the output.
  ///
  /// Example:
  /// ```dart
  /// // Migration or batch import
  /// await firestore.collection('posts')
  ///   .doc(postId)
  ///   .set(post.toFirestoreRaw());
  /// ```
  Map<String, dynamic> toFirestoreRaw({
    List<String>? fieldsToExclude,
  }) {
    final json = toJson();
    final processed = Map<String, dynamic>.from(json);

    // Remove null values and excluded fields
    processed.removeWhere((key, value) => value == null);
    if (fieldsToExclude != null) {
      for (final field in fieldsToExclude) {
        processed.remove(field);
      }
    }

    // Convert DateTime to Timestamp but don't use FieldValue
    processed.forEach((key, value) {
      if (value is DateTime) {
        processed[key] = Timestamp.fromDate(value);
      }
    });

    return processed;
  }

  /// Convert for Firebase callable functions.
  ///
  /// Timestamps are kept as milliseconds and server-managed timestamp fields
  /// (from [getCreateTimestampFields] and [getUpdateTimestampFields]) are removed
  /// since the server will add them.
  ///
  /// Example:
  /// ```dart
  /// final callable = FirebaseFunctions.instance.httpsCallable('createPost');
  /// await callable.call(post.toCallable());
  /// ```
  Map<String, dynamic> toCallable() {
    final json = toJson();
    return _processForContext(json, SerializationContext.callable);
  }

  /// Process the generated JSON for specific context.
  Map<String, dynamic> _processForContext(
    Map<String, dynamic> json,
    SerializationContext context, {
    bool isCreate = false,
    bool isUpdate = false,
    bool useServerTimestamp = true,
    List<String>? fieldsToExclude,
  }) {
    final processed = Map<String, dynamic>.from(json);

    // Remove null values for cleaner payloads
    processed.removeWhere((key, value) => value == null);

    // Remove explicitly excluded fields
    if (fieldsToExclude != null) {
      for (final field in fieldsToExclude) {
        processed.remove(field);
      }
    }

    // Handle special timestamp fields based on context
    _processTimestamps(
      processed,
      context,
      isCreate: isCreate,
      isUpdate: isUpdate,
      useServerTimestamp: useServerTimestamp,
    );

    // Allow subclasses to add custom processing
    return postProcessJson(processed, context);
  }

  /// Process timestamp fields based on context.
  void _processTimestamps(
    Map<String, dynamic> json,
    SerializationContext context, {
    bool isCreate = false,
    bool isUpdate = false,
    bool useServerTimestamp = true,
  }) {
    final createOnlyFields = getCreateTimestampFields();
    final updateAlwaysFields = getUpdateTimestampFields();

    switch (context) {
      case SerializationContext.firestore:
        if (isCreate && useServerTimestamp) {
          // Creating new document with server timestamps
          for (final field in createOnlyFields) {
            if (!json.containsKey(field) || json[field] == null) {
              json[field] = FieldValue.serverTimestamp();
            } else {
              // If field has a value, convert DateTime to Timestamp
              if (json[field] is DateTime) {
                json[field] = Timestamp.fromDate(json[field] as DateTime);
              } else if (json[field] is int) {
                // Convert milliseconds to Timestamp
                json[field] = Timestamp.fromMillisecondsSinceEpoch(json[field] as int);
              }
            }
          }
          for (final field in updateAlwaysFields) {
            json[field] = FieldValue.serverTimestamp();
          }
        } else if (isCreate && !useServerTimestamp) {
          // Creating with specific timestamps (e.g., data import)
          // Convert DateTime objects to Timestamp
          for (final field in [...createOnlyFields, ...updateAlwaysFields]) {
            if (json.containsKey(field) && json[field] != null) {
              if (json[field] is DateTime) {
                json[field] = Timestamp.fromDate(json[field] as DateTime);
              } else if (json[field] is int) {
                json[field] = Timestamp.fromMillisecondsSinceEpoch(json[field] as int);
              }
            }
          }
        } else if (isUpdate) {
          // Updating existing document
          // Remove create-only fields (like createdAt) entirely
          for (final field in createOnlyFields) {
            json.remove(field);
          }
          // Update the update-always fields
          for (final field in updateAlwaysFields) {
            json[field] = FieldValue.serverTimestamp();
          }
        }
        break;

      case SerializationContext.callable:
        // Remove all server-managed timestamp fields
        // The server will add them
        for (final field in [...createOnlyFields, ...updateAlwaysFields]) {
          json.remove(field);
        }
        break;

      case SerializationContext.local:
        // Keep timestamps as milliseconds for local storage
        break;
    }
  }

  /// Fields that should only be set on document creation (like createdAt).
  ///
  /// These fields are removed entirely on updates to preserve original values.
  /// Override this method to specify your model's creation timestamp fields.
  ///
  /// Default: `['createdAt']`
  ///
  /// Example:
  /// ```dart
  /// @override
  /// List<String> getCreateTimestampFields() {
  ///   return ['createdAt', 'firstSeenAt'];
  /// }
  /// ```
  List<String> getCreateTimestampFields() {
    return ['createdAt'];
  }

  /// Fields that should always be updated with server timestamp (like updatedAt).
  ///
  /// Override this method to specify your model's update timestamp fields.
  ///
  /// Default: `['updatedAt']`
  ///
  /// Example:
  /// ```dart
  /// @override
  /// List<String> getUpdateTimestampFields() {
  ///   return ['updatedAt', 'modifiedAt'];
  /// }
  /// ```
  List<String> getUpdateTimestampFields() {
    return ['updatedAt'];
  }

  /// Override to add custom post-processing for specific models.
  ///
  /// This method is called after all standard processing is complete,
  /// allowing you to add custom logic for specific serialization contexts.
  ///
  /// Parameters:
  /// - [json]: The processed JSON map
  /// - [context]: The serialization context
  ///
  /// Returns: The modified JSON map
  ///
  /// Example:
  /// ```dart
  /// @override
  /// Map<String, dynamic> postProcessJson(
  ///   Map<String, dynamic> json,
  ///   SerializationContext context,
  /// ) {
  ///   if (context == SerializationContext.firestore) {
  ///     json['_version'] = 1;
  ///   }
  ///   return json;
  /// }
  /// ```
  Map<String, dynamic> postProcessJson(
    Map<String, dynamic> json,
    SerializationContext context,
  ) {
    return json;
  }

  // Backwards compatibility aliases

  /// Legacy method for Firestore conversion.
  ///
  /// @deprecated Use [toFirestoreCreate] or [toFirestoreUpdate] instead
  /// for more explicit control.
  ///
  /// This method is provided for backward compatibility with existing code.
  @Deprecated('Use toFirestoreCreate() or toFirestoreUpdate() instead')
  Map<String, dynamic> toFirestore({bool isUpdate = false}) {
    return isUpdate ? toFirestoreUpdate() : toFirestoreCreate();
  }
}
