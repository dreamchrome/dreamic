# Dreamic Package Coding Standards

**CRITICAL: This file enforces strict architectural patterns when using the dreamic package. AI assistants MUST follow these rules.**

---

## 🔴 MANDATORY: State Management

### Cubits - ALWAYS Required

**REQUIRED:**
- **ALWAYS** extend `CubitBase<T>` from dreamic for ALL cubits
- **ALWAYS** extend `CubitBaseState` from dreamic for ALL state classes
- **ALWAYS** use `emitSafe()` instead of `emit()`
- **ALWAYS** use `PageStatus` or `WidgetStatus` enums from dreamic for status fields

**FORBIDDEN:**
- **NEVER** use plain `Cubit` or `BlocBase` directly
- **NEVER** use raw `emit()` - this can crash if cubit is closed
- **NEVER** create custom status strings - use dreamic's status enums

**Example:**
```dart
import 'package:dreamic/dreamic.dart';

// State class
class MyPageState extends CubitBaseState {
  final List<Item> items;
  final String? errorMessage;
  
  const MyPageState({
    super.pageStatus = PageStatus.loading,
    this.items = const [],
    this.errorMessage,
  });
  
  @override
  MyPageState copyWith({
    PageStatus? pageStatus,
    List<Item>? items,
    String? errorMessage,
  }) {
    return MyPageState(
      pageStatus: pageStatus ?? this.pageStatus,
      items: items ?? this.items,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
  
  @override
  List<Object?> get props => [
    pageStatus,
    items,
    errorMessage,
  ];
}

// Cubit class
class MyPageCubit extends CubitBase<MyPageState> {
  
  MyPageCubit() : super(const MyPageState());
  
  Future<void> loadData() async {
    emitSafe(state.copyWith(pageStatus: PageStatus.loading));
    
    final result = await _repo.getData();
    
    result.fold(
      (failure) => emitSafe(state.copyWith(
        pageStatus: PageStatus.error,
        errorMessage: failure.message,
      )),
      (items) => emitSafe(state.copyWith(
        pageStatus: PageStatus.loaded,
        items: items,
      )),
    );
  }
}
```

---

## 🔴 MANDATORY: UI Architecture

### Page Wrappers - ALWAYS Required

**REQUIRED:**
- **ALWAYS** wrap pages with `PageStatusWrapper` from dreamic
- **ALWAYS** wrap page content with `PageStatusBodyWrapper` from dreamic
- **ALWAYS** provide `PageStatusWrapperConfigs` to `PageStatusWrapper`

**FORBIDDEN:**
- **NEVER** create pages without these wrappers
- **NEVER** handle loading/error states manually when PageStatusWrapper exists

**Benefits:** Automatic handling of loading states, errors, and offline scenarios

**Example:**
```dart
import 'package:flutter/material.dart';
import 'package:dreamic/presentation/elements/page_status_wrapper.dart';

class MyPage extends StatelessWidget {
  const MyPage({super.key});
  
  @override
  Widget build(BuildContext context) {
    return PageStatusWrapper<MyPageCubit, MyPageState>(
      cubitFactory: () => MyPageCubit()..getInitialData(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My Page'),
        ),
        body: PageStatusBodyWrapper<MyPageCubit, MyPageState>(
          loadedChildBuilder: (context, state) {
            return ListView.builder(
              itemCount: state.items.length,
              itemBuilder: (context, index) => _buildItem(state.items[index]),
            );
          },
        ),
      ),
    );
  }
  
  Widget _buildItem(Item item) {
    return ListTile(title: Text(item.name));
  }
}
```

### Tappable Widgets - ALWAYS Required

**REQUIRED:**
- **ALWAYS** wrap tappable widgets with dreamic's `TappableAction`
- **ALWAYS** use `TappableActionInkedWell` instead of `InkWell`
- **ALWAYS** configure `requireNetwork` in `TappableActionConfig` based on whether the action needs network connectivity

**FORBIDDEN:**
- **NEVER** use bare `GestureDetector`, `InkWell`, or `InkResponse` without dreamic wrappers

**Benefits:** Built-in debouncing, loading states, disabled state handling, automatic network checking

