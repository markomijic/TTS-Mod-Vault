/// Workshop operations: download mods by id and update mods to the version
/// on Steam. Port of v2 `downloadModsByIds`, `downloadModUpdates` and
/// `_downloadSingleMod` with typed results.
library;

import 'package:dio/dio.dart' show DioException;
import 'package:file/file.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/core/cancellation/cancellation_token.dart';
import 'package:tts_mod_vault/core/logging/app_log.dart';
import 'package:tts_mod_vault/data/fs/file_ops.dart';
import 'package:tts_mod_vault/data/net/dio_client.dart';
import 'package:tts_mod_vault/data/net/preview_image.dart';
import 'package:tts_mod_vault/data/net/steam_workshop_client.dart';
import 'package:tts_mod_vault/data/net/workshop_json_converter.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';
import 'package:tts_mod_vault/features/operations/application/operation_runner.dart';
import 'package:tts_mod_vault/features/workshop/application/workshop_results.dart';

export 'package:tts_mod_vault/features/workshop/application/workshop_results.dart';

/// Progress label key while downloading Workshop items by id.
const String workshopDownloadProgressLabel = 'workshop.downloading';

/// Progress label key while updating Workshop mods.
const String workshopUpdateProgressLabel = 'workshop.updating';

/// Progress label key while asking Steam for item details.
const String workshopDetailsProgressLabel = 'workshop.fetchingDetails';

/// Seconds Steam's `time_updated` must exceed the mod's `EpochTime` by
/// before the mod counts as outdated: the two stamps of one upload are
/// routinely a few seconds apart.
const int workshopUpdateToleranceSeconds = 60;

/// The Steam Web API client used by the Workshop operations; overridable in
/// tests to point at a local server.
final steamWorkshopClientProvider = Provider<SteamWorkshopClient>(
  (ref) => SteamWorkshopClient(dio: ref.watch(dioProvider)),
);

/// The Workshop facade.
final workshopServiceProvider = Provider<WorkshopService>(WorkshopService.new);

/// Starts Workshop operations on the runner. Each method throws
/// [StateError] when another operation is already running. Not `final`, so
/// widget tests can substitute a fake.
class WorkshopService {
  /// Creates the service on [ref].
  WorkshopService(this.ref);

  /// Supplies the runner and the operations' collaborators.
  final Ref ref;

  OperationRunner get _runner => ref.read(operationRunnerProvider.notifier);

  /// Downloads the Workshop items [ids] into [targetDir].
  Future<WorkshopDownloadBatchResult> downloadByIds(
    List<String> ids, {
    required String targetDir,
  }) => _runner.run(
    DownloadWorkshopModsOperation(ref: ref, ids: ids, targetDir: targetDir),
  );

  /// Updates [mods] to the version on Steam; with [force] even when Steam
  /// is not newer.
  Future<WorkshopUpdateBatchResult> updateMods(
    List<Mod> mods, {
    bool force = false,
  }) => _runner.run(
    UpdateWorkshopModsOperation(ref: ref, mods: mods, force: force),
  );

  /// Requests cancellation of the running operation.
  void cancel() => _runner.cancel();
}

