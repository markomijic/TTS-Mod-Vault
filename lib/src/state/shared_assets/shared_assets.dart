import 'dart:isolate' show Isolate;

import 'package:hooks_riverpod/hooks_riverpod.dart' show Notifier;
import 'package:tts_mod_vault/src/state/shared_assets/shared_assets_state.dart';
import 'package:tts_mod_vault/src/state/shared_assets/models/shared_asset_entry.dart';
import 'package:tts_mod_vault/src/state/shared_assets/models/mod_shared_assets_entry.dart';
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show ModTypeEnum;
import 'package:tts_mod_vault/src/state/provider.dart'
    show existingAssetListsProvider, modsProvider, storageProvider;
import 'package:tts_mod_vault/src/utils.dart' show getFileNameFromURL;
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart';

class SharedAssetsNotifier extends Notifier<SharedAssetsState> {
  SharedAssetsNotifier();

  @override
  SharedAssetsState build() {
    return const SharedAssetsState();
  }

  Future<void> computeSharedAssets() async {
    state = state.copyWith(status: SharedAssetsStatusEnum.computing);

    try {
      // Get all mods and their URLs
      final allMods = ref.read(modsProvider.notifier).getAllMods();
      final jsonFileNames = allMods.map((mod) => mod.jsonFileName).toList();
      final allModUrls =
          ref.read(storageProvider).getModUrlsBulk(jsonFileNames);

      // Create a map of mod metadata
      final modMetadata = {
        for (final mod in allMods)
          mod.jsonFileName: _ModMetadata(
            jsonFileName: mod.jsonFileName,
            saveName: mod.saveName,
            modType: mod.modType,
          )
      };

      // Get existing assets for file path lookups
      final existingAssets = ref.read(existingAssetListsProvider);

      // Run computation in isolate
      final result = await Isolate.run(() => _computeSharedAssetsInIsolate(
            allModUrls,
            modMetadata,
            _ExistingAssetsMaps(
              assetBundles: existingAssets.assetBundles,
              audio: existingAssets.audio,
              images: existingAssets.images,
              models: existingAssets.models,
              pdf: existingAssets.pdf,
            ),
          ));

      state = state.copyWith(
        status: SharedAssetsStatusEnum.ready,
        sharedAssets: result.assetEntries,
        modSharedAssets: result.modEntries,
      );
    } catch (e) {
      state = state.copyWith(
        status: SharedAssetsStatusEnum.error,
        errorMessage: 'Error computing shared assets: $e',
      );
    }
  }

  static _ComputationResult _computeSharedAssetsInIsolate(
    Map<String, Map<String, String>?> allModUrls,
    Map<String, _ModMetadata> modMetadata,
    _ExistingAssetsMaps existingAssets,
  ) {
    // Phase 1: Build asset usage map
    final Map<String, _AssetUsageInfo> assetUsageMap = {};

    for (final modEntry in allModUrls.entries) {
      final modJsonFileName = modEntry.key;
      final urls = modEntry.value;
      if (urls == null) continue;

      final modMeta = modMetadata[modJsonFileName];
      if (modMeta == null) continue;

      for (final urlEntry in urls.entries) {
        final url = urlEntry.key;
        final assetTypeStr = urlEntry.value;
        final filename = getFileNameFromURL(url);

        // Determine asset type
        AssetTypeEnum? assetType;
        for (final type in AssetTypeEnum.values) {
          if (type.subtypes.contains(assetTypeStr)) {
            assetType = type;
            break;
          }
        }
        if (assetType == null) continue;

        // Add to usage map
        assetUsageMap
            .putIfAbsent(
              filename,
              () => _AssetUsageInfo(
                filename: filename,
                assetType: assetType!,
                usingMods: [],
              ),
            )
            .usingMods
            .add(_ModIdentifier(
              jsonFileName: modJsonFileName,
              saveName: modMeta.saveName,
              modType: modMeta.modType,
            ));
      }
    }

    // Phase 2: Filter to shared assets only (2+ mods)
    final sharedAssetEntries = <SharedAssetEntry>[];

    for (final assetInfo in assetUsageMap.values) {
      if (assetInfo.usingMods.length < 2) continue;

      // Count mod types
      final modTypeCounts = <ModTypeEnum, int>{};
      for (final modId in assetInfo.usingMods) {
        modTypeCounts[modId.modType] = (modTypeCounts[modId.modType] ?? 0) + 1;
      }

      // Find file path
      final filePath = _findFilePath(assetInfo.filename, assetInfo.assetType, existingAssets);

      sharedAssetEntries.add(SharedAssetEntry(
        filename: assetInfo.filename,
        filePath: filePath,
        assetType: assetInfo.assetType,
        modJsonFileNames:
            assetInfo.usingMods.map((m) => m.jsonFileName).toSet(),
        modTypeCounts: modTypeCounts,
      ));
    }

    // Phase 3: Build mod-centric view
    final Map<String, List<SharedAssetInfo>> modSharedMap = {};

    for (final asset in sharedAssetEntries) {
      for (final modJsonFileName in asset.modJsonFileNames) {
        modSharedMap.putIfAbsent(modJsonFileName, () => []).add(
              SharedAssetInfo(
                filename: asset.filename,
                assetType: asset.assetType,
                filePath: asset.filePath,
                shareCount: asset.shareCount,
              ),
            );
      }
    }

    final modEntries = <ModSharedAssetsEntry>[];
    for (final entry in modSharedMap.entries) {
      final modMeta = modMetadata[entry.key];
      if (modMeta == null) continue;

      modEntries.add(ModSharedAssetsEntry(
        modJsonFileName: entry.key,
        modSaveName: modMeta.saveName,
        modType: modMeta.modType,
        sharedAssets: entry.value,
      ));
    }

    return _ComputationResult(
      assetEntries: sharedAssetEntries,
      modEntries: modEntries,
    );
  }

