import 'package:dreamic/app/app_cubit.dart';
import 'package:dreamic/versioning/app_version_update_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Version-gating consolidation tests (Phase 5 — Issues 80/88/91/114).
///
/// These exercise the Phase-5 status-machine logic directly via [AppCubit]'s
/// `@visibleForTesting` seams ([AppCubit.handleVersionUpdateForTest],
/// [AppCubit.emitStartupStatusForTest]):
///
///  - the sticky-`updateRequired` guarded setter (`_emitStartupStatus`) refusing
///    every startup downgrade (`normal` / `networkError` / `error`) once a
///    too-old version has set `updateRequired` (Issues 88/91);
///  - the version-now-valid sticky-guard-exempt exit in `_handleVersionUpdate`'s
///    `VersionUpdateType.none` branch (Issue 114).
///
/// DEVIATION (documented in the tasklist): the *full* `getInitialData()`
/// cold-start regression — driving a below-required version through the real
/// [AppVersionUpdateService] to `AppStatus.updateRequired` — is NOT unit-tested
/// here. The real service resolves the platform version via `Platform.isIOS` /
/// `Platform.isAndroid` (both false on the macOS test VM → the "Unknown
/// platform" `0.0.0` branch, which can never be too-old) and reads
/// `getPackageInfo()` (a platform channel) + Firebase Remote Config, so a too-old
/// state is not reproducible on the VM runner — the same platform-mock
/// constraint Phases 3/4 documented for `dreamicBootstrap` /
/// `DreamicServices.initialize`. The subscribe-before-`initialize()` reorder
/// (Issue 80) is structurally fixed in `_initializeVersionUpdateService` and the
/// sticky guard it depends on is what these tests cover; the end-to-end
/// too-old-at-cold-start behavior is verified by later-phase consumer/device
/// verification.

