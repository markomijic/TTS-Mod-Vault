import 'package:file_picker/file_picker.dart' show FilePicker, FileType;
import 'package:flutter/foundation.dart' show compute, debugPrint;
import 'package:flutter/material.dart' show BuildContext, Navigator, showDialog;
import 'package:hooks_riverpod/hooks_riverpod.dart' show Ref, StateNotifier;
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show BulkUpdateResultsDialog, BulkUrlCheckResultsDialog;
import 'package:tts_mod_vault/src/state/backup/backup_state.dart'
    show BackupStatusEnum;
import 'package:tts_mod_vault/src/state/backup/backup_status_enum.dart'
    show ExistingBackupStatusEnum;
import 'package:tts_mod_vault/src/state/backup/import_backup.dart'
    show JsonConflictChoice, JsonImportConflict;
import 'package:tts_mod_vault/src/state/bulk_actions/bulk_actions_state.dart'
    show
        BulkActionsState,
        BulkActionsStatusEnum,
        BulkBackupBehaviorEnum,
        PostBackupDeletionEnum;
import 'package:tts_mod_vault/src/state/bulk_actions/mod_update_result.dart'
    show ModUpdateResult, ModUpdateStatus;
import 'package:tts_mod_vault/src/state/bulk_actions/mod_url_check_result.dart'
    show ModUrlCheckResult;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show Mod;
import 'package:tts_mod_vault/src/state/mods/mods_isolates.dart'
    show
        updateUrlPrefixesFilesIsolate,
        UpdateUrlPrefixesParams,
        extractUrlsFromJsonString;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        backupProvider,
        deleteAssetsProvider,
        directoriesProvider,
        downloadProvider,
        importBackupProvider,
        loaderProvider,
        logProvider,
        modsProvider,
        selectedModProvider,
        selectedModTypeProvider,
        storageProvider;

class BulkActionsNotifier extends StateNotifier<BulkActionsState> {
  final Ref ref;

  BulkActionsNotifier(this.ref) : super(const BulkActionsState());

  void _resetState() {
    state = BulkActionsState(
      status: BulkActionsStatusEnum.idle,
      cancelledBulkAction: false,
      currentModNumber: 0,
      totalModNumber: 0,
      statusMessage: "",
    );
  }

  Future<String?> _getBackupFolder() async {
    final backupsDir = ref.read(directoriesProvider).backupsDir;

    final backupFolder = await FilePicker.platform.getDirectoryPath(
      lockParentWindow: true,
      initialDirectory: backupsDir.isEmpty ? null : backupsDir,
    );

    return backupFolder;
  }