  static String? _findFilePath(
    String filename,
    AssetTypeEnum assetType,
    _ExistingAssetsMaps existingAssets,
  ) {
    switch (assetType) {
      case AssetTypeEnum.assetBundle:
        return existingAssets.assetBundles[filename];
      case AssetTypeEnum.audio:
        return existingAssets.audio[filename];
      case AssetTypeEnum.image:
        return existingAssets.images[filename];
      case AssetTypeEnum.model:
        return existingAssets.models[filename];
      case AssetTypeEnum.pdf:
        return existingAssets.pdf[filename];
    }
  }

  void setViewMode(SharedAssetsViewMode mode) {
    state = state.copyWith(viewMode: mode);
  }

  void toggleSortOrder() {
    state = state.copyWith(sortAscending: !state.sortAscending);
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void toggleAssetTypeFilter(AssetTypeEnum type) {
    final current = Set<AssetTypeEnum>.from(state.filteredAssetTypes);
    if (current.contains(type)) {
      current.remove(type);
    } else {
      current.add(type);
    }
    state = state.copyWith(filteredAssetTypes: current);
  }

  void toggleModTypeFilter(ModTypeEnum type) {
    final current = Set<ModTypeEnum>.from(state.filteredModTypes);
    if (current.contains(type)) {
      current.remove(type);
    } else {
      current.add(type);
    }
    state = state.copyWith(filteredModTypes: current);
  }

  void clearAllFilters() {
    state = state.copyWith(
      filteredAssetTypes: const {},
      filteredModTypes: const {},
      searchQuery: '',
    );
  }

  void resetState() {
    state = const SharedAssetsState();
  }
}

// Helper classes for isolate communication (must be top-level)
class _ModMetadata {
  final String jsonFileName;
  final String saveName;
  final ModTypeEnum modType;

  _ModMetadata({
    required this.jsonFileName,
    required this.saveName,
    required this.modType,
  });
}

class _ModIdentifier {
  final String jsonFileName;
  final String saveName;
  final ModTypeEnum modType;

  _ModIdentifier({
    required this.jsonFileName,
    required this.saveName,
    required this.modType,
  });
}

class _AssetUsageInfo {
  final String filename;
  final AssetTypeEnum assetType;
  final List<_ModIdentifier> usingMods;

  _AssetUsageInfo({
    required this.filename,
    required this.assetType,
    required this.usingMods,
  });
}

class _ExistingAssetsMaps {
  final Map<String, String> assetBundles;
  final Map<String, String> audio;
  final Map<String, String> images;
  final Map<String, String> models;
  final Map<String, String> pdf;

  _ExistingAssetsMaps({
    required this.assetBundles,
    required this.audio,
    required this.images,
    required this.models,
    required this.pdf,
  });
}

class _ComputationResult {
  final List<SharedAssetEntry> assetEntries;
  final List<ModSharedAssetsEntry> modEntries;

  _ComputationResult({
    required this.assetEntries,
    required this.modEntries,
  });
}
