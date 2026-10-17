/// The concrete bulk operations of plan Phase 5 (v2 `BulkActionsNotifier`):
/// download, backup (skip / replace / replace-if-out-of-date with optional
/// post-backup deletion and "set as default folder"), download + backup,
/// delete assets, check URLs, update from Workshop and update URL prefixes.
/// Each composes the per-mod operations of the other features through the
/// shared `OperationContext`.
library;

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/core/logging/app_log.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/backups/application/backup_operations.dart';
import 'package:tts_mod_vault/features/backups/application/backup_service.dart';
import 'package:tts_mod_vault/features/bulk/application/bulk_operation.dart';
import 'package:tts_mod_vault/features/cleanup/application/delete_assets_service.dart';
import 'package:tts_mod_vault/features/downloads/application/check_urls_operation.dart';
import 'package:tts_mod_vault/features/downloads/application/download_assets_operation.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';
import 'package:tts_mod_vault/features/operations/application/operation.dart';
import 'package:tts_mod_vault/features/startup/application/directories_controller.dart';
import 'package:tts_mod_vault/features/url_updates/application/update_urls_operation.dart';
import 'package:tts_mod_vault/features/workshop/application/workshop_service.dart';

// --- download -------------------------------------------------------------

/// Outcome of [BulkDownloadOperation].
final class BulkDownloadResult {
  /// Creates a result.
  const BulkDownloadResult({required this.outcomes, required this.cancelled});

  /// One entry per mod processed, in order.
  final List<BulkModOutcome<DownloadBatchResult>> outcomes;

  /// Whether the run stopped early.
  final bool cancelled;

  /// Mods the run got to.
  int get modsProcessed => outcomes.length;

  /// Mods whose download step threw.
  int get modsFailed => outcomes.where((o) => o.failed).length;

  /// Files downloaded across every mod.
  int get downloadedFiles => _sum((r) => r.downloadedCount);

  /// Files that failed across every mod.
  int get failedFiles => _sum((r) => r.failedCount);

  /// Files skipped (ignored domains) across every mod.
  int get skippedFiles => _sum((r) => r.skippedCount);

  int _sum(int Function(DownloadBatchResult result) pick) => outcomes.fold(
    0,
    (sum, o) => sum + (o.value == null ? 0 : pick(o.value!)),
  );

  @override
  String toString() =>
      'BulkDownloadResult(mods: $modsProcessed, files: $downloadedFiles, '
      'failed: $failedFiles${cancelled ? ', cancelled' : ''})';
}

/// Downloads the missing files of every mod (v2 `downloadAllMods`): one
/// [DownloadAssetsOperation] per mod, stopping when one reports a cancel.
final class BulkDownloadOperation
    extends BulkOperation<DownloadBatchResult, BulkDownloadResult> {
  /// Creates the operation.
  BulkDownloadOperation({required super.ref, required super.mods});

  @override
  String get bulkKindName => 'download';

  @override
  Future<DownloadBatchResult> processMod(OperationContext ctx, Mod mod) =>
      DownloadAssetsOperation(ref: ref, mod: currentMod(mod)).run(ctx);

  @override
  bool stopAfter(DownloadBatchResult value) => value.cancelledCount > 0;

  @override
  BulkDownloadResult assemble({required bool cancelled}) => BulkDownloadResult(
    outcomes: List.unmodifiable(outcomes),
    cancelled: cancelled,
  );

  @override
  String summaryMessage(BulkDownloadResult result) =>
      'Bulk download finished: ${result.downloadedFiles} file(s) for '
      '${result.modsProcessed} mod(s)'
      '${result.failedFiles == 0 ? '' : ', ${result.failedFiles} file(s) failed'}';
}

// --- backup ---------------------------------------------------------------

/// What happened to one mod in a bulk backup.
final class BulkBackupModOutcome {
  /// Creates an outcome.
  const BulkBackupModOutcome({
    required this.skipped,
    this.backup,
    this.deletion,
  });

