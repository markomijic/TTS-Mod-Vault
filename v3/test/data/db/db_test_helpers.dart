import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/data/db/daos/mods_dao.dart';
import 'package:tts_mod_vault/domain/enums/asset_type.dart';
import 'package:tts_mod_vault/domain/enums/mod_type.dart';
import 'package:tts_mod_vault/domain/models/mod_ref.dart';

/// Builds a [ModUpsert] for tests with sensible defaults. The JSON lives in
/// the standard folder for [type] unless [parentDir] is given (used to put
/// two files with the same basename in different folders).
ModUpsert modUpsert(
  String id, {
  ModType type = ModType.mod,
  String? parentDir,
  String? folder,
  String? saveName,
  int? epochTime,
  int mtimeMs = 1000,
  int sizeBytes = 100,
  String? imagePath,
  List<ModAssetInput> assets = const [],
}) {
  final parent =
      parentDir ??
      switch (type) {
        ModType.mod => p.join('Mods', 'Workshop'),
        ModType.save => 'Saves',
        ModType.savedObject => p.join('Saves', 'Saved Objects'),
      };
  return ModUpsert(
    ref: ModRef.fromPath(type, p.join(parent, '$id.json')),
    folder: folder ?? p.basename(parent),
    saveName: saveName ?? 'Mod $id',
    epochTime: epochTime,
    mtimeMs: mtimeMs,
    sizeBytes: sizeBytes,
    imagePath: imagePath,
    assets: assets,
  );
}

/// The normalised JSON path [modUpsert] produces for [id] and [type].
String modPath(String id, {ModType type = ModType.mod, String? parentDir}) =>
    modUpsert(id, type: type, parentDir: parentDir).ref.jsonPath;

/// An image asset input for [url].
ModAssetInput image(String url) =>
    (url: url, assetKey: 'FaceURL', type: AssetType.image);

/// An audio asset input for [url].
ModAssetInput audio(String url) =>
    (url: url, assetKey: 'CurrentAudioURL', type: AssetType.audio);

/// A model asset input for [url].
ModAssetInput model(String url) =>
    (url: url, assetKey: 'MeshURL', type: AssetType.model);

/// A PDF asset input for [url].
ModAssetInput pdf(String url) =>
    (url: url, assetKey: 'PDFUrl', type: AssetType.pdf);
