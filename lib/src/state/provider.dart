import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/src/models/log_entry.dart';
import 'package:tts_mod_vault/src/providers/log_provider.dart';
import 'package:tts_mod_vault/src/state/asset/existing_assets_state.dart';
import 'package:tts_mod_vault/src/state/asset/existing_assets.dart';
import 'package:tts_mod_vault/src/state/backup/backup_cache.dart';
import 'package:tts_mod_vault/src/state/backup/backup_state.dart';
import 'package:tts_mod_vault/src/state/backup/backup.dart';
import 'package:tts_mod_vault/src/state/backup/existing_backups.dart';
import 'package:tts_mod_vault/src/state/backup/existing_backups_state.dart';
import 'package:tts_mod_vault/src/state/backup/import_backup.dart';
import 'package:tts_mod_vault/src/state/backup/import_backup_state.dart';
import 'package:tts_mod_vault/src/state/backup/models/existing_backup_model.dart';
import 'package:tts_mod_vault/src/state/bulk_actions/bulk_actions.dart';
import 'package:tts_mod_vault/src/state/bulk_actions/bulk_actions_state.dart';
import 'package:tts_mod_vault/src/state/cleanup/cleanup.dart';
import 'package:tts_mod_vault/src/state/cleanup/cleanup_state.dart';
import 'package:tts_mod_vault/src/state/delete_assets/delete_assets.dart';
import 'package:tts_mod_vault/src/state/delete_assets/delete_assets_state.dart';
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
import 'package:tts_mod_vault/src/state/sort_and_filter/backup_sort_and_filter.dart';
import 'package:tts_mod_vault/src/state/sort_and_filter/backup_sort_and_filter_state.dart';
import 'package:tts_mod_vault/src/state/sort_and_filter/sort_and_filter.dart';
import 'package:tts_mod_vault/src/state/sort_and_filter/sort_and_filter_state.dart';
import 'package:tts_mod_vault/src/state/storage/storage.dart';

enum AppPage { mods, backups }

final logProvider = StateNotifierProvider<LogNotifier, List<LogEntry>>((ref) {
  return LogNotifier();
});

final filteredLogProvider =
    Provider.family<List<LogEntry>, String>((ref, searchQuery) {
  final logs = ref.watch(logProvider);

  if (searchQuery.isEmpty) {
    return logs;
  }

  final lowerQuery = searchQuery.toLowerCase();
  return logs.where((entry) {
    return entry.message.toLowerCase().contains(lowerQuery) ||
        entry.formattedTimestamp.contains(lowerQuery);
  }).toList();
});

final selectedPageProvider = StateProvider<AppPage>((ref) => AppPage.mods);

final multiModsProvider = StateProvider<Set<String>>((ref) => {});

final selectedModProvider = Provider<Mod?>((ref) {
  final paths = ref.watch(multiModsProvider);
  if (paths.isEmpty) return null;

  final modsState = ref.watch(modsProvider);
  if (!modsState.hasValue) return null;

  final modType = ref.watch(selectedModTypeProvider);
  final selectedPath = paths.first;
  final data = modsState.value!;

  final list = switch (modType) {
    ModTypeEnum.mod => data.mods,
    ModTypeEnum.save => data.saves,
    ModTypeEnum.savedObject => data.savedObjects,
  };

  for (final mod in list) {
    if (mod.jsonFilePath == selectedPath) return mod;
  }
  return null;
});

final selectedModsListProvider = Provider<List<Mod>>((ref) {
  final paths = ref.watch(multiModsProvider);
  if (paths.isEmpty) return [];

  final modsState = ref.watch(modsProvider);
  if (!modsState.hasValue) return [];

  final modType = ref.watch(selectedModTypeProvider);
  final data = modsState.value!;

  final list = switch (modType) {
    ModTypeEnum.mod => data.mods,
    ModTypeEnum.save => data.saves,
    ModTypeEnum.savedObject => data.savedObjects,
  };

  final modsByPath = {for (final mod in list) mod.jsonFilePath: mod};
  return paths.map((p) => modsByPath[p]).whereType<Mod>().toList();
});

// Separate search queries for each page
final modsSearchQueryProvider = StateProvider<String>((ref) => '');
final backupsSearchQueryProvider = StateProvider<String>((ref) => '');

final selectedModTypeProvider =
    StateProvider<ModTypeEnum>((ref) => ModTypeEnum.mod);

final loadingMessageProvider = StateProvider<String>((ref) => 'Loading');

final selectedUrlProvider = StateProvider<String>((ref) => '');

final storageProvider = Provider((ref) => Storage());

final backupCacheProvider = Provider((ref) => BackupCache());

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

