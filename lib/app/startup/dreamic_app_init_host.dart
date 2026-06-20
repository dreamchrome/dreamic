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

  @override
  void initState() {
    super.initState();
    _initFuture = widget.initFutureFactory();
  }

  void _retry() {
    setState(() {
      _generation++;
      _initFuture = widget.initFutureFactory();
    });
  }

  @override
  Widget build(BuildContext context) {
    final errorBuilder = widget.errorBuilder;
    return DreamicAppInitGate(
      // A fresh Key per generation forces Flutter to dispose the old gate State
      // (and its captured Future) and construct a fresh one on retry.
      key: ValueKey<int>(_generation),
      initFuture: _initFuture,
      splash: widget.splash,
      minimumSplashDuration: widget.minimumSplashDuration,
      // Forward null when no errorBuilder is supplied so the gate falls back to
      // its built-in default error widget (Issue 112).
      errorWidget:
          errorBuilder == null ? null : errorBuilder(context, _retry),
      child: widget.child,
    );
  }
}
