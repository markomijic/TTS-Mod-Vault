import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/src/state/asset/existing_assets_state.dart';
import 'package:tts_mod_vault/src/state/asset/existing_assets.dart';
import 'package:tts_mod_vault/src/state/backup/backup_state.dart';
import 'package:tts_mod_vault/src/state/backup/backup.dart';
import 'package:tts_mod_vault/src/state/backup/existing_backups.dart';
import 'package:tts_mod_vault/src/state/backup/existing_backups_state.dart';
import 'package:tts_mod_vault/src/state/backup/import_backup.dart';
import 'package:tts_mod_vault/src/state/backup/import_backup_state.dart';
import 'package:tts_mod_vault/src/state/bulk_actions/bulk_actions.dart';
import 'package:tts_mod_vault/src/state/bulk_actions/bulk_actions_state.dart';
import 'package:tts_mod_vault/src/state/cleanup/cleanup.dart';
import 'package:tts_mod_vault/src/state/cleanup/cleanup_state.dart';
import 'package:tts_mod_vault/src/state/directories/directories.dart';
import 'package:tts_mod_vault/src/state/directories/directories_state.dart';
import 'package:tts_mod_vault/src/state/download/download.dart';
import 'package:tts_mod_vault/src/state/download/download_state.dart';
import 'package:tts_mod_vault/src/state/loader/loader.dart';
import 'package:tts_mod_vault/src/state/mods/mod_model.dart';
import 'package:tts_mod_vault/src/state/mods/mods_state.dart';
import 'package:tts_mod_vault/src/state/mods/mods.dart';
import 'package:tts_mod_vault/src/state/settings/settings.dart';
import 'package:tts_mod_vault/src/state/settings/settings_state.dart';
import 'package:tts_mod_vault/src/state/sort_and_filter/sort_and_filter.dart';
import 'package:tts_mod_vault/src/state/sort_and_filter/sort_and_filter_state.dart';
import 'package:tts_mod_vault/src/state/storage/storage.dart';

final selectedModProvider = StateProvider<Mod?>((ref) => null);

final searchQueryProvider = StateProvider<String>((ref) => '');

final selectedModTypeProvider =
    StateProvider<ModTypeEnum>((ref) => ModTypeEnum.mod);

final loadingMessageProvider = StateProvider<String>((ref) => 'Loading');

final selectedUrlProvider = StateProvider<String>((ref) => '');

final storageProvider = Provider((ref) => Storage());

final directoriesProvider =
    StateNotifierProvider<DirectoriesNotifier, DirectoriesState>(
  (ref) => DirectoriesNotifier(ref),
);

final existingAssetListsProvider =
    StateNotifierProvider<ExistingAssetsNotifier, ExistingAssetsListsState>(
  (ref) => ExistingAssetsNotifier(ref),
);

final existingBackupsProvider =
    StateNotifierProvider<ExistingBackupsStateNotifier, ExistingBackupsState>(
  (ref) => ExistingBackupsStateNotifier(ref),
);

final loaderProvider = Provider<LoaderNotifier>((ref) {
  return LoaderNotifier(ref);
});

final modsProvider = AsyncNotifierProvider<ModsStateNotifier, ModsState>(
    () => ModsStateNotifier());

final downloadProvider = StateNotifierProvider<DownloadNotifier, DownloadState>(
  (ref) => DownloadNotifier(ref),
);

final cleanupProvider = StateNotifierProvider<CleanupNotifier, CleanUpState>(
  (ref) => CleanupNotifier(ref),
);

final backupProvider = StateNotifierProvider<BackupNotifier, BackupState>(
  (ref) => BackupNotifier(ref),
);

final importBackupProvider =
    StateNotifierProvider<ImportBackupNotifier, ImportBackupState>(
  (ref) => ImportBackupNotifier(ref),
);

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>(
  (ref) => SettingsNotifier(ref),
);

final bulkActionsProvider =
    StateNotifierProvider<BulkActionsNotifier, BulkActionsState>(
  (ref) => BulkActionsNotifier(ref),
);

final sortAndFilterProvider =
    StateNotifierProvider<SortAndFilterNotifier, SortAndFilterState>(
  (ref) => SortAndFilterNotifier(ref),
);

final actionInProgressProvider = Provider<bool>((ref) {
  final modsAsyncValue = ref.watch(modsProvider);
  final downloading = ref.watch(downloadProvider).downloading;
  final bulkActionStatus = ref.watch(bulkActionsProvider).status;
  final cleanUpStatus = ref.watch(cleanupProvider).status;
  final backupStatus = ref.watch(backupProvider).status;
  final importBackupStatus = ref.watch(importBackupProvider).status;

  return cleanUpStatus != CleanUpStatusEnum.idle ||
      backupStatus != BackupStatusEnum.idle ||
      importBackupStatus != ImportBackupStatusEnum.idle ||
      bulkActionStatus != BulkActionsStatusEnum.idle ||
      downloading ||
      modsAsyncValue is AsyncLoading;
});

final filteredModsProvider = Provider<List<Mod>>((ref) {
  final searchQuery = ref.watch(searchQueryProvider);
  final sortAndFilter = ref.watch(sortAndFilterProvider);
  final selectedBackupStatuses =
      ref.watch(sortAndFilterProvider).filteredBackupStatuses;
  final selectedModType = ref.watch(selectedModTypeProvider);
  final modsState = ref.watch(modsProvider).unwrapPrevious().valueOrNull;

  if (modsState == null) {
    return [];
  }

  List<Mod> mods = switch (selectedModType) {
    ModTypeEnum.mod => modsState.mods,
    ModTypeEnum.save => modsState.saves,
    ModTypeEnum.savedObject => modsState.savedObjects,
  };

  Set<String> selectedFolders = switch (selectedModType) {
    ModTypeEnum.mod => sortAndFilter.filteredModsFolders,
    ModTypeEnum.save => sortAndFilter.filteredSavesFolders,
    ModTypeEnum.savedObject => sortAndFilter.filteredSavesFolders,
  };

  // Filter mods
  List<Mod> filteredMods = mods.where((mod) {
    if (searchQuery.isNotEmpty) {
      if (!mod.saveName.toLowerCase().contains(searchQuery.toLowerCase())) {
        return false; // Exclude if doesn't match search
      }
    }

    if (selectedFolders.isNotEmpty) {
      if (!selectedFolders.contains(mod.parentFolderName)) {
        return false; // Exclude if not in selected folders
      }
    }

    if (selectedBackupStatuses.isNotEmpty) {
      if (!selectedBackupStatuses.contains(mod.backupStatus)) {
        return false; // Exclude if not in selected backup statuses
      }
    }

    return true;
  }).toList();

  // Sort mods
  switch (sortAndFilter.sortOption) {
    case SortOptionEnum.alphabeticalAsc:
      filteredMods.sort((a, b) =>
          a.saveName.toLowerCase().compareTo(b.saveName.toLowerCase()));
      break;
    case SortOptionEnum.dateCreatedDesc:
      filteredMods
          .sort((a, b) => b.createdAtTimestamp.compareTo(a.createdAtTimestamp));
      break;
    case SortOptionEnum.missingAssets:
      filteredMods.sort((a, b) =>
          (b.missingAssetCount ?? 0).compareTo(a.missingAssetCount ?? 0));
  }

  return filteredMods;
});
