/// Facade the multi-select view calls for every bulk action: builds the
/// bulk operation and hands it to the `OperationRunner`.
library;

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/bulk/application/bulk_operation.dart';
import 'package:tts_mod_vault/features/bulk/application/bulk_operations.dart';
import 'package:tts_mod_vault/features/cleanup/application/delete_assets_service.dart'
    show DeleteAssetsScope, PostBackupDeletion;
import 'package:tts_mod_vault/features/operations/application/operation_runner.dart';
import 'package:tts_mod_vault/features/url_updates/application/update_urls_operation.dart'
    show UpdateUrlsResult;
import 'package:tts_mod_vault/features/workshop/application/workshop_results.dart'
    show WorkshopUpdateBatchResult;

export 'package:tts_mod_vault/features/bulk/application/bulk_operation.dart'
    show BulkBackupBehavior, BulkModOutcome;
export 'package:tts_mod_vault/features/bulk/application/bulk_operations.dart'
    show
        BulkBackupModOutcome,
        BulkBackupResult,
        BulkDeleteAssetsResult,
        BulkDownloadAndBackupModOutcome,
        BulkDownloadAndBackupResult,
        BulkDownloadResult,
        BulkUrlCheckResult;
export 'package:tts_mod_vault/features/cleanup/application/delete_assets_service.dart'
    show DeleteAssetsScope, PostBackupDeletion;

/// The bulk actions facade.
final bulkServiceProvider = Provider<BulkService>(BulkService.new);

/// Starts bulk operations on the runner. Each method throws [StateError]
/// when another operation is running (the UI disables the actions while
/// `anyOperationRunningProvider` is true); cancellation comes back inside
/// the result models. Not `final`, so widget tests can substitute a fake.
class BulkService {
  /// Creates the service on [ref].
  BulkService(this.ref);

  /// Supplies the runner and the operations' collaborators.
  final Ref ref;

  OperationRunner get _runner => ref.read(operationRunnerProvider.notifier);

  /// Downloads the missing files of every mod.
  Future<BulkDownloadResult> downloadMods(List<Mod> mods) =>
      _runner.run(BulkDownloadOperation(ref: ref, mods: mods));

  /// Backs up every mod into [folder] following [behavior] for mods that
  /// already have a backup, then applies [postBackupDeletion]; with
  /// [setAsDefaultFolder] the folder becomes the default backups folder.
  Future<BulkBackupResult> backupMods(
    List<Mod> mods, {
    required String folder,
    required BulkBackupBehavior behavior,
    PostBackupDeletion postBackupDeletion = PostBackupDeletion.none,
    bool setAsDefaultFolder = false,
  }) => _runner.run(
    BulkBackupOperation(
      ref: ref,
      mods: mods,
      folder: folder,
      behavior: behavior,
      postBackupDeletion: postBackupDeletion,
      setAsDefaultFolder: setAsDefaultFolder,
    ),
  );

  /// Downloads then backs up every mod; see [backupMods] for the options.
  Future<BulkDownloadAndBackupResult> downloadAndBackupMods(
    List<Mod> mods, {
    required String folder,
    required BulkBackupBehavior behavior,
    PostBackupDeletion postBackupDeletion = PostBackupDeletion.none,
    bool setAsDefaultFolder = false,
  }) => _runner.run(
    BulkDownloadAndBackupOperation(
      ref: ref,
      mods: mods,
      folder: folder,
      behavior: behavior,
      postBackupDeletion: postBackupDeletion,
      setAsDefaultFolder: setAsDefaultFolder,
    ),
  );

  /// Deletes the cached files of every mod that [scope] covers.
  Future<BulkDeleteAssetsResult> deleteModAssets(
    List<Mod> mods, {
    required DeleteAssetsScope scope,
  }) => _runner.run(
    BulkDeleteAssetsOperation(ref: ref, mods: mods, scope: scope),
  );

  /// Checks the asset URLs of every mod.
  Future<BulkUrlCheckResult> checkUrls(List<Mod> mods) =>
      _runner.run(BulkCheckUrlsOperation(ref: ref, mods: mods));

  /// Updates every mod from the Workshop; with [force] even when Steam is
  /// not newer.
  Future<WorkshopUpdateBatchResult> updateWorkshopMods(
    List<Mod> mods, {
    bool force = false,
  }) => _runner.run(
    BulkUpdateWorkshopOperation(ref: ref, mods: mods, force: force),
  );

  /// Rewrites the URLs of every mod starting with any of [oldPrefixes] to
  /// start with [newPrefix]; with [renameFiles] the cached files follow.
  Future<UpdateUrlsResult> updateUrls(
    List<Mod> mods, {
    required List<String> oldPrefixes,
    required String newPrefix,
    bool renameFiles = false,
  }) => _runner.run(
    BulkUpdateUrlsOperation(
      ref: ref,
      mods: mods,
      oldPrefixes: oldPrefixes,
      newPrefix: newPrefix,
      renameFiles: renameFiles,
    ),
  );

  /// Requests cancellation of the running operation; the current per-mod
  /// step finishes (honouring its own cancel checks) and the loop stops.
  void cancel() => _runner.cancel();
}
