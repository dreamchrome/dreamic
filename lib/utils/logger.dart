import 'package:flutter/foundation.dart';

import '../app/app_config_base.dart';
import '../error_reporting/error_reporter_interface.dart';

enum LogLevel {
  debugVerbose,
  debug,
  info,
  warn,
  error,
}

/// One breadcrumb captured (already gated + redacted) before the error reporter
/// is attached. Held in [Logger]'s [_earlyBreadcrumbBuffer] and flushed on
/// attach (breadcrumbs-then-errors — ERH-032).
class BufferedBreadcrumb {
  const BufferedBreadcrumb(this.message, this.category, this.data);
  final String message;
  final String? category;
  final Map<String, dynamic>? data;
}

class Logger {
  static Function(String message)? _onLogFunction;
  static ErrorReporter? _customErrorReporter;
  static ErrorReportingConfig? _errorReportingConfig;

  /// Set the error reporting configuration
  /// This is typically called automatically by the error handling initialization
  static void setErrorReportingConfig(ErrorReportingConfig? config) {
    _errorReportingConfig = config;
  }

  /// Set a custom error reporter for logging errors
  /// This is typically called automatically by the error handling initialization
  static void setCustomErrorReporter(ErrorReporter? reporter) {
    _customErrorReporter = reporter;
  }

  static void setLogFunction(Function(String message)? function) {
    _onLogFunction = function;
  }

  /// Maximum number of breadcrumbs held in the early buffer before the reporter
  /// attaches. Mirrors the early-ERROR buffer's cap (drop-oldest) so a pre-attach
  /// breadcrumb burst cannot grow the buffer without bound (ERH-022).
  static const int _earlyBreadcrumbBufferCap = 50;

  /// Bounded, always-present buffer of breadcrumbs emitted (gated + redacted)
  /// BEFORE the reporter attached. Drained on attach (breadcrumbs-then-errors —
  /// ERH-032). The flush itself is wired where the reporter attaches
  /// (`appInitErrorHandling`); the flushed breadcrumbs are NOT re-redacted.
  static final List<BufferedBreadcrumb> _earlyBreadcrumbBuffer = <BufferedBreadcrumb>[];

  /// Buffers an early (pre-attach) breadcrumb with drop-oldest eviction beyond
  /// [_earlyBreadcrumbBufferCap].
  static void _bufferEarlyBreadcrumb(BufferedBreadcrumb crumb) {
    _earlyBreadcrumbBuffer.add(crumb);
    while (_earlyBreadcrumbBuffer.length > _earlyBreadcrumbBufferCap) {
      _earlyBreadcrumbBuffer.removeAt(0);
    }
  }

  /// Snapshots and clears the early-breadcrumb buffer for the attach-time flush
  /// (owned by `appInitErrorHandling` in Phase 3). Clearing on read prevents a
  /// re-flush of the same entries. The caller forwards each to the now-attached
  /// reporter **without** re-redacting (they were redacted at emit time).
  static List<BufferedBreadcrumb> drainEarlyBreadcrumbs() {
    if (_earlyBreadcrumbBuffer.isEmpty) {
      return const <BufferedBreadcrumb>[];
    }
    final snapshot = List<BufferedBreadcrumb>.of(_earlyBreadcrumbBuffer);
    _earlyBreadcrumbBuffer.clear();
    return snapshot;
  }

  /// Test-only: current early-breadcrumb buffer length.
  @visibleForTesting
  static int get earlyBreadcrumbBufferLengthForTest => _earlyBreadcrumbBuffer.length;

  /// Test-only: clear the early-breadcrumb buffer so module-level state does not
  /// leak across test cases.
  @visibleForTesting
  static void resetEarlyBreadcrumbBufferForTest() => _earlyBreadcrumbBuffer.clear();

  static void log(LogLevel level, String message) {
    if (_shouldLog(level)) {
      // Use print() in release mode for web to ensure logs appear in production
      // debugPrint is compiled away in Flutter release builds
      final logMessage = level == LogLevel.debugVerbose ? 'DEBUGVERBOSE: $message' : message;

      if (kReleaseMode && kIsWeb) {
        // ignore: avoid_print
        print(logMessage);
      } else {
        debugPrint(logMessage);
      }
      _onLogFunction?.call(message);
    }
  }

