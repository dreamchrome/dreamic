import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../utils/logger.dart';

/// A `StatefulWidget` that gates the router (and any other "router-required"
/// content) on a single app-provided `Future<void>`.
///
/// Relocated from `router_arc`'s `AppInitGate` (REQ-009) into dreamic so it is
/// router-agnostic universal startup infrastructure: its [child] is any
/// `*App.router` (`MaterialApp.router` / `CupertinoApp.router` /
/// `WidgetsApp.router`), it takes a single `Future<void>`, deep-link
/// preservation is platform-buffer based, and it is single-shot with no
/// internal retry. It uses no go_router (or any router) symbol internally.
///
/// The widget shows the supplied [splash] while [initFuture] is pending,
/// swaps to the supplied [child] (which the consumer wraps as `*App.router`)
/// when the Future resolves successfully, or swaps to [errorWidget] (or a
/// sensible default) when the Future fails. There is no internal retry — the
/// retry affordance lives in [DreamicAppInitHost] above, which re-mounts the
/// gate via a fresh `Key`.
///
/// **Canonical placement.** Compose under `DreamicAppInitHost` (which owns the
/// gate's `Key` and the bootstrap `Future`):
///
/// ```dart
/// DreamicAppInitHost(
///   initFutureFactory: () => dreamicBootstrap(),
///   splash: const DreamicSplash(),
///   errorBuilder: (ctx, retry) => MyInitError(onRetry: retry),
///   child: MaterialApp.router(routerConfig: routerArc.goRouter),
/// )
/// ```
///
/// **Why wrap, not inject.** The wrap form (with `*App.router` as the gate's
/// [child]) preserves the platform-buffered deep link across initialization.
/// Injecting via `MaterialApp.router(builder:)` is *not* equivalent: the
/// platform's URL/intent buffer is consumed on first router mount, so the
/// router widget itself must be the one that mounts after the init Future
/// resolves — not a child of an already-mounted router.
///
/// **Single-Future API.** The gate accepts one `Future<void>`; consumers
/// compose multiple init tasks via `Future.wait`, `Future.delayed`, or any
/// other Future combinator (here, `dreamicBootstrap()`) before passing the
/// result here.
///
/// **Single-shot lifecycle.** [initFuture] is captured on first `initState`
/// and is *not* swapped when the parent rebuilds the widget with a different
/// Future identity. To re-run initialization (e.g., after a transient error
/// and an explicit retry affordance), the parent rebuilds the gate via a
/// `Key` change. On `Key` change Flutter disposes the old State and constructs
/// a fresh one, capturing the new Future. [DreamicAppInitHost] drives exactly
/// this.
///
/// **No internal timeout.** If [initFuture] hangs, the splash remains until the
/// Future resolves or errors. Apply timeouts inside the consumer's init Future
/// composition (`dreamicBootstrap(bootstrapTimeout: …)`).
///
/// **Above-`MaterialApp` rendering.** The gate renders [splash] and (on error)
/// [errorWidget] *above* the [child]'s `*App.router`, so neither inherits a
/// `Directionality`/`MaterialLocalizations` ancestor — and the debug
/// splash-is-plain guard forbids the `WidgetsApp` that would otherwise supply
/// them. The gate therefore wraps its pending ([splash]) and error
/// ([errorWidget]) branches in a default
/// `Directionality(textDirection: TextDirection.ltr)` (consumer-overridable by
/// nesting their own), so a text-bearing splash or app error widget does not
/// throw "No Directionality widget found". The gate provides **only**
/// `Directionality`, **not** `MediaQuery`, so splash/error widgets must avoid
/// `MediaQuery.of(context)` and any `BlocProvider`-scoped cubit only provided
/// below `*App.router`.
class DreamicAppInitGate extends StatefulWidget {
  /// Wraps [child] with a splash-while-loading and error-on-failure gate
  /// driven by [initFuture].
  const DreamicAppInitGate({
    super.key,
    required this.initFuture,
    required this.splash,
    required this.child,
    this.errorWidget,
    this.onInitError,
    this.minimumSplashDuration = const Duration(milliseconds: 800),
  });

  /// The single `Future<void>` whose resolution gates the [child].
  ///
  /// Captured on first build; identity changes on subsequent rebuilds are
  /// ignored (single-shot lifecycle). Compose multiple async tasks into one
  /// Future before passing it here.
  final Future<void> initFuture;

  /// The widget shown while [initFuture] is pending. A plain widget — **not a
  /// routing app** (`MaterialApp`/`CupertinoApp`/`WidgetsApp`). A routing app
  /// here mounts its own `Navigator`, which consumes the platform initial route
  /// during init and rewrites the URL to `'/'`, stripping deep-link query params
  /// (e.g. a magic-link `oobCode`) before [child] can read them — so this is
  /// debug-asserted. No URL exists during init, so there is no address-bar
  /// reflection on web.
  final Widget splash;

