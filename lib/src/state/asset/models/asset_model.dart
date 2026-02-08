import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart';

class Asset {
  final String url;
  final bool fileExists;
  final AssetTypeEnum type;
  final String? filePath;

  Asset({
    required this.url,
    required this.fileExists,
    required this.type,
    this.filePath,
  });
}
