import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/domain/constants.dart';
import 'package:tts_mod_vault/domain/enums/asset_type.dart';

part 'directories.freezed.dart';
part 'directories.g.dart';

/// The three user-chosen roots and every TTS path derived from them.
///
/// Only [modsDir], [savesDir] and [backupsDir] are stored; everything else
/// is derived with `package:path` so separators follow the host OS.
/// [backupsDir] is empty when the user has not picked a backups folder yet.
@freezed
abstract class Directories with _$Directories {
  const factory Directories({
    required String modsDir,
    required String savesDir,
    @Default('') String backupsDir,
  }) = _Directories;

  const Directories._();

  factory Directories.fromJson(Map<String, Object?> json) =>
      _$DirectoriesFromJson(json);

  /// No folders chosen yet.
  static const Directories empty = Directories(modsDir: '', savesDir: '');

  /// `Mods/Workshop`, where Workshop mod JSONs live.
  String get workshopDir => p.join(modsDir, ttsWorkshopFolder);

  /// `Saves/Saved Objects`.
  String get savedObjectsDir => p.join(savesDir, ttsSavedObjectsFolder);

  /// `Mods/Thumbnails`, where TTS keeps save thumbnails.
  String get thumbnailsDir => p.join(modsDir, ttsThumbnailsFolder);

  /// The cache folder for [type], e.g. `Mods/Images`.
  String assetDir(AssetType type) => p.join(modsDir, type.folderName);

  /// The "Raw" sibling folder for [type] (`Mods/Images Raw`,
  /// `Mods/Models Raw`), or null for types TTS does not write raw files for.
  String? rawAssetDir(AssetType type) {
    final raw = type.rawFolderName;
    return raw == null ? null : p.join(modsDir, raw);
  }

  /// Whether a backups folder has been chosen.
  bool get hasBackupsDir => backupsDir.isNotEmpty;
}
