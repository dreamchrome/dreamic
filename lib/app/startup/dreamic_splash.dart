import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import '../../utils/logger.dart';

/// The conventional logo asset path the native `flutter_native_splash:` codegen
/// also points at, so `const DreamicSplash()` renders a logo that matches the
/// native launch screen **by construction** (one asset feeds both) — preserving
/// the seamless native→Flutter handoff with zero per-call config (Issue 113).
const String _defaultLogoAsset = 'assets/splash_logo.png';

/// The default branded logo: the conventional `assets/splash_logo.png` the
/// `flutter_native_splash:` `image:` config also uses. Resolved via the
/// `ImageStream` decode-readiness path so the native splash is held until the
/// Flutter logo bitmap is decoded (no background-only flash, Issue 70). A
/// missing/broken asset degrades via the safety timeout (Issue 70/74).
const ImageProvider<Object> _defaultLogo = AssetImage(_defaultLogoAsset);

/// The default safety timeout bounding the native-splash teardown so a
/// missing/broken/never-resolving logo (or readiness hook) can't strand the
/// native launch screen over the running app (Issue 70/108).
const Duration _defaultSafetyTimeout = Duration(seconds: 2);

/// Signature for the injectable `FlutterNativeSplash.remove()` seam. Defaults to
/// the real `remove()`; tests inject a spy to assert at-most-once teardown
/// without depending on the platform channel (Issue 70/97 — `remove()` is itself
/// a safe no-op on the non-web VM test runner per Issue 66).
typedef NativeSplashRemove = void Function();

/// Holds the native OS launch splash up until [DreamicSplash] tears it down,
/// giving a **flash-free** native→Flutter handoff.
///
/// Call this **once, as early as possible** in `main()` — right after
/// `WidgetsFlutterBinding.ensureInitialized()` (pass the binding it returns) and
/// before `runApp`. It calls `FlutterNativeSplash.preserve()`, which defers
/// Flutter's first *presented* frame so the OS splash stays composited until
/// `DreamicSplash` calls `FlutterNativeSplash.remove()`.
///
/// **This is the load-bearing half of the handoff.** `DreamicSplash` already
/// gates `remove()` on its logo bitmap being decoded (the `ImageProvider` decode
/// listener, or [DreamicSplash.removeNativeSplashWhen] for a `Widget` logo). But
/// `remove()` (= `WidgetsBinding.allowFirstFrame()`) is a **no-op unless
/// `preserve()` was called first** — without this, the OS splash dismisses on
/// its own schedule (at the natural first frame), which can expose a white frame
/// before the Flutter logo is painted (the handoff "blink"). With this in place,
/// the OS splash is not removed until the Flutter logo frame is ready, so the
/// transition is logo→logo with nothing white between.
///
/// Safe by construction: `DreamicSplash` also calls `remove()` from its
/// [DreamicSplash.safetyTimeout] and from `dispose()`, so the first frame is
/// always eventually allowed even if the decode never completes.
///
/// **Web no-op** — `preserve()`/`remove()` are web no-ops in
/// `flutter_native_splash`; the `index.html` loader is the web analog.
void dreamicPreserveNativeSplash(WidgetsBinding binding) {
  if (kIsWeb) return;
  FlutterNativeSplash.preserve(widgetsBinding: binding);
}

