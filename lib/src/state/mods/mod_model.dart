import 'package:tts_mod_vault/src/state/asset/asset_lists_model.dart';
import 'package:tts_mod_vault/src/state/asset/asset_model.dart';
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart';

class Mod {
  final String directory;
  final String name;
  final int updateTime;
  final String? fileName;
  final String? imageFilePath;
  final AssetLists? assetLists;
  final int? totalCount;
  final int? totalExistsCount;

  Mod({
    required this.directory,
    required this.name,
    required this.updateTime,
    this.fileName,
    this.imageFilePath,
    this.assetLists,
    this.totalCount,
    this.totalExistsCount,
  });

  factory Mod.fromJson(Map<String, dynamic> json) {
    return Mod(
      directory: json['Directory'] as String,
      name: json['Name'] as String,
      updateTime: json['UpdateTime'] as int,
    );
  }

  List<Asset> getAllAssets() {
    if (assetLists == null) return [];

    return [
      ...assetLists!.assetBundles,
      ...assetLists!.audio,
      ...assetLists!.images,
      ...assetLists!.models,
      ...assetLists!.pdf,
    ];
  }

  List<Asset> getAssetsByType(AssetTypeEnum type) {
    if (assetLists == null) return [];

    switch (type) {
      case AssetTypeEnum.assetBundle:
        return assetLists?.assetBundles ?? [];
      case AssetTypeEnum.audio:
        return assetLists?.audio ?? [];
      case AssetTypeEnum.image:
        return assetLists?.images ?? [];
      case AssetTypeEnum.model:
        return assetLists?.models ?? [];
      case AssetTypeEnum.pdf:
        return assetLists?.pdf ?? [];
    }
  }
}
