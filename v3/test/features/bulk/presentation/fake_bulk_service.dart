// A `BulkService` double: records every call with the choices the dialogs
// collected and answers with configurable results, without touching the
// runner, the disk or the network.

// Test doubles expose recorded calls on purpose.
// ignore_for_file: avoid_public_notifier_properties

import 'package:hooks_riverpod/misc.dart' show Override;
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/backups/application/backup_service.dart'
    show BackupResult;
import 'package:tts_mod_vault/features/bulk/application/bulk_service.dart';
import 'package:tts_mod_vault/features/cleanup/application/delete_assets_service.dart'
    show DeleteAssetsResult;
import 'package:tts_mod_vault/features/downloads/application/downloads_providers.dart'
    show DownloadBatchResult, DownloadOutcome, DownloadStatus, UrlCheckResult;
import 'package:tts_mod_vault/features/url_updates/application/url_updates_service.dart'
    show UpdateUrlsResult;
import 'package:tts_mod_vault/features/workshop/application/workshop_service.dart'
    show WorkshopUpdateBatchResult, WorkshopUpdateResult, WorkshopUpdateStatus;

/// The choices of a bulk backup call.
typedef BackupCall = ({
  List<Mod> mods,
  String folder,
  BulkBackupBehavior behavior,
  PostBackupDeletion deletion,
  bool setAsDefault,
});

/// The choices of a bulk URL update call.
typedef UpdateUrlsCall = ({
  List<Mod> mods,
  List<String> oldPrefixes,
  String newPrefix,
  bool renameFiles,
});

/// Records calls and returns configurable results; by default every mod
/// succeeds (one file downloaded, one backup written, one file deleted,
/// every URL live, updated from the Workshop, one mod rewritten).
final class FakeBulkService extends BulkService {
  FakeBulkService(super.ref);

  /// Mods of every `downloadMods` call.
  final List<List<Mod>> downloadCalls = [];

  /// Every `backupMods` call.
  final List<BackupCall> backupCalls = [];

  /// Every `downloadAndBackupMods` call.
  final List<BackupCall> downloadAndBackupCalls = [];

  /// `(mods, scope)` of every `deleteModAssets` call.
  final List<(List<Mod>, DeleteAssetsScope)> deleteCalls = [];

  /// Mods of every `checkUrls` call.
  final List<List<Mod>> checkUrlsCalls = [];

  /// `(mods, force)` of every `updateWorkshopMods` call.
  final List<(List<Mod>, bool)> updateWorkshopCalls = [];

  /// Every `updateUrls` call.
  final List<UpdateUrlsCall> updateUrlsCalls = [];

  /// Result overrides; null means the default success result.
  BulkDownloadResult? downloadResult;
  BulkBackupResult? backupResult;
  BulkDownloadAndBackupResult? downloadAndBackupResult;
  BulkDeleteAssetsResult? deleteResult;
  BulkUrlCheckResult? checkUrlsResult;
  WorkshopUpdateBatchResult? updateWorkshopResult;
  UpdateUrlsResult? updateUrlsResult;

  /// Whether calls throw as the runner does while something runs.
  bool alreadyRunning = false;

  void _guard() {
    if (alreadyRunning) throw StateError('An operation is already running');
  }

  /// One downloaded image for [mod].
  static DownloadBatchResult downloadedOne(Mod mod) => DownloadBatchResult([
    DownloadOutcome(
      url: 'https://example.com/${mod.id}.png',
      type: AssetType.image,
      status: DownloadStatus.downloaded,
      path: '${mod.id}.png',
    ),
  ]);

  /// A written archive for [mod] in [folder].
  static BackupResult backupOf(Mod mod, String folder) => BackupResult(
    backup: Backup(
      path: p.join(folder, '${mod.displayName}.ttsmod'),
      fileName: '${mod.displayName}.ttsmod',
      folder: p.basename(folder),
      modified: DateTime(2024, 6),
      sizeBytes: 1024,
      assetCount: 1,
      matchingModPath: mod.jsonPath,
    ),
    assetCount: 1,
    skipped: 0,
  );

  @override
  Future<BulkDownloadResult> downloadMods(List<Mod> mods) async {
    _guard();
    downloadCalls.add(mods);
    return downloadResult ??
        BulkDownloadResult(
          outcomes: [
            for (final mod in mods)
              BulkModOutcome(mod: mod, value: downloadedOne(mod)),
          ],
          cancelled: false,
        );
  }

