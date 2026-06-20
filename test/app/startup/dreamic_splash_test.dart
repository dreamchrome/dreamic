import 'dart:async';
import 'dart:ui' as ui;

import 'package:dreamic/app/startup/dreamic_splash.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A controllable `ImageProvider` whose decode the test drives manually:
/// [complete] emits a (1×1) `ImageInfo` (first decoded frame), [fail] surfaces
/// a decode error, and leaving it untouched simulates an image that never
/// resolves. Backed by a manually-fed `ImageStreamCompleter`.
class _ControllableImageProvider extends ImageProvider<_ControllableImageProvider> {
  _ControllableImageProvider();

  final _ManualImageStreamCompleter _completer = _ManualImageStreamCompleter();

  /// Emits the first `ImageInfo` (decoded frame) to the resolved stream.
  Future<void> complete() async {
    final image = await _createTestImage();
    _completer.emit(ImageInfo(image: image));
  }

  /// Surfaces a decode error to the resolved stream.
  void fail(Object error) => _completer.fail(error);

  @override
  Future<_ControllableImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<_ControllableImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _ControllableImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return _completer;
  }
}

class _ManualImageStreamCompleter extends ImageStreamCompleter {
  void emit(ImageInfo info) => setImage(info);
  void fail(Object error) => reportError(exception: error);
}

Future<ui.Image> _createTestImage() {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder);
  final picture = recorder.endRecording();
  return picture.toImage(1, 1);
}

void main() {
  group('DreamicSplash — native handoff (ImageProvider decode, Issue 70)', () {
    testWidgets(
        'teardown is deferred until the first ImageInfo decodes',
        (tester) async {
      var removeCalls = 0;
      final provider = _ControllableImageProvider();

      await tester.pumpWidget(
        DreamicSplash(
          logo: provider,
          // Long timeout so the decode listener — not the safety timer — drives
          // the teardown in this case.
          safetyTimeout: const Duration(seconds: 30),
          removeNativeSplash: () => removeCalls++,
        ),
      );
      // Flush the post-frame callback that resolves the ImageStream.
      await tester.pump();

      // Image has not decoded yet → native splash still held.
      expect(removeCalls, 0);

      await provider.complete();
      await tester.pump();

      // First decoded frame → exactly one teardown.
      expect(removeCalls, 1);
    });

    testWidgets(
        'safety timeout fires remove() when the image never resolves',
        (tester) async {
      var removeCalls = 0;
      final provider = _ControllableImageProvider();

      await tester.pumpWidget(
        DreamicSplash(
          logo: provider,
          safetyTimeout: const Duration(seconds: 2),
          removeNativeSplash: () => removeCalls++,
        ),
      );
      await tester.pump();

      // The image never resolves; before the timeout, nothing fired.
      expect(removeCalls, 0);

      // Advance past the safety timeout.
      await tester.pump(const Duration(seconds: 2));
      expect(removeCalls, 1);

      // A late decode after the timeout must NOT double-fire (guard).
      await provider.complete();
      await tester.pump();
      expect(removeCalls, 1);
    });

    testWidgets('a decode error degrades to an immediate single remove()',
        (tester) async {
      var removeCalls = 0;
      final provider = _ControllableImageProvider();

      await tester.pumpWidget(
        DreamicSplash(
          logo: provider,
          safetyTimeout: const Duration(seconds: 30),
          removeNativeSplash: () => removeCalls++,
        ),
      );
      await tester.pump();

      provider.fail(Exception('broken asset'));
      await tester.pump();

      expect(removeCalls, 1);
    });
  });

  group('DreamicSplash — removeNativeSplashWhen hook (Issue 108)', () {
    testWidgets('the hook gates teardown and fires exactly once on completion',
        (tester) async {
      var removeCalls = 0;
      final ready = Completer<void>();

      await tester.pumpWidget(
        DreamicSplash(
          logo: const SizedBox(), // a Widget logo: no ImageStream to await
          removeNativeSplashWhen: ready.future,
          safetyTimeout: const Duration(seconds: 30),
          removeNativeSplash: () => removeCalls++,
        ),
      );
      await tester.pump();

      // Not ready yet → held.
      expect(removeCalls, 0);

      ready.complete();
      await tester.pump();
      expect(removeCalls, 1);
    });

    testWidgets('a throwing hook degrades to a single remove() (error-as-ready)',
        (tester) async {
      var removeCalls = 0;
      final ready = Completer<void>();

      await tester.pumpWidget(
        DreamicSplash(
          logo: const SizedBox(),
          removeNativeSplashWhen: ready.future,
          safetyTimeout: const Duration(seconds: 30),
          removeNativeSplash: () => removeCalls++,
        ),
      );
      await tester.pump();
      expect(removeCalls, 0);

      ready.completeError(Exception('readiness failed'));
      await tester.pump();
      // catch-and-degrade → exactly one teardown.
      expect(removeCalls, 1);
    });

    testWidgets(
        'a never-completing hook still fires remove() via the safety timeout',
        (tester) async {
      var removeCalls = 0;
      // A Future that never completes.
      final ready = Completer<void>();

      await tester.pumpWidget(
        DreamicSplash(
          logo: const SizedBox(),
          removeNativeSplashWhen: ready.future,
          safetyTimeout: const Duration(seconds: 2),
          removeNativeSplash: () => removeCalls++,
        ),
      );
      await tester.pump();
      expect(removeCalls, 0);

      await tester.pump(const Duration(seconds: 2));
      expect(removeCalls, 1);
    });
  });

  group('DreamicSplash — dispose fallback (Issue 74)', () {
    testWidgets(
        'disposing before decode/timeout still invokes remove() exactly once',
        (tester) async {
      var removeCalls = 0;
      final provider = _ControllableImageProvider();

      await tester.pumpWidget(
        DreamicSplash(
          logo: provider,
          // Long timeout so the timer does NOT fire before dispose.
          safetyTimeout: const Duration(seconds: 30),
          removeNativeSplash: () => removeCalls++,
        ),
      );
      await tester.pump();
      expect(removeCalls, 0);

      // Simulate the gate transitioning splash→child early: replace the splash
      // with another widget so DreamicSplash is disposed before the image
      // decodes or the safety timeout fires.
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Text('child'),
        ),
      );

      expect(find.text('child'), findsOneWidget);
      // The dispose-time fallback released the native splash exactly once.
      expect(removeCalls, 1);

      // A late decode after dispose must NOT double-fire.
      await provider.complete();
      await tester.pump();
      expect(removeCalls, 1);
    });
  });

  group('DreamicSplash — rendering', () {
    testWidgets(
        'renders the default centered-logo with no MaterialApp/MediaQuery ancestor',
        (tester) async {
      // Pump directly with no MaterialApp / Directionality / MediaQuery — the
      // splash must self-provide a Directionality and use no MediaQuery (Issue
      // 61/73). Use a Widget logo to avoid an asset-bundle lookup.
      await tester.pumpWidget(
        DreamicSplash(
          logo: const Text('logo'),
          backgroundColor: const Color(0xFF112233),
          safetyTimeout: const Duration(seconds: 30),
          removeNativeSplash: () {},
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('logo'), findsOneWidget);
      // Self-provides a Directionality.
      expect(find.byType(Directionality), findsOneWidget);
    });

    testWidgets('a custom child replaces the default visual', (tester) async {
      await tester.pumpWidget(
        DreamicSplash(
          safetyTimeout: const Duration(seconds: 30),
          removeNativeSplash: () {},
          child: const Text('custom-splash'),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('custom-splash'), findsOneWidget);
    });
  });
}