  /// Whether the backup was not written because of the behaviour rule.
  final bool skipped;

  /// The archive written, or null when skipped.
  final BackupResult? backup;

  /// The post-backup deletion, or null when none was requested or the run
  /// was cancelled before it.
  final DeleteAssetsResult? deletion;

  @override
  String toString() =>
      'BulkBackupModOutcome(${skipped ? 'skipped' : backup?.backup.fileName}'
      '${deletion == null ? '' : ', deleted ${deletion!.deleted}'})';
}

/// Outcome of [BulkBackupOperation].
final class BulkBackupResult {
  /// Creates a result.
  const BulkBackupResult({
    required this.outcomes,
    required this.cancelled,
    required this.backupsDirChanged,
  });

  /// One entry per mod processed, in order.
  final List<BulkModOutcome<BulkBackupModOutcome>> outcomes;

  /// Whether the run stopped early.
  final bool cancelled;

  /// Whether the chosen folder became the default backups folder.
  final bool backupsDirChanged;

  /// Mods the run got to.
  int get modsProcessed => outcomes.length;

  /// Archives written.
  int get backedUp => outcomes.where((o) => o.value?.backup != null).length;

  /// Mods skipped by the behaviour rule.
  int get skipped => outcomes.where((o) => o.value?.skipped ?? false).length;

  /// Mods whose step threw.
  int get modsFailed => outcomes.where((o) => o.failed).length;

  /// Asset files deleted after the backups.
  int get filesDeleted =>
      outcomes.fold(0, (sum, o) => sum + (o.value?.deletion?.deleted ?? 0));

  /// Asset files that could not be deleted.
  int get deleteFailed =>
      outcomes.fold(0, (sum, o) => sum + (o.value?.deletion?.failed ?? 0));

  @override
  String toString() =>
      'BulkBackupResult(backedUp: $backedUp, skipped: $skipped, '
      'deleted: $filesDeleted${cancelled ? ', cancelled' : ''})';
}

/// The per-mod backup rules shared by [BulkBackupOperation] and
/// [BulkDownloadAndBackupOperation] (v2 `backupAllMods` loop body).
final class _BackupStep {
  _BackupStep({
    required this.ref,
    required this.folder,
    required this.behavior,
    required this.postBackupDeletion,
  });

  final Ref ref;
  final String folder;
  final BulkBackupBehavior behavior;
  final PostBackupDeletion postBackupDeletion;

  /// Decides whether [mod] gets a backup and where, writes it, then runs
  /// the optional deletion. [mod] must be the current library state's view.
  Future<BulkBackupModOutcome> run(OperationContext ctx, Mod mod) async {
    var perform = true;
    String? existingDir;
    if (mod.backupStatus != BackupStatus.none) {
      switch (behavior) {
        case BulkBackupBehavior.skip:
          perform = false;
        case BulkBackupBehavior.replace:
          existingDir = _dirOf(mod.backup);
        case BulkBackupBehavior.replaceIfOutOfDate:
          if (mod.backupStatus != BackupStatus.outOfDate) {
            perform = false;
          } else {
            existingDir = _dirOf(mod.backup);
          }
      }
    }
    final scope = postBackupDeletion.scope;
    if (!perform && scope == null) {
      ctx.log.info(
        LogSource.backup,
        'Skipped backup of "${mod.displayName}": '
        '${_skipReason(mod.backupStatus)}',
        modPath: mod.jsonPath,
        operationId: ctx.operationId,
      );
      return const BulkBackupModOutcome(skipped: true);
    }

    BackupResult? backup;
    if (perform) {
      final target = await ref
          .read(backupServiceProvider)
          .backupTargetFor(mod, chosenDir: existingDir ?? folder);
      backup = await CreateBackupOperation(
        ref: ref,
        mod: mod,
        targetDir: target.dir,
      ).run(ctx);
    } else {
      ctx.log.info(
        LogSource.backup,
        'Skipped backup of "${mod.displayName}": '
        '${_skipReason(mod.backupStatus)}; deleting its assets',
        modPath: mod.jsonPath,
        operationId: ctx.operationId,
      );
    }

    DeleteAssetsResult? deletion;
    if (scope != null && !ctx.isCancelled) {
      final current =
          ref.read(libraryControllerProvider).value?.modByPath(mod.jsonPath) ??
          mod;
      deletion = await DeleteModAssetsOperation(
        ref: ref,
        mod: current,
        scope: scope,
      ).run(ctx);
    }
    return BulkBackupModOutcome(
      skipped: !perform,
      backup: backup,
      deletion: deletion,
    );
  }