  /// The widget mounted after [initFuture] resolves successfully. The
  /// canonical content here is `*App.router` (e.g., `MaterialApp.router`)
  /// so the platform-buffered deep link is consumed on first mount.
  final Widget child;

  /// The widget shown when [initFuture] errors. When `null`, the gate
  /// renders `ErrorWidget(error)` in debug (Flutter's standard red-screen
  /// affordance — works without a `Material` ancestor) and
  /// `SizedBox.shrink()` in release (blank — surfacing zero internal detail).
  ///
  /// The gate is single-shot — there is no framework-level retry. If a retry
  /// affordance is required, wire it in the consumer's own error widget and
  /// have it trigger a `Key` change to re-mount the gate. [DreamicAppInitHost]
  /// provides this.
  final Widget? errorWidget;

  /// Optional callback fired (once) when [initFuture] errors, after the error
  /// is `loge`'d and before/as the gate transitions to its error branch.
  ///
  /// Lets a parent (e.g. [DreamicAppInitHost]) react to a bootstrap failure —
  /// notably to auto-retry by re-mounting the gate via a `Key` change before
  /// the [errorWidget] is shown. The gate still transitions to its error state
  /// regardless; if the parent re-mounts, that errored State is disposed before
  /// it paints. This is a notification only — it does not suppress [errorWidget].
  final void Function(Object error)? onInitError;

  /// The minimum time the [splash] is held before the success→[child]
  /// transition, defaulting to `const Duration(milliseconds: 800)`.
  ///
  /// The gate holds [splash] until `max(initFuture, minimumSplashDuration)`, so
  /// the minimum adds zero latency to a normal cold start (bootstrap already
  /// exceeds 800ms) — it only smooths the rare fast path and guarantees a
  /// visible Flutter splash for the native handoff. Set to `Duration.zero` to
  /// remove the splash as soon as bootstrap completes.
  ///
  /// **The min-hold gates only the success→[child] transition.** If
  /// [initFuture] errors (a fatal bootstrap task) or its outer timeout fires,
  /// the gate shows [errorWidget] **immediately**, without waiting out the
  /// minimum — errors are never artificially delayed.
  final Duration minimumSplashDuration;

  @override
  State<DreamicAppInitGate> createState() => _DreamicAppInitGateState();
}

enum _InitState { pending, ready, error }

class _DreamicAppInitGateState extends State<DreamicAppInitGate> {
  late final Future<void> _initFuture;
  _InitState _state = _InitState.pending;
  Object? _error;

  /// Whether the init Future has resolved successfully. The success→[child]
  /// transition waits for both this AND [_minimumElapsed].
  bool _initCompleted = false;

  /// Whether [DreamicAppInitGate.minimumSplashDuration] has elapsed.
  bool _minimumElapsed = false;

  /// Cancelable timer backing the min-hold so a transition to error (or an
  /// early dispose) never leaves a pending timer.
  Timer? _minimumTimer;

  @override
  void initState() {
    super.initState();
    _initFuture = widget.initFuture;
    _initFuture.then(
      (_) {
        if (!mounted) return;
        _initCompleted = true;
        _maybePromoteToReady();
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!mounted) return;
        // A handled `.then(onError:)` async error bypasses
        // `FlutterError.onError` / `PlatformDispatcher.onError`, and the host's
        // `errorBuilder` never receives the error object — so without this an
        // init failure (including the 45s bootstrap timeout) is silently
        // swallowed in release. `loge()` both logs AND reports to the error
        // backend (Crashlytics / custom reporter) when attached.
        loge(error, 'DreamicAppInitGate: initialization failed', stackTrace);
        // Notify the parent (e.g. the host's auto-retry) BEFORE transitioning,
        // so it can re-mount this gate via a `Key` change and the errored State
        // is disposed before its error branch ever paints.
        widget.onInitError?.call(error);
        // The min-hold gates only the success→child transition; show the
        // error immediately without waiting out `minimumSplashDuration` — and
        // cancel the pending min-hold timer (its only purpose was the
        // success→child smoothing).
        _minimumTimer?.cancel();
        _minimumTimer = null;
        setState(() {
          _state = _InitState.error;
          _error = error;
        });
      },
    );