  @override
  Future<BulkBackupResult> backupMods(
    List<Mod> mods, {
    required String folder,
    required BulkBackupBehavior behavior,
    PostBackupDeletion postBackupDeletion = PostBackupDeletion.none,
    bool setAsDefaultFolder = false,
  }) async {
    _guard();
    backupCalls.add((
      mods: mods,
      folder: folder,
      behavior: behavior,
      deletion: postBackupDeletion,
      setAsDefault: setAsDefaultFolder,
    ));
    return backupResult ??
        BulkBackupResult(
          outcomes: [
            for (final mod in mods)
              BulkModOutcome(
                mod: mod,
                value: BulkBackupModOutcome(
                  skipped: false,
                  backup: backupOf(mod, folder),
                ),
              ),
          ],
          cancelled: false,
          backupsDirChanged: setAsDefaultFolder,
        );
  }

  @override
  Future<BulkDownloadAndBackupResult> downloadAndBackupMods(
    List<Mod> mods, {
    required String folder,
    required BulkBackupBehavior behavior,
    PostBackupDeletion postBackupDeletion = PostBackupDeletion.none,
    bool setAsDefaultFolder = false,
  }) async {
    _guard();
    downloadAndBackupCalls.add((
      mods: mods,
      folder: folder,
      behavior: behavior,
      deletion: postBackupDeletion,
      setAsDefault: setAsDefaultFolder,
    ));
    return downloadAndBackupResult ??
        BulkDownloadAndBackupResult(
          outcomes: [
            for (final mod in mods)
              BulkModOutcome(
                mod: mod,
                value: BulkDownloadAndBackupModOutcome(
                  download: downloadedOne(mod),
                  backup: BulkBackupModOutcome(
                    skipped: false,
                    backup: backupOf(mod, folder),
                  ),
                ),
              ),
          ],
          cancelled: false,
          backupsDirChanged: setAsDefaultFolder,
        );
  }

  @override
  Future<BulkDeleteAssetsResult> deleteModAssets(
    List<Mod> mods, {
    required DeleteAssetsScope scope,
  }) async {
    _guard();
    deleteCalls.add((mods, scope));
    return deleteResult ??
        BulkDeleteAssetsResult(
          outcomes: [
            for (final mod in mods)
              BulkModOutcome(
                mod: mod,
                value: const DeleteAssetsResult(deleted: 1, failed: 0),
              ),
          ],
          cancelled: false,
        );
  }

  @override
  Future<BulkUrlCheckResult> checkUrls(List<Mod> mods) async {
    _guard();
    checkUrlsCalls.add(mods);
    return checkUrlsResult ??
        BulkUrlCheckResult(
          outcomes: [
            for (final mod in mods)
              BulkModOutcome(
                mod: mod,
                value: const UrlCheckResult(
                  invalidUrls: [],
                  cancelled: false,
                  checked: 2,
                  total: 2,
                ),
              ),
          ],
          cancelled: false,
        );
  }

  @override
  Future<WorkshopUpdateBatchResult> updateWorkshopMods(
    List<Mod> mods, {
    bool force = false,
  }) async {
    _guard();
    updateWorkshopCalls.add((mods, force));
    return updateWorkshopResult ??
        WorkshopUpdateBatchResult([
          for (final mod in mods)
            WorkshopUpdateResult(
              id: mod.id,
              modName: mod.displayName,
              jsonPath: mod.jsonPath,
              status: WorkshopUpdateStatus.updated,
            ),
        ]);
  }

  @override
  Future<UpdateUrlsResult> updateUrls(
    List<Mod> mods, {
    required List<String> oldPrefixes,
    required String newPrefix,
    bool renameFiles = false,
  }) async {
    _guard();
    updateUrlsCalls.add((
      mods: mods,
      oldPrefixes: oldPrefixes,
      newPrefix: newPrefix,
      renameFiles: renameFiles,
    ));
    return updateUrlsResult ??
        UpdateUrlsResult(
          modsProcessed: mods.length,
          modsUpdated: mods.length,
          filesRenamed: 0,
          failed: const [],
          cancelled: false,
        );
  }
}

/// Overrides `bulkServiceProvider` with a [FakeBulkService]; read the
/// provider from the container and cast to reach the recorded calls.
Override fakeBulkServiceOverride() =>
    bulkServiceProvider.overrideWith(FakeBulkService.new);
