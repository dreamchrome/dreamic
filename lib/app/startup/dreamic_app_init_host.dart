import 'dart:async';

import 'package:flutter/widgets.dart';

import 'dreamic_app_init_gate.dart';

/// Signature for [DreamicAppInitHost.errorBuilder]. [retry] re-runs the
/// bootstrap from the top by re-mounting the gate with a fresh `Key` and a
/// fresh `Future`.
typedef DreamicAppInitErrorBuilder = Widget Function(
  BuildContext context,
  VoidCallback retry,
);

/// The canonical startup entry point — a thin `StatefulWidget` that owns the
/// two pieces of retry state [DreamicAppInitGate] deliberately omits: the
/// gate's `Key` and the bootstrap `Future`.
///
/// The host calls [initFutureFactory] **once per generation** — once on the
/// initial mount and once on each retry, never on a plain rebuild — so Firebase
/// init / singleton registration don't re-run when the parent rebuilds. On
/// retry it `setState`s a fresh `Key` **and** a fresh `Future`, re-mounting the
/// gate cleanly, which re-runs the **entire** `dreamicBootstrap()` from the
/// top. The bootstrap must therefore be idempotent for the retry to recover.
///
/// `bootstrapTimeout` is **not** a host parameter — it is owned by
/// `dreamicBootstrap()`, which the app passes inside the [initFutureFactory]
/// closure (`() => dreamicBootstrap(bootstrapTimeout: …)`), co-located inside
/// the init Future it bounds.
///
/// ```dart
/// runApp(DreamicAppInitHost(
///   initFutureFactory: () => dreamicBootstrap(),
///   splash: const DreamicSplash(),
///   errorBuilder: (ctx, retry) => MyInitError(onRetry: retry),
///   child: MaterialApp.router(routerConfig: routerArc.goRouter),
/// ));
/// ```
class DreamicAppInitHost extends StatefulWidget {
  const DreamicAppInitHost({
    super.key,
    required this.initFutureFactory,
    required this.splash,
    required this.child,
    this.errorBuilder,
    this.minimumSplashDuration = const Duration(milliseconds: 800),
    this.autoRetryCount = 1,
    this.autoRetryDelay = const Duration(milliseconds: 800),
  });

  /// Builds the bootstrap `Future` for one generation. Called once on the
  /// initial mount and once per retry — **never** on a plain rebuild.
  ///
  /// Typically `() => dreamicBootstrap(...)`. Any `bootstrapTimeout` is passed
  /// inside this closure, since the timeout composes inside the init Future.
  final Future<void> Function() initFutureFactory;

  /// The widget shown while the bootstrap `Future` is pending. A plain widget —
  /// not a routing app (see [DreamicAppInitGate.splash]).
  final Widget splash;

  /// The widget mounted after the bootstrap `Future` resolves successfully —
  /// the canonical `*App.router` (see [DreamicAppInitGate.child]).
  final Widget child;

  /// Builds the init-error UI, receiving a `retry` callback that re-runs the
  /// bootstrap from the top.
  ///
  /// **Optional.** When omitted, the host forwards `null` to the gate, which
  /// renders its built-in default error widget (`ErrorWidget` in debug,
  /// `SizedBox.shrink()` in release) — so a consumer gets zero-config error
  /// handling and supplies [errorBuilder] only for branded error UI.
  final DreamicAppInitErrorBuilder? errorBuilder;

  /// Forwarded to [DreamicAppInitGate.minimumSplashDuration]. Defaults to
  /// `const Duration(milliseconds: 800)`.
  final Duration minimumSplashDuration;

  /// How many times the bootstrap is silently re-run before the manual
  /// [errorBuilder] screen is shown. Defaults to `1` — a transient cold-start
  /// failure (e.g. a contended IndexedDB lock on web, or a flaky first network
  /// call) typically clears on a second attempt, the same reason a manual Retry
  /// tends to work, so one silent retry self-heals the common case for every
  /// consumer. Set to `0` to restore the no-auto-retry behavior (show the error
  /// screen on the first failure).
  ///
  /// With `autoRetryCount > 0` the host re-mounts the gate automatically (after
  /// [autoRetryDelay]) on failure, keeping the [splash] up the whole time so an
  /// auto-recovered failure is a seamless blip rather than a flashed error
  /// screen. The manual [errorBuilder] shows only once the auto-retry budget is
  /// exhausted. The budget is per host lifetime and is NOT replenished by a
  /// manual retry. (A deterministic — non-transient — failure therefore surfaces
  /// the error screen one bootstrap cycle later than with `0`.)
  final int autoRetryCount;

