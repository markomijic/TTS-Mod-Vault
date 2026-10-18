/// Downloads the missing asset files of one mod (all of them, one type, or
/// one asset) and brings the store and the library state up to date.
library;

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/app/providers/infrastructure_providers.dart';
import 'package:tts_mod_vault/core/logging/app_log.dart';
import 'package:tts_mod_vault/data/fs/file_ops.dart';
import 'package:tts_mod_vault/data/net/asset_downloader.dart';
import 'package:tts_mod_vault/data/net/dio_client.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/asset_detail/application/mod_assets_provider.dart';
import 'package:tts_mod_vault/features/downloads/application/network_options.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';
import 'package:tts_mod_vault/features/library/application/library_settings.dart';
import 'package:tts_mod_vault/features/operations/application/operation.dart';
import 'package:tts_mod_vault/features/startup/application/directories_controller.dart';

export 'package:tts_mod_vault/data/net/asset_downloader.dart'
    show DownloadBatchResult, DownloadOutcome, DownloadRequest, DownloadStatus;

/// Progress label key for downloads of [type]: `downloading.images`,
/// `downloading.assetbundles`, `downloading.audio`, `downloading.models`,
/// `downloading.pdf`.
String downloadProgressLabel(AssetType type) =>
    'downloading.${type.folderName.toLowerCase()}';

/// Whether the audio assets of [mod] are shown given the global option;
/// mirrors the rule of `modAssetsProvider`, which cannot be reused here
/// because it is an auto-dispose family bound to the library state.
bool includeAudioFor(Mod mod, {required bool ignoreAudioGlobally}) =>
    !mod.audio.hideAudio(ignoreAudioGlobally: ignoreAudioGlobally);

/// Downloads the files of [mod] that are not on disk: every type in
/// `AssetType.values` order like v2, or only [onlyType], or only
/// [onlyAsset]. Audio assets hidden by the mod's visibility and the global
/// option are left alone unless named explicitly through [onlyAsset].
///
/// Each downloaded file is added to `existing_files`, then the library
/// re-summarises every mod sharing those files plus [mod] itself and the
/// asset list provider is invalidated. The result lists every request's
/// outcome; cancellation shows up as cancelled outcomes, not as an error.
final class DownloadAssetsOperation extends Operation<DownloadBatchResult> {
  /// Creates the operation. [ref] supplies the collaborators.
  DownloadAssetsOperation({
    required this.ref,
    required this.mod,
    this.onlyType,
    this.onlyAsset,
  });

  /// Supplies the database, file system, network client and library.
  final Ref ref;

  /// The mod whose files are downloaded.
  final Mod mod;

  /// Restrict to one asset type.
  final AssetType? onlyType;

  /// Restrict to one asset (its type decides the folder).
  final Asset? onlyAsset;

  DownloadBatchResult _partial = DownloadBatchResult.empty;

  @override
  OperationKind get kind => OperationKind.downloadAssets;

  @override
  DownloadBatchResult? cancelledResult() => _partial;

