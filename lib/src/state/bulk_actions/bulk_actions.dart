import 'package:file_picker/file_picker.dart' show FilePicker;
import 'package:flutter/foundation.dart' show compute, debugPrint;
import 'package:hooks_riverpod/hooks_riverpod.dart' show Ref, StateNotifier;
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/src/state/backup/backup_state.dart'
    show BackupStatusEnum;
import 'package:tts_mod_vault/src/state/backup/backup_status_enum.dart'
    show ExistingBackupStatusEnum;
import 'package:tts_mod_vault/src/state/bulk_actions/bulk_actions_state.dart'
    show BulkActionsState, BulkActionsStatusEnum, BulkBackupBehaviorEnum;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show Mod;
import 'package:tts_mod_vault/src/state/mods/mods_isolates.dart';
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        backupProvider,
        directoriesProvider,
        downloadProvider,
        loaderProvider,
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

  // Bulk actions methods
  Future<void> downloadAllMods(List<Mod> mods) async {
    state = state.copyWith(
      status: BulkActionsStatusEnum.downloadAll,
      totalModNumber: mods.length,
    );

    for (final mod in mods) {
      if (state.cancelledBulkAction) {
        continue;
      }

      debugPrint('Downloading: ${mod.saveName}');

      state = state.copyWith(
          currentModNumber: mods.indexOf(mod) + 1,
          statusMessage:
              'Downloading all ${ref.read(selectedModTypeProvider).label}s (${mods.indexOf(mod) + 1}/${state.totalModNumber})');

      final modUrls = await ref.read(modsProvider.notifier).getUrlsByMod(mod);
      final completeMod =
          await ref.read(modsProvider.notifier).getCompleteMod(mod, modUrls);

      ref.read(modsProvider.notifier).setSelectedMod(completeMod);
      await ref.read(downloadProvider.notifier).downloadAllFiles(completeMod);
      await ref.read(modsProvider.notifier).updateSelectedMod(completeMod);
    }

    _resetState();
    ref.read(downloadProvider.notifier).resetState();
  }

  Future<void> backupAllMods(
    List<Mod> mods,
    BulkBackupBehaviorEnum backupBehavior,
    String? folder,
  ) async {
    state = state.copyWith(
      status: BulkActionsStatusEnum.backupAll,
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

    for (final mod in mods) {
      if (state.cancelledBulkAction) {
        continue;
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

      debugPrint('Backing up: ${mod.saveName}');

      state = state.copyWith(
          currentModNumber: mods.indexOf(mod) + 1,
          statusMessage:
              'Backing up all ${ref.read(selectedModTypeProvider).label}s (${mods.indexOf(mod) + 1}/${state.totalModNumber})');

      final modUrls = await ref.read(modsProvider.notifier).getUrlsByMod(mod);
      final completeMod =
          await ref.read(modsProvider.notifier).getCompleteMod(mod, modUrls);

      ref.read(modsProvider.notifier).setSelectedMod(completeMod);
      await ref
          .read(backupProvider.notifier)
          .createBackup(completeMod, modBackupFolder);
      await ref.read(modsProvider.notifier).updateSelectedMod(completeMod);
    }

    _resetState();
  }

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

    for (final mod in mods) {
      if (state.cancelledBulkAction) {
        continue;
      }

      debugPrint('Downloading & backing up: ${mod.saveName}');

      state = state.copyWith(
          currentModNumber: mods.indexOf(mod) + 1,
          statusMessage:
              'Downloading & backing up all ${ref.read(selectedModTypeProvider).label}s (${mods.indexOf(mod) + 1}/${state.totalModNumber})');

      final modUrls = await ref.read(modsProvider.notifier).getUrlsByMod(mod);
      final completeMod =
          await ref.read(modsProvider.notifier).getCompleteMod(mod, modUrls);
      ref.read(modsProvider.notifier).setSelectedMod(completeMod);

      await ref.read(downloadProvider.notifier).downloadAllFiles(completeMod);
      await ref.read(modsProvider.notifier).updateSelectedMod(completeMod);

      if (state.cancelledBulkAction) {
        continue;
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
        await ref
            .read(backupProvider.notifier)
            .createBackup(selectedMod, modBackupFolder);
        await ref.read(modsProvider.notifier).updateSelectedMod(selectedMod);
      }
    }

    _resetState();
    ref.read(downloadProvider.notifier).resetState();
  }

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

    for (final mod in mods) {
      if (state.cancelledBulkAction) {
        continue;
      }

      debugPrint('Updating URLs: ${mod.saveName}');

      state = state.copyWith(
          currentModNumber: mods.indexOf(mod) + 1,
          statusMessage:
              'Updating URLs of all ${ref.read(selectedModTypeProvider).label}s (${mods.indexOf(mod) + 1}/${state.totalModNumber})');

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

  // Cancel methods
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

  void _cancelAllBackups() async {
    state = state.copyWith(
      cancelledBulkAction: true,
      statusMessage:
          "Cancelling backup of all ${ref.read(selectedModTypeProvider).label}s",
    );
  }

  void _cancelUpdateUrls() async {
    state = state.copyWith(
      cancelledBulkAction: true,
      statusMessage:
          "Cancelling URL update for all ${ref.read(selectedModTypeProvider).label}s",
    );
  }

  void _cancelDownloadAndBackupAll() async {
    if (ref.read(backupProvider).status == BackupStatusEnum.idle) {
      ref.read(downloadProvider.notifier).cancelAllDownloads();
    }

    state = state.copyWith(
      cancelledBulkAction: true,
      statusMessage:
          "Cancelling download & backup of all ${ref.read(selectedModTypeProvider).label}s",
    );
  }
}