**Example:**
```dart
import 'package:dreamic/dreamic.dart';

// Default config - requires network (for API calls, cloud functions)
TappableAction(
  onTap: () => context.read<MyCubit>().saveToServer(),
  config: TappableActionConfig(), // requireNetwork: true (default)
  builder: (context, onTap) {
    return ElevatedButton(
      onPressed: onTap,
      child: Text('Save to Server'),
    );
  },
)

// No network required (for local operations, navigation)
TappableAction(
  onTap: () => context.read<MyCubit>().filterLocalData(),
  config: TappableActionConfig(requireNetwork: false),
  builder: (context, onTap) {
    return ElevatedButton(
      onPressed: onTap,
      child: Text('Filter'),
    );
  },
)

// High-frequency interactions (no network, fast cooldown)
TappableAction(
  onTap: () => context.read<MyCubit>().incrementCounter(),
  config: TappableActionConfig.highFrequency(),
  builder: (context, onTap) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(Icons.add),
    );
  },
)

// Critical actions (requires network, longer cooldown, initial delay)
TappableAction(
  onTap: () => context.read<MyCubit>().deleteAccount(),
  config: TappableActionConfig.critical(),
  builder: (context, onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
      child: Text('Delete Account'),
    );
  },
)

// InkWell with custom config
TappableActionInkedWell(
  onTap: () => context.read<MyCubit>().navigateToDetails(),
  config: TappableActionConfig(requireNetwork: false),
  child: ListTile(title: Text('View Details')),
)
```

**TappableActionConfig Options:**
- `requireNetwork: true` (default) - Disables action when offline, for server operations
- `requireNetwork: false` - Allows action when offline, for local operations
- `debounceTaps: true` (default) - Prevents rapid repeated taps
- `coolDownDuration` - Minimum time between taps
- `delayBeforeFirstTapDuration` - Initial delay before first tap is allowed
- `minDisabledDuration` - Minimum time action stays disabled after tap
- `groupId` - Groups multiple TappableActions to disable together
- `disableVisuallyDuringDebouncing` - Shows disabled state during cooldown

**Preset Configs:**
- `TappableActionConfig()` - Default (requires network, debouncing enabled)
- `TappableActionConfig.highFrequency()` - For rapid interactions (no network required, short cooldown)
- `TappableActionConfig.critical()` - For dangerous operations (requires network, long cooldown, initial delay)

### StatefulWidgets - ALWAYS Required

**REQUIRED:**
- **ALWAYS** use `SetStateSafeMixin` from dreamic in ALL StatefulWidget classes
- **ALWAYS** use `setStateSafe()` instead of `setState()`

**FORBIDDEN:**
- **NEVER** use raw `setState()` - it can crash if widget is unmounted

**Example:**
```dart
import 'package:dreamic/dreamic.dart';

class MyStatefulWidget extends StatefulWidget {
  @override
  State<MyStatefulWidget> createState() => _MyStatefulWidgetState();
}

class _MyStatefulWidgetState extends State<MyStatefulWidget> 
    with SetStateSafeMixin {
  int _counter = 0;
  
  void _increment() {
    setStateSafe(() {
      _counter++;
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Text('Count: $_counter');
  }
}
```

---

## 🔴 MANDATORY: Dialogs and User Interaction

### Standard Dialogs - ALWAYS Required

**REQUIRED:**
- **ALWAYS** use `adaptive_dialog` package methods for standard dialogs
- **ALWAYS** use `showOkAlertDialog()` for simple alerts
- **ALWAYS** use `showOkCancelAlertDialog()` for confirmations
- **ALWAYS** use `showTextInputDialog()` for text input

**FORBIDDEN:**
- **NEVER** use `showDialog()` for standard OK/Cancel/Alert dialogs
- **NEVER** use platform-specific dialogs (`AlertDialog`, `CupertinoAlertDialog`) for standard dialogs

**ALLOWED:**
- Using `showDialog()` is acceptable ONLY for custom dialogs requiring special layouts or filling most of the screen

**Example:**
```dart
import 'package:adaptive_dialog/adaptive_dialog.dart';

// Simple alert
await showOkAlertDialog(
  context: context,
  title: 'Success',
  message: 'Operation completed successfully',
);

// Confirmation
final result = await showOkCancelAlertDialog(
  context: context,
  title: 'Delete Item',
  message: 'Are you sure you want to delete this item?',
);

if (result == OkCancelResult.ok) {
  // User confirmed
}

// Text input
final name = await showTextInputDialog(
  context: context,
  title: 'Enter Name',
  textFields: [
    DialogTextField(hintText: 'Name'),
  ],
);
```

