import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guard test: no direct `FirebaseFirestore.instance` may be used under `lib/**`
/// outside the allowlisted `app_config_base.dart` (the one file that
/// legitimately holds the `FirebaseFirestore.instanceFor(...)` calls the
/// `AppConfigBase.firestore` getter is built from). Acquire Firestore via
/// `AppConfigBase.firestore` so apps configured to use a non-default Firestore
/// database resolve correctly.
///
/// Run via `flutter test`.
void main() {
  group('Firestore accessor guard (no direct FirebaseFirestore.instance)', () {
    // The single allowlisted file: it holds the FirebaseFirestore.instanceFor
    // calls the AppConfigBase.firestore getter is built from.
    const allowlistedFile = 'app_config_base.dart';

    // The do-not-edit marker emitted by json_serializable / freezed. We skip
    // generated files so the guard isn't hostage to generator output we can't
    // hand-fix. The real header is `// GENERATED CODE - DO NOT MODIFY BY HAND`.
    const generatedMarker = 'GENERATED CODE - DO NOT MODIFY';

    // Word boundary so the ALLOWED `FirebaseFirestore.instanceFor(...)` form
    // (the named-database accessor the getter itself uses) is NOT flagged — only
    // a bare `FirebaseFirestore.instance` (end of token) matches.
    final bannedPattern = RegExp(r'FirebaseFirestore\.instance\b');

    /// Strips Dart comments (`//` and `///` line comments, `/* ... */` block
    /// comments) from [source] while PRESERVING newlines, so reported line
    /// numbers stay accurate and inert commented references (e.g. the
    /// `// FirebaseFirestore.instance.settings` in `app_firebase_init.dart`) do
    /// not false-positive. String literals are left intact; the banned form
    /// does not appear inside string literals in this package, and stripping
    /// strings would needlessly complicate the scanner.
    String stripComments(String source) {
      final out = StringBuffer();
      var i = 0;
      final n = source.length;
      while (i < n) {
        final ch = source[i];
        final next = i + 1 < n ? source[i + 1] : '';

        // Line comment (covers both `//` and `///`): drop through end of line,
        // but keep the newline itself so line numbers are preserved.
        if (ch == '/' && next == '/') {
          while (i < n && source[i] != '\n') {
            i++;
          }
          continue;
        }

        // Block comment `/* ... */`: replace with whitespace, preserving any
        // newlines inside so line numbers stay accurate.
        if (ch == '/' && next == '*') {
          i += 2;
          while (i < n && !(source[i] == '*' && i + 1 < n && source[i + 1] == '/')) {
            if (source[i] == '\n') {
              out.write('\n');
            }
            i++;
          }
          i += 2; // skip the closing `*/`
          continue;
        }

        out.write(ch);
        i++;
      }
      return out.toString();
    }

    /// Resolves the package `lib/` directory robustly, anchored to the package
    /// root rather than an assumed cwd (a mis-resolved root would scan zero files
    /// and pass vacuously). Walks up from the current directory until a directory
    /// containing both `pubspec.yaml` and `lib/` is found.
    Directory resolveLibDir() {
      var dir = Directory.current.absolute;
      while (true) {
        final pubspec = File('${dir.path}/pubspec.yaml');
        final lib = Directory('${dir.path}/lib');
        if (pubspec.existsSync() && lib.existsSync()) {
          return lib;
        }
        final parent = dir.parent;
        if (parent.path == dir.path) {
          fail(
            'Could not locate the package root (a directory containing both '
            'pubspec.yaml and lib/) walking up from ${Directory.current.path}.',
          );
        }
        dir = parent;
      }
    }

    test('no lib/**/*.dart acquires Firestore via a direct FirebaseFirestore.instance', () {
      final libDir = resolveLibDir();
      final offenders = <String>[];
      var scannedCount = 0;

      for (final entity in libDir.listSync(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        if (!entity.path.endsWith('.dart')) continue;

        final fileName = entity.uri.pathSegments.last;
        if (fileName == allowlistedFile) continue;

        final source = entity.readAsStringSync();

        // Skip generator output we cannot hand-fix.
        if (source.contains(generatedMarker)) continue;

        scannedCount++;

        final stripped = stripComments(source);
        final lines = stripped.split('\n');
        for (var lineNo = 0; lineNo < lines.length; lineNo++) {
          if (bannedPattern.hasMatch(lines[lineNo])) {
            // Report the path relative to lib/ for a stable, readable message.
            final rel = entity.path.substring(libDir.path.length + 1);
            offenders.add('lib/$rel:${lineNo + 1}');
          }
        }
      }

      // Vacuous-pass guard: a mis-resolved root would scan zero files and pass
      // while protecting nothing.
      expect(
        scannedCount,
        greaterThan(0),
        reason: 'Guard scanned zero .dart files under ${libDir.path} — the scan '
            'root is mis-resolved and the guard would pass vacuously.',
      );

      expect(
        offenders,
        isEmpty,
        reason: 'Direct FirebaseFirestore.instance found outside '
            '$allowlistedFile — acquire Firestore via AppConfigBase.firestore '
            'instead:\n${offenders.join('\n')}',
      );
    });
  });
}
