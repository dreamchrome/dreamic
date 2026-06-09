/// Small, self-contained responsive utilities for `dreamic` — a zero
/// third-party-dependency replacement for the thin slice of
/// `responsive_framework` the app actually used (device-class detection and
/// "pick a value by breakpoint").
///
/// ## The split: structure vs dimensions
///
/// This file exposes **two** reactivity models. Keeping them straight is the
/// whole point of the API surface, so it is the first thing documented:
///
/// - **Breakpoints for structure** — *which* layout (one column vs two,
///   show/hide a panel). Read via [ResponsiveContext.deviceSize] /
///   [ResponsiveContext.responsive]. These resolve the **[ResponsiveScope]'s
///   whole-window device class** and rebuild dependents **only when the class
///   flips** (segment-only rebuilds), never on every pixel of a resize.
///
/// - **Interpolation for dimensions** — font size, spacing, gaps, max content
///   width. Read via [ResponsiveContext.clampByViewportWidth] /
///   [ResponsiveContext.responsiveByViewportWidth]. These read the **nearest
///   [MediaQuery] width at the call site** (the whole window normally, or a
///   sized sub-region under a deliberately nested [MediaQuery]) and rebuild
///   **per-pixel**, by design.
///
/// The `Viewport` qualifier on the width helpers marks "tracks the local width
/// *here*, not the device class" — so the two models can never be confused at a
/// call site. A consequence of this split: the width helpers read [MediaQuery]
/// directly and therefore need only a [MediaQuery] ancestor — **not** a
/// [ResponsiveScope] — whereas the class-based accessors throw a [FlutterError]
/// without a scope (see [ResponsiveScope] and [_ResponsiveData]).
///
/// ## Configuration
///
/// Set [Breakpoints] once at startup before `runApp`, then wrap the app in a
/// single [ResponsiveScope] (top-level, above `MaterialApp`, is supported).
///
/// ## Usage
///
/// ```dart
/// void main() {
///   // Configure once, before runApp (optional — defaults are 600 / 1024).
///   Breakpoints.tablet = 600;
///   Breakpoints.desktop = 1024;
///   runApp(const ResponsiveScope(child: MyApp()));
/// }
///
/// class HomeBody extends StatelessWidget {
///   const HomeBody({super.key});
///
///   @override
///   Widget build(BuildContext context) {
///     // Structure: pick a layout by device class (segment-only rebuilds).
///     final columns = context.responsive<int>(mobile: 1, tablet: 2, desktop: 3);
///
///     // Dimensions: interpolate by call-site viewport width (per-pixel).
///     final gutter = context.clampByViewportWidth(minValue: 12, maxValue: 32);
///     final maxContentWidth = context.responsiveByViewportWidth<double>(
///       breakpoints: {0: 480, 600: 720, 1024: 960},
///       fallback: 480,
///     );
///
///     return GridView.count(
///       crossAxisCount: columns,
///       padding: EdgeInsets.all(gutter),
///       children: [/* ... constrained to maxContentWidth ... */],
///     );
///   }
/// }
/// ```
///
/// Only `package:flutter/widgets.dart` is imported; the file is intentionally
/// Flutter-SDK-only.
library;

import 'package:flutter/widgets.dart';

/// Default device-class breakpoints, in logical pixels.
///
/// Library-private so they don't widen the public surface; they only seed the
/// mutable [Breakpoints] fields below and let tests restore the defaults.
const double _kDefaultTabletBreakpoint = 600;
const double _kDefaultDesktopBreakpoint = 1024;

/// The current viewport-width / layout class of the window.
///
/// This is the **layout width class** the UI should adapt its *structure* to
/// (narrow / medium / wide), derived from the [ResponsiveScope]'s width via
/// [classify]. It is deliberately orthogonal to two other device concepts in
/// this package, which it must not be conflated with:
///
/// - [DevicePlatform] — the **operating system** (iOS / Android / web / macOS /
///   Windows / Linux). For "is this a phone OS?" use `DevicePlatform`, not
///   `DeviceSize`.
/// - `DeviceFormFactor` — the **physical device form factor** (phone / tablet /
///   desktop / browser), used server-side for notification-delivery
///   prioritization and **not** barrel-exported. It shares the `tablet` /
///   `desktop` names with `DeviceSize` (and `phone` ≈ `mobile`), but it
///   describes the hardware, whereas `DeviceSize` describes the **current
///   window width**.
enum DeviceSize {
  /// Narrow window — `width < Breakpoints.tablet`.
  mobile,