  // MARK: Download
  Future<void> downloadAllMods(List<Mod> mods) async {
    ref
        .read(logProvider.notifier)
        .addInfo('Starting bulk download for ${mods.length} mods');

    state = state.copyWith(
      status: BulkActionsStatusEnum.downloadAll,
      totalModNumber: mods.length,
    );

    final modsNotifier = ref.read(modsProvider.notifier);
    final downloadNotifier = ref.read(downloadProvider.notifier);
    final Set<String> allAffectedFilenames = {};

    for (int i = 0; i < mods.length; i++) {
      final mod = mods[i];

      if (state.cancelledBulkAction) {
        break;
      }

      // Yield to UI thread on every iteration to keep app responsive
      await Future.delayed(Duration.zero);

      debugPrint('Downloading: ${mod.saveName}');

      state = state.copyWith(
          currentModNumber: i + 1,
          statusMessage:
              'Downloading "${mod.saveName}" (${i + 1}/${state.totalModNumber})');

      modsNotifier.setSelectedMod(mod);
      final downloaded = await downloadNotifier.downloadAllFiles(mod);
      allAffectedFilenames.addAll(downloaded);
      await modsNotifier.updateSelectedMod(mod);
    }

    // Refresh other mods that share any of the downloaded assets
    if (allAffectedFilenames.isNotEmpty) {
      await modsNotifier.refreshModsWithSharedAssets(allAffectedFilenames);
    }

    if (state.cancelledBulkAction) {
      ref.read(logProvider.notifier).addWarning(
          'Bulk download cancelled (${state.currentModNumber}/${mods.length} completed)');
    } else {
      ref
          .read(logProvider.notifier)
          .addSuccess('Bulk download completed: ${mods.length} mods');
    }

    _resetState();
    downloadNotifier.resetState();
  }

// MARK: Backup
  Future<void> backupAllMods(
    List<Mod> mods,
    BulkBackupBehaviorEnum backupBehavior,
    String? folder,
    PostBackupDeletionEnum postBackupDeletion,
    bool setAsDefaultBackupFolder,
  ) async {
    ref
        .read(logProvider.notifier)
        .addInfo('Starting bulk backup for ${mods.length} mods');

    state = state.copyWith(
      status: BulkActionsStatusEnum.backupAll,
      totalModNumber: mods.length,
      statusMessage:
          "Select a folder to backup all ${ref.read(selectedModTypeProvider).label}s",
    );

    final selectedBackupFolder =
        folder != null && folder.isNotEmpty ? folder : await _getBackupFolder();
    if (selectedBackupFolder == null) {
      ref
          .read(logProvider.notifier)
          .addWarning('Bulk backup cancelled - no folder selected');
      _resetState();
      return;
    }

    final modsNotifier = ref.read(modsProvider.notifier);
    final backupNotifier = ref.read(backupProvider.notifier);
    final Set<String> allDeletedFilenames = {};

    for (int i = 0; i < mods.length; i++) {
      Mod currentMod = mods[i];

      if (state.cancelledBulkAction) {
        break;
      }

      // Yield to UI thread on every iteration to keep app responsive
      await Future.delayed(Duration.zero);

      String modBackupFolder = selectedBackupFolder;
      bool performBackup = true;

      if (currentMod.backupStatus != ExistingBackupStatusEnum.noBackup) {
        switch (backupBehavior) {
          case BulkBackupBehaviorEnum.skip:
            performBackup = false;
            break;

          case BulkBackupBehaviorEnum.replace:
            if (currentMod.backup != null) {
              modBackupFolder = p.dirname(currentMod.backup!.filepath);
            }
            break;

          case BulkBackupBehaviorEnum.replaceIfOutOfDate:
            if (currentMod.backupStatus != ExistingBackupStatusEnum.outOfDate) {
              performBackup = false;
              break;
            }
            if (currentMod.backup != null) {
              modBackupFolder = p.dirname(currentMod.backup!.filepath);
            }
            break;
        }
      }

      // Nothing to do for this mod if we're neither backing up nor deleting.
      if (!performBackup && postBackupDeletion == PostBackupDeletionEnum.none) {
        continue;
      }

      debugPrint(performBackup
          ? 'Backing up: ${currentMod.saveName}'
          : 'Deleting assets for: ${currentMod.saveName}');

      state = state.copyWith(
          currentModNumber: i + 1,
          statusMessage: performBackup
              ? 'Backing up "${currentMod.saveName}" (${i + 1}/${state.totalModNumber})'
              : 'Deleting assets for "${currentMod.saveName}" (${i + 1}/${state.totalModNumber})');

      modsNotifier.setSelectedMod(currentMod);
      if (performBackup) {
        await backupNotifier.createBackup(currentMod, modBackupFolder);
        currentMod = await modsNotifier.updateModBackup(currentMod);
      }

      // Delete assets after backup if configured
      if (postBackupDeletion != PostBackupDeletionEnum.none) {
        if (state.cancelledBulkAction) {
          break;
        }

        state = state.copyWith(
            statusMessage:
                'Deleting assets for "${currentMod.saveName}" (${i + 1}/${state.totalModNumber})');

        final deletedFilenames = await ref
            .read(deleteAssetsProvider.notifier)
            .deleteModAssetsAfterBackup(currentMod, postBackupDeletion);
        allDeletedFilenames.addAll(deletedFilenames);

        if (deletedFilenames.isNotEmpty) {
          await modsNotifier.updateSelectedMod(currentMod);
        }
      }
    }

    // Refresh other mods that share any of the deleted assets
    if (allDeletedFilenames.isNotEmpty) {
      await modsNotifier.refreshModsWithSharedAssets(allDeletedFilenames);
    }

    if (state.cancelledBulkAction) {
      ref.read(logProvider.notifier).addWarning(
          'Bulk backup cancelled (${state.currentModNumber}/${mods.length} completed)');
    } else {
      ref.read(logProvider.notifier).addSuccess(
          'Bulk backup completed: ${state.currentModNumber} mods backed up');
    }

    final wasCancelled = state.cancelledBulkAction;

    _resetState();

    // Save the chosen folder as default and reload only after all backups are
    // done, so the reload doesn't disrupt the in-progress backup.
    if (setAsDefaultBackupFolder && !wasCancelled) {
      await ref
          .read(directoriesProvider.notifier)
          .setAsDefaultBackupDirAndReload(selectedBackupFolder);
    }
  }

// MARK: DL & Backup
  Future<void> downloadAndBackupAllMods(
    List<Mod> mods,
    BulkBackupBehaviorEnum backupBehavior,
    String? folder,
    PostBackupDeletionEnum postBackupDeletion,
    bool setAsDefaultBackupFolder,
  ) async {
    state = state.copyWith(
      status: BulkActionsStatusEnum.downloadAndBackupAll,
      totalModNumber: mods.length,
      statusMessage:
          "Select a folder to backup all ${ref.read(selectedModTypeProvider).label}s",
    );

    final selectedBackupFolder =
        folder != null && folder.isNotEmpty ? folder : await _getBackupFolder();
    if (selectedBackupFolder == null) {
      _resetState();
      return;
    }

    final modsNotifier = ref.read(modsProvider.notifier);
    final downloadNotifier = ref.read(downloadProvider.notifier);
    final backupNotifier = ref.read(backupProvider.notifier);
    final Set<String> allAffectedFilenames = {};

    for (int i = 0; i < mods.length; i++) {
      Mod currentMod = mods[i];

      if (state.cancelledBulkAction) {
        break;
      }

      // Yield to UI thread on every iteration to keep app responsive
      await Future.delayed(Duration.zero);

      debugPrint('Downloading & backing up: ${currentMod.saveName}');

      state = state.copyWith(
          currentModNumber: i + 1,
          statusMessage:
              'Downloading & backing up "${currentMod.saveName}" (${i + 1}/${state.totalModNumber})');

      modsNotifier.setSelectedMod(currentMod);
      final downloaded = await downloadNotifier.downloadAllFiles(currentMod);
      allAffectedFilenames.addAll(downloaded);
      currentMod = await modsNotifier.updateSelectedMod(currentMod);

      if (state.cancelledBulkAction) {
        break;
      }

      String modBackupFolder = selectedBackupFolder;
      bool performBackup = true;

      if (currentMod.backupStatus != ExistingBackupStatusEnum.noBackup) {
        switch (backupBehavior) {
          case BulkBackupBehaviorEnum.skip:
            performBackup = false;
            break;

          case BulkBackupBehaviorEnum.replace:
            if (currentMod.backup != null) {
              modBackupFolder = p.dirname(currentMod.backup!.filepath);
            }
            break;

          case BulkBackupBehaviorEnum.replaceIfOutOfDate:
            if (currentMod.backupStatus != ExistingBackupStatusEnum.outOfDate) {
              performBackup = false;
              break;
            }
            if (currentMod.backup != null) {
              modBackupFolder = p.dirname(currentMod.backup!.filepath);
            }
            break;
        }
      }

      final selectedMod = ref.read(selectedModProvider);
      if (selectedMod != null) {
        if (performBackup) {
          await backupNotifier.createBackup(selectedMod, modBackupFolder);
          currentMod = await modsNotifier.updateModBackup(selectedMod);
        }

        // Delete assets after backup if configured
        if (postBackupDeletion != PostBackupDeletionEnum.none) {
          if (state.cancelledBulkAction) {
            break;
          }

          state = state.copyWith(
              statusMessage:
                  'Deleting assets for "${currentMod.saveName}" (${i + 1}/${state.totalModNumber})');

          final deletedFilenames = await ref
              .read(deleteAssetsProvider.notifier)
              .deleteModAssetsAfterBackup(selectedMod, postBackupDeletion);
          allAffectedFilenames.addAll(deletedFilenames);

          if (deletedFilenames.isNotEmpty) {
            await modsNotifier.updateSelectedMod(selectedMod);
          }
        }
      }
    }

    // Refresh other mods that share any of the affected assets
    if (allAffectedFilenames.isNotEmpty) {
      await modsNotifier.refreshModsWithSharedAssets(allAffectedFilenames);
    }

    final wasCancelled = state.cancelledBulkAction;

    _resetState();
    downloadNotifier.resetState();

    // Save the chosen folder as default and reload only after all backups are
    // done, so the reload doesn't disrupt the in-progress backup.
    if (setAsDefaultBackupFolder && !wasCancelled) {
      await ref
          .read(directoriesProvider.notifier)
          .setAsDefaultBackupDirAndReload(selectedBackupFolder);
    }
  }

// MARK: Delete Assets
  Future<void> deleteAssetsAllMods(
    List<Mod> mods,
    PostBackupDeletionEnum deletionOption,
  ) async {
    if (mods.isEmpty) return;

    ref
        .read(logProvider.notifier)
        .addInfo('Starting bulk asset deletion for ${mods.length} mods');

    state = state.copyWith(
      status: BulkActionsStatusEnum.deleteAssetsAll,
      totalModNumber: mods.length,
      statusMessage: 'Deleting assets...',
    );

    final modsNotifier = ref.read(modsProvider.notifier);
    final Set<String> allDeletedFilenames = {};

    for (int i = 0; i < mods.length; i++) {
      final currentMod = mods[i];

      if (state.cancelledBulkAction) {
        break;
      }

      // Yield to UI thread on every iteration to keep app responsive
      await Future.delayed(Duration.zero);

      debugPrint('Deleting assets for: ${currentMod.saveName}');

      state = state.copyWith(
          currentModNumber: i + 1,
          statusMessage:
              'Deleting assets for "${currentMod.saveName}" (${i + 1}/${state.totalModNumber})');

      modsNotifier.setSelectedMod(currentMod);

      final deletedFilenames = await ref
          .read(deleteAssetsProvider.notifier)
          .deleteModAssetsAfterBackup(currentMod, deletionOption);
      allDeletedFilenames.addAll(deletedFilenames);

      if (deletedFilenames.isNotEmpty) {
        await modsNotifier.updateSelectedMod(currentMod);
      }
    }

    // Refresh other mods that share any of the deleted assets
    if (allDeletedFilenames.isNotEmpty) {
      await modsNotifier.refreshModsWithSharedAssets(allDeletedFilenames);
    }

    if (state.cancelledBulkAction) {
      ref.read(logProvider.notifier).addWarning(
          'Bulk asset deletion cancelled (${state.currentModNumber}/${mods.length} completed)');
    } else {
      ref.read(logProvider.notifier).addSuccess(
          'Bulk asset deletion completed: ${mods.length} mods processed');
    }

    _resetState();
  }

// MARK: Check URLs
  Future<void> checkUrlsAllMods(List<Mod> mods, BuildContext context) async {
    if (mods.isEmpty) return;

    // Capture a stable navigator before the loop runs: the first
    // setSelectedMod() collapses the multi-selection, which unmounts
    // MultiSelectView (the BuildContext passed in when invoked from there).
    final navigator = Navigator.of(context, rootNavigator: true);

    ref
        .read(logProvider.notifier)
        .addInfo('Starting bulk URL check for ${mods.length} mods');

    state = state.copyWith(
      status: BulkActionsStatusEnum.checkUrlsAll,
      totalModNumber: mods.length,
      statusMessage: 'Checking URLs...',
    );

    final modsNotifier = ref.read(modsProvider.notifier);
    final downloadNotifier = ref.read(downloadProvider.notifier);
    final results = <ModUrlCheckResult>[];

    for (int i = 0; i < mods.length; i++) {
      final mod = mods[i];

      if (state.cancelledBulkAction) {
        break;
      }

      // Yield to UI thread on every iteration to keep app responsive
      await Future.delayed(Duration.zero);

      debugPrint('Checking URLs: ${mod.saveName}');

      state = state.copyWith(
          currentModNumber: i + 1,
          statusMessage:
              'Checking URLs for "${mod.saveName}" (${i + 1}/${state.totalModNumber})');

      modsNotifier.setSelectedMod(mod);

      final invalidUrls = await downloadNotifier.checkModUrlsLive(mod);

      results.add(ModUrlCheckResult(
        modName: mod.saveName,
        invalidUrls: invalidUrls ?? const [],
        cancelled: invalidUrls == null,
      ));
    }

    final wasCancelled = state.cancelledBulkAction;

    if (wasCancelled) {
      ref.read(logProvider.notifier).addWarning(
          'Bulk URL check cancelled (${state.currentModNumber}/${mods.length} completed)');
    } else {
      ref
          .read(logProvider.notifier)
          .addSuccess('Bulk URL check completed: ${mods.length} mods checked');
    }

    _resetState();
    downloadNotifier.resetState();

    if (navigator.mounted) {
      showDialog(
        context: navigator.context,
        builder: (context) => BulkUrlCheckResultsDialog(
          results: results,
          wasCancelled: wasCancelled,
        ),
      );
    }
  }

// MARK: Update URLs
  Future<void> updateUrlPrefixesAllMods(
    List<Mod> mods,
    List<String> oldPrefixes,
    String newPrefix,
    bool renameFile,
  ) async {
    state = state.copyWith(
      status: BulkActionsStatusEnum.updateUrls,
      totalModNumber: mods.length,
    );

    Map<String, Map<String, String>> allModUrlsData = {};

    for (int i = 0; i < mods.length; i++) {
      final mod = mods[i];

      if (state.cancelledBulkAction) {
        break;
      }

      // Yield to UI thread on every iteration to keep app responsive
      await Future.delayed(Duration.zero);

      debugPrint('Updating URLs: ${mod.saveName}');

      state = state.copyWith(
          currentModNumber: i + 1,
          statusMessage:
              'Updating URLs for "${mod.saveName}" (${i + 1}/${state.totalModNumber})');

      final assets = Map.fromEntries(
          mod.getAllAssets().map((a) => MapEntry(a.url, a.filePath)));
      final modJsonFilePath = mod.jsonFilePath;

      final result = await compute(
        updateUrlPrefixesFilesIsolate,
        UpdateUrlPrefixesParams(
          modJsonFilePath,
          oldPrefixes,
          newPrefix,
          renameFile,
          assets,
        ),
      );

      if (result.updated) {
        final jsonURLs = extractUrlsFromJsonString(result.jsonString);
        allModUrlsData[mod.jsonFileName] = jsonURLs;
      }
    }

    if (allModUrlsData.isNotEmpty) {
      await ref.read(storageProvider).saveAllModUrlsData(allModUrlsData);
    }

    _resetState();
    ref.read(loaderProvider).refreshAppData();
  }

// MARK: Update mods
  Future<void> updateModsAll(
    List<Mod> mods,
    bool forceUpdate,
    BuildContext context,
  ) async {
    // Capture a stable navigator before the loop runs: the first
    // setSelectedMod() collapses the multi-selection, which unmounts
    // MultiSelectView (the BuildContext passed in when invoked from there).
    final navigator = Navigator.of(context, rootNavigator: true);

    state = state.copyWith(
      status: BulkActionsStatusEnum.updateModsAll,
      totalModNumber: mods.length,
      statusMessage: 'Checking for mod updates...',
    );

    final downloadNotifier = ref.read(downloadProvider.notifier);
    final allResults = <ModUpdateResult>[];

    debugPrint('Updating ${mods.length} mods');

    for (int i = 0; i < mods.length; i++) {
      final mod = mods[i];

      if (state.cancelledBulkAction) {
        // Add cancelled status for remaining mods
        for (int j = i; j < mods.length; j++) {
          final remainingMod = mods[j];
          allResults.add(ModUpdateResult(
            modId: remainingMod.jsonFileName.replaceAll('.json', ''),
            modName: remainingMod.saveName,
            status: ModUpdateStatus.failed,
            errorMessage: 'Cancelled by user',
          ));
        }
        break;
      }

      // Yield to UI thread to keep app responsive
      await Future.delayed(Duration.zero);

      debugPrint('Updating mod: ${mod.saveName}');

      state = state.copyWith(
          currentModNumber: i + 1,
          statusMessage:
              'Updating "${mod.saveName}" (${i + 1}/${state.totalModNumber})');

      ref.read(modsProvider.notifier).setSelectedMod(mod);

      final result = await downloadNotifier.downloadModUpdates(
        mods: [mod],
        forceUpdate: forceUpdate,
      );

      // Accumulate results
      allResults.addAll(result.results);

      debugPrint('Update result: ${result.summaryMessage}');
    }

    final cancelled = state.cancelledBulkAction;
    _resetState();

    // Show results dialog
    if (navigator.mounted) {
      showDialog(
        context: navigator.context,
        builder: (context) => BulkUpdateResultsDialog(
          results: allResults,
          wasCancelled: cancelled,
        ),
      );
    }
  }

