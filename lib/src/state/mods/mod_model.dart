import 'package:tts_mod_vault/src/state/asset/models/asset_lists_model.dart';
import 'package:tts_mod_vault/src/state/asset/models/asset_model.dart';
import 'package:tts_mod_vault/src/state/backup/backup_status_enum.dart';
import 'package:tts_mod_vault/src/state/backup/models/existing_backup_model.dart';
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart';

enum ModTypeEnum {
  mod('mod'),
  save('save'),
  savedObject('saved object');

  final String label;
  const ModTypeEnum(this.label);
}

enum AudioAssetVisibility {
  useGlobalSetting,
  alwaysShow,
  alwaysHide,
}

class Mod {
  final ModTypeEnum modType;
  final String jsonFilePath;
  final String jsonFileName;
  final String parentFolderName;
  final String saveName;
  final int createdAtTimestamp;
  final AssetLists assetLists;
  final int assetCount;
  final int existingAssetCount;
  final AudioAssetVisibility audioVisibility;
  final bool hasAudioAssets;
  final String? dateTimeStamp;
  final String? imageFilePath;
  final ExistingBackupStatusEnum backupStatus;
  final ExistingBackup? backup;

  const Mod({
    required this.modType,
    required this.jsonFilePath,
    required this.jsonFileName,
    required this.parentFolderName,
    required this.saveName,
    required this.backupStatus,
    required this.createdAtTimestamp,
    required this.backup,
    required this.dateTimeStamp,
    required this.imageFilePath,
    required this.assetLists,
    required this.assetCount,
    required this.existingAssetCount,
    required this.audioVisibility,
    required this.hasAudioAssets,
  });

  factory Mod.fromInitial(
    InitialMod initial, {
    required AssetLists assetLists,
    required int assetCount,
    required int existingAssetCount,
    required int missingAssetCount,
    required AudioAssetVisibility audioVisibility,
    required bool hasAudioAssets,
    ExistingBackup? backup,
  }) {
    return Mod(
      modType: initial.modType,
      jsonFilePath: initial.jsonFilePath,
      jsonFileName: initial.jsonFileName,
      parentFolderName: initial.parentFolderName,
      saveName: initial.saveName,
      createdAtTimestamp: initial.createdAtTimestamp,
      dateTimeStamp: initial.dateTimeStamp,
      imageFilePath: initial.imageFilePath,
      backupStatus: initial.backupStatus,
      backup: backup,
      assetLists: assetLists,
      assetCount: assetCount,
      existingAssetCount: existingAssetCount,
      audioVisibility: audioVisibility,
      hasAudioAssets: hasAudioAssets,
    );
  }

  int get missingAssetCount => assetCount - existingAssetCount;

  List<Asset> getAllAssets() {
    return [
      ...assetLists.assetBundles,
      ...assetLists.audio,
      ...assetLists.images,
      ...assetLists.models,
      ...assetLists.pdf,
    ];
  }

  List<Asset> getAssetsByType(AssetTypeEnum type) {
    switch (type) {
      case AssetTypeEnum.assetBundle:
        return assetLists.assetBundles;
      case AssetTypeEnum.audio:
        return assetLists.audio;
      case AssetTypeEnum.image:
        return assetLists.images;
      case AssetTypeEnum.model:
        return assetLists.models;
      case AssetTypeEnum.pdf:
        return assetLists.pdf;
    }
  }
}

class InitialMod {
  final ModTypeEnum modType;
  final String jsonFilePath;
  final String jsonFileName;
  final String parentFolderName;
  final String saveName;
  final int createdAtTimestamp;
  final String? dateTimeStamp;
  final String? imageFilePath;
  final ExistingBackupStatusEnum backupStatus;

  const InitialMod({
    required this.modType,
    required this.jsonFilePath,
    required this.jsonFileName,
    required this.parentFolderName,
    required this.saveName,
    required this.createdAtTimestamp,
    required this.dateTimeStamp,
    required this.imageFilePath,
    required this.backupStatus,
  });
}