    // Hold the splash for at least `minimumSplashDuration` to smooth the rare
    // fast path. A zero (or negative) duration promotes as soon as the init
    // Future completes.
    if (widget.minimumSplashDuration <= Duration.zero) {
      _minimumElapsed = true;
    } else {
      _minimumTimer = Timer(widget.minimumSplashDuration, () {
        _minimumTimer = null;
        if (!mounted) return;
        _minimumElapsed = true;
        _maybePromoteToReady();
      });
    }

    // The splash MUST be a plain widget, not a routing app. The wrapping
    // `assert` is stripped in release (zero cost); in debug it schedules a
    // one-shot subtree check that fails loudly if the splash mounts a router.
    // See [_debugScheduleSplashIsPlainCheck].
    assert(_debugScheduleSplashIsPlainCheck());
  }

  /// Transitions to [_InitState.ready] only once BOTH the init Future has
  /// completed successfully AND the minimum splash duration has elapsed. A
  /// no-op if the gate has already errored.
  void _maybePromoteToReady() {
    if (_state == _InitState.error) return;
    if (_initCompleted && _minimumElapsed && _state != _InitState.ready) {
      setState(() {
        _state = _InitState.ready;
      });
    }
  }

  /// Debug-only guard. A `MaterialApp` / `CupertinoApp` / `WidgetsApp` used as
  /// [DreamicAppInitGate.splash] mounts its own `Navigator`, which — while
  /// [initFuture] is pending — consumes the platform initial route, fails to
  /// match a deep link, and rewrites the URL to `'/'`, stripping deep-link
  /// query parameters (e.g. a magic-link `oobCode`) before
  /// [DreamicAppInitGate.child] (the `*App.router`) can read them. All three
  /// app types build a `WidgetsApp`, so finding one in the splash subtree
  /// catches every case without a `material`/`cupertino` import. (A
  /// `Directionality` is not a `WidgetsApp`, so the default wrap below does not
  /// trip this guard.)
  ///
  /// Returns `true` so it can be wrapped in `assert(...)` (debug-only). The
  /// check runs in a post-frame callback because the splash subtree is not yet
  /// mounted during `initState`; it no-ops if the gate has already swapped past
  /// the pending state (so it never inspects the routing [child]).
  bool _debugScheduleSplashIsPlainCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _state != _InitState.pending) return;
      WidgetsApp? offender;
      void walk(Element el) {
        if (offender != null) return;
        if (el.widget is WidgetsApp) {
          offender = el.widget as WidgetsApp;
          return;
        }
        el.visitChildren(walk);
      }

      context.visitChildElements(walk);
      if (offender != null) {
        throw FlutterError.fromParts(<DiagnosticsNode>[
          ErrorSummary(
            'DreamicAppInitGate.splash must be a plain widget, not a routing app.',
          ),
          ErrorDescription(
            'The splash subtree contains a ${offender.runtimeType}. MaterialApp, '
            'CupertinoApp and WidgetsApp each mount a Navigator; while the init '
            'Future is pending that Navigator consumes the platform initial '
            'route, fails to match a deep link, and rewrites the URL to "/", '
            'stripping deep-link query parameters (for example a magic-link '
            'oobCode) before DreamicAppInitGate.child (the *App.router) can read them.',
          ),
          ErrorHint(
            'Use a plain widget for the splash — e.g. DreamicSplash, or a '
            'Directionality wrapping a themed CircularProgressIndicator — and '
            'keep the *App.router as DreamicAppInitGate.child, the only routing '
            'app in the tree.',
          ),
        ]);
      }
    });
    return true;
  }

  @override
  void didUpdateWidget(covariant DreamicAppInitGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Future identity changes are intentionally ignored (single-shot
    // lifecycle). Consumers re-run init via a `Key` change that replaces this
    // State entirely — DreamicAppInitHost does this on retry.
  }

  @override
  void dispose() {
    _minimumTimer?.cancel();
    _minimumTimer = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _InitState.pending:
        // The pending (splash) branch renders above the child's *App.router,
        // so provide a default Directionality for text-bearing splashes.
        return Directionality(
          textDirection: TextDirection.ltr,
          child: widget.splash,
        );
      case _InitState.ready:
        return widget.child;
      case _InitState.error:
        final custom = widget.errorWidget;
        // The error branch also renders above the child's *App.router; wrap it
        // in a default Directionality. The default error widget (ErrorWidget /
        // SizedBox.shrink) needs no ancestor but is harmlessly wrapped too.
        return Directionality(
          textDirection: TextDirection.ltr,
          child: custom ?? _defaultErrorWidget(_error),
        );
    }
  }
}

Widget _defaultErrorWidget(Object? error) {
  if (kDebugMode) {
    return ErrorWidget(error ?? 'DreamicAppInitGate: initialization Future errored');
  }
  return const SizedBox.shrink();
}