  /// Medium window — `Breakpoints.tablet <= width < Breakpoints.desktop`.
  tablet,

  /// Wide window — `width >= Breakpoints.desktop`.
  desktop,
}

/// Globally configurable device-class breakpoints, in logical pixels.
///
/// Configure **once at startup, before `runApp`** — e.g. in `main()`:
///
/// ```dart
/// void main() {
///   Breakpoints.tablet = 700;
///   Breakpoints.desktop = 1200;
///   runApp(const ResponsiveScope(child: MyApp()));
/// }
/// ```
///
/// These are process-global mutable statics; there is no per-call
/// configuration. Set `tablet < desktop`: [classify] assumes ascending
/// thresholds, so an inverted pair (e.g. `tablet = 2000`, `desktop = 1024`)
/// silently misclassifies. There is **no runtime guard** for this, by
/// minimalism — a misconfiguration is a startup error that is immediately
/// visible in development.
class Breakpoints {
  /// Minimum width (logical px) classified as [DeviceSize.tablet].
  static double tablet = _kDefaultTabletBreakpoint;

  /// Minimum width (logical px) classified as [DeviceSize.desktop].
  static double desktop = _kDefaultDesktopBreakpoint;
}

/// Classifies a window [width] (logical px) into a [DeviceSize].
///
/// Ordered `desktop → tablet → mobile`, assuming ascending [Breakpoints]
/// (`tablet < desktop`):
///
/// - `width >= Breakpoints.desktop` → [DeviceSize.desktop]
/// - `Breakpoints.tablet <= width < Breakpoints.desktop` → [DeviceSize.tablet]
/// - `width < Breakpoints.tablet` → [DeviceSize.mobile]
///
/// Exposed only for direct unit testing ([visibleForTesting]); it is **not**
/// part of the public package surface (the barrel's `show` clause excludes it).
/// Production code reads the class through [ResponsiveScope] /
/// [ResponsiveContext], never by calling this directly.
@visibleForTesting
DeviceSize classify(double width) {
  if (width >= Breakpoints.desktop) return DeviceSize.desktop;
  if (width >= Breakpoints.tablet) return DeviceSize.tablet;
  return DeviceSize.mobile;
}

/// Carries the current [DeviceSize] down the tree and notifies dependents
/// **only when the class flips** — the segment-only rebuild gate.
///
/// Private by design: the public surface exposes the device *class* (via
/// [ResponsiveContext]), not this widget. Owned and rebuilt by
/// [ResponsiveScope].
class _ResponsiveData extends InheritedWidget {
  const _ResponsiveData({
    required this.deviceSize,
    required super.child,
  });

  /// The whole-window device class captured by the enclosing [ResponsiveScope].
  final DeviceSize deviceSize;

  /// Resolves the nearest [_ResponsiveData] and registers [context] as a
  /// dependent.
  ///
  /// Throws a [FlutterError] (in **both debug and release**) when no
  /// [ResponsiveScope] is present, rather than relying on a debug-only `assert`
  /// that would degrade to a bare null-dereference error in release.
  static DeviceSize of(BuildContext context) {
    final data =
        context.dependOnInheritedWidgetOfExactType<_ResponsiveData>();
    if (data == null) {
      throw FlutterError(
        'No ResponsiveScope found. Wrap your app in a ResponsiveScope.',
      );
    }
    return data.deviceSize;
  }

  @override
  bool updateShouldNotify(_ResponsiveData old) =>
      old.deviceSize != deviceSize;
}

/// Debug-only threshold: how many **consecutive** rebuilds with a *fresh*
/// [ResponsiveScope.child] instance, *without a device-class change*, before the
/// scope warns (once) that segment-only rebuilds are being defeated.
///
/// Sized so a real per-pixel resize drag (~60 fps) trips it in a fraction of a
/// second, while a one-off legitimate `child` swap (streak resets to 0 on the
/// next stable rebuild) never does. Used only inside an `assert`, so it — and
/// all the tracking it gates — is tree-shaken out of release builds.
const int _kUnstableChildWarnThreshold = 10;

