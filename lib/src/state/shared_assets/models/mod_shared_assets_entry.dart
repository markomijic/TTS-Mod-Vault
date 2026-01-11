import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show ModTypeEnum;
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart';

class SharedAssetInfo {
  final String filename;
  final AssetTypeEnum assetType;
  final String? filePath;
  final int shareCount;

  const SharedAssetInfo({
    required this.filename,
    required this.assetType,
    required this.filePath,
    required this.shareCount,
  });
}

class ModSharedAssetsEntry {
  final String modJsonFileName;
  final String modSaveName;
  final ModTypeEnum modType;
  final List<SharedAssetInfo> sharedAssets;

  const ModSharedAssetsEntry({
    required this.modJsonFileName,
    required this.modSaveName,
    required this.modType,
    required this.sharedAssets,
  });

  int get sharedAssetCount => sharedAssets.length;
}