/// Downloads Workshop items by id: details lookup (one batched call),
/// app-id check, BSON download, conversion to JSON, write to
/// `<targetDir>/<id>.json` (creation time preserved), preview image to
/// `<id>.png` (best effort), then `LibraryController.refreshMod`.
final class DownloadWorkshopModsOperation
    extends Operation<WorkshopDownloadBatchResult> {
  /// Creates the operation.
  DownloadWorkshopModsOperation({
    required this.ref,
    required this.ids,
    required this.targetDir,
  });

  /// Supplies the client, file system and library.
  final Ref ref;

  /// Workshop ids (blank entries are ignored).
  final List<String> ids;

  /// Folder the JSONs are written to.
  final String targetDir;

  final List<WorkshopDownloadResult> _results = [];
  List<String> _cleanIds = const [];

  @override
  OperationKind get kind => OperationKind.downloadWorkshop;

  @override
  WorkshopDownloadBatchResult? cancelledResult() =>
      WorkshopDownloadBatchResult([
        ..._results,
        for (final id in _cleanIds.skip(_results.length))
          WorkshopDownloadResult(
            id: id,
            status: WorkshopItemStatus.ok,
            cancelled: true,
          ),
      ]);

  @override
  Future<WorkshopDownloadBatchResult> run(OperationContext ctx) async {
    final log = ctx.log;
    _cleanIds = [
      for (final id in ids)
        if (id.trim().isNotEmpty) id.trim(),
    ];
    if (_cleanIds.isEmpty) {
      log.warning(
        LogSource.workshop,
        'No Workshop ids given',
        operationId: ctx.operationId,
      );
      return WorkshopDownloadBatchResult(const []);
    }
    final worker = _WorkshopItemDownloader(ref, ctx);
    final total = _cleanIds.length;
    log.info(
      LogSource.workshop,
      'Downloading $total Workshop item(s) to $targetDir',
      operationId: ctx.operationId,
    );
    ctx.report(
      OperationProgress(
        kind: kind,
        label: workshopDetailsProgressLabel,
        total: total,
      ),
    );

    final details = await worker.detailsFor(_cleanIds);
    for (var i = 0; i < total; i++) {
      final id = _cleanIds[i];
      if (ctx.isCancelled) {
        _results.add(
          WorkshopDownloadResult(
            id: id,
            status: WorkshopItemStatus.ok,
            cancelled: true,
          ),
        );
        continue;
      }
      void progress(double stage) => ctx.report(
        OperationProgress(
          kind: kind,
          label: workshopDownloadProgressLabel,
          done: i,
          total: total,
          fraction: (i + stage) / total,
          detail: details[id]?.title ?? id,
        ),
      );
      progress(0);
      final result = await worker.downloadItem(
        id: id,
        details: details[id],
        targetDir: targetDir,
        onStage: progress,
      );
      _results.add(result);
      ctx.report(
        OperationProgress(
          kind: kind,
          label: workshopDownloadProgressLabel,
          done: i + 1,
          total: total,
          fraction: (i + 1) / total,
        ),
      );
    }

    final batch = WorkshopDownloadBatchResult(_results);
    final message =
        'Downloaded ${batch.successCount}/${batch.total} Workshop item(s)'
        '${batch.failedCount > 0 ? ', ${batch.failedCount} failed' : ''}'
        '${batch.cancelledCount > 0 ? ', ${batch.cancelledCount} cancelled' : ''}';
    if (batch.failedCount > 0 || batch.wasCancelled) {
      log.warning(
        LogSource.workshop,
        message,
        details: [for (final r in batch.failed) '[${r.id}] ${_describe(r)}']
            .join('\n'),
        operationId: ctx.operationId,
      );
    } else {
      log.success(LogSource.workshop, message, operationId: ctx.operationId);
    }
    return batch;
  }

  static String _describe(WorkshopDownloadResult result) =>
      result.error ?? result.status.name;
}

