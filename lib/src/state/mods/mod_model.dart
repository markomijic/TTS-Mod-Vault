import 'package:tts_mod_vault/src/state/asset/models/asset_lists_model.dart';
import 'package:tts_mod_vault/src/state/asset/models/asset_model.dart';
import 'package:tts_mod_vault/src/state/backup/models/existing_backup_model.dart';
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart';

enum ModTypeEnum {
  mod('mod'),
  save('save'),
  savedObject('saved object');

  final String label;
  const ModTypeEnum(this.label);
}

class Mod {
  final ModTypeEnum modType;
  final String jsonFilePath;
  final String jsonFileName;
  final String parentFolderName;
  final String saveName;
  final String? dateTimeStamp;
  final ExistingBackup? backup;
  final String? imageFilePath;
  final AssetLists? assetLists;
  final int? totalCount;
  final int? totalExistsCount;

  Mod({
    required this.modType,
    required this.jsonFilePath,
    required this.jsonFileName,
    required this.parentFolderName,
    required this.saveName,
    this.dateTimeStamp,
    this.backup,
    this.imageFilePath,
    this.assetLists,
    this.totalCount,
    this.totalExistsCount,
  });

  Mod copyWith({
    String? jsonFilePath,
    String? parentFolderName,
    String? saveName,
    String? dateTimeStamp,
    ExistingBackup? backup,
    String? jsonFileName,
    String? imageFilePath,
    AssetLists? assetLists,
    int? totalCount,
    int? totalExistsCount,
  }) {
    return Mod(
      modType: modType,
      jsonFilePath: jsonFilePath ?? this.jsonFilePath,
      jsonFileName: jsonFileName ?? this.jsonFileName,
      parentFolderName: parentFolderName ?? this.parentFolderName,
      saveName: saveName ?? this.saveName,
      dateTimeStamp: dateTimeStamp ?? this.dateTimeStamp,
      backup: backup ?? this.backup,
      imageFilePath: imageFilePath ?? this.imageFilePath,
      assetLists: assetLists ?? this.assetLists,
      totalCount: totalCount ?? this.totalCount,
      totalExistsCount: totalExistsCount ?? this.totalExistsCount,
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
