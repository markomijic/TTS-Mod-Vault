import 'package:riverpod/riverpod.dart';
import 'package:tts_mod_vault/src/state/asset/selected_asset_notifier.dart';
import 'package:tts_mod_vault/src/state/asset/selected_asset_state.dart';
import 'package:tts_mod_vault/src/state/directories/directories.dart';
import 'package:tts_mod_vault/src/state/directories/directories_state.dart';
import 'package:tts_mod_vault/src/state/download/download_notifier.dart';
import 'package:tts_mod_vault/src/state/download/download_state.dart';
import 'package:tts_mod_vault/src/state/mods/mods_state.dart';
import 'package:tts_mod_vault/src/state/mods/mods_notifier.dart';

final directoriesProvider =
    StateNotifierProvider<DirectoriesNotifier, DirectoriesState>(
  (ref) => DirectoriesNotifier(),
);

final modsProvider = StateNotifierProvider<ModsStateNotifier, ModsState>((ref) {
  final directories = ref.watch(directoriesProvider);
  return ModsStateNotifier(directories);
});

final selectedAssetProvider =
    StateNotifierProvider<SelectedAssetNotifier, SelectedAssetState?>((ref) {
  return SelectedAssetNotifier();
});

final downloadProvider =
    StateNotifierProvider<DownloadNotifier, DownloadState>((ref) {
  final directories = ref.watch(directoriesProvider);
  return DownloadNotifier(directories);
});