/// A branded, **plain** splash widget that paints on the first Flutter frame and
/// owns the native→Flutter splash handoff.
///
/// `DreamicSplash` is the canonical [DreamicAppInitGate.splash] — it renders the
/// app's brand (a centered logo over a brand background, or a fully custom
/// [child]) while `dreamicBootstrap()` runs behind it, and removes the native
/// launch screen once its logo is **paint-ready**, so there is no white (or
/// background-only) flash at handoff.
///
/// **Common case (near-zero config).** Supply [logo] (an `ImageProvider` or a
/// `Widget`) plus [backgroundColor]/[backgroundGradient] → a centered-logo-on-
/// brand-background splash. [logo] is **optional**, defaulting to
/// `AssetImage('assets/splash_logo.png')` — the same asset each app points its
/// `flutter_native_splash:` `image:` config at — so `const DreamicSplash()`
/// renders the branded logo that matches the native screen by construction
/// (Issue 113). A generic dreamic-shipped fallback logo is deliberately *not*
/// provided: it would mismatch every app's native screen and reintroduce the
/// handoff flash. If the conventional asset is absent, the decode listener never
/// resolves and the [safetyTimeout] fires `remove()` (graceful degradation).
///
/// **Elaborate case.** Supply [child] to fully replace the default visual
/// ([logo]/background slots ignored) while **still** getting the native handoff.
///
/// **Animated logo (Issue 30).** [logo] accepts a `Widget` (not only an
/// `ImageProvider`), so an animated widget (Lottie/Rive/`AnimatedBuilder`)
/// works in the centered-logo case; [child] likewise. A non-`ImageProvider`
/// logo has no single `ImageStream` to await, so supply [removeNativeSplashWhen]
/// (a readiness `Future`) to gate the native teardown — otherwise the teardown
/// falls back to a post-frame `remove()`.
///
/// **Plain widget (CC2 / Issues 61/73).** `DreamicSplash` renders **above** the
/// app's `MaterialApp` (no inherited `Directionality`/`MaterialLocalizations`/
/// `MediaQuery`, and CC2 forbids the `WidgetsApp` that would supply them), so it
/// self-provides a `Directionality`, uses **no** `MediaQuery`-dependent widget
/// (it sizes the default logo via fixed dimensions / `LayoutBuilder`, not
/// `MediaQuery.of`), and mounts no `WidgetsApp`/router. A custom [child]/[logo]
/// that needs `MediaQuery`/Material must wrap its own.
///
/// **Web (Issue 8/68).** `FlutterNativeSplash.preserve()`/`remove()` are guarded
/// behind `!kIsWeb` (no-ops on web — the `index.html` loader is the web analog);
/// the splash still renders as a plain Flutter widget. `DreamicSplash` holds
/// **no** timing logic — `minimumSplashDuration` is enforced entirely by the
/// gate (the `remove()` readiness/timeout is a separate concern it owns because
/// it owns `remove()`).
class DreamicSplash extends StatefulWidget {
  const DreamicSplash({
    super.key,
    this.logo = _defaultLogo,
    this.backgroundColor,
    this.backgroundGradient,
    this.child,
    this.logoWidth = 200.0,
    this.logoHeight = 200.0,
    this.removeNativeSplashWhen,
    this.safetyTimeout = _defaultSafetyTimeout,
    @visibleForTesting this.removeNativeSplash,
  }) : assert(
          backgroundColor == null || backgroundGradient == null,
          'Supply at most one of backgroundColor / backgroundGradient.',
        );

  /// The logo shown centered on the brand background. Either an `ImageProvider`
  /// (decode-readiness gated — the no-flash default path) or a `Widget` (e.g. an
  /// animated logo, gated by [removeNativeSplashWhen] / post-frame fallback).
  ///
  /// Defaults to `AssetImage('assets/splash_logo.png')` (Issue 113). Ignored
  /// when [child] is supplied.
  final Object? logo;

  /// Solid brand background color. Mutually exclusive with [backgroundGradient].
  final Color? backgroundColor;

  /// Brand background gradient. Mutually exclusive with [backgroundColor].
  final Gradient? backgroundGradient;

  /// A fully custom splash visual replacing the default centered-logo layout.
  /// When supplied, [logo]/[backgroundColor]/[backgroundGradient]/[logoWidth]/
  /// [logoHeight] are ignored — but the native handoff still applies.
  final Widget? child;

  /// Fixed display width for an `ImageProvider` [logo] (no `MediaQuery`).
  final double logoWidth;

  /// Fixed display height for an `ImageProvider` [logo] (no `MediaQuery`).
  final double logoHeight;

  /// Optional readiness hook for an animated / custom-[child] / non-
  /// `ImageProvider` [logo] (which has no single `ImageStream` to await): the
  /// native splash is removed when this `Future` completes. It is wrapped in the
  /// same [safetyTimeout] as the `ImageProvider` path, and a throwing or
  /// never-completing `Future` degrades to an immediate `remove()`
  /// (error-as-ready) rather than stranding the native splash or aborting
  /// bootstrap (Issue 108). Absent this hook, a non-`ImageProvider` logo falls
  /// back to a post-frame `remove()`.
  final Future<void>? removeNativeSplashWhen;

