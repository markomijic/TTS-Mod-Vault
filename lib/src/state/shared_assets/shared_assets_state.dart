import 'package:tts_mod_vault/src/state/shared_assets/models/shared_asset_entry.dart';
import 'package:tts_mod_vault/src/state/shared_assets/models/mod_shared_assets_entry.dart';
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart';
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show ModTypeEnum;

enum SharedAssetsStatusEnum {
  idle,
  computing,
  ready,
  error,
}

enum SharedAssetsViewMode {
  assetCentric, // Asset → Mods using it
  modCentric, // Mod → Shared assets
}

class SharedAssetsState {
  final SharedAssetsStatusEnum status;
  final SharedAssetsViewMode viewMode;
  final String? errorMessage;

  // Data for asset-centric view
  final List<SharedAssetEntry> sharedAssets;

  // Data for mod-centric view
  final List<ModSharedAssetsEntry> modSharedAssets;

  // Filtering state
  final Set<AssetTypeEnum> filteredAssetTypes;
  final Set<ModTypeEnum> filteredModTypes;
  final String searchQuery;
  final bool sortAscending;

  const SharedAssetsState({
    this.status = SharedAssetsStatusEnum.idle,
    this.viewMode = SharedAssetsViewMode.assetCentric,
    this.errorMessage,
    this.sharedAssets = const [],
    this.modSharedAssets = const [],
    this.filteredAssetTypes = const {},
    this.filteredModTypes = const {},
    this.searchQuery = '',
    this.sortAscending = false, // Default: most shared first
  });

  SharedAssetsState copyWith({
    SharedAssetsStatusEnum? status,
    SharedAssetsViewMode? viewMode,
    String? errorMessage,
    List<SharedAssetEntry>? sharedAssets,
    List<ModSharedAssetsEntry>? modSharedAssets,
    Set<AssetTypeEnum>? filteredAssetTypes,
    Set<ModTypeEnum>? filteredModTypes,
    String? searchQuery,
    bool? sortAscending,
  }) {
    return SharedAssetsState(
      status: status ?? this.status,
      viewMode: viewMode ?? this.viewMode,
      errorMessage: errorMessage,
      sharedAssets: sharedAssets ?? this.sharedAssets,
      modSharedAssets: modSharedAssets ?? this.modSharedAssets,
      filteredAssetTypes: filteredAssetTypes ?? this.filteredAssetTypes,
      filteredModTypes: filteredModTypes ?? this.filteredModTypes,
      searchQuery: searchQuery ?? this.searchQuery,
      sortAscending: sortAscending ?? this.sortAscending,
    );
  }

  // Get filtered and sorted asset-centric view
  List<SharedAssetEntry> get filteredSharedAssets {
    var results = sharedAssets;

    // Asset type filter
    if (filteredAssetTypes.isNotEmpty) {
      results = results
          .where((a) => filteredAssetTypes.contains(a.assetType))
          .toList();
    }

    // Mod type filter
    if (filteredModTypes.isNotEmpty) {
      results = results.where((a) {
        return filteredModTypes.any((type) => (a.modTypeCounts[type] ?? 0) > 0);
      }).toList();
    }

    // Search filter
    if (searchQuery.isNotEmpty) {
      final query = searchQuery.toLowerCase();
      results = results
          .where((a) => a.filename.toLowerCase().contains(query))
          .toList();
    }

    // Sort by share count
    results.sort((a, b) {
      final comparison = a.shareCount.compareTo(b.shareCount);
      return sortAscending ? comparison : -comparison;
    });

    return results;
  }

  // Get filtered and sorted mod-centric view
  List<ModSharedAssetsEntry> get filteredModSharedAssets {
    var results = modSharedAssets;

    // Asset type filter
    if (filteredAssetTypes.isNotEmpty) {
      results = results.map((mod) {
        final filteredAssets = mod.sharedAssets
            .where((a) => filteredAssetTypes.contains(a.assetType))
            .toList();
        return filteredAssets.isEmpty
            ? null
            : ModSharedAssetsEntry(
                modJsonFileName: mod.modJsonFileName,
                modSaveName: mod.modSaveName,
                modType: mod.modType,
                sharedAssets: filteredAssets,
              );
      }).whereType<ModSharedAssetsEntry>().toList();
    }

    // Mod type filter
    if (filteredModTypes.isNotEmpty) {
      results = results
          .where((mod) => filteredModTypes.contains(mod.modType))
          .toList();
    }

    // Search filter
    if (searchQuery.isNotEmpty) {
      final query = searchQuery.toLowerCase();
      results = results
          .where((mod) => mod.modSaveName.toLowerCase().contains(query))
          .toList();
    }

    // Sort by shared asset count
    results.sort((a, b) {
      final comparison = a.sharedAssetCount.compareTo(b.sharedAssetCount);
      return sortAscending ? comparison : -comparison;
    });

    return results;
  }
}
