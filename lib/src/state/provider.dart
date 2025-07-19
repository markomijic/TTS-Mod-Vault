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