  /// Bounds every native-teardown path so a missing/broken asset or a
  /// never-completing readiness hook can't strand the native splash. Defaults to
  /// `~Duration(seconds: 2)` (Issue 70/108).
  final Duration safetyTimeout;

  /// Test seam for `FlutterNativeSplash.remove()`. When `null`, the real
  /// (web-guarded) `remove()` is used. Tests inject a spy to assert exactly one
  /// teardown across the three trigger paths (Issue 70/97).
  @visibleForTesting
  final NativeSplashRemove? removeNativeSplash;

  @override
  State<DreamicSplash> createState() => _DreamicSplashState();
}

class _DreamicSplashState extends State<DreamicSplash> {
  /// At-most-once teardown guard. The first of the three trigger paths
  /// (logo-decode listener, [DreamicSplash.safetyTimeout], `dispose()`) to fire
  /// sets this, calls `remove()`, and cancels the listener + timer; the others
  /// no-op. Load-bearing, not defensive-only: `FlutterNativeSplash.remove()`
  /// (2.4.8) is **not** idempotent on web (Issue 97).
  bool _nativeSplashRemoved = false;

  ImageStream? _logoStream;
  ImageStreamListener? _logoListener;
  Timer? _safetyTimer;

  @override
  void initState() {
    super.initState();
    // Schedule readiness resolution after the first frame: an ImageProvider
    // needs a resolved `ImageConfiguration` (`createLocalImageConfiguration`
    // requires a mounted `BuildContext`).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _startNativeHandoffTeardown();
    });
  }

  /// Wires up exactly one readiness path:
  /// - a custom [DreamicSplash.removeNativeSplashWhen] Future (error-as-ready,
  ///   timeout-bounded), else
  /// - an `ImageProvider` logo's decode listener (timeout-bounded), else
  /// - a post-frame `remove()` for a non-`ImageProvider` logo with no hook.
  ///
  /// Every path is additionally backstopped by the [DreamicSplash.safetyTimeout]
  /// (and by `dispose()`), all routed through [_removeNativeSplashOnce].
  void _startNativeHandoffTeardown() {
    // Arm the safety timeout for ALL paths first, so a hook/decode that never
    // fires still releases the native splash.
    _safetyTimer = Timer(widget.safetyTimeout, _removeNativeSplashOnce);

    final readiness = widget.removeNativeSplashWhen;
    if (readiness != null) {
      // Custom readiness hook: best-effort — a throw or a hang must not strand
      // the native splash nor abort bootstrap. Catch-and-degrade to remove()
      // (error-as-ready); the safety timer covers the never-completing case
      // (Issue 108).
      readiness.then(
        (_) {
          // _removeNativeSplashOnce is idempotent and mount-safe (it never
          // setState's), so an early dispose having already torn down just
          // no-ops here.
          _removeNativeSplashOnce();
        },
        onError: (Object error, StackTrace stackTrace) {
          // A readiness-hook failure is visual polish lateness, not a fatal
          // task (contrast Issue 81/84) — log and degrade to an immediate
          // teardown.
          logw(
            'DreamicSplash: removeNativeSplashWhen failed; '
            'removing native splash immediately (error-as-ready): $error',
          );
          _removeNativeSplashOnce();
        },
      );
      return;
    }

    final logo = widget.logo;
    if (widget.child == null && logo is ImageProvider) {
      _awaitLogoDecode(logo);
      return;
    }

    // Non-ImageProvider logo / custom child with no readiness hook: there is no
    // single ImageStream to await, so fall back to a post-frame remove(). The
    // safety timer is already armed as a backstop.
    _removeNativeSplashOnce();
  }

  /// Defers `remove()` until the logo's first `ImageInfo` (decoded bitmap),
  /// so the static native logo stays up until the Flutter logo is paint-ready
  /// (no background-only flash, Issue 70). Bounded by the safety timer.
  void _awaitLogoDecode(ImageProvider provider) {
    final stream = provider.resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener(
      (ImageInfo info, bool synchronousCall) {
        // First decoded frame → safe to tear down the native splash.
        _removeNativeSplashOnce();
      },
      onError: (Object error, StackTrace? stackTrace) {
        // Broken/missing asset: don't strand the native splash — degrade to an
        // immediate remove() (the safety timer would otherwise cover it).
        logw(
          'DreamicSplash: logo image failed to decode; '
          'removing native splash immediately: $error',
        );
        _removeNativeSplashOnce();
      },
    );
    _logoStream = stream;
    _logoListener = listener;
    stream.addListener(listener);
  }

  /// The single at-most-once teardown. First caller wins: sets the guard, calls
  /// the (web-guarded) `remove()`, and cancels the listener + safety timer; all
  /// later callers no-op (Issue 97).
  void _removeNativeSplashOnce() {
    if (_nativeSplashRemoved) return;
    _nativeSplashRemoved = true;

    _cancelReadinessWatchers();

    // Web no-ops: the index.html loader is the web analog (Issue 8/68).
    if (kIsWeb) return;

    try {
      (widget.removeNativeSplash ?? FlutterNativeSplash.remove)();
    } catch (e, stackTrace) {
      // remove() must never crash startup; a teardown failure is logged and
      // swallowed.
      loge(e, 'DreamicSplash: FlutterNativeSplash.remove() failed', stackTrace);
    }
  }

  void _cancelReadinessWatchers() {
    final listener = _logoListener;
    if (listener != null) {
      _logoStream?.removeListener(listener);
    }
    _logoStream = null;
    _logoListener = null;
    _safetyTimer?.cancel();
    _safetyTimer = null;
  }

  @override
  void dispose() {
    // Final guarantee that the native splash never outlives the Flutter splash:
    // the gate can transition splash→child (success) or splash→errorWidget (a
    // fatal bootstrap error) BEFORE the logo decodes or the safety timeout
    // fires, disposing us early. Without this dispose-time remove() the native
    // splash's deferred first frame is never released and the app appears frozen
    // (Issue 74). Routed through the same at-most-once guard.
    _removeNativeSplashOnce();
    _cancelReadinessWatchers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Self-provide a Directionality — DreamicSplash renders above MaterialApp
    // with no inherited Directionality/MaterialLocalizations (CC2 forbids the
    // WidgetsApp that would supply them). The gate also wraps the splash branch
    // in a default Directionality (defense-in-depth) — Issues 61/73.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: _buildVisual(),
    );
  }

  Widget _buildVisual() {
    final child = widget.child;
    if (child != null) {
      // Full-custom visual: the brand background still applies as a backdrop so
      // a transparent child composes over brand, not the default black.
      return _withBackground(child);
    }
    return _withBackground(Center(child: _buildLogo()));
  }

  Widget _buildLogo() {
    final logo = widget.logo;
    if (logo is Widget) {
      // Animated/custom logo widget (Issue 30) — rendered as-is.
      return logo;
    }
    if (logo is ImageProvider) {
      // Fixed dimensions — NO MediaQuery (Issue 73).
      return Image(
        image: logo,
        width: widget.logoWidth,
        height: widget.logoHeight,
        fit: BoxFit.contain,
        // A broken asset shows nothing (the native splash teardown is handled by
        // the decode error listener, not here).
        errorBuilder: (context, error, stackTrace) =>
            const SizedBox.shrink(),
      );
    }
    // logo == null and no child: a bare brand background (still gets the
    // handoff via the post-frame remove() fallback).
    return const SizedBox.shrink();
  }

  Widget _withBackground(Widget child) {
    final gradient = widget.backgroundGradient;
    if (gradient != null) {
      return DecoratedBox(
        decoration: BoxDecoration(gradient: gradient),
        child: child,
      );
    }
    // Default to a transparent backdrop when no brand color is supplied (the
    // native splash beneath already paints the brand until handoff).
    return ColoredBox(
      color: widget.backgroundColor ?? const Color(0x00000000),
      child: child,
    );
  }
}