VersionUpdateInfo _info(
  VersionUpdateType type, {
  String current = '1.0.0',
  String required = '2.0.0',
  String recommended = '2.0.0',
}) =>
    VersionUpdateInfo(
      updateType: type,
      currentVersion: current,
      requiredVersion: required,
      recommendedVersion: recommended,
      appStoreUrl: 'https://example.com',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppCubit cubit;

  setUp(() {
    // networkRequired:false keeps the real network check / version service out
    // of these unit tests; we drive status transitions through the seams.
    cubit = AppCubit(networkRequired: false);
  });

  tearDown(() async {
    await cubit.close();
  });

  group('version-update handler branches', () {
    test('a required update sets AppStatus.updateRequired', () {
      cubit.handleVersionUpdateForTest(_info(VersionUpdateType.required));

      expect(cubit.state.appStatus, AppStatus.updateRequired);
      expect(cubit.state.showVersionUpdateBanner, isFalse);
      expect(cubit.state.versionUpdateInfo?.updateType,
          VersionUpdateType.required);
    });

    test('a recommended update sets the banner (separate field, not appStatus)',
        () {
      cubit.handleVersionUpdateForTest(_info(VersionUpdateType.recommended));

      // The banner is a separate field; appStatus stays normal.
      expect(cubit.state.showVersionUpdateBanner, isTrue);
      expect(cubit.state.appStatus, AppStatus.normal);
      expect(cubit.state.versionUpdateInfo?.updateType,
          VersionUpdateType.recommended);
    });

    test('a none update when not blocked leaves appStatus normal', () {
      cubit.handleVersionUpdateForTest(_info(VersionUpdateType.none));

      expect(cubit.state.appStatus, AppStatus.normal);
      expect(cubit.state.showVersionUpdateBanner, isFalse);
    });
  });

  group('sticky updateRequired guard (Issues 88/91)', () {
    setUp(() {
      // Model the cold-start sequence: the version microtask sets updateRequired
      // first, before any startup downgrade runs.
      cubit.handleVersionUpdateForTest(_info(VersionUpdateType.required));
      expect(cubit.state.appStatus, AppStatus.updateRequired);
    });

    test('_finalizeAppStartup normal does NOT downgrade updateRequired (Issue 88)',
        () {
      cubit.emitStartupStatusForTest(cubit.state.copyWith(
        appStatus: AppStatus.normal,
        showNetworkRetry: false,
        networkErrorMessage: '',
      ));

      expect(cubit.state.appStatus, AppStatus.updateRequired);
    });

    test(
        'offline + too-old: networkError (no-network else-branch) does NOT '
        'downgrade — too-old wins over offline (Issue 89)', () {
      cubit.emitStartupStatusForTest(cubit.state.copyWith(
        appStatus: AppStatus.networkError,
        networkStatus: NetworkStatus.none,
        networkErrorMessage: 'Unable to connect to the server.',
        showNetworkRetry: true,
      ));

      expect(cubit.state.appStatus, AppStatus.updateRequired);
    });

    test(
        'offline + too-old: networkError (network-init-exception catch-branch) '
        'does NOT downgrade (Issue 91, load-bearing)', () {
      // The catch-branch sibling of the else-branch above — same downgrade
      // shape, routed through the same guarded setter.
      cubit.emitStartupStatusForTest(cubit.state.copyWith(
        appStatus: AppStatus.networkError,
        networkStatus: NetworkStatus.none,
        networkErrorMessage: 'Network initialization failed. Please try again.',
        showNetworkRetry: true,
      ));

      expect(cubit.state.appStatus, AppStatus.updateRequired);
    });

    test('defensive: an error emit does NOT downgrade updateRequired', () {
      cubit.emitStartupStatusForTest(cubit.state.copyWith(
        appStatus: AppStatus.error,
        networkErrorMessage: 'Failed to initialize app',
      ));

      expect(cubit.state.appStatus, AppStatus.updateRequired);
    });

    test('the guard only blocks downgrades — a fresh updateRequired re-emit passes',
        () {
      cubit.emitStartupStatusForTest(cubit.state.copyWith(
        appStatus: AppStatus.updateRequired,
      ));

      expect(cubit.state.appStatus, AppStatus.updateRequired);
    });
  });

  group('guard is inert when not blocked', () {
    test('startup status emits flow normally when not in updateRequired', () {
      // No required event delivered; status starts normal.
      cubit.emitStartupStatusForTest(cubit.state.copyWith(
        appStatus: AppStatus.networkError,
        showNetworkRetry: true,
      ));
      expect(cubit.state.appStatus, AppStatus.networkError);

      cubit.emitStartupStatusForTest(cubit.state.copyWith(
        appStatus: AppStatus.normal,
      ));
      expect(cubit.state.appStatus, AppStatus.normal);
    });
  });

  group('version-now-valid recovery exit (Issue 114)', () {
    test(
        'from updateRequired, a none event transitions updateRequired → normal '
        'in-session', () {
      cubit.handleVersionUpdateForTest(_info(VersionUpdateType.required));
      expect(cubit.state.appStatus, AppStatus.updateRequired);

      // Mid-session RC change lowers the minimum → VersionUpdateType.none.
      cubit.handleVersionUpdateForTest(_info(VersionUpdateType.none));

      expect(cubit.state.appStatus, AppStatus.normal);
      expect(cubit.state.showVersionUpdateBanner, isFalse);
    });

    test('a none event does NOT downgrade a networkError status', () {
      // Not blocked: a no-network startup leaves networkError. A subsequent
      // none version event must not clobber it (the exit is conditional on
      // currently being updateRequired).
      cubit.emitStartupStatusForTest(cubit.state.copyWith(
        appStatus: AppStatus.networkError,
        showNetworkRetry: true,
      ));
      expect(cubit.state.appStatus, AppStatus.networkError);

      cubit.handleVersionUpdateForTest(_info(VersionUpdateType.none));

      expect(cubit.state.appStatus, AppStatus.networkError);
    });

    test('a none event does NOT change a normal status', () {
      expect(cubit.state.appStatus, AppStatus.normal);

      cubit.handleVersionUpdateForTest(_info(VersionUpdateType.none));

      expect(cubit.state.appStatus, AppStatus.normal);
    });
  });
}