  static void error(Object error, [String? message, StackTrace? stackTrace]) {
    final timestamp = DateTime.now().toIso8601String();

    // Use print() in release mode for web to ensure logs appear in production
    void logOutput(String msg) {
      if (kReleaseMode && kIsWeb) {
        // ignore: avoid_print
        print(msg);
      } else {
        debugPrint(msg);
      }
    }

    if (message != null) {
      logOutput('[$timestamp] MESSAGE: $message');
      _onLogFunction?.call(message);
    }

    logOutput('[$timestamp] ERROR: ${error.toString()}');
    if (stackTrace != null) {
      logOutput('STACKTRACE: ${stackTrace.toString()}');
    }

    _crashReport(error, trace: stackTrace);
  }

  /// Records a breadcrumb — a trail event attached to the next captured error.
  ///
  /// Gated at **emit time** by [AppConfigBase.breadcrumbLevel] (independent of
  /// the console [logLevel] — BEH-3/BEH-4): a breadcrumb whose [level] is below
  /// the threshold is dropped. The breadcrumb's own level comes from the
  /// optional [level] param; **when omitted it defaults to [LogLevel.info]**
  /// (ERH-031). Gating uses [LogLevel] only — never a backend level type; the
  /// `LogLevel`→`SentryLevel` translation is Sentry-side (the reporter), not here
  /// (ERH-026).
  ///
  /// The message + every value in [data] are redacted (fail-closed — ERH-005,
  /// ERH-017, ERH-047) before being forwarded. When **no reporter is attached**
  /// the (gated, redacted) breadcrumb is buffered into the bounded
  /// [_earlyBreadcrumbBuffer] (ERH-022/ERH-032) so the pre-attach trail is not
  /// lost; the flush-on-attach (breadcrumbs-then-errors) is wired where the
  /// reporter attaches.
  ///
  /// Never throws into the caller — breadcrumbs are diagnostic and must not
  /// perturb the code they trace.
  static void breadcrumb(
    String message, {
    String? category,
    Map<String, dynamic>? data,
    LogLevel level = LogLevel.info,
  }) {
    try {
      if (!_shouldBreadcrumb(level)) {
        return;
      }
      final redacted = _redactSensitiveData(message, data);
      final reporter = _customErrorReporter;
      if (reporter != null) {
        reporter.addBreadcrumb(
          redacted.message,
          category: category,
          data: redacted.data,
        );
      } else {
        // No reporter attached yet — buffer so the pre-attach trail survives
        // (flushed on attach, breadcrumbs-then-errors). Already redacted, so the
        // flush must NOT re-redact (ERH-032).
        _bufferEarlyBreadcrumb(BufferedBreadcrumb(
          redacted.message,
          category,
          redacted.data,
        ));
      }
    } catch (_) {
      // Diagnostics must never break the traced code path.
    }
  }

  /// Whether a breadcrumb at [level] meets the [AppConfigBase.breadcrumbLevel]
  /// threshold, evaluated at emit time and independent of the console
  /// [logLevel]. dreamic-public gating uses [LogLevel] ONLY (ERH-026). Wrapped
  /// in a try/catch so an early-boot read (GetIt not ready) defaults to the
  /// `info` threshold rather than throwing.
  static bool _shouldBreadcrumb(LogLevel level) {
    try {
      return level.index >= AppConfigBase.breadcrumbLevel.index;
    } catch (_) {
      // If GetIt isn't initialized (e.g., in tests), gate at the `info` default.
      return level.index >= LogLevel.info.index;
    }
  }