---

## 🔴 MANDATORY: Logging

### Logger - ALWAYS Required

**REQUIRED:**
- **ALWAYS** use dreamic's logging functions: `logd()`, `logw()`, `loge()`
- **ALWAYS** include meaningful context in log messages

**FORBIDDEN:**
- **NEVER** use `print()`, `debugPrint()`, or `dart:developer log()`

**Example:**
```dart
import 'package:dreamic/dreamic.dart';

logd('loadData: Starting data fetch');
logw('loadData: Retry attempt ${retryCount}');
loge('loadData: Failed with error: ${error}');
```

---

## 🔴 MANDATORY: Firebase Integration

### Firebase Functions - ALWAYS Required

**REQUIRED:**
- **ALWAYS** use `AppConfigBase.firebaseFunctionCallable()` from dreamic for Firebase callable functions
- **ALWAYS** pass model data using `toCallable()` method from BaseFirestoreModel

**FORBIDDEN:**
- **NEVER** call Firebase functions directly using `FirebaseFunctions.instance`

**Benefits:** Ensures proper error handling, timeouts, and logging

**Example:**
```dart
import 'package:dreamic/dreamic.dart';

Future<void> createPost(PostModel post) async {
  final callable = AppConfigBase.firebaseFunctionCallable('createPost');
  
  try {
    final result = await callable.call({
      'post': post.toCallable(), // Uses dreamic's serialization
    });
    
    logd('createPost: Success - ${result.data}');
  } catch (e) {
    loge('createPost: Failed - $e');
  }
}
```

---

## 🔴 MANDATORY: Data Models and Serialization

### Model Structure - ALWAYS Required

**REQUIRED:**
- **ALWAYS** extend `BaseFirestoreModel` from dreamic for ALL Firestore-persisted models
- **ALWAYS** use `@JsonSerializable(explicitToJson: true)` annotation
- **ALWAYS** include the generated part file: `part 'model_name.g.dart';`
- **ALWAYS** create `factory Model.fromJson()` and override `toJson()` methods
- **ALWAYS** create `factory Model.fromFirestore(DocumentSnapshot doc)` method
- **ALWAYS** create `copyWith()` method for immutability
- **ALWAYS** override `getCreateTimestampFields()` and `getUpdateTimestampFields()` methods
- **ALWAYS** include `id` field with `@JsonKey(includeFromJson: true, includeToJson: false)`
- **ALWAYS** include `createdAt` field with `@SmartTimestampConverter()` for persisted models
- **ALWAYS** include `updatedAt` field with `@SmartTimestampConverter()` for persisted models
- **ALWAYS** create custom `JsonConverter` classes for models used as fields in other models

**FORBIDDEN:**
- **NEVER** manually write serialization code - always use json_serializable
- **NEVER** use plain DateTime without timestamp converters
- **NEVER** forget to create converters for nested models
- **NEVER** break backward compatibility without migration strategy

**Example:**
```dart
import 'package:dreamic/dreamic.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

part 'post_model.g.dart';

@JsonSerializable(explicitToJson: true)
class PostModel extends BaseFirestoreModel {
  @JsonKey(includeFromJson: true, includeToJson: false)
  final String id;
  
  final String title;
  final String content;
  final String authorId;
  
  @SmartTimestampConverter()
  final DateTime? createdAt;
  
  @SmartTimestampConverter()
  final DateTime? updatedAt;
  
  PostModel({
    this.id = '',
    required this.title,
    required this.content,
    required this.authorId,
    this.createdAt,
    this.updatedAt,
  });
  
  factory PostModel.fromJson(Map<String, dynamic> json) => 
      _$PostModelFromJson(json);
  
  @override
  Map<String, dynamic> toJson() => _$PostModelToJson(this);
  
  factory PostModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return PostModel.fromJson({'id': doc.id, ...data});
  }
  
  PostModel copyWith({
    String? id,
    String? title,
    String? content,
    String? authorId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PostModel(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      authorId: authorId ?? this.authorId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
  
  @override
  List<String> getCreateTimestampFields() => ['createdAt'];
  
  @override
  List<String> getUpdateTimestampFields() => ['updatedAt'];
}

// Create converters for use in other models
class PostModelConverter 
    implements JsonConverter<PostModel, Map<String, dynamic>> {
  const PostModelConverter();
  
  @override
  PostModel fromJson(Map<String, dynamic> json) => PostModel.fromJson(json);
  
  @override
  Map<String, dynamic> toJson(PostModel object) => object.toJson();
}

class PostModelNullableConverter 
    implements JsonConverter<PostModel?, Map<String, dynamic>?> {
  const PostModelNullableConverter();
  
  @override
  PostModel? fromJson(Map<String, dynamic>? json) => 
      json == null ? null : PostModel.fromJson(json);
  
  @override
  Map<String, dynamic>? toJson(PostModel? object) => object?.toJson();
}
```

