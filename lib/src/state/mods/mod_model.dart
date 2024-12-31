import 'package:tts_mod_vault/src/state/asset/asset_lists_model.dart';

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
}
