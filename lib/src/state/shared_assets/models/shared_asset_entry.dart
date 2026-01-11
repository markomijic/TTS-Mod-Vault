import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart';
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show ModTypeEnum;

class SharedAssetEntry {
  final String filename;
  final String? filePath;
  final AssetTypeEnum assetType;
  final Set<String> modJsonFileNames;
  final Map<ModTypeEnum, int> modTypeCounts;

  const SharedAssetEntry({
    required this.filename,
    required this.filePath,
    required this.assetType,
    required this.modJsonFileNames,
    required this.modTypeCounts,
  });

  int get shareCount => modJsonFileNames.length;
}