final deleteAssetsProvider =
    NotifierProvider<DeleteAssetsNotifier, DeleteAssetsState>(
  () => DeleteAssetsNotifier(),
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

final refreshingSharedAssetsProvider = StateProvider<bool>((ref) => false);

final actionInProgressProvider = Provider<bool>((ref) {
  final modsAsyncValue = ref.watch(modsProvider);
  final isDownloading = ref.watch(downloadProvider).isDownloading;
  final bulkActionStatus = ref.watch(bulkActionsProvider).status;
  final cleanUpStatus = ref.watch(cleanupProvider).status;
  final deleteAssetsStatus = ref.watch(deleteAssetsProvider).status;
  final backupStatus = ref.watch(backupProvider).status;
  final deletingBackup = ref.watch(existingBackupsProvider).deletingBackup;
  final refreshingSharedAssets = ref.watch(refreshingSharedAssetsProvider);

  return deleteAssetsStatus != DeleteAssetsStatusEnum.idle ||
      cleanUpStatus != CleanUpStatusEnum.idle ||
      backupStatus != BackupStatusEnum.idle ||
      bulkActionStatus != BulkActionsStatusEnum.idle ||
      isDownloading ||
      modsAsyncValue is AsyncLoading ||
      deletingBackup ||
      refreshingSharedAssets;
});

final backupSortAndFilterProvider =
    StateNotifierProvider<BackupSortAndFilterNotifier, BackupSortAndFilterState>(
  (ref) => BackupSortAndFilterNotifier(),
);

final filteredBackupsProvider = Provider<List<ExistingBackup>>((ref) {
  final existingBackups = ref.watch(existingBackupsProvider);
  final searchQuery = ref.watch(backupsSearchQueryProvider);
  final backupSortAndFilter = ref.watch(backupSortAndFilterProvider);

  final filtered = existingBackups.backups.where((bk) {
    if (searchQuery.isNotEmpty &&
        !bk.filename.toLowerCase().contains(searchQuery.toLowerCase())) {
      return false;
    }

    if (backupSortAndFilter.filteredBackupFolders.isNotEmpty &&
        !backupSortAndFilter.filteredBackupFolders
            .contains(bk.parentFolderName)) {
      return false;
    }

    if (backupSortAndFilter.filteredMatchStatuses.isNotEmpty) {
      final hasMatch = bk.matchingModFilepath != null;
      final matchesStatus = (backupSortAndFilter.filteredMatchStatuses
                  .contains(BackupMatchStatusEnum.hasMatchingMod) &&
              hasMatch) ||
          (backupSortAndFilter.filteredMatchStatuses
                  .contains(BackupMatchStatusEnum.noMatchingMod) &&
              !hasMatch);
      if (!matchesStatus) return false;
    }

    return true;
  }).toList();

  switch (backupSortAndFilter.sortOption) {
    case BackupSortOptionEnum.alphabeticalAsc:
      filtered.sort(
          (a, b) => a.filename.toLowerCase().compareTo(b.filename.toLowerCase()));
    case BackupSortOptionEnum.newestFirst:
      filtered.sort(
          (a, b) => b.lastModifiedTimestamp.compareTo(a.lastModifiedTimestamp));
    case BackupSortOptionEnum.largestFirst:
      filtered.sort((a, b) => b.fileSize.compareTo(a.fileSize));
  }

  return filtered;
});

final filteredModsProvider = Provider<List<Mod>>((ref) {
  final searchQuery = ref.watch(modsSearchQueryProvider);
  final sortAndFilter = ref.watch(sortAndFilterProvider);
  final selectedBackupStatuses =
      ref.watch(sortAndFilterProvider).filteredBackupStatuses;
  final selectedModType = ref.watch(selectedModTypeProvider);
  final modsState = ref.watch(modsProvider).unwrapPrevious().valueOrNull;

  if (modsState == null) {
    return [];
  }

  List<Mod> allMods = switch (selectedModType) {
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
  List<Mod> filteredMods = allMods.where((mod) {
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

    if (sortAndFilter.filteredAssets.isNotEmpty) {
      if (sortAndFilter.filteredAssets.contains(FilterAssetsEnum.complete)) {
        return mod.assetCount == mod.existingAssetCount;
      }

      if (sortAndFilter.filteredAssets.contains(FilterAssetsEnum.missing)) {
        return (mod.missingAssetCount) > 0;
      }

      if (sortAndFilter.filteredAssets.contains(FilterAssetsEnum.audio)) {
        return mod.hasAudioAssets;
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
      filteredMods
          .sort((a, b) => (b.missingAssetCount).compareTo(a.missingAssetCount));
      break;
    case SortOptionEnum.lastModifiedDesc:
      filteredMods.sort((a, b) =>
          (b.lastModifiedTimestamp).compareTo(a.lastModifiedTimestamp));
      break;
  }

  return filteredMods;
});
