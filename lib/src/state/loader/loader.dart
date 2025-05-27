import 'package:flutter/material.dart' show VoidCallback, debugPrint;
import 'package:hooks_riverpod/hooks_riverpod.dart' show Ref;
import 'package:tts_mod_vault/src/state/provider.dart'
    show backupProvider, existingAssetListsProvider, modsProvider;

class LoaderNotifier {
  final Ref ref;

  LoaderNotifier(this.ref);

  Future<void> loadAppData(VoidCallback onDataLoaded) async {
    debugPrint("loadAppData");

    await ref
        .read(existingAssetListsProvider.notifier)
        .loadExistingAssetsLists();
    await ref.read(modsProvider.notifier).loadModsData();
    onDataLoaded();
  }

  Future<void> refreshAppData() async {
    debugPrint("refreshAppData");

    await ref
        .read(existingAssetListsProvider.notifier)
        .loadExistingAssetsLists();
    await ref.read(modsProvider.notifier).loadModsData(
          modJsonFileName: ref.read(backupProvider).lastImportedJsonFileName,
        );
  }
}
