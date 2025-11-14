## Navigation

**Required Patterns:**
- **ALWAYS** use AutoRoute package for navigation
- **ALWAYS** use typed route navigation with AutoRoute's generated methods
- **ALWAYS** follow the established route structure in `app_router.dart`

**Forbidden Patterns:**
- **NEVER** use `Navigator.push()`, `Navigator.pop()` directly, except for closing dialogs

---

## 🔴 MANDATORY: Firestore Database Constants

### Collection/Document Names - ALWAYS Required

**REQUIRED:**
- **ALWAYS** store Firestore collection names in `db_constants.dart` as exported constants
- **ALWAYS** store Firestore subcollection names in `db_constants.dart` as exported constants
- **ALWAYS** store known constant document names in `db_constants.dart` as exported constants
- **ALWAYS** use descriptive naming: `col` prefix for collections, `subcol` prefix for subcollections, `doc` prefix for documents
- **ALWAYS** keep collection names unique across the entire database, including subcollections
- **ALWAYS** design collection names to support `collectionGroup()` queries
q
**FORBIDDEN:**
- **NEVER** hardcode collection or document names as string literals in code
- **NEVER** create duplicate constants for the same collection/document
- **NEVER** reuse collection names in different document hierarchies

**Example:**
```dart
// db_constants.dart
const String colUsers = 'users';
const String colPosts = 'posts';

// ✅ GOOD - Unique subcollection names
const String subcolPostComments = 'postComments';
const String subcolProjectComments = 'projectComments';

// ❌ BAD - Reusing same name in different contexts
// const String subcolComments = 'comments';  // DON'T DO THIS

const String docSettings = 'settings';

// Usage in code
import 'package:yourapp_common/data/helpers/db_constants.dart';

final usersRef = FirebaseFirestore.instance.collection(colUsers);
final postRef = usersRef.doc(userId).collection(colPosts).doc(postId);
final commentsRef = postRef.collection(subcolPostComments);

// CollectionGroup query - works because names are unique
final allPostComments = FirebaseFirestore.instance
    .collectionGroup(subcolPostComments)
    .where('approved', isEqualTo: true);
```

---


## 🔴 MANDATORY: Design System

### Colors, Styles, and Sizes - ALWAYS Use Constants

**REQUIRED:**
- **ALWAYS** use colors from `colors.dart` in the common project
- **ALWAYS** use styles from `styles.dart` in the common project
- **ALWAYS** use sizes and spacing from `sizes.dart` in the common project
- **ALWAYS** use `AppColors` class for all color constants
- **ALWAYS** use `AppStyles` class for consistent text styles
- **ALWAYS** use `AppSizes` class for spacing, dimensions, and other size-related constants

**FORBIDDEN:**
- **NEVER** hardcode colors, sizes, or spacing values directly in widgets

**Example:**
```dart
import 'package:yourapp_common/presentation/helpers/colors.dart';
import 'package:yourapp_common/presentation/helpers/styles.dart';
import 'package:yourapp_common/presentation/helpers/sizes.dart';

Container(
  padding: EdgeInsets.all(AppSizes.paddingMedium),
  decoration: BoxDecoration(
    color: AppColors.primaryBackground,
    borderRadius: BorderRadius.circular(AppSizes.radiusSmall),
  ),
  child: Text(
    'Hello World',
    style: AppStyles.heading1,
  ),
)
```

---

## 🔴 MANDATORY: Responsive Design

### Responsive Framework - ALWAYS Use

**REQUIRED:**
- **ALWAYS** use `responsive_framework` package for responsive layouts
- **ALWAYS** use `ResponsiveBreakpoints.of(context)` to check screen size breakpoints
- **ALWAYS** use `ResponsiveValue<T>` for values that need to change based on screen size
- **ALWAYS** use named breakpoint constants: `MOBILE`, `TABLET`, `DESKTOP`

**Example:**
```dart
import 'package:responsive_framework/responsive_framework.dart';

// Check breakpoints
padding: ResponsiveBreakpoints.of(context).isMobile
    ? const EdgeInsets.all(8.0)
    : const EdgeInsets.all(16.0),

// Use ResponsiveValue for multiple breakpoints
padding: ResponsiveValue<EdgeInsets>(
  context,
  defaultValue: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
  conditionalValues: [
    const Condition.largerThan(
      name: MOBILE,
      value: EdgeInsets.symmetric(horizontal: 18.0, vertical: 6.0),
    ),
  ],
).value,
```

---