  // MARK: Import
  Future<void> importBackups({
    String? filePath,
    Future<JsonConflictChoice> Function(JsonImportConflict conflict)?
        onJsonConflict,
    String? targetJsonDir,
  }) async {
    state = state.copyWith(
        status: BulkActionsStatusEnum.importingBackups,
        statusMessage: 'Select TTSMOD files to import');

    final List<String> filePaths;

    if (filePath != null && filePath.isNotEmpty) {
      // Use the provided filepath directly
      filePaths = [filePath];
    } else {
      // Show file picker
      final backupsDir = ref.read(directoriesProvider).backupsDir;

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        lockParentWindow: true,
        initialDirectory: backupsDir.isEmpty ? null : backupsDir,
        allowedExtensions: ['ttsmod'],
        allowMultiple: true,
      );

      if (result == null || result.files.isEmpty) {
        _resetState();
        return;
      }

      filePaths = result.files
          .map((f) => f.path)
          .where((p) => p != null && p.isNotEmpty)
          .cast<String>()
          .toList();
    }

    if (filePaths.isEmpty) {
      _resetState();
      return;
    }

    final Set<String> allImportedFilenames = {};

    for (int i = 0; i < filePaths.length; i++) {
      final path = filePaths[i];

      if (state.cancelledBulkAction) {
        break;
      }

      // Yield to UI thread on every iteration to keep app responsive
      await Future.delayed(Duration.zero);

      final fileName = p.basenameWithoutExtension(path);
      debugPrint('Importing: $fileName');

      state = state.copyWith(
          currentModNumber: i + 1,
          totalModNumber: filePaths.length,
          statusMessage:
              'Importing "$fileName" (${i + 1}/${filePaths.length})');

      final importedFilenames =
          await ref.read(importBackupProvider.notifier).importBackupFromPath(
                path,
                onJsonConflict: onJsonConflict,
                targetJsonDir: targetJsonDir,
              );
      allImportedFilenames.addAll(importedFilenames);
    }

