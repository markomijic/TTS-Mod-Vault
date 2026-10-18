/// Facade the UI calls for downloads and URL checks: builds the operation
/// and hands it to the [OperationRunner].
library;

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/downloads/application/check_urls_operation.dart';
import 'package:tts_mod_vault/features/downloads/application/download_assets_operation.dart';
import 'package:tts_mod_vault/features/operations/application/operation_runner.dart';

export 'package:tts_mod_vault/features/downloads/application/check_urls_operation.dart'
    show UrlCheckResult, checkUrlsProgressLabel;
export 'package:tts_mod_vault/features/downloads/application/download_assets_operation.dart'
    show
        DownloadBatchResult,
        DownloadOutcome,
        DownloadStatus,
        downloadProgressLabel;

/// The downloads facade.
final downloadsServiceProvider = Provider<DownloadsService>(
  DownloadsService.new,
);

/// Starts download and URL-check operations on the runner. Each method
/// throws [StateError] when another operation is already running (the UI
/// disables the actions while `anyOperationRunningProvider` is true).
/// Cancellation comes back inside the result models, never as an error.
/// Not `final`, so widget tests can substitute a fake.
class DownloadsService {
  /// Creates the service on [ref].
  DownloadsService(this.ref);

  /// Supplies the runner and the operations' collaborators.
  final Ref ref;

  OperationRunner get _runner => ref.read(operationRunnerProvider.notifier);

  /// Downloads every missing file of [mod].
  Future<DownloadBatchResult> downloadMod(Mod mod) =>
      _runner.run(DownloadAssetsOperation(ref: ref, mod: mod));

  /// Downloads the missing files of [type] of [mod].
  Future<DownloadBatchResult> downloadType(Mod mod, AssetType type) =>
      _runner.run(DownloadAssetsOperation(ref: ref, mod: mod, onlyType: type));

  /// Downloads one missing [asset] of [mod].
  Future<DownloadBatchResult> downloadAsset(Mod mod, Asset asset) => _runner
      .run(DownloadAssetsOperation(ref: ref, mod: mod, onlyAsset: asset));

  /// Checks every asset URL of [mod] and stores the dead ones.
  Future<UrlCheckResult> checkUrls(Mod mod) =>
      _runner.run(CheckUrlsOperation(ref: ref, mod: mod));

  /// Checks one [asset] URL of [mod] and updates its entry in the stored
  /// invalid list.
  Future<UrlCheckResult> checkUrl(Mod mod, Asset asset) =>
      _runner.run(CheckUrlsOperation(ref: ref, mod: mod, onlyAsset: asset));

  /// Requests cancellation of the running operation.
  void cancel() => _runner.cancel();
}