/// Establishes the responsive device-class context for its subtree.
///
/// Reads `MediaQuery.sizeOf(context).width`, classifies it via [classify], and
/// publishes the result through an inherited [_ResponsiveData] so that
/// [ResponsiveContext.deviceSize] / [ResponsiveContext.responsive] resolve.
///
/// Place this **above the subtree that must not rebuild on resize**, and pass a
/// **stable `child` reference**: the segment-only-rebuild guarantee (BEH-05)
/// depends on the same `child` instance being forwarded across resizes. The
/// scope itself may rebuild per-pixel as the window changes, but the subtree is
/// preserved as long as `child` is unchanged — so prefer a `const` child:
///
/// ```dart
/// runApp(const ResponsiveScope(child: MyApp()));
/// ```
///
/// **Why it is a [StatefulWidget].** The widget carries no runtime state — it is
/// stateful purely so a **debug-only diagnostic** can track the `child` across
/// rebuilds. If an ancestor rebuilds the scope on every resize frame while
/// constructing the `child` inline (an unstable reference), the whole subtree
/// rebuilds per-pixel and the segment-only guarantee is silently lost. To make
/// that loud, [build] watches for the failure's exact signature — the `child`
/// instance changing on a rebuild that did **not** change the device class — and
/// after [_kUnstableChildWarnThreshold] consecutive such rebuilds emits a single
/// `debugPrint`. It checks *identity*, not const-ness, so a non-const-but-stable
/// `child` is fine; the entire check is inside an `assert` and costs nothing in
/// release.
///
/// Top-level placement (above `MaterialApp`) is valid: `runApp` wraps the app
/// in a root `View` that supplies a `MediaQuery` via `MediaQuery.fromView`, so
/// the scope always resolves one. The one caveat: a `runWidget` / multi-view
/// bootstrap must ensure a `View` / `MediaQuery` sits above the scope.
class ResponsiveScope extends StatefulWidget {
  const ResponsiveScope({super.key, required this.child});

  /// The subtree that reads the device class. Pass a **stable** reference
  /// (ideally `const`) to preserve it across resizes.
  final Widget child;

  @override
  State<ResponsiveScope> createState() => _ResponsiveScopeState();
}

class _ResponsiveScopeState extends State<ResponsiveScope> {
  // Debug-only churn tracking. Every field below is read/written only inside the
  // `assert` block in [build], so the diagnostic is stripped from release.
  Widget? _lastChild;
  DeviceSize? _lastClass;
  int _churnStreak = 0;
  bool _warned = false;

  @override
  Widget build(BuildContext context) {
    final deviceSize = classify(MediaQuery.sizeOf(context).width);
    assert(() {
      // The failure signature: a fresh `child` arrived on a rebuild that did NOT
      // change the device class — i.e. a within-class resize is rebuilding the
      // whole subtree instead of preserving it (segment-only rebuilds defeated).
      final churned = _lastChild != null &&
          !identical(_lastChild, widget.child) &&
          deviceSize == _lastClass;
      if (churned) {
        if (++_churnStreak >= _kUnstableChildWarnThreshold && !_warned) {
          _warned = true;
          debugPrint(
            'WARNING (dreamic ResponsiveScope): `child` changed on $_churnStreak '
            'consecutive rebuilds with no device-class change — the whole subtree '
            'is rebuilding on every resize frame instead of only when the device '
            'class flips. Pass a stable `child` (a `const` widget, or one hoisted '
            'out of any ancestor that rebuilds during resize).',
          );
        }
      } else {
        _churnStreak = 0;
      }
      _lastChild = widget.child;
      _lastClass = deviceSize;
      return true;
    }());
    return _ResponsiveData(deviceSize: deviceSize, child: widget.child);
  }
}

/// `BuildContext` extension exposing the responsive API.
///
/// Two groups of members with **different reactivity models** — see the file
/// header's structure-vs-dimensions split:
///
/// - **Class-based reads** ([deviceSize]; the exact-match predicates [isMobile],
///   [isTablet], [isDesktop]; the ordered-threshold predicates
///   [isTabletOrLarger], [isTabletOrSmaller], [isAtLeast], [isAtMost]; and
///   [responsive]) resolve the [ResponsiveScope]'s whole-window class and
///   rebuild **only when the class flips**. They require a [ResponsiveScope]
///   ancestor.
/// - **Viewport-width helpers** ([responsiveByViewportWidth],
///   [clampByViewportWidth]) read the nearest [MediaQuery] width at the call
///   site and rebuild **per-pixel**. They require only a [MediaQuery] ancestor.
extension ResponsiveContext on BuildContext {
  /// The current whole-window [DeviceSize], from the enclosing
  /// [ResponsiveScope].
  ///
  /// Throws a [FlutterError] if no [ResponsiveScope] is present.
  DeviceSize get deviceSize => _ResponsiveData.of(this);

