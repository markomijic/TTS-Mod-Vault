import 'dart:math' show Random;

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/src/state/asset/existing_assets_state.dart';
import 'package:tts_mod_vault/src/state/asset/existing_assets.dart';
import 'package:tts_mod_vault/src/state/backup/backup_state.dart';
import 'package:tts_mod_vault/src/state/backup/backup.dart';
import 'package:tts_mod_vault/src/state/backup/existing_backups.dart';
import 'package:tts_mod_vault/src/state/backup/existing_backups_state.dart';
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

final cardModProvider =
    FutureProvider.family.autoDispose<Mod, String>((ref, jsonFileName) async {
  await Future.delayed(Duration(milliseconds: Random().nextInt(500) + 1));

  return ref.read(modsProvider.notifier).getCardMod(jsonFileName);
});

final downloadProvider = StateNotifierProvider<DownloadNotifier, DownloadState>(
  (ref) => DownloadNotifier(ref),
);

final cleanupProvider = StateNotifierProvider<CleanupNotifier, CleanUpState>(
  (ref) => CleanupNotifier(ref),
);

final backupProvider = StateNotifierProvider<BackupNotifier, BackupState>(
  (ref) => BackupNotifier(ref),
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

  return mods.where((mod) {
    // Filter by search query (only if query is not empty)
    if (searchQuery.isNotEmpty) {
      if (!mod.saveName.toLowerCase().contains(searchQuery.toLowerCase())) {
        return false; // Exclude if doesn't match search
      }
    }

    // Filter by selected folders (only if folders are selected)
    if (selectedFolders.isNotEmpty) {
      if (!selectedFolders.contains(mod.parentFolderName)) {
        return false; // Exclude if not in selected folders
      }
    }

    // Filter by selected backup states (only if backup statuses are selected)
    if (selectedBackupStatuses.isNotEmpty) {
      if (!selectedBackupStatuses.contains(mod.backupStatus)) {
        return false; // Exclude if not in selected backup statuses
      }
    }

    return true; // Include if passes all filters (or no filters applied)
  }).toList();
});

final actionInProgressProvider = Provider<bool>((ref) {
  final downloading = ref.watch(downloadProvider).downloading;
  final downloadingAllMods = ref.watch(bulkActionsProvider).downloadingAllMods;
  final modsAsyncValue = ref.watch(modsProvider);
  final cleanUpStatus = ref.watch(cleanupProvider).status;

  return cleanUpStatus != CleanUpStatusEnum.idle ||
      downloading ||
      downloadingAllMods ||
      modsAsyncValue is AsyncLoading;
});
