import 'package:flutter/animation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart' show Ref, StateNotifier;
import 'package:tts_mod_vault/src/state/loader/loader_state.dart'
    show LoaderState;
import 'package:tts_mod_vault/src/state/provider.dart';

class LoaderNotifier extends StateNotifier<LoaderState> {
  final Ref ref;

  LoaderNotifier(this.ref) : super(LoaderState());

  Future<void> loadAppData(VoidCallback onLoaded) async {
    if (await ref
        .read(directoriesProvider.notifier)
        .checkIfTtsDirectoryExists()) {
      await ref
          .read(existingAssetListsProvider.notifier)
          .loadExistingAssetsLists();
      await ref
          .read(modsProvider.notifier)
          .loadModsData(onDataLoaded: () => onLoaded());
    } else {
      state = LoaderState(ttsDirNotFound: true);
    }
  }

  Future<void> refreshAppData() async {
    await ref
        .read(existingAssetListsProvider.notifier)
        .loadExistingAssetsLists();
    await ref.read(modsProvider.notifier).loadModsData(
          modJsonFileName: ref.read(backupProvider).lastImportedJsonFileName,
        );
  }
}