/// Re-downloads [mods] whose Steam `time_updated` is newer than their
/// `EpochTime` by more than [workshopUpdateToleranceSeconds] (every mod
/// with [force]). Each updated JSON replaces the mod's file in place and
/// the mod is refreshed in the library.
final class UpdateWorkshopModsOperation
    extends Operation<WorkshopUpdateBatchResult> {
  /// Creates the operation.
  UpdateWorkshopModsOperation({
    required this.ref,
    required this.mods,
    this.force = false,
  });

  /// Supplies the client, file system and library.
  final Ref ref;

  /// The mods to update (Workshop mods; the id is the JSON's basename).
  final List<Mod> mods;

  /// Update even when Steam's version is not newer.
  final bool force;

  final List<WorkshopUpdateResult> _results = [];

  @override
  OperationKind get kind => OperationKind.updateWorkshop;

  @override
  WorkshopUpdateBatchResult? cancelledResult() => WorkshopUpdateBatchResult([
    ..._results,
    for (final mod in mods.skip(_results.length))
      WorkshopUpdateResult(
        id: mod.id,
        modName: mod.displayName,
        jsonPath: mod.jsonPath,
        status: WorkshopUpdateStatus.cancelled,
      ),
  ]);

  @override
  Future<WorkshopUpdateBatchResult> run(OperationContext ctx) async {
    final log = ctx.log;
    if (mods.isEmpty) return WorkshopUpdateBatchResult(const []);
    final worker = _WorkshopItemDownloader(ref, ctx);
    final total = mods.length;
    log.info(
      LogSource.workshop,
      'Checking $total Workshop mod(s) for updates${force ? ' (forced)' : ''}',
      operationId: ctx.operationId,
    );
    ctx.report(
      OperationProgress(
        kind: kind,
        label: workshopDetailsProgressLabel,
        total: total,
      ),
    );

    final details = await worker.detailsFor([for (final m in mods) m.id]);
    for (var i = 0; i < total; i++) {
      final mod = mods[i];
      WorkshopUpdateResult result;
      if (ctx.isCancelled) {
        result = _result(mod, WorkshopUpdateStatus.cancelled);
      } else {
        result = await _updateOne(
          worker,
          mod,
          details[mod.id],
          onStage: (stage) => ctx.report(
            OperationProgress(
              kind: kind,
              label: workshopUpdateProgressLabel,
              done: i,
              total: total,
              fraction: (i + stage) / total,
              detail: mod.displayName,
            ),
          ),
        );
      }
      _results.add(result);
      ctx.report(
        OperationProgress(
          kind: kind,
          label: workshopUpdateProgressLabel,
          done: i + 1,
          total: total,
          fraction: (i + 1) / total,
        ),
      );
    }

    final batch = WorkshopUpdateBatchResult(_results);
    final message =
        'Updated ${batch.updatedCount}/${batch.total} Workshop mod(s)'
        '${batch.upToDateCount > 0 ? ', ${batch.upToDateCount} already up to date' : ''}'
        '${batch.failedCount > 0 ? ', ${batch.failedCount} failed' : ''}'
        '${batch.cancelledCount > 0 ? ', ${batch.cancelledCount} cancelled' : ''}';
    if (batch.failedCount > 0 || batch.wasCancelled) {
      log.warning(
        LogSource.workshop,
        message,
        details: [
          for (final r in batch.results)
            if (r.status == WorkshopUpdateStatus.failed)
              '[${r.id}] ${r.error ?? r.itemStatus?.name ?? 'failed'}',
        ].join('\n'),
        operationId: ctx.operationId,
      );
    } else {
      log.success(LogSource.workshop, message, operationId: ctx.operationId);
    }
    return batch;
  }

  Future<WorkshopUpdateResult> _updateOne(
    _WorkshopItemDownloader worker,
    Mod mod,
    WorkshopItemDetails? details, {
    required void Function(double stage) onStage,
  }) async {
    final item = details ?? WorkshopItemDetails.missing(mod.id);
    final status = item.statusFor();
    if (!status.isOk) {
      worker.ctx.log.warning(
        LogSource.workshop,
        'Cannot update "${mod.displayName}": ${_statusText(status)}',
        modPath: mod.jsonPath,
        operationId: worker.ctx.operationId,
      );
      return _result(
        mod,
        WorkshopUpdateStatus.failed,
        itemStatus: status,
        error: _statusText(status),
      );
    }
    final steamEpoch = item.timeUpdated!;
    final currentEpoch = mod.epochTime ?? 0;
    if (!force &&
        !(steamEpoch > currentEpoch &&
            (steamEpoch - currentEpoch).abs() >
                workshopUpdateToleranceSeconds)) {
      return _result(mod, WorkshopUpdateStatus.upToDate);
    }
    final download = await worker.downloadItem(
      id: mod.id,
      details: item,
      targetDir: p.dirname(mod.jsonPath),
      onStage: onStage,
      modPath: mod.jsonPath,
    );
    if (download.cancelled) {
      return _result(mod, WorkshopUpdateStatus.cancelled);
    }
    if (!download.isSuccess) {
      return _result(
        mod,
        WorkshopUpdateStatus.failed,
        itemStatus: download.status,
        error: download.error ?? _statusText(download.status),
      );
    }
    return _result(mod, WorkshopUpdateStatus.updated);
  }

  static WorkshopUpdateResult _result(
    Mod mod,
    WorkshopUpdateStatus status, {
    WorkshopItemStatus? itemStatus,
    String? error,
  }) => WorkshopUpdateResult(
    id: mod.id,
    modName: mod.displayName,
    jsonPath: mod.jsonPath,
    status: status,
    itemStatus: itemStatus,
    error: error,
  );

  static String _statusText(WorkshopItemStatus status) => switch (status) {
    WorkshopItemStatus.ok => 'ok',
    WorkshopItemStatus.notFound => 'the item is not on the Workshop',
    WorkshopItemStatus.unlisted => 'the item is unlisted or private',
    WorkshopItemStatus.wrongApp =>
      'the item does not belong to Tabletop Simulator',
    WorkshopItemStatus.invalid => 'Steam returned no usable details',
  };
}

/// The per-item steps shared by both operations.
final class _WorkshopItemDownloader {
  _WorkshopItemDownloader(this.ref, this.ctx);

  final Ref ref;
  final OperationContext ctx;

  SteamWorkshopClient get _client => ref.read(steamWorkshopClientProvider);
  FileSystem get _fs => ref.read(fileSystemProvider);

  /// Details for [ids] keyed by id. A failed lookup is logged and yields an
  /// empty map, so every item ends as [WorkshopItemStatus.invalid].
  Future<Map<String, WorkshopItemDetails>> detailsFor(List<String> ids) async {
    try {
      final list = await _client.getPublishedFileDetails(ids, token: ctx.token);
      return {for (final d in list) d.id: d};
    } on OperationCancelledException {
      rethrow;
    } on Object catch (error, stackTrace) {
      ctx.log.error(
        LogSource.workshop,
        'Could not fetch Workshop item details',
        error: error,
        stackTrace: stackTrace,
        operationId: ctx.operationId,
      );
      return {for (final id in ids) id: WorkshopItemDetails.lookupFailed(id)};
    }
  }