### Serialization Methods - Context-Aware Usage

**CRITICAL RULES:**

| Method | When to Use | Timestamp Handling |
|--------|-------------|-------------------|
| `toFirestoreCreate()` | Creating new Firestore documents | Sets `FieldValue.serverTimestamp()` for `createdAt` and `updatedAt` |
| `toFirestoreUpdate()` | Updating existing Firestore documents | Removes `createdAt`, sets `FieldValue.serverTimestamp()` for `updatedAt` |
| `toCallable()` | Passing data to Firebase Cloud Functions | Removes ALL timestamp fields (server manages them) |
| `toJson()` | Local storage/caching | Converts timestamps to milliseconds (int) |
| `toFirestoreRaw()` | Data migration with historical timestamps | Converts DateTime to Timestamp exactly as-is |

**REQUIRED:**
- **ALWAYS** use `toFirestoreCreate()` when adding new documents to Firestore
- **ALWAYS** use `toFirestoreUpdate()` when updating existing documents
- **ALWAYS** use `toCallable()` when passing data to Firebase Cloud Functions
- **ALWAYS** use `toJson()` for local storage, caching, or JSON serialization

**FORBIDDEN:**
- **NEVER** use `toJson()` for Firestore operations (timestamp handling is incorrect)
- **NEVER** use `toFirestoreCreate()` for updates (overwrites `createdAt`)
- **NEVER** use `toFirestoreCreate()` or `toFirestoreUpdate()` for Cloud Functions (causes FieldValue errors)

**Example:**
```dart
import 'package:yourapp_common/data/helpers/db_constants.dart';

class PostService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // CREATE - Server sets both timestamps
  Future<String> createPost(PostModel post) async {
    final docRef = await _firestore.collection(colPosts).add(
      post.toFirestoreCreate() // ✅ CORRECT
    );
    return docRef.id;
  }
  
  // UPDATE - Preserves createdAt, updates updatedAt
  Future<void> updatePost(String postId, PostModel post) async {
    await _firestore.collection(colPosts).doc(postId).update(
      post.toFirestoreUpdate() // ✅ CORRECT
    );
  }
  
  // CLOUD FUNCTION CALL
  Future<void> createPostViaFunction(PostModel post) async {
    final callable = AppConfigBase.firebaseFunctionCallable('createPost');
    await callable.call({
      'post': post.toCallable(), // ✅ CORRECT
    });
  }
  
  // LOCAL STORAGE
  Future<void> saveDraft(PostModel post) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'draft_${post.id}', 
      jsonEncode(post.toJson()), // ✅ CORRECT
    );
  }
}
```

### Enum Serialization - ALWAYS Required

**REQUIRED:**
- **ALWAYS** use `RobustEnumConverter` base classes from dreamic for enum fields
- **ALWAYS** choose the appropriate converter strategy:
  - `NullableEnumConverter<T>` - For optional enum fields (unknown values → null)
  - `DefaultEnumConverter<T>` - For required enum fields (unknown values → default value)
  - `LoggingEnumConverter<T>` - For required enum fields with monitoring (unknown values → log + default)
- **ALWAYS** annotate enum fields with `@YourEnumConverter()` annotation
- **ALWAYS** implement `enumValues` getter returning `EnumType.values`
- **ALWAYS** implement `defaultValue` getter for `DefaultEnumConverter` and `LoggingEnumConverter`

**FORBIDDEN:**
- **NEVER** add "unknown" or similar technical values to enums
- **NEVER** use `@JsonKey(unknownEnumValue: ...)` annotations
- **NEVER** leave enum fields without robust enum converters