  /// Whether the current layout width class is [DeviceSize.mobile].
  ///
  /// Reports the **layout width class** (a narrow window) derived from the
  /// [ResponsiveScope] — **not** the OS / device platform. For "is this a phone
  /// OS?" use [DevicePlatform.isMobile] instead; both ship from the same barrel
  /// and the identical name is the only thing they share.
  bool get isMobile => deviceSize == DeviceSize.mobile;

  /// Whether the current layout width class is [DeviceSize.tablet].
  ///
  /// Reports the **layout width class** (a medium-width window) derived from the
  /// [ResponsiveScope] — **not** the OS / device platform (see
  /// [DevicePlatform]).
  bool get isTablet => deviceSize == DeviceSize.tablet;

  /// Whether the current layout width class is [DeviceSize.desktop].
  ///
  /// Reports the **layout width class** (a wide window) derived from the
  /// [ResponsiveScope] — **not** the OS / device platform. For desktop OS
  /// detection use [DevicePlatform.isDesktop].
  bool get isDesktop => deviceSize == DeviceSize.desktop;

  /// Whether the current layout width class is [DeviceSize.tablet] or wider —
  /// the ordered "larger than mobile" threshold.
  ///
  /// Equivalent to `!isMobile`, but reads as an ascending threshold rather than
  /// a negation, mirroring the "the tablet value applies to tablet and larger"
  /// semantics of [responsive]. Shorthand for `isAtLeast(DeviceSize.tablet)`.
  ///
  /// Reports the **layout width class** (window width), **not** the OS / device
  /// platform — for "is this a phone OS?" use [DevicePlatform.isMobile] (see
  /// [isMobile]).
  bool get isTabletOrLarger => isAtLeast(DeviceSize.tablet);

  /// Whether the current layout width class is [DeviceSize.tablet] or narrower —
  /// the ordered "smaller than desktop" threshold.
  ///
  /// Equivalent to `!isDesktop`, but reads as a descending threshold. Shorthand
  /// for `isAtMost(DeviceSize.tablet)`.
  ///
  /// Reports the **layout width class** (window width), **not** the OS / device
  /// platform (see [DevicePlatform]).
  bool get isTabletOrSmaller => isAtMost(DeviceSize.tablet);

  /// Whether the current layout width class is at least [min] on the ordered
  /// scale `mobile < tablet < desktop` (inclusive lower bound).
  ///
  /// The general test behind [isTabletOrLarger]; use it for an explicit
  /// threshold at the call site — `context.isAtLeast(DeviceSize.tablet)` reads
  /// as "tablet or wider." The two degenerate ends collapse into existing
  /// getters: `isAtLeast(DeviceSize.mobile)` is always `true`, and
  /// `isAtLeast(DeviceSize.desktop)` equals [isDesktop] — so [DeviceSize.tablet]
  /// is the only threshold that adds expressiveness over [isMobile] /
  /// [isDesktop].
  ///
  /// Compares [DeviceSize] declaration order via `index`, so it relies on the
  /// enum staying declared in ascending-width order (mobile, tablet, desktop).
  bool isAtLeast(DeviceSize min) => deviceSize.index >= min.index;

  /// Whether the current layout width class is at most [max] on the ordered
  /// scale `mobile < tablet < desktop` (inclusive upper bound).
  ///
  /// The general test behind [isTabletOrSmaller]. The two degenerate ends
  /// collapse into existing getters: `isAtMost(DeviceSize.desktop)` is always
  /// `true`, and `isAtMost(DeviceSize.mobile)` equals [isMobile].
  ///
  /// Compares [DeviceSize] declaration order via `index`, so it relies on the
  /// enum staying declared in ascending-width order (mobile, tablet, desktop).
  bool isAtMost(DeviceSize max) => deviceSize.index <= max.index;