  /// Downloads one item. [onStage] gets 0.25 after the details check, 0.5
  /// after the BSON download, 0.75 after the JSON write.
  Future<WorkshopDownloadResult> downloadItem({
    required String id,
    required WorkshopItemDetails? details,
    required String targetDir,
    required void Function(double stage) onStage,
    String? modPath,
  }) async {
    final log = ctx.log;
    final opId = ctx.operationId;
    final item = details ?? WorkshopItemDetails.missing(id);
    final status = item.statusFor();
    if (!status.isOk) {
      log.error(
        LogSource.workshop,
        'Cannot download Workshop item $id: '
        '${UpdateWorkshopModsOperation._statusText(status)}',
        details: item.toString(),
        modPath: modPath,
        operationId: opId,
      );
      return WorkshopDownloadResult(
        id: id,
        title: item.title,
        status: status,
        error: UpdateWorkshopModsOperation._statusText(status),
      );
    }
    onStage(0.25);

    final jsonPath = p.normalize(p.join(targetDir, '$id.json'));
    try {
      final bson = await _client.download(item.fileUrl!, token: ctx.token);
      ctx.checkCancelled();
      onStage(0.5);
      final json = workshopBsonToJson(
        bson,
        timeUpdated: item.timeUpdated!,
        title: item.title,
      );
      await _fs.directory(targetDir).create(recursive: true);
      await _fs.writeStringPreservingCreationTime(jsonPath, json);
      onStage(0.75);
    } on OperationCancelledException {
      return WorkshopDownloadResult(
        id: id,
        title: item.title,
        status: status,
        cancelled: true,
      );
    } on Object catch (error, stackTrace) {
      final description = error is DioException
          ? 'Failed to download the Workshop file'
                '${error.response?.statusCode == null ? '' : ' (${error.response!.statusCode})'}'
          : 'Could not convert or write the mod file';
      log.error(
        LogSource.workshop,
        '$description: $id',
        error: error,
        stackTrace: stackTrace,
        modPath: modPath ?? jsonPath,
        url: item.fileUrl,
        operationId: opId,
      );
      return WorkshopDownloadResult(
        id: id,
        title: item.title,
        status: status,
        error: '$description: $error',
      );
    }

    await _writePreview(item, targetDir, id, jsonPath);
    if (ctx.isCancelled) {
      // The JSON is complete; still index it before reporting cancellation.
      await _refresh(jsonPath);
      return WorkshopDownloadResult(
        id: id,
        title: item.title,
        status: status,
        jsonPath: jsonPath,
        cancelled: true,
      );
    }
    await _refresh(jsonPath);
    log.success(
      LogSource.workshop,
      'Downloaded Workshop item "${item.title ?? id}" to $jsonPath',
      modPath: jsonPath,
      operationId: opId,
    );
    return WorkshopDownloadResult(
      id: id,
      title: item.title,
      status: status,
      jsonPath: jsonPath,
    );
  }

  /// Downloads and squares the preview image next to the JSON; problems are
  /// logged as warnings and never fail the item.
  Future<void> _writePreview(
    WorkshopItemDetails item,
    String targetDir,
    String id,
    String jsonPath,
  ) async {
    final previewUrl = item.previewUrl;
    if (previewUrl == null) return;
    try {
      final bytes = await _client.download(previewUrl, token: ctx.token);
      final png = squarePreviewPng(bytes);
      if (png == null) {
        ctx.log.warning(
          LogSource.workshop,
          'Preview image of $id could not be decoded',
          modPath: jsonPath,
          url: previewUrl,
          operationId: ctx.operationId,
        );
        return;
      }
      await _fs.file(p.join(targetDir, '$id.png')).writeAsBytes(png);
    } on OperationCancelledException {
      // The JSON is already written; the image is optional.
    } on Object catch (error, stackTrace) {
      ctx.log.warning(
        LogSource.workshop,
        'Preview image of $id could not be downloaded',
        details: '$error\n$stackTrace',
        modPath: jsonPath,
        url: previewUrl,
        operationId: ctx.operationId,
      );
    }
  }

  Future<void> _refresh(String jsonPath) async {
    if (!ref.mounted) return;
    try {
      await ref
          .read(libraryControllerProvider.notifier)
          .refreshMod(jsonPath, type: ModType.mod);
    } on Object catch (error, stackTrace) {
      ctx.log.error(
        LogSource.workshop,
        'Downloaded mod could not be indexed; refresh the library',
        error: error,
        stackTrace: stackTrace,
        modPath: jsonPath,
        operationId: ctx.operationId,
      );
    }
  }
}