    // Refresh other mods that share any of the imported assets
    if (allImportedFilenames.isNotEmpty) {
      await ref
          .read(modsProvider.notifier)
          .refreshModsWithSharedAssets(allImportedFilenames);
    }

    _resetState();
  }

  // MARK: Cancel
  Future<void> cancelBulkAction() async {
    switch (state.status) {
      case BulkActionsStatusEnum.idle:
        break;

      case BulkActionsStatusEnum.updateUrls:
        _cancelUpdateUrls();
        break;

      case BulkActionsStatusEnum.downloadAll:
        _cancelDownloadAll();
        break;

      case BulkActionsStatusEnum.backupAll:
        _cancelAllBackups();
        break;

      case BulkActionsStatusEnum.downloadAndBackupAll:
        _cancelDownloadAndBackupAll();
        break;

      case BulkActionsStatusEnum.updateModsAll:
        _cancelUpdateModsAll();
        break;

      case BulkActionsStatusEnum.importingBackups:
        _cancelImportingBackups();
        break;

      case BulkActionsStatusEnum.deleteAssetsAll:
        _cancelDeleteAssetsAll();
        break;

      case BulkActionsStatusEnum.checkUrlsAll:
        _cancelCheckUrlsAll();
        break;
    }
  }

  void _cancelCheckUrlsAll() {
    ref.read(downloadProvider.notifier).cancelAllDownloads();

    state = state.copyWith(
      cancelledBulkAction: true,
      statusMessage:
          "Cancelling URL check for all ${ref.read(selectedModTypeProvider).label}s",
    );
  }

  void _cancelDownloadAll() {
    ref.read(downloadProvider.notifier).cancelAllDownloads();

    state = state.copyWith(
      cancelledBulkAction: true,
      statusMessage:
          "Cancelling download of all ${ref.read(selectedModTypeProvider).label}s",
    );
  }

  void _cancelImportingBackups() {
    state = state.copyWith(
      cancelledBulkAction: true,
      statusMessage: "Cancelling importing backups",
    );
  }

  Future<void> _cancelAllBackups() async {
    state = state.copyWith(
      cancelledBulkAction: true,
      statusMessage:
          "Cancelling backup of all ${ref.read(selectedModTypeProvider).label}s",
    );
  }

  Future<void> _cancelUpdateUrls() async {
    state = state.copyWith(
      cancelledBulkAction: true,
      statusMessage:
          "Cancelling URL update for all ${ref.read(selectedModTypeProvider).label}s",
    );
  }

  Future<void> _cancelDownloadAndBackupAll() async {
    if (ref.read(backupProvider).status == BackupStatusEnum.idle) {
      ref.read(downloadProvider.notifier).cancelAllDownloads();
    }

    state = state.copyWith(
      cancelledBulkAction: true,
      statusMessage:
          "Cancelling download & backup of all ${ref.read(selectedModTypeProvider).label}s",
    );
  }

  Future<void> _cancelUpdateModsAll() async {
    state = state.copyWith(
        cancelledBulkAction: true, statusMessage: "Cancelling updating mods");
  }

  void _cancelDeleteAssetsAll() {
    state = state.copyWith(
      cancelledBulkAction: true,
      statusMessage:
          "Cancelling asset deletion for all ${ref.read(selectedModTypeProvider).label}s",
    );
  }
}