  /// Picks a value by device class, with fallback chaining toward the smaller
  /// class.
  ///
  /// `mobile` is required; `tablet` and `desktop` are optional and **inherit
  /// from the smaller class** when omitted:
  ///
  /// - [DeviceSize.desktop] → `desktop ?? tablet ?? mobile`
  /// - [DeviceSize.tablet] → `tablet ?? mobile`
  /// - [DeviceSize.mobile] → `mobile`
  ///
  /// This intentionally replaces most `ResponsiveValue` "larger than" usage:
  /// "the tablet value applies to tablet and larger." For example,
  /// `context.responsive(mobile: a, desktop: c)` returns `a` on a tablet (the
  /// omitted `tablet` inherits from `mobile` — it does **not** skip ahead to
  /// `desktop`) and `c` on a desktop.
  ///
  /// Caveat (nullable `T`): because an omitted `tablet` / `desktop` inherits
  /// from the smaller class, do **not** use a nullable `T` expecting an
  /// explicit `null` to be returned for an omitted class — there is no way to
  /// distinguish "omitted" from "explicitly null."
  T responsive<T>({required T mobile, T? tablet, T? desktop}) {
    switch (deviceSize) {
      case DeviceSize.desktop:
        return desktop ?? tablet ?? mobile;
      case DeviceSize.tablet:
        return tablet ?? mobile;
      case DeviceSize.mobile:
        return mobile;
    }
  }

  /// Picks a value by **call-site viewport width**, choosing the highest
  /// threshold that is `<=` the current width.
  ///
  /// `breakpoints` maps a minimum width (logical px) to the value that applies
  /// at or above it; `fallback` is returned when the width is below every
  /// threshold. Selection is **order-independent** — entries are sorted
  /// internally, so the input map's insertion order does not matter.
  ///
  /// ```dart
  /// final columns = context.responsiveByViewportWidth<int>(
  ///   breakpoints: {0: 1, 600: 2, 1024: 3},
  ///   fallback: 1,
  /// );
  /// ```
  ///
  /// **Width read (shared with [clampByViewportWidth]):** reads the nearest
  /// [MediaQuery] width at the call site (`MediaQuery.sizeOf(this).width`) —
  /// **not** the [ResponsiveScope]'s device class. In a normal single-
  /// [MediaQuery] app this equals the device width; it diverges only under a
  /// deliberately nested [MediaQuery] override, where it tracks the local
  /// sub-region (the intended "size to fit the space here" behavior — note the
  /// `Viewport` in the name). It rebuilds **per-pixel** by design and requires
  /// only a [MediaQuery] ancestor — **no [ResponsiveScope] needed**.
  T responsiveByViewportWidth<T>({
    required Map<double, T> breakpoints,
    required T fallback,
  }) {
    final width = MediaQuery.sizeOf(this).width;
    final entries = breakpoints.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key)); // high → low
    for (final entry in entries) {
      if (entry.key <= width) return entry.value;
    }
    return fallback;
  }

  /// Linearly interpolates between [minValue] and [maxValue] across the width
  /// range `[minW, maxW]`, clamped at both ends — the CSS `clamp()` equivalent.
  ///
  /// Returns [minValue] at or below `minW`, [maxValue] at or above `maxW`, and
  /// the proportional value in between. Values past either end are **clamped,
  /// never extrapolated**.
  ///
  /// ```dart
  /// final fontSize = context.clampByViewportWidth(
  ///   minValue: 14, maxValue: 20, minW: 360, maxW: 1200,
  /// );
  /// ```
  ///
  /// Hardening: if a caller passes a degenerate range (`minW >= maxW`, i.e.
  /// zero or negative span), this returns [minValue] instead of producing a
  /// `NaN` / `Infinity` from a divide-by-zero.
  ///
  /// **Width read (shared with [responsiveByViewportWidth]):** reads the nearest
  /// [MediaQuery] width at the call site (`MediaQuery.sizeOf(this).width`) —
  /// **not** the [ResponsiveScope]'s device class. In a normal single-
  /// [MediaQuery] app this equals the device width; it diverges only under a
  /// deliberately nested [MediaQuery] override, where it tracks the local
  /// sub-region (note the `Viewport` in the name). It rebuilds **per-pixel** by
  /// design and requires only a [MediaQuery] ancestor — **no [ResponsiveScope]
  /// needed**.
  double clampByViewportWidth({
    required double minValue,
    required double maxValue,
    double minW = 360,
    double maxW = 1200,
  }) {
    final w = MediaQuery.sizeOf(this).width;
    final range = maxW - minW;
    if (range <= 0) return minValue; // degenerate-range guard (BEH-08)
    final t = ((w - minW) / range).clamp(0.0, 1.0);
    return minValue + (maxValue - minValue) * t;
  }
}
