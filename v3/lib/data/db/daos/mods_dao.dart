import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:tts_mod_vault/data/db/app_database.dart';
import 'package:tts_mod_vault/data/db/stat_fingerprint.dart';
import 'package:tts_mod_vault/data/db/tables.dart';
import 'package:tts_mod_vault/domain/enums/asset_type.dart';
import 'package:tts_mod_vault/domain/enums/audio_visibility.dart';
import 'package:tts_mod_vault/domain/models/mod_ref.dart';
import 'package:tts_mod_vault/domain/rules/file_key.dart';

part 'mods_dao.g.dart';

/// One URL found in a mod JSON: the URL, the JSON key it sat under and the
/// asset type derived from that key.
typedef ModAssetInput = ({String url, String assetKey, AssetType type});

/// A parsed mod ready to be written by [ModsDao.upsertMods].
///
/// Carries the indexable row fields and the mod's asset URLs. The user-owned
/// columns (`audio_visibility`, `invalid_urls_json`) are not part of it:
/// new rows get their defaults and existing rows keep their values.
final class ModUpsert {
  const ModUpsert({
    required this.ref,
    required this.folder,
    required this.saveName,
    required this.epochTime,
    required this.mtimeMs,
    required this.sizeBytes,
    required this.imagePath,
    required this.assets,
  });

  final ModRef ref;
  final String folder;
  final String saveName;
  final int? epochTime;
  final int mtimeMs;
  final int sizeBytes;
  final String? imagePath;
  final List<ModAssetInput> assets;
}

/// Writes to the `mods` and `mod_assets` tables. Rows are keyed by the
/// mod's normalised `json_path` (`ModRef.jsonPath`).
@DriftAccessor(tables: [Mods, ModAssets])
class ModsDao extends DatabaseAccessor<AppDatabase> with _$ModsDaoMixin {
  ModsDao(super.db);

  /// `json_path` to stat fingerprint for every indexed mod, for change
  /// detection against a fresh directory scan.
  Future<Map<String, StatFingerprint>> fingerprints() async {
    final query = selectOnly(mods)
      ..addColumns([mods.jsonPath, mods.mtimeMs, mods.sizeBytes]);
    final rows = await query.get();
    return {
      for (final row in rows)
        row.read(mods.jsonPath)!: (
          mtimeMs: row.read(mods.mtimeMs)!,
          sizeBytes: row.read(mods.sizeBytes)!,
        ),
    };
  }

  /// Inserts or updates each mod (by `json_path`) and replaces its asset
  /// rows, all in one transaction. `file_key` is computed with
  /// [fileKeyFromUrl]; a URL that appears twice in one mod is stored once
  /// (first occurrence wins).
  Future<void> upsertMods(List<ModUpsert> items) async {
    if (items.isEmpty) return;
    await batch((b) {
      for (final item in items) {
        b.insert(
          mods,
          _insertCompanion(item),
          onConflict: DoUpdate(
            (_) => _updateCompanion(item),
            target: [mods.jsonPath],
          ),
        );
        b.deleteWhere(modAssets, (t) => t.modPath.equals(item.ref.jsonPath));
        b.insertAll(
          modAssets,
          _assetCompanions(item),
          mode: InsertMode.insertOrIgnore,
        );
      }
    });
  }

  /// Removes the mods at [paths]; their asset rows go via cascade.
  Future<void> deleteByPaths(Iterable<String> paths) async {
    final list = paths.toList(growable: false);
    if (list.isEmpty) return;
    await customUpdate(
      'DELETE FROM mods WHERE json_path IN (SELECT value FROM json_each(?))',
      variables: [Variable.withString(jsonEncode(list))],
      updates: {mods, modAssets},
      updateKind: UpdateKind.delete,
    );
  }

  /// Sets the per-mod audio override.
  Future<void> setAudioVisibility(
    String jsonPath,
    AudioVisibility visibility,
  ) => (update(mods)..where((t) => t.jsonPath.equals(jsonPath))).write(
    ModsCompanion(audioVisibility: Value(visibility)),
  );

  /// Stores the URLs a URL check flagged as dead (empty clears the column).
  Future<void> setInvalidUrls(String jsonPath, List<String> urls) =>
      (update(mods)..where((t) => t.jsonPath.equals(jsonPath))).write(
        ModsCompanion(
          invalidUrlsJson: Value(urls.isEmpty ? null : jsonEncode(urls)),
        ),
      );

  /// Records a rename: the new `SaveName` and the rewritten file's stat.
  Future<void> rename(
    String jsonPath, {
    required String saveName,
    required int mtimeMs,
    int? sizeBytes,
  }) => (update(mods)..where((t) => t.jsonPath.equals(jsonPath))).write(
    ModsCompanion(
      saveName: Value(saveName),
      mtimeMs: Value(mtimeMs),
      sizeBytes: sizeBytes == null ? const Value.absent() : Value(sizeBytes),
    ),
  );

  ModsCompanion _insertCompanion(ModUpsert item) => ModsCompanion.insert(
    jsonPath: item.ref.jsonPath,
    id: item.ref.id,
    type: item.ref.type,
    folder: item.folder,
    saveName: item.saveName,
    epochTime: Value(item.epochTime),
    mtimeMs: item.mtimeMs,
    sizeBytes: item.sizeBytes,
    imagePath: Value(item.imagePath),
  );

  /// Everything except the key and the user-owned columns.
  ModsCompanion _updateCompanion(ModUpsert item) => ModsCompanion(
    id: Value(item.ref.id),
    type: Value(item.ref.type),
    folder: Value(item.folder),
    saveName: Value(item.saveName),
    epochTime: Value(item.epochTime),
    mtimeMs: Value(item.mtimeMs),
    sizeBytes: Value(item.sizeBytes),
    imagePath: Value(item.imagePath),
  );

  List<ModAssetsCompanion> _assetCompanions(ModUpsert item) {
    final seen = <String>{};
    return [
      for (final asset in item.assets)
        if (seen.add(asset.url))
          ModAssetsCompanion.insert(
            modPath: item.ref.jsonPath,
            url: asset.url,
            assetKey: asset.assetKey,
            assetType: asset.type,
            fileKey: fileKeyFromUrl(asset.url),
          ),
    ];
  }
}