**Example:**
```dart
import 'package:dreamic/dreamic.dart';

// 1. Nullable strategy for optional fields
enum UserType { guest, member, admin }

class UserTypeConverter extends NullableEnumConverter<UserType> {
  const UserTypeConverter();
  
  @override
  List<UserType> get enumValues => UserType.values;
}

@JsonSerializable(explicitToJson: true)
class UserModel extends BaseFirestoreModel {
  @UserTypeConverter()
  final UserType? type;  // nullable - unknown values become null
  
  // ... rest of model
}

// 2. Default strategy for required fields
enum Priority { low, medium, high }

class PriorityConverter extends DefaultEnumConverter<Priority> {
  const PriorityConverter();
  
  @override
  List<Priority> get enumValues => Priority.values;
  
  @override
  Priority get defaultValue => Priority.medium;  // Safe default
}

@JsonSerializable(explicitToJson: true)
class TaskModel extends BaseFirestoreModel {
  @PriorityConverter()
  final Priority priority;  // non-nullable - unknown values become medium
  
  // ... rest of model
}
```

### Code Generation - ALWAYS Run After Changes

**REQUIRED:**
After creating or modifying any models, **ALWAYS** run:

```bash
dart run build_runner build --delete-conflicting-outputs
```

---

## 🔴 MANDATORY: Repository Pattern

### Repository Structure - ALWAYS Required

**REQUIRED:**
- **ALWAYS** create an interface file (`*_repo_int.dart`) and implementation file (`*_repo_impl.dart`)
- **ALWAYS** use `Either<RepositoryFailure, T>` from dartz for methods that can fail
- **ALWAYS** use `Future<Either<RepositoryFailure, Unit>>` for async operations that don't return data
- **ALWAYS** use `Stream<T>` for reactive data updates
- **ALWAYS** use broadcast streams (`StreamController<T>.broadcast()`) for multiple listeners
- **ALWAYS** implement `dispose()` method to close StreamControllers
- **ALWAYS** log key operations with `logd()` and errors with `loge()`

**FORBIDDEN:**
- **NEVER** throw exceptions - always return `Either<RepositoryFailure, T>`
- **NEVER** expose mutable state directly
- **NEVER** forget to close StreamControllers
- **NEVER** hardcode cache keys

**Example:**
```dart
import 'package:dartz/dartz.dart';
import 'package:dreamic/dreamic.dart';

// Interface
abstract class PostRepoInt {
  Future<Either<RepositoryFailure, Post>> getPost(String postId);
  Future<Either<RepositoryFailure, Unit>> createPost(Post post);
  Future<Either<RepositoryFailure, Unit>> updatePost(Post post);
  Stream<Post> getPostStream(String postId);
  void dispose();
}

// Implementation
class PostRepoImpl implements PostRepoInt {
  final _streamController = StreamController<Post>.broadcast();
  
  @override
  Future<Either<RepositoryFailure, Post>> getPost(String postId) async {
    try {
      logd('getPost: Fetching post $postId');
      
      final doc = await FirebaseFirestore.instance
          .collection(colPosts)
          .doc(postId)
          .get();
      
      if (!doc.exists) {
        return left(RepositoryFailure(message: 'Post not found'));
      }
      
      final post = Post.fromFirestore(doc);
      return right(post);
    } catch (e) {
      loge('getPost: Failed - $e');
      return left(RepositoryFailure(message: e.toString()));
    }
  }
  
  @override
  Future<Either<RepositoryFailure, Unit>> createPost(Post post) async {
    try {
      logd('createPost: Creating post');
      
      await FirebaseFirestore.instance
          .collection(colPosts)
          .add(post.toFirestoreCreate());
      
      _streamController.add(post);
      return right(unit);
    } catch (e) {
      loge('createPost: Failed - $e');
      return left(RepositoryFailure(message: e.toString()));
    }
  }
  
  @override
  Stream<Post> getPostStream(String postId) => _streamController.stream;
  
  @override
  void dispose() => _streamController.close();
}
```

---

## 🟡 RECOMMENDED: Smart Loading for Fast Operations

### Loading Wrapper - Use for Operations Expected to Be Fast

**WHEN TO USE `callWithLoadingAfterTimeout()`:**

This pattern is for operations that:
1. **Usually complete quickly** (< 500ms) but occasionally take longer
2. **Must block user interaction** while in progress (to prevent double-submission or conflicting actions)
3. **Would cause jarring flicker** if you showed loading immediately

