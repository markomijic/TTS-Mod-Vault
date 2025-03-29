import 'package:riverpod/riverpod.dart';
import 'package:tts_mod_vault/src/state/asset/existing_asset_notifier.dart';
import 'package:tts_mod_vault/src/state/asset/selected_asset_notifier.dart';
import 'package:tts_mod_vault/src/state/asset/selected_asset_state.dart';
import 'package:tts_mod_vault/src/state/cleanup/cleanup_notifier.dart';
import 'package:tts_mod_vault/src/state/cleanup/cleanup_state.dart';
import 'package:tts_mod_vault/src/state/directories/directories.dart';
import 'package:tts_mod_vault/src/state/directories/directories_state.dart';
import 'package:tts_mod_vault/src/state/download/download_notifier.dart';
import 'package:tts_mod_vault/src/state/download/download_state.dart';
import 'package:tts_mod_vault/src/state/mods/mod_model.dart';
import 'package:tts_mod_vault/src/state/mods/mods_state.dart';
import 'package:tts_mod_vault/src/state/mods/mods_notifier.dart';
import 'package:tts_mod_vault/src/state/storage/storage_notifier.dart';

final storageProvider = Provider((ref) => Storage());

final directoriesProvider =
    StateNotifierProvider<DirectoriesNotifier, DirectoriesState>(
  (ref) => DirectoriesNotifier(),
);

final stringListProvider =
    StateNotifierProvider<StringListNotifier, AssetTypeLists>((ref) {
  final directories = ref.watch(directoriesProvider);
  return StringListNotifier(directories);
});

/* final modsProvider = StateNotifierProvider<ModsStateNotifier, ModsState>(
  (ref) => ModsStateNotifier(ref),
); */

final modsProvider = AsyncNotifierProvider<ModsStateNotifier, ModsState>(
    () => ModsStateNotifier());

final selectedModProvider = StateProvider<Mod?>((ref) => null);

final selectedAssetProvider =
    StateNotifierProvider<SelectedAssetNotifier, SelectedAssetState?>(
  (ref) => SelectedAssetNotifier(),
);

final downloadProvider = StateNotifierProvider<DownloadNotifier, DownloadState>(
  (ref) => DownloadNotifier(ref),
);

final cleanupProvider = StateNotifierProvider<CleanupNotifier, CleanUpState>(
  (ref) => CleanupNotifier(ref),
);

final actionInProgressProvider = Provider<bool>((ref) {
  final isDownloading = ref.watch(downloadProvider).isDownloading;
  // TODO check if applied
  final modsIsLoading = ref.watch(modsProvider).isLoading;
  final cleanUpStatus = ref.watch(cleanupProvider).status;

  return cleanUpStatus != CleanUpStatusEnum.idle ||
      isDownloading ||
      modsIsLoading;
});