  /// Redacts sensitive data from a breadcrumb's [message] and every value in its
  /// [data] map **before** it is forwarded to any reporter. Backend-agnostic;
  /// runs in dreamic's public [Logger] (ERH-005). The stack is never touched
  /// here (web stack frames are script-load URLs, not request URLs).
  ///
  /// **Fail-closed (ERH-017, ERH-047 / BEH-8):** on ANY redaction error, the
  /// message **and every value** in [data] are replaced with a placeholder
  /// derived from the error's `runtimeType` (e.g. `[redaction-error:
  /// NotAllowedError]`) — **never** `error.toString()`, which could itself embed
  /// a secret. A console-only diagnostic is emitted; nothing unredacted is ever
  /// forwarded.
  static ({String message, Map<String, dynamic>? data}) _redactSensitiveData(
    String message,
    Map<String, dynamic>? data,
  ) {
    try {
      final redactedMessage = _redactString(message);
      Map<String, dynamic>? redactedData;
      if (data != null) {
        redactedData = <String, dynamic>{};
        for (final entry in data.entries) {
          final value = entry.value;
          redactedData[entry.key] =
              value is String ? _redactString(value) : value;
        }
      }
      return (message: redactedMessage, data: redactedData);
    } catch (e) {
      // Fail closed: never forward unredacted. The class name comes from
      // runtimeType (not toString, which could embed a secret — ERH-047).
      final placeholder = '[redaction-error: ${e.runtimeType}]';
      void diag(String msg) {
        if (kReleaseMode && kIsWeb) {
          // ignore: avoid_print
          print(msg);
        } else {
          debugPrint(msg);
        }
      }

      diag('Breadcrumb redaction failed; replacing with placeholder ($placeholder).');
      Map<String, dynamic>? scrubbed;
      if (data != null) {
        scrubbed = <String, dynamic>{
          for (final key in data.keys) key: placeholder,
        };
      }
      return (message: placeholder, data: scrubbed);
    }
  }

  /// Redacts an error before it is forwarded to a reporter from the error
  /// chokepoint (`_recordErrorSafe`, Phase 3). Reuses the central, backend-
  /// agnostic redaction (ERH-005) so error payloads get the same fail-closed
  /// scrubbing as breadcrumbs (BEH-8).
  ///
  /// Applies the v1 pattern set to `error.toString()`. When the redacted string
  /// **differs** from the original (a secret was scrubbed), the redacted STRING
  /// is returned so the secret never reaches the backend. When it is unchanged
  /// the **original error object** is returned untouched — so reporters keep the
  /// rich error type (and the stack, which the caller forwards separately) in the
  /// common no-secret case.
  ///
  /// **Fail-closed (ERH-017, ERH-047 / BEH-8):** on ANY redaction error the
  /// error is replaced with a placeholder derived from the *redaction* error's
  /// `runtimeType` (e.g. `[redaction-error: NotAllowedError]`) — never
  /// `toString()`, which could embed a secret — with a console-only diagnostic;
  /// nothing unredacted is ever forwarded. The stack is preserved by the caller
  /// (it is not passed here). Never throws.
  ///
  /// NOTE: dedup (Phase 3) keys on the ORIGINAL `(error, stackTrace)` identity
  /// **before** this runs, so a fail-closed placeholder can never collapse two
  /// distinct errors into one (ERH-028 / BEH-9).
  static Object redactErrorForReporting(Object error) {
    try {
      final original = error.toString();
      final redacted = _redactString(original);
      // Unchanged → keep the original object (rich type preserved). Changed →
      // forward the redacted string so the secret is scrubbed.
      return identical(redacted, original) || redacted == original ? error : redacted;
    } catch (e) {
      final placeholder = '[redaction-error: ${e.runtimeType}]';
      if (kReleaseMode && kIsWeb) {
        // ignore: avoid_print
        print('Error redaction failed; replacing with placeholder ($placeholder).');
      } else {
        debugPrint('Error redaction failed; replacing with placeholder ($placeholder).');
      }
      return placeholder;
    }
  }

  /// Applies the v1 redaction pattern set to a single string: magic-link
  /// `oobCode`, `Bearer`/bare token values, and emails embedded in URLs.
  static String _redactString(String input) {
    var out = input;
    // oobCode query/path param (magic-link out-of-band code).
    out = out.replaceAll(_oobCodePattern, r'oobCode=[redacted]');
    // Authorization: Bearer <token> / "token": "<token>".
    out = out.replaceAll(_bearerPattern, r'Bearer [redacted]');
    out = out.replaceAll(_tokenKvPattern, r'$1[redacted]');
    // Email embedded in a URL query param (e.g. ?email=a@b.com).
    out = out.replaceAll(_emailInUrlPattern, r'$1[redacted]');
    return out;
  }