**Perfect Use Cases:**
- **Implicit auto-save** - Saving form data as user changes tabs/sections (usually instant from cache, occasionally needs network)
- **Optimistic updates** - Toggling favorites, likes, switches where you expect instant feedback but need to handle slow network
- **Quick validations** - Checking username availability, validating codes (usually cached/fast, occasionally slow)
- **Smart search** - Debounced search where most queries are cached but some require API calls
- **Background sync operations** - Syncing data on tab change where sync is usually instant but occasionally needs to catch up

**DO NOT USE FOR:**
- **Explicit user actions** (clicking "Save" button, "Submit" button) - Use `PageStatus.processingAction` with immediate loading feedback instead
- **Initial page data loading** - Use `PageStatus.loading` in state instead
- **Operations expected to be slow** (file uploads, report generation) - Show immediate loading state
- **Background operations** that don't need to block the UI
- **Operations where user expects to wait** (checkout, payment processing) - Show immediate loading

**Why This Pattern?**
- Prevents **loading flicker** on fast operations (no "flash of loading spinner")
- Provides **progressive disclosure** of loading state (only shows if actually needed)
- Maintains **responsive feel** when operations are fast
- Still provides **user feedback** when operations are unexpectedly slow

**Benefits:** 
- Only shows blocking loading overlay if operation exceeds threshold (default 750ms)
- Prevents loading flicker on fast operations (cached data, quick API responses)
- Supports multiple concurrent operations with automatic reference counting
- Provides consistent loading UI across the entire app

**Example - Implicit Auto-Save (Perfect Use Case):**
```dart
import 'package:dreamic/dreamic.dart';

// User changes a setting - we want to save immediately but don't want loading flicker
Future<void> onSettingChanged(String key, dynamic value) async {
  // Update UI immediately (optimistic)
  emitSafe(state.copyWith(
    settings: {...state.settings, key: value},
  ));
  
  // Save in background - only show loading if it takes > 750ms
  final result = await callWithLoadingAfterTimeout(
    () async => await _repo.saveSetting(key, value),
    timeoutBeforeLoadingMill: 750,
  );
  
  result.fold(
    (failure) {
      // Revert optimistic update
      emitSafe(state.copyWith(
        settings: state.previousSettings,
        errorMessage: 'Failed to save setting',
      ));
    },
    (_) {
      // Success - setting already updated in UI
    },
  );
}
```

**Example - Tab Change with Auto-Save:**
```dart
Future<void> onTabChanged(int newTabIndex) async {
  // Save current tab's data before switching
  // Usually fast (cached), occasionally slow (network sync required)
  final result = await callWithLoadingAfterTimeout(
    () async => await _repo.saveDraft(state.currentTabData),
    timeoutBeforeLoadingMill: 500,
  );
  
  result.fold(
    (failure) => emitSafe(state.copyWith(
      errorMessage: 'Could not save changes',
      // Don't change tabs on failure
    )),
    (_) => emitSafe(state.copyWith(
      currentTabIndex: newTabIndex,
      // Load new tab data
    )),
  );
}
```

**Example - Optimistic Toggle (Like/Favorite):**
```dart
Future<void> toggleFavorite(String itemId) async {
  // Update UI immediately
  final newFavorites = state.favorites.contains(itemId)
      ? state.favorites.where((id) => id != itemId).toList()
      : [...state.favorites, itemId];
  
  emitSafe(state.copyWith(favorites: newFavorites));
  
  // Sync with server - only show loading if slow
  final result = await callWithLoadingAfterTimeout(
    () async => await _repo.updateFavorite(itemId, newFavorites.contains(itemId)),
    timeoutBeforeLoadingMill: 1000, // Higher threshold for optimistic updates
  );
  
  result.fold(
    (failure) {
      // Revert on failure
      emitSafe(state.copyWith(
        favorites: state.favorites,
        errorMessage: 'Failed to update favorite',
      ));
    },
    (_) {
      // Success - UI already updated
    },
  );
}
```