  /// Persists [folder] as the default backups folder and re-indexes the
  /// library so the archives already in it appear (v2
  /// `setAsDefaultBackupDirAndReload`).
  Future<void> setAsDefault(OperationContext ctx) async {
    final directories = await ref.read(directoriesProvider.future);
    if (directories.backupsDir == folder) return;
    await ref.read(directoriesProvider.notifier).setBackupsDir(folder);
    ctx.log.info(
      LogSource.backup,
      'Backups folder set to $folder; refreshing the library',
      operationId: ctx.operationId,
    );
    if (ref.mounted) {
      await ref.read(libraryControllerProvider.notifier).refresh();
    }
  }

  static String? _dirOf(Backup? backup) =>
      backup == null ? null : p.dirname(backup.path);

  static String _skipReason(BackupStatus status) => switch (status) {
    BackupStatus.upToDate => 'its backup is up to date',
    BackupStatus.outOfDate => 'it already has a backup',
    BackupStatus.assetCountMismatch =>
      'its backup has a different number of assets',
    BackupStatus.none => 'no backup',
  };
}

/// Backs up every mod (v2 `backupAllMods`): each gets a
/// [CreateBackupOperation] into [folder] (or into its existing backup's
/// folder for the replace behaviours), then the optional
/// [DeleteModAssetsOperation]. With [setAsDefaultFolder] the folder becomes
/// the default backups folder once the loop finished without a cancel.
final class BulkBackupOperation
    extends BulkOperation<BulkBackupModOutcome, BulkBackupResult> {
  /// Creates the operation.
  BulkBackupOperation({
    required super.ref,
    required super.mods,
    required this.folder,
    required this.behavior,
    this.postBackupDeletion = PostBackupDeletion.none,
    this.setAsDefaultFolder = false,
  }) : _step = _BackupStep(
         ref: ref,
         folder: folder,
         behavior: behavior,
         postBackupDeletion: postBackupDeletion,
       );

  /// Folder new archives are written into.
  final String folder;

  /// What to do with mods that already have a backup.
  final BulkBackupBehavior behavior;

  /// What to do with the cached files afterwards.
  final PostBackupDeletion postBackupDeletion;

  /// Whether [folder] becomes the default backups folder.
  final bool setAsDefaultFolder;

  final _BackupStep _step;
  bool _dirChanged = false;

  @override
  String get bulkKindName => 'backup';

  @override
  Future<BulkBackupModOutcome> processMod(OperationContext ctx, Mod mod) =>
      _step.run(ctx, currentMod(mod));

  @override
  Future<void> finish(OperationContext ctx, {required bool cancelled}) async {
    if (!setAsDefaultFolder || cancelled) return;
    await _step.setAsDefault(ctx);
    _dirChanged = true;
  }

  @override
  BulkBackupResult assemble({required bool cancelled}) => BulkBackupResult(
    outcomes: List.unmodifiable(outcomes),
    cancelled: cancelled,
    backupsDirChanged: _dirChanged,
  );

  @override
  String summaryMessage(BulkBackupResult result) =>
      'Bulk backup finished: ${result.backedUp} backed up, '
      '${result.skipped} skipped'
      '${postBackupDeletion == PostBackupDeletion.none ? '' : ', ${result.filesDeleted} asset file(s) deleted'}';
}

