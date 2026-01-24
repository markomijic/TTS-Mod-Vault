import 'package:file_picker/file_picker.dart' show FilePicker, FileType;
import 'package:flutter/foundation.dart' show compute, debugPrint;
import 'package:flutter/material.dart' show BuildContext, showDialog;
import 'package:hooks_riverpod/hooks_riverpod.dart' show Ref, StateNotifier;
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show BulkUpdateResultsDialog;
import 'package:tts_mod_vault/src/state/backup/backup_state.dart'
    show BackupStatusEnum;
import 'package:tts_mod_vault/src/state/backup/backup_status_enum.dart'
    show ExistingBackupStatusEnum;
import 'package:tts_mod_vault/src/state/bulk_actions/bulk_actions_state.dart'
    show BulkActionsState, BulkActionsStatusEnum, BulkBackupBehaviorEnum;
import 'package:tts_mod_vault/src/state/bulk_actions/mod_update_result.dart'
    show ModUpdateResult, ModUpdateStatus;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show Mod;
import 'package:tts_mod_vault/src/state/mods/mods_isolates.dart'
    show
        updateUrlPrefixesFilesIsolate,
        UpdateUrlPrefixesParams,
        extractUrlsFromJsonString;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        backupProvider,
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
      await downloadNotifier.downloadAllFiles(mod);
      await modsNotifier.updateSelectedMod(mod);
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

    for (int i = 0; i < mods.length; i++) {
      final mod = mods[i];

      if (state.cancelledBulkAction) {
        break;
      }

      // Yield to UI thread on every iteration to keep app responsive
      await Future.delayed(Duration.zero);

      String modBackupFolder = selectedBackupFolder;

      if (mod.backupStatus != ExistingBackupStatusEnum.noBackup) {
        switch (backupBehavior) {
          case BulkBackupBehaviorEnum.skip:
            continue;

          case BulkBackupBehaviorEnum.replace:
            if (mod.backup != null) {
              modBackupFolder = p.dirname(mod.backup!.filepath);
            }
            break;

          case BulkBackupBehaviorEnum.replaceIfOutOfDate:
            if (mod.backupStatus != ExistingBackupStatusEnum.outOfDate) {
              continue;
            }
            if (mod.backup != null) {
              modBackupFolder = p.dirname(mod.backup!.filepath);
            }
            break;
        }
      }

      debugPrint('Backing up: ${mod.saveName}');

      state = state.copyWith(
          currentModNumber: i + 1,
          statusMessage:
              'Backing up "${mod.saveName}" (${i + 1}/${state.totalModNumber})');

      modsNotifier.setSelectedMod(mod);
      await backupNotifier.createBackup(mod, modBackupFolder);
      modsNotifier.updateModBackup(mod);
    }

    if (state.cancelledBulkAction) {
      ref.read(logProvider.notifier).addWarning(
          'Bulk backup cancelled (${state.currentModNumber}/${mods.length} completed)');
    } else {
      ref.read(logProvider.notifier).addSuccess(
          'Bulk backup completed: ${state.currentModNumber} mods backed up');
    }

    _resetState();
  }

// MARK: DL & Backup
  Future<void> downloadAndBackupAllMods(
    List<Mod> mods,
    BulkBackupBehaviorEnum backupBehavior,
    String? folder,
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

    for (int i = 0; i < mods.length; i++) {
      final mod = mods[i];

      if (state.cancelledBulkAction) {
        break;
      }

      // Yield to UI thread on every iteration to keep app responsive
      await Future.delayed(Duration.zero);

      debugPrint('Downloading & backing up: ${mod.saveName}');

      state = state.copyWith(
          currentModNumber: i + 1,
          statusMessage:
              'Downloading & backing up "${mod.saveName}" (${i + 1}/${state.totalModNumber})');

      modsNotifier.setSelectedMod(mod);
      await downloadNotifier.downloadAllFiles(mod);
      await modsNotifier.updateSelectedMod(mod);

      if (state.cancelledBulkAction) {
        break;
      }

      String modBackupFolder = selectedBackupFolder;

      if (mod.backupStatus != ExistingBackupStatusEnum.noBackup) {
        switch (backupBehavior) {
          case BulkBackupBehaviorEnum.skip:
            continue;

          case BulkBackupBehaviorEnum.replace:
            if (mod.backup != null) {
              modBackupFolder = p.dirname(mod.backup!.filepath);
            }
            break;

          case BulkBackupBehaviorEnum.replaceIfOutOfDate:
            if (mod.backupStatus != ExistingBackupStatusEnum.outOfDate) {
              continue;
            }
            if (mod.backup != null) {
              modBackupFolder = p.dirname(mod.backup!.filepath);
            }
            break;
        }
      }

      final selectedMod = ref.read(selectedModProvider);
      if (selectedMod != null) {
        await backupNotifier.createBackup(selectedMod, modBackupFolder);
        modsNotifier.updateModBackup(selectedMod);
      }
    }

    _resetState();
    downloadNotifier.resetState();
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
    if (context.mounted) {
      showDialog(
        context: context,
        builder: (context) => BulkUpdateResultsDialog(
          results: allResults,
          wasCancelled: cancelled,
        ),
      );
    }
  }

  // MARK: Import
  Future<void> importBackups() async {
    state = state.copyWith(
        status: BulkActionsStatusEnum.importingBackups,
        statusMessage: 'Select TTSMOD files to import');

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

    for (int i = 0; i < result.files.length; i++) {
      final filePath = result.files[i].path;

      if (filePath == null || filePath.isEmpty) continue;

      if (state.cancelledBulkAction) {
        break;
      }

      // Yield to UI thread on every iteration to keep app responsive
      await Future.delayed(Duration.zero);

      final fileName = p.basenameWithoutExtension(filePath);
      debugPrint('Importing: $fileName');

      state = state.copyWith(
          currentModNumber: i + 1,
          totalModNumber: result.files.length,
          statusMessage:
              'Importing "$fileName" (${i + 1}/${result.files.length})');

      await ref
          .read(importBackupProvider.notifier)
          .importBackupFromPath(filePath);
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
    }
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
}