**CONTRAST: Explicit Save Button (DON'T use callWithLoadingAfterTimeout):**
```dart
// ❌ DON'T DO THIS for explicit user actions
Future<void> onSaveButtonPressed() async {
  // User clicked "Save" - they EXPECT to wait
  // Show loading immediately, don't use callWithLoadingAfterTimeout
  emitSafe(state.copyWith(pageStatus: PageStatus.processingAction));
  
  final result = await _repo.savePost(state.post);
  
  result.fold(
    (failure) => emitSafe(state.copyWith(
      pageStatus: PageStatus.error,
      errorMessage: failure.message,
    )),
    (_) => emitSafe(state.copyWith(
      pageStatus: PageStatus.loaded,
      // Show success message
    )),
  );
}
```

**Example - Smart Search with Caching:**
```dart
// Search that's usually instant (cached) but occasionally needs API
Future<void> search(String query) async {
  // Debounce would happen before this
  
  final result = await callWithLoadingAfterTimeout(
    () async => await _repo.search(query),
    timeoutBeforeLoadingMill: 500, // Show loading only if cache miss + slow network
  );
  
  result.fold(
    (failure) => emitSafe(state.copyWith(
      searchResults: [],
      errorMessage: 'Search failed',
    )),
    (results) => emitSafe(state.copyWith(
      searchResults: results,
    )),
  );
}
```

**Configuration:**
```dart
// Configure global callbacks (typically in main.dart)
configureTimeoutLoadingCallbacks(
  onLoadingStart: () => myCustomLoadingStart(),
  onLoadingFinish: () => myCustomLoadingFinish(),
);

// Reset state if needed (error recovery)
resetLoadingState();

// Debug: Check active loading count
final activeCount = getActiveLoadingCallsCount();
```

**Advanced - Multiple Concurrent Operations:**
```dart
// Supports multiple concurrent operations with automatic reference counting
// Loading overlay stays visible until ALL operations complete
Future<void> syncMultipleTabs() async {
  final results = await Future.wait([
    callWithLoadingAfterTimeout(() => _repo.syncTab1()),
    callWithLoadingAfterTimeout(() => _repo.syncTab2()),
    callWithLoadingAfterTimeout(() => _repo.syncTab3()),
  ]);
  
  // Loading overlay only shown if ANY operation is slow
  // Automatically dismissed after all complete
}
```

**Default Behavior:**
- Default timeout: 750ms (from `AppConfigBase.timeoutBeforeShowingLoadingMill`)
- Default callbacks: Uses `AppCubit.overlayLoadingStart/Finish()`
- Automatic reference counting for multiple concurrent operations
- Loading shown only if operation exceeds timeout
- Error handling propagates exceptions after cleanup

**Key Insight:**
The timeout threshold (default 750ms) represents your app's "instant" feel. Operations faster than this feel instantaneous to users. Operations slower than this need visual feedback. This pattern bridges the gap between optimistic UI updates and reality.

---


## 🔴 MANDATORY: Error Handling

### Retry Logic - ALWAYS Use When Appropriate

**REQUIRED:**
- **ALWAYS** use `retryIt()` from dreamic for operations that may fail due to network issues
- **ALWAYS** configure retry attempts based on operation criticality

**Example:**
```dart
import 'package:dreamic/dreamic.dart';

Future<void> criticalOperation() async {
  final result = await retryIt(
    () async => await _repo.performCriticalAction(),
    maxAttempts: AppConfigBase.retryAttemptsCountMax,
  );
  
  result.fold(
    (failure) => emitSafe(state.copyWith(
      status: PageStatus.errorRetryable,
      errorMessage: failure.message,
    )),
    (data) => emitSafe(state.copyWith(
      status: PageStatus.loaded,
      data: data,
    )),
  );
}
```

---

## 🟡 RECOMMENDED: File Organization

### Cubit Placement

**RECOMMENDED:**
- Place cubit and state files in a `cubit` subfolder of the page or widget folder they are associated with
- Follow the established folder structure in the project

**Example Structure:**
```
lib/
  presentation/
    pages/
      home/
        home_page.dart
        cubit/
          home_cubit.dart
          home_state.dart
      details/
        details_page.dart
        cubit/
          details_cubit.dart
          details_state.dart
```

---

## 🟡 RECOMMENDED: Authentication Patterns

### Auth Service Usage

**RECOMMENDED:**
- Always use `isLoggedInAsync()` instead of checking `currentFbUser` directly
- Wait for `waitForCanCheckLoginState()` before checking auth status on app start
- Use `forceRefreshAuthState()` when you need to ensure the latest auth state

**Example:**
```dart
import 'package:dreamic/dreamic.dart';

// Check login status
final isLoggedIn = await g<AuthServiceInt>().isLoggedInAsync();

// Wait for auth state to be ready
await g<AuthServiceInt>().waitForCanCheckLoginState();

// Force refresh
await g<AuthServiceInt>().forceRefreshAuthState();

// Listen to login state changes
g<AuthServiceInt>().isLoggedInStream.listen((isLoggedIn) {
  if (!isLoggedIn) {
    // User logged out
  }
});
```

---

## 🟡 RECOMMENDED: Testing

### Unit Testing

**RECOMMENDED:**
- Write unit tests for all cubits
- Write unit tests for all business logic in repositories and services
- Use `MockCubitBase` from dreamic for testing cubits

**Example:**
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:dreamic/dreamic.dart';
import 'package:mocktail/mocktail.dart';

class MockMyRepo extends Mock implements MyRepoInt {}

void main() {
  late MyPageCubit cubit;
  late MockMyRepo mockRepo;
  
  setUp(() {
    mockRepo = MockMyRepo();
    cubit = MyPageCubit(mockRepo);
  });
  
  tearDown(() {
    cubit.close();
  });
  
  test('loadData emits loaded state on success', () async {
    final items = [Item(id: '1', name: 'Test')];
    
    when(() => mockRepo.getData()).thenAnswer(
      (_) async => right(items),
    );
    
    await cubit.loadData();
    
    expect(cubit.state.status, PageStatus.loaded);
    expect(cubit.state.items, items);
  });
}
```

---

## 📋 Quick Reference Checklist

When creating/modifying code, verify:

- [ ] Cubit extends `CubitBase` (not plain Cubit)
- [ ] State extends `CubitBaseState`
- [ ] Using `emitSafe()` (not `emit()`)
- [ ] Page wrapped with `PageStatusWrapper` and `PageStatusBodyWrapper`
- [ ] Using `TappableAction` or `TappableActionInkedWell` for tappable widgets
- [ ] StatefulWidget uses `SetStateSafeMixin` and `setStateSafe()`
- [ ] Using `adaptive_dialog` for standard dialogs
- [ ] Using `logd()`, `logw()`, `loge()` (not `print()`)
- [ ] Using AutoRoute for navigation (not Navigator directly)
- [ ] Using `AppConfigBase.firebaseFunctionCallable()` for Firebase functions
- [ ] Firestore collection/document names are constants in `db_constants.dart`
- [ ] Models extend `BaseFirestoreModel`
- [ ] Models use `@JsonSerializable(explicitToJson: true)`
- [ ] Models have proper timestamp converters (`@SmartTimestampConverter()`)
- [ ] Using correct serialization method (`toFirestoreCreate()`, `toFirestoreUpdate()`, `toCallable()`, `toJson()`)
- [ ] Enums use robust enum converters from dreamic
- [ ] Repository uses `Either<RepositoryFailure, T>` return type
- [ ] Using `callWithLoadingAfterTimeout()` for time-consuming operations
- [ ] Using design system constants (AppColors, AppStyles, AppSizes)
- [ ] Using `ResponsiveBreakpoints` or `ResponsiveValue` for responsive design
- [ ] Ran `dart run build_runner build` after model changes

---

## 🎯 Summary: The Dreamic Way

1. **State Management:** CubitBase + CubitBaseState + emitSafe()
2. **UI Wrappers:** PageStatusWrapper + PageStatusBodyWrapper + TappableAction
3. **Safe Mutations:** SetStateSafeMixin + setStateSafe()
4. **Dialogs:** adaptive_dialog package methods
5. **Logging:** logd(), logw(), loge()
6. **Navigation:** AutoRoute typed routes
7. **Firebase:** AppConfigBase.firebaseFunctionCallable()
8. **Database:** Constants in db_constants.dart
9. **Models:** BaseFirestoreModel + JsonSerializable + SmartTimestampConverter
10. **Serialization:** Context-aware methods (toFirestoreCreate/Update/Callable/Json)
11. **Enums:** RobustEnumConverter subclasses
12. **Repositories:** Either<RepositoryFailure, T>
13. **Loading:** callWithLoadingAfterTimeout()
14. **Design:** AppColors + AppStyles + AppSizes
15. **Responsive:** ResponsiveBreakpoints + ResponsiveValue
16. **Network:** Check AppCubit.networkStatus

**Remember:** These patterns are NOT optional suggestions. They are MANDATORY architectural requirements when using the dreamic package. Following them ensures consistency, reliability, and maintainability across the entire application.