  /// How long the [splash] is held before each auto-retry re-mount. Defaults to
  /// `const Duration(milliseconds: 800)`. A short delay lets a transient
  /// contended resource (e.g. a locked IndexedDB) settle before the re-run, and
  /// avoids a tight failure loop. Ignored when [autoRetryCount] is `0`.
  final Duration autoRetryDelay;

  @override
  State<DreamicAppInitHost> createState() => _DreamicAppInitHostState();
}

class _DreamicAppInitHostState extends State<DreamicAppInitHost> {
  /// Monotonic generation counter. Backs both the gate's `Key` and the
  /// per-generation `Future`, so a retry re-mounts the gate (disposing the old
  /// State) and re-runs the bootstrap exactly once.
  int _generation = 0;

  /// The bootstrap `Future` for the current generation. Captured once from
  /// [DreamicAppInitHost.initFutureFactory] per generation, NOT re-invoked on a
  /// plain rebuild.
  late Future<void> _initFuture;

  /// Remaining silent re-runs before the manual error screen is shown. Seeded
  /// from [DreamicAppInitHost.autoRetryCount]; decremented per auto-retry.
  late int _autoRetriesRemaining;

  /// True between a failure that triggered an auto-retry and the scheduled
  /// re-mount. While set, [build] shows the [splash] directly (no gate) so the
  /// transient failure never flashes the error screen.
  bool _autoRetrying = false;

  /// Backs the [autoRetryDelay] hold; canceled on dispose / manual retry.
  Timer? _autoRetryTimer;

  @override
  void initState() {
    super.initState();
    _autoRetriesRemaining = widget.autoRetryCount;
    _initFuture = widget.initFutureFactory();
  }

  @override
  void dispose() {
    _autoRetryTimer?.cancel();
    _autoRetryTimer = null;
    super.dispose();
  }

  void _retry() {
    // A manual retry cancels any pending auto-retry and re-mounts immediately.
    _autoRetryTimer?.cancel();
    _autoRetryTimer = null;
    setState(() {
      _autoRetrying = false;
      _generation++;
      _initFuture = widget.initFutureFactory();
    });
  }

  /// The gate's `onInitError` hook. If auto-retry budget remains, consume one,
  /// hold the splash for [DreamicAppInitHost.autoRetryDelay], then re-mount the
  /// gate (a fresh generation re-runs the idempotent bootstrap). Otherwise this
  /// is a no-op and the gate shows its error branch as usual.
  void _handleGateError(Object error) {
    if (!mounted) return;
    if (_autoRetriesRemaining <= 0 || _autoRetrying) return;
    _autoRetriesRemaining--;
    setState(() {
      // Bridge to the re-mount with the splash so the error screen is never
      // shown for an auto-recovered failure.
      _autoRetrying = true;
    });
    _autoRetryTimer?.cancel();
    _autoRetryTimer = Timer(widget.autoRetryDelay, () {
      _autoRetryTimer = null;
      if (!mounted) return;
      _retry();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_autoRetrying) {
      // Keep the SAME splash up between the failed generation and the auto-retry
      // re-mount. Wrapped in a default Directionality to match the gate's
      // pending branch (the splash may bear text and renders above *App.router).
      return Directionality(
        textDirection: TextDirection.ltr,
        child: widget.splash,
      );
    }
    final errorBuilder = widget.errorBuilder;
    return DreamicAppInitGate(
      // A fresh Key per generation forces Flutter to dispose the old gate State
      // (and its captured Future) and construct a fresh one on retry.
      key: ValueKey<int>(_generation),
      initFuture: _initFuture,
      splash: widget.splash,
      minimumSplashDuration: widget.minimumSplashDuration,
      onInitError: _handleGateError,
      // Forward null when no errorBuilder is supplied so the gate falls back to
      // its built-in default error widget (Issue 112).
      errorWidget:
          errorBuilder == null ? null : errorBuilder(context, _retry),
      child: widget.child,
    );
  }
}