// --- download and backup --------------------------------------------------

/// What happened to one mod in a bulk download + backup.
final class BulkDownloadAndBackupModOutcome {
  /// Creates an outcome.
  const BulkDownloadAndBackupModOutcome({required this.download, this.backup});

  /// The download step.
  final DownloadBatchResult download;

  /// The backup step, or null when the run was cancelled during the
  /// download.
  final BulkBackupModOutcome? backup;
}

/// Outcome of [BulkDownloadAndBackupOperation].
final class BulkDownloadAndBackupResult {
  /// Creates a result.
  const BulkDownloadAndBackupResult({
    required this.outcomes,
    required this.cancelled,
    required this.backupsDirChanged,
  });

  /// One entry per mod processed, in order.
  final List<BulkModOutcome<BulkDownloadAndBackupModOutcome>> outcomes;

  /// Whether the run stopped early.
  final bool cancelled;

  /// Whether the chosen folder became the default backups folder.
  final bool backupsDirChanged;

  /// Mods the run got to.
  int get modsProcessed => outcomes.length;

  /// Mods whose step threw.
  int get modsFailed => outcomes.where((o) => o.failed).length;

  /// Files downloaded across every mod.
  int get downloadedFiles => outcomes.fold(
    0,
    (sum, o) => sum + (o.value?.download.downloadedCount ?? 0),
  );

  /// Files that failed to download across every mod.
  int get failedFiles =>
      outcomes.fold(0, (sum, o) => sum + (o.value?.download.failedCount ?? 0));

  /// Archives written.
  int get backedUp =>
      outcomes.where((o) => o.value?.backup?.backup != null).length;

  /// Mods skipped by the behaviour rule.
  int get skipped =>
      outcomes.where((o) => o.value?.backup?.skipped ?? false).length;

  /// Asset files deleted after the backups.
  int get filesDeleted => outcomes.fold(
    0,
    (sum, o) => sum + (o.value?.backup?.deletion?.deleted ?? 0),
  );

  @override
  String toString() =>
      'BulkDownloadAndBackupResult(files: $downloadedFiles, '
      'backedUp: $backedUp, skipped: $skipped${cancelled ? ', cancelled' : ''})';
}

/// Downloads then backs up every mod (v2 `downloadAndBackupAllMods`): the
/// download step first, then, unless cancelled meanwhile, the same backup
/// rules as [BulkBackupOperation] on the refreshed mod.
final class BulkDownloadAndBackupOperation
    extends
        BulkOperation<
          BulkDownloadAndBackupModOutcome,
          BulkDownloadAndBackupResult
        > {
  /// Creates the operation.
  BulkDownloadAndBackupOperation({
    required super.ref,
    required super.mods,
    required this.folder,
    required this.behavior,
    this.postBackupDeletion = PostBackupDeletion.none,
    this.setAsDefaultFolder = false,
  }) : _step = _BackupStep(
         ref: ref,
         folder: folder,
         behavior: behavior,
         postBackupDeletion: postBackupDeletion,
       );

  /// Folder new archives are written into.
  final String folder;

  /// What to do with mods that already have a backup.
  final BulkBackupBehavior behavior;

  /// What to do with the cached files afterwards.
  final PostBackupDeletion postBackupDeletion;

  /// Whether [folder] becomes the default backups folder.
  final bool setAsDefaultFolder;

  final _BackupStep _step;
  bool _dirChanged = false;

  @override
  String get bulkKindName => 'downloadAndBackup';

  @override
  Future<BulkDownloadAndBackupModOutcome> processMod(
    OperationContext ctx,
    Mod mod,
  ) async {
    final download = await DownloadAssetsOperation(
      ref: ref,
      mod: currentMod(mod),
    ).run(ctx);
    if (download.cancelledCount > 0 || ctx.isCancelled) {
      return BulkDownloadAndBackupModOutcome(download: download);
    }
    final backup = await _step.run(ctx, currentMod(mod));
    return BulkDownloadAndBackupModOutcome(download: download, backup: backup);
  }

  @override
  bool stopAfter(BulkDownloadAndBackupModOutcome value) =>
      value.download.cancelledCount > 0 || value.backup == null;

  @override
  Future<void> finish(OperationContext ctx, {required bool cancelled}) async {
    if (!setAsDefaultFolder || cancelled) return;
    await _step.setAsDefault(ctx);
    _dirChanged = true;
  }

  @override
  BulkDownloadAndBackupResult assemble({required bool cancelled}) =>
      BulkDownloadAndBackupResult(
        outcomes: List.unmodifiable(outcomes),
        cancelled: cancelled,
        backupsDirChanged: _dirChanged,
      );

  @override
  String summaryMessage(BulkDownloadAndBackupResult result) =>
      'Bulk download & backup finished: ${result.downloadedFiles} file(s) '
      'downloaded, ${result.backedUp} backed up, ${result.skipped} skipped';
}

