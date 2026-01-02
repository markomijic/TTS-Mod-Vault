import 'dart:io' show File;
import 'dart:isolate' show Isolate;

import 'package:hooks_riverpod/hooks_riverpod.dart' show Notifier;
import 'package:tts_mod_vault/src/state/delete_assets/delete_assets_state.dart'
    show DeleteAssetsState, DeleteAssetsStatusEnum, SharedAssetInfo, ScanResult;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart'
    show Mod, ModTypeEnum;
import 'package:tts_mod_vault/src/state/provider.dart'
    show existingAssetListsProvider, modsProvider, storageProvider;
import 'package:tts_mod_vault/src/utils.dart' show getFileNameFromURL;
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart'
    show AssetTypeEnum;

class DeleteAssetsNotifier extends Notifier<DeleteAssetsState> {
  DeleteAssetsNotifier();

  @override
  DeleteAssetsState build() {
    return const DeleteAssetsState();
  }

  Future<void> scanModAssets(Mod selectedMod) async {
    state = state.copyWith(
      status: DeleteAssetsStatusEnum.scanning,
      statusMessage: 'Scanning for assets that can be safely deleted...',
    );

    try {
      // Get all assets from the selected mod
      final selectedModAssets = selectedMod.getAllAssets();
      if (selectedModAssets.isEmpty) {
        state = state.copyWith(
          status: DeleteAssetsStatusEnum.completed,
          statusMessage: 'No assets found in this mod',
        );
        return;
      }

      // Get all mods and their URLs
      final allMods = ref.read(modsProvider.notifier).getAllMods();
      final jsonFileNames = allMods.map((mod) => mod.jsonFileName).toList();
      final allModUrls =
          ref.read(storageProvider).getModUrlsBulk(jsonFileNames);

      // Create a map of mod type for each mod
      final modTypeMap = {
        for (final mod in allMods) mod.jsonFileName: mod.modType
      };

      // Run the scanning in an isolate to avoid blocking the UI
      final result = await Isolate.run(() => _scanForDeletableAssets(
            selectedMod.jsonFileName,
            selectedModAssets.map((a) => a.url).toList(),
            allModUrls,
            modTypeMap,
          ));

      if (result.filesToDelete.isEmpty) {
        state = state.copyWith(
          status: DeleteAssetsStatusEnum.completed,
          statusMessage:
              'No assets can be safely deleted (all assets are used by other mods)',
        );
        return;
      }

      state = state.copyWith(
        status: DeleteAssetsStatusEnum.awaitingConfirmation,
        filesToDelete: result.filesToDelete,
        totalFiles: result.filesToDelete.length,
        sharedAssetInfo: result.sharedAssetInfo,
        statusMessage:
            'Found ${result.filesToDelete.length} asset(s) that can be safely deleted',
      );
    } catch (e) {
      state = state.copyWith(
        status: DeleteAssetsStatusEnum.error,
        errorMessage: 'Error scanning assets: $e',
      );
    }
  }

  static ScanResult _scanForDeletableAssets(
    String selectedModJsonFileName,
    List<String> selectedModAssetUrls,
    Map<String, Map<String, String>?> allModUrls,
    Map<String, ModTypeEnum> modTypeMap,
  ) {
    // Build a map of filename -> Set of mod names that use it
    final Map<String, Set<String>> assetUsageMap = {};

    for (final modEntry in allModUrls.entries) {
      final modJsonFileName = modEntry.key;
      final urls = modEntry.value;
      if (urls == null) continue;

      for (final url in urls.keys) {
        final filename = getFileNameFromURL(url);
        assetUsageMap.putIfAbsent(filename, () => {}).add(modJsonFileName);
      }
    }

    // Find assets that are only used by the selected mod and count shared assets
    final List<String> filesToDelete = [];
    int sharedWithMods = 0;
    int sharedWithSaves = 0;
    int sharedWithSavedObjects = 0;
    final Map<String, List<String>> sharedAssetDetails = {};

    for (final url in selectedModAssetUrls) {
      final filename = getFileNameFromURL(url);
      final modsUsingAsset = assetUsageMap[filename] ?? {};

      // Only delete if this asset is used by exactly one mod (the selected mod)
      if (modsUsingAsset.length == 1 &&
          modsUsingAsset.contains(selectedModJsonFileName)) {
        filesToDelete.add(filename);
      } else if (modsUsingAsset.length > 1) {
        // Track which mods are using this asset (excluding the selected mod)
        final sharingMods = <String>[];

        for (final modJsonFileName in modsUsingAsset) {
          if (modJsonFileName == selectedModJsonFileName) continue;

          sharingMods.add(modJsonFileName);

          final modType = modTypeMap[modJsonFileName];
          if (modType == ModTypeEnum.mod) {
            sharedWithMods++;
          } else if (modType == ModTypeEnum.save) {
            sharedWithSaves++;
          } else if (modType == ModTypeEnum.savedObject) {
            sharedWithSavedObjects++;
          }
        }

        if (sharingMods.isNotEmpty) {
          sharedAssetDetails[url] = sharingMods;
        }
      }
    }

    return ScanResult(
      filesToDelete: filesToDelete,
      sharedAssetInfo: SharedAssetInfo(
        sharedWithMods: sharedWithMods,
        sharedWithSaves: sharedWithSaves,
        sharedWithSavedObjects: sharedWithSavedObjects,
        sharedAssetDetails: sharedAssetDetails,
      ),
    );
  }

  Future<void> executeDelete() async {
    if (state.status != DeleteAssetsStatusEnum.awaitingConfirmation) {
      return;
    }

    state = state.copyWith(
      status: DeleteAssetsStatusEnum.deleting,
      currentFile: 0,
      statusMessage: 'Deleting assets...',
    );

    try {
      final filesToDelete = state.filesToDelete;
      final existingAssets = ref.read(existingAssetListsProvider);

      await _deleteFiles(filesToDelete, existingAssets);

      // Refresh existing assets lists after deletion
      for (final type in AssetTypeEnum.values) {
        await ref
            .read(existingAssetListsProvider.notifier)
            .setExistingAssetsListByType(type);
      }

      state = state.copyWith(
        status: DeleteAssetsStatusEnum.completed,
        currentFile: filesToDelete.length,
        statusMessage: 'Successfully deleted ${filesToDelete.length} asset(s)',
      );
    } catch (e) {
      state = state.copyWith(
        status: DeleteAssetsStatusEnum.error,
        errorMessage: 'Error deleting assets: $e',
      );
    }
  }

  static Future<void> _deleteFiles(
      List<String> fileNames, existingAssets) async {
    for (final fileName in fileNames) {
      try {
        // Search for the file in all asset type directories
        String? filePath;

        // Check each asset type map for the filename
        if (existingAssets.assetBundles.containsKey(fileName)) {
          filePath = existingAssets.assetBundles[fileName];
        } else if (existingAssets.audio.containsKey(fileName)) {
          filePath = existingAssets.audio[fileName];
        } else if (existingAssets.images.containsKey(fileName)) {
          filePath = existingAssets.images[fileName];
        } else if (existingAssets.models.containsKey(fileName)) {
          filePath = existingAssets.models[fileName];
        } else if (existingAssets.pdf.containsKey(fileName)) {
          filePath = existingAssets.pdf[fileName];
        }

        if (filePath != null) {
          final file = File(filePath);
          if (await file.exists()) {
            await file.delete();
          }
        }
      } catch (e) {
        // Continue with other files even if one fails
        continue;
      }
    }
  }

  void resetState() {
    state = const DeleteAssetsState();
  }
}