  @override
  Future<DownloadBatchResult> run(OperationContext ctx) async {
    final log = ctx.log;
    final modPath = mod.jsonPath;
    final options = await ref
        .read(networkOptionsProvider.notifier)
        .ensureLoaded();
    final directories = await ref.read(directoriesProvider.future);
    final missing = await _missingAssets();
    ctx.checkCancelled();

    if (missing.isEmpty) {
      log.info(
        LogSource.download,
        'Nothing to download for "${mod.displayName}": every file is '
        'already on disk',
        modPath: modPath,
        operationId: ctx.operationId,
      );
      return DownloadBatchResult.empty;
    }

    log.info(
      LogSource.download,
      'Downloading ${missing.length} missing file(s) for "${mod.displayName}"',
      modPath: modPath,
      operationId: ctx.operationId,
    );

    final downloader = AssetDownloader(
      dio: ref.read(dioProvider),
      fs: ref.read(fileSystemProvider),
      log: log,
    );
    var result = DownloadBatchResult.empty;
    for (final type in AssetType.values) {
      final ofType = [
        for (final asset in missing)
          if (asset.type == type) asset,
      ];
      if (ofType.isEmpty) continue;
      if (ctx.isCancelled) {
        result = result.merge(
          DownloadBatchResult([
            for (final asset in ofType)
              DownloadOutcome(
                url: asset.url,
                type: asset.type,
                status: DownloadStatus.cancelled,
                fileKey: asset.fileKey,
              ),
          ]),
        );
        _partial = result;
        continue;
      }
      final label = downloadProgressLabel(type);
      final targetDir = directories.assetDir(type);
      ctx.report(
        OperationProgress(kind: kind, label: label, total: ofType.length),
      );
      final batch = await downloader.downloadAll(
        requests: [
          for (final asset in ofType)
            DownloadRequest(url: asset.url, type: type, targetDir: targetDir),
        ],
        concurrency: options.concurrentDownloads,
        ignoredDomains: options.ignoredDomains,
        token: ctx.token,
        onProgress: (progress) => ctx.report(
          OperationProgress(
            kind: kind,
            label: label,
            done: progress.done,
            total: progress.total,
            fraction: progress.fraction,
          ),
        ),
        modPath: modPath,
        operationId: ctx.operationId,
      );
      result = result.merge(batch);
      _partial = result;
      await _recordDownloaded(batch);
    }

    await _applyToLibrary(result);
    _logSummary(log, result, ctx.operationId);
    return result;
  }

  /// The assets of [mod] that have no cached file, honouring [onlyType],
  /// [onlyAsset] and the audio visibility rule.
  Future<List<Asset>> _missingAssets() async {
    final only = onlyAsset;
    if (only != null) return only.exists ? const [] : [only];
    final ignoreAudio = ref.read(libraryOptionsProvider).ignoreAudioGlobally;
    final assets = await ref
        .read(appDatabaseProvider)
        .libraryQueries
        .assetsForMod(
          mod.jsonPath,
          includeAudio: includeAudioFor(mod, ignoreAudioGlobally: ignoreAudio),
        );
    final type = onlyType;
    return [
      for (final asset in assets)
        if (!asset.exists && (type == null || asset.type == type)) asset,
    ];
  }

  /// Adds the files of [batch] to the `existing_files` index.
  Future<void> _recordDownloaded(DownloadBatchResult batch) async {
    final dao = ref.read(appDatabaseProvider).existingFilesDao;
    for (final outcome in batch.downloaded) {
      final key = outcome.fileKey;
      final path = outcome.path;
      if (key == null || path == null) continue;
      await dao.upsert(outcome.type, key, path);
    }
  }

  /// Re-summarises the mods sharing the downloaded files and [mod] itself,
  /// then invalidates the asset list of [mod].
  Future<void> _applyToLibrary(DownloadBatchResult result) async {
    if (!ref.mounted) return;
    final library = ref.read(libraryControllerProvider.notifier);
    final keys = {for (final outcome in result.downloaded) ?outcome.fileKey};
    if (keys.isNotEmpty) await library.applyAssetFileChange(keys);
    if (!ref.mounted) return;
    await library.resummarizeMod(mod.jsonPath);
    if (ref.mounted) ref.invalidate(modAssetsProvider(mod.jsonPath));
  }

  void _logSummary(AppLog log, DownloadBatchResult result, String opId) {
    final message =
        'Downloaded ${result.downloadedCount}/${result.total} files for '
        '"${mod.displayName}"'
        '${result.failedCount > 0 ? ', ${result.failedCount} failed' : ''}'
        '${result.skippedCount > 0 ? ', ${result.skippedCount} skipped' : ''}'
        '${result.cancelledCount > 0 ? ', ${result.cancelledCount} cancelled' : ''}';
    if (result.failedCount > 0 || result.cancelledCount > 0) {
      log.warning(
        LogSource.download,
        message,
        modPath: mod.jsonPath,
        operationId: opId,
      );
    } else {
      log.success(
        LogSource.download,
        message,
        modPath: mod.jsonPath,
        operationId: opId,
      );
    }
  }
}