// --- delete assets --------------------------------------------------------

/// Outcome of [BulkDeleteAssetsOperation].
final class BulkDeleteAssetsResult {
  /// Creates a result.
  const BulkDeleteAssetsResult({
    required this.outcomes,
    required this.cancelled,
  });

  /// One entry per mod processed, in order.
  final List<BulkModOutcome<DeleteAssetsResult>> outcomes;

  /// Whether the run stopped early.
  final bool cancelled;

  /// Mods the run got to.
  int get modsProcessed => outcomes.length;

  /// Mods whose step threw.
  int get modsFailed => outcomes.where((o) => o.failed).length;

  /// Files deleted across every mod.
  int get filesDeleted =>
      outcomes.fold(0, (sum, o) => sum + (o.value?.deleted ?? 0));

  /// Files that could not be deleted.
  int get deleteFailed =>
      outcomes.fold(0, (sum, o) => sum + (o.value?.failed ?? 0));

  @override
  String toString() =>
      'BulkDeleteAssetsResult(mods: $modsProcessed, deleted: $filesDeleted'
      '${cancelled ? ', cancelled' : ''})';
}

/// Deletes the cached files of every mod (v2 `deleteAssetsAllMods`): one
/// [DeleteModAssetsOperation] per mod with [scope].
final class BulkDeleteAssetsOperation
    extends BulkOperation<DeleteAssetsResult, BulkDeleteAssetsResult> {
  /// Creates the operation.
  BulkDeleteAssetsOperation({
    required super.ref,
    required super.mods,
    required this.scope,
  });

  /// Which files of each mod.
  final DeleteAssetsScope scope;

  @override
  String get bulkKindName => 'deleteAssets';

  @override
  Future<DeleteAssetsResult> processMod(OperationContext ctx, Mod mod) =>
      DeleteModAssetsOperation(
        ref: ref,
        mod: currentMod(mod),
        scope: scope,
      ).run(ctx);

  @override
  BulkDeleteAssetsResult assemble({required bool cancelled}) =>
      BulkDeleteAssetsResult(
        outcomes: List.unmodifiable(outcomes),
        cancelled: cancelled,
      );

  @override
  String summaryMessage(BulkDeleteAssetsResult result) =>
      'Bulk asset deletion finished: ${result.filesDeleted} file(s) deleted '
      'for ${result.modsProcessed} mod(s)'
      '${result.deleteFailed == 0 ? '' : ', ${result.deleteFailed} file(s) failed'}';
}

// --- check URLs -----------------------------------------------------------

/// Outcome of [BulkCheckUrlsOperation].
final class BulkUrlCheckResult {
  /// Creates a result.
  const BulkUrlCheckResult({required this.outcomes, required this.cancelled});

  /// One entry per mod processed, in order.
  final List<BulkModOutcome<UrlCheckResult>> outcomes;

  /// Whether the run stopped early.
  final bool cancelled;

