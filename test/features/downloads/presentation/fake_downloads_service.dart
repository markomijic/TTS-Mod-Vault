// A `DownloadsService` double: records every call and answers with
// configurable results, without touching the runner or the network.

// Test doubles expose recorded calls on purpose.
// ignore_for_file: avoid_public_notifier_properties

import 'package:hooks_riverpod/misc.dart' show Override;
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/downloads/application/downloads_providers.dart';

/// Records calls and returns [downloadResult] / [urlCheckResult]. Set
/// [alreadyRunning] to make every call throw the runner's [StateError].
final class FakeDownloadsService extends DownloadsService {
  FakeDownloadsService(super.ref);

  /// Mods passed to `downloadMod`.
  final List<Mod> downloadModCalls = [];

  /// `(mod, type)` pairs passed to `downloadType`.
  final List<(Mod, AssetType)> downloadTypeCalls = [];

  /// `(mod, asset)` pairs passed to `downloadAsset`.
  final List<(Mod, Asset)> downloadAssetCalls = [];

  /// Mods passed to `checkUrls`.
  final List<Mod> checkUrlsCalls = [];

  /// `(mod, asset)` pairs passed to `checkUrl`.
  final List<(Mod, Asset)> checkUrlCalls = [];

  /// Mods passed to `validateDownload`.
  final List<Mod> validateCalls = [];

  /// Unreachable hosts and dead URLs every `validateDownload` reports.
  List<String> validationUnreachable = const [];

  /// Dead URLs every `validateDownload` reports.
  List<String> validationInvalid = const [];

  /// Result of every download call.
  DownloadBatchResult downloadResult = oneDownloaded;

  /// Result of every URL check.
  UrlCheckResult urlCheckResult = const UrlCheckResult(
    invalidUrls: [],
    cancelled: false,
    checked: 3,
    total: 3,
  );

  /// Whether the single-URL check answers "live" (the result then has no
  /// invalid URL) or "dead" (the result lists the checked URL).
  bool singleUrlLive = false;

  /// Whether calls throw as the runner does while something runs.
  bool alreadyRunning = false;

  /// One downloaded image.
  static final DownloadBatchResult oneDownloaded = DownloadBatchResult(const [
    DownloadOutcome(
      url: 'https://example.com/images/img2.png',
      type: AssetType.image,
      status: DownloadStatus.downloaded,
      path: 'img2.png',
    ),
  ]);

  void _guard() {
    if (alreadyRunning) throw StateError('An operation is already running');
  }

  @override
  Future<DownloadBatchResult> downloadMod(Mod mod) async {
    _guard();
    downloadModCalls.add(mod);
    return downloadResult;
  }

  @override
  Future<DownloadBatchResult> downloadType(Mod mod, AssetType type) async {
    _guard();
    downloadTypeCalls.add((mod, type));
    return downloadResult;
  }

  @override
  Future<DownloadBatchResult> downloadAsset(Mod mod, Asset asset) async {
    _guard();
    downloadAssetCalls.add((mod, asset));
    return downloadResult;
  }

  @override
  Future<DownloadValidationResult> validateDownload(Mod mod) async {
    _guard();
    validateCalls.add(mod);
    return DownloadValidationResult(
      mod: mod,
      unreachableDomains: validationUnreachable,
      invalidUrls: validationInvalid,
    );
  }

  @override
  Future<UrlCheckResult> checkUrls(Mod mod) async {
    _guard();
    checkUrlsCalls.add(mod);
    return urlCheckResult;
  }

  @override
  Future<UrlCheckResult> checkUrl(Mod mod, Asset asset) async {
    _guard();
    checkUrlCalls.add((mod, asset));
    return UrlCheckResult(
      invalidUrls: singleUrlLive ? const [] : [asset.url],
      cancelled: false,
      checked: 1,
      total: 1,
    );
  }
}

/// Overrides `downloadsServiceProvider` with a [FakeDownloadsService]; read the
/// provider from the container and cast to reach the recorded calls.
Override fakeDownloadsServiceOverride() =>
    downloadsServiceProvider.overrideWith(FakeDownloadsService.new);
