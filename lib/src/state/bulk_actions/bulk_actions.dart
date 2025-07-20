import 'package:file_picker/file_picker.dart' show FilePicker;
import 'package:flutter/material.dart' show debugPrint;
import 'package:hooks_riverpod/hooks_riverpod.dart' show Ref, StateNotifier;
import 'package:tts_mod_vault/src/state/backup/backup_state.dart'
    show BackupStatusEnum;
import 'package:tts_mod_vault/src/state/bulk_actions/bulk_actions_state.dart'
    show BulkActionEnum, BulkActionsState;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show Mod;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        backupProvider,
        directoriesProvider,
        downloadProvider,
        modsProvider,
        selectedModProvider;

class BulkActionsNotifier extends StateNotifier<BulkActionsState> {
  final Ref ref;

  BulkActionsNotifier(this.ref) : super(const BulkActionsState());

  void _resetState() {
    state = BulkActionsState(
      status: BulkActionEnum.idle,
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
      status: BulkActionEnum.downloadAll,
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
              'Downloading all mods (${mods.indexOf(mod) + 1}/${state.totalModNumber})');

      final completeMod =
          await ref.read(modsProvider.notifier).getCardMod(mod.jsonFileName);

      ref.read(modsProvider.notifier).setSelectedMod(completeMod);
      await ref.read(downloadProvider.notifier).downloadAllFiles(completeMod);
      await ref.read(modsProvider.notifier).updateSelectedMod(completeMod);
    }

    _resetState();
    ref.read(downloadProvider.notifier).resetState();
  }

  Future<void> backupAllMods(List<Mod> mods) async {
    state = state.copyWith(
      status: BulkActionEnum.backupAll,
      totalModNumber: mods.length,
      statusMessage: "Select a folder to backup all mods",
    );

    final backupFolder = await _getBackupFolder();
    if (backupFolder == null) {
      _resetState();
      return;
    }

    for (final mod in mods) {
      if (state.cancelledBulkAction) {
        continue;
      }

      debugPrint('Backing up: ${mod.saveName}');

      state = state.copyWith(
          currentModNumber: mods.indexOf(mod) + 1,
          statusMessage:
              'Backing up all mods (${mods.indexOf(mod) + 1}/${state.totalModNumber})');

      final completeMod =
          await ref.read(modsProvider.notifier).getCardMod(mod.jsonFileName);

      ref.read(modsProvider.notifier).setSelectedMod(completeMod);
      await ref
          .read(backupProvider.notifier)
          .createBackup(completeMod, backupFolder);
    }

    _resetState();
  }

  Future<void> downloadAndBackupAllMods(List<Mod> mods) async {
    state = state.copyWith(
      status: BulkActionEnum.downloadAndBackupAll,
      totalModNumber: mods.length,
      statusMessage: "Select a folder to backup all mods",
    );

    final backupFolder = await _getBackupFolder();
    if (backupFolder == null) {
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
              'Downloading & backing up all mods (${mods.indexOf(mod) + 1}/${state.totalModNumber})');

      final completeMod =
          await ref.read(modsProvider.notifier).getCardMod(mod.jsonFileName);
      ref.read(modsProvider.notifier).setSelectedMod(completeMod);

      await ref.read(downloadProvider.notifier).downloadAllFiles(completeMod);
      await ref.read(modsProvider.notifier).updateSelectedMod(completeMod);

      if (state.cancelledBulkAction) {
        continue;
      }

      final selectedMod = ref.read(selectedModProvider);
      if (selectedMod != null) {
        await ref
            .read(backupProvider.notifier)
            .createBackup(selectedMod, backupFolder);
      }
    }

    _resetState();
    ref.read(downloadProvider.notifier).resetState();
  }

  // Cancel methods
  Future<void> cancelBulkAction() async {
    switch (state.status) {
      case BulkActionEnum.idle:
        break;

      case BulkActionEnum.downloadAll:
        _cancelDownloadAll();
        break;

      case BulkActionEnum.backupAll:
        _cancelAllBackups();
        break;

      case BulkActionEnum.downloadAndBackupAll:
        _cancelDownloadAndBackupAll();
        break;
    }
  }

  void _cancelDownloadAll() {
    ref.read(downloadProvider.notifier).cancelAllDownloads();

    state = state.copyWith(
      cancelledBulkAction: true,
      statusMessage: "Cancelling all downloads",
    );
  }

  void _cancelAllBackups() async {
    state = state.copyWith(
      cancelledBulkAction: true,
      statusMessage: "Cancelling backing up all mods",
    );
  }

  void _cancelDownloadAndBackupAll() async {
    if (ref.read(backupProvider).status == BackupStatusEnum.idle) {
      ref.read(downloadProvider.notifier).cancelAllDownloads();
    }

    state = state.copyWith(
      cancelledBulkAction: true,
      statusMessage: "Cancelling downloading & backing up all mods",
    );
  }
}