  /// `(mod, result)` for every mod whose check produced a result.
  List<(Mod, UrlCheckResult)> get results => [
    for (final o in outcomes)
      if (o.value case final value?) (o.mod, value),
  ];

  /// Mods the run got to.
  int get modsChecked => outcomes.length;

  /// Mods whose step threw.
  int get modsFailed => outcomes.where((o) => o.failed).length;

  /// Dead URLs found across every mod.
  int get invalidUrlCount =>
      outcomes.fold(0, (sum, o) => sum + (o.value?.invalidUrls.length ?? 0));

  @override
  String toString() =>
      'BulkUrlCheckResult(mods: $modsChecked, invalid: $invalidUrlCount'
      '${cancelled ? ', cancelled' : ''})';
}

/// Checks the asset URLs of every mod (v2 `checkUrlsAllMods`): one
/// [CheckUrlsOperation] per mod, stopping when one reports a cancel.
final class BulkCheckUrlsOperation
    extends BulkOperation<UrlCheckResult, BulkUrlCheckResult> {
  /// Creates the operation.
  BulkCheckUrlsOperation({required super.ref, required super.mods});

  @override
  String get bulkKindName => 'checkUrls';

  @override
  Future<UrlCheckResult> processMod(OperationContext ctx, Mod mod) =>
      CheckUrlsOperation(ref: ref, mod: currentMod(mod)).run(ctx);

  @override
  bool stopAfter(UrlCheckResult value) => value.cancelled;

  @override
  BulkUrlCheckResult assemble({required bool cancelled}) => BulkUrlCheckResult(
    outcomes: List.unmodifiable(outcomes),
    cancelled: cancelled,
  );

  @override
  String summaryMessage(BulkUrlCheckResult result) =>
      'Bulk URL check finished: ${result.modsChecked} mod(s) checked, '
      '${result.invalidUrlCount} URL(s) not reachable';
}

// --- delegating wrappers --------------------------------------------------

/// Updates every mod from the Workshop (v2 `updateModsAll`). The inner
/// [UpdateWorkshopModsOperation] already iterates mods with its own
/// progress and per-mod results, so this is a thin wrapper that keeps the
/// bulk facade uniform.
final class BulkUpdateWorkshopOperation
    extends Operation<WorkshopUpdateBatchResult> {
  /// Creates the operation.
  BulkUpdateWorkshopOperation({
    required Ref ref,
    required List<Mod> mods,
    bool force = false,
  }) : _inner = UpdateWorkshopModsOperation(ref: ref, mods: mods, force: force);

  final UpdateWorkshopModsOperation _inner;

  /// The mods being updated.
  @visibleForTesting
  List<Mod> get mods => _inner.mods;

  @override
  OperationKind get kind => _inner.kind;

  @override
  WorkshopUpdateBatchResult? cancelledResult() => _inner.cancelledResult();

  @override
  Future<WorkshopUpdateBatchResult> run(OperationContext ctx) =>
      _inner.run(ctx);
}

/// Rewrites URL prefixes in every mod (v2 `updateUrlPrefixesAllMods`); a
/// thin wrapper over [UpdateUrlsOperation], which iterates mods itself.
final class BulkUpdateUrlsOperation extends Operation<UpdateUrlsResult> {
  /// Creates the operation.
  BulkUpdateUrlsOperation({
    required Ref ref,
    required List<Mod> mods,
    required List<String> oldPrefixes,
    required String newPrefix,
    bool renameFiles = false,
  }) : _inner = UpdateUrlsOperation(
         ref: ref,
         mods: mods,
         oldPrefixes: oldPrefixes,
         newPrefix: newPrefix,
         renameFiles: renameFiles,
       );

  final UpdateUrlsOperation _inner;

  @override
  OperationKind get kind => _inner.kind;

  @override
  UpdateUrlsResult? cancelledResult() => _inner.cancelledResult();

  @override
  Future<UpdateUrlsResult> run(OperationContext ctx) => _inner.run(ctx);
}