  /// Matches `oobCode=<value>` (the value up to a `&`, whitespace, or quote).
  static final RegExp _oobCodePattern =
      RegExp(r'oobCode=[^&\s"' "'" r']+', caseSensitive: false);

  /// Matches `Bearer <token>`.
  static final RegExp _bearerPattern =
      RegExp(r'Bearer\s+[^\s"' "'" r']+', caseSensitive: false);

  /// Matches a `token`/`access_token`/`id_token`-style key-value pair, capturing
  /// the key+separator so it can be preserved while the value is redacted.
  static final RegExp _tokenKvPattern = RegExp(
    r'((?:access_|id_|refresh_)?token["' "'" r']?\s*[:=]\s*["' "'" r']?)[^&\s"' "'" r']+',
    caseSensitive: false,
  );

  /// Matches an email embedded as a URL query param value (`?email=`/`&email=`),
  /// capturing the key+separator so it is preserved.
  static final RegExp _emailInUrlPattern = RegExp(
    r'([?&][^=&\s]*email[^=&\s]*=)[^&\s"' "'" r']+',
    caseSensitive: false,
  );

  static bool _shouldLog(LogLevel messageLevel) {
    try {
      final configLevel = AppConfigBase.logLevel;
      return messageLevel.index >= configLevel.index;
    } catch (_) {
      // If GetIt isn't initialized (e.g., in tests), default to debug level
      return messageLevel.index >= LogLevel.debug.index;
    }
  }

  static void _crashReport(Object error, {StackTrace? trace}) {
    final stackTrace = trace ?? StackTrace.current;
    final config = _errorReportingConfig ?? const ErrorReportingConfig();

    // Check for master kill switch first
    if (AppConfigBase.doDisableErrorReporting) {
      return;
    }

    // Check if blocked by emulator mode (unless force override is set)
    final isBlockedByEmulator =
        AppConfigBase.doUseBackendEmulator && !AppConfigBase.doForceErrorReporting;

    // Determine if we should use error reporting based on configuration
    final shouldUseErrorReporting = !isBlockedByEmulator &&
        (config.enableInDebug || !kDebugMode) &&
        (config.enableOnWeb || !kIsWeb);

    // Report to the single registered reporter, if any. dreamic ships no
    // built-in reporter — the consuming app supplies one (Crashlytics, Sentry,
    // …) via configureErrorReporting(). It follows the same gates: blocked by
    // emulator/kill-switch and respects enableInDebug/enableOnWeb.
    //
    // Redact (fail-closed) before forwarding so EVERY loge()-originated report —
    // a direct loge() call, the early-error-buffer flush, and deferred bootstrap
    // diagnostics, all of which funnel through here — has the same BEH-8
    // scrubbing as the `_recordErrorSafe` chokepoint (ERH-005/017/047 / BEH-8).
    // `redactErrorForReporting` returns the ORIGINAL object untouched when no
    // secret is present, so the common no-secret case keeps the rich error type
    // and the loge regression path is unchanged. `_recordErrorSafe` redacts
    // separately and does NOT route through `_crashReport`, so there is no
    // double-redaction (and redaction is idempotent regardless).
    if (_customErrorReporter != null && shouldUseErrorReporting) {
      _customErrorReporter!.recordError(redactErrorForReporting(error), stackTrace);
    }
  }
}

// Convenience methods
void logv(String message) => Logger.log(LogLevel.debugVerbose, message);
void logd(String message) => Logger.log(LogLevel.debug, message);
void logi(String message) => Logger.log(LogLevel.info, message);
void logw(String message) => Logger.log(LogLevel.warn, message);
void loge(Object error, [String? message, StackTrace? trace]) =>
    Logger.error(error, message, trace);
void logBreadcrumb(
  String message, {
  String? category,
  Map<String, dynamic>? data,
  LogLevel level = LogLevel.info,
}) =>
    Logger.breadcrumb(message, category: category, data: data, level: level);
