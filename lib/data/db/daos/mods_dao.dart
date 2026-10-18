import 'dart:convert';
import 'dart:math' show min;

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

  /// Asset rows per multi-row `INSERT ... VALUES` statement in
  /// [upsertMods]: 5 columns x 199 rows = 995 bound parameters, under the
  /// 999 limit of older SQLite builds.
  static const int assetRowsPerStatement = 199;

  /// Inserts or updates each mod (by `json_path`) and replaces its asset
  /// rows, all in one transaction. `file_key` is computed with
  /// [fileKeyFromUrl]; a URL that appears twice in one mod is stored once
  /// (first occurrence wins). The user-owned columns of an existing row
  /// (`audio_visibility`, `invalid_urls_json`) are left alone.
  ///
  /// The asset rows go in as multi-row `INSERT ... VALUES` statements of
  /// [assetRowsPerStatement] rows. Measured on the reference library's ~19k
  /// rows (`tool/bench/db_probe.dart`): one bound insert per row through
  /// drift's `batch` and a `json_each` expansion of one JSON array both land
  /// around 235 ms, the multi-row form around 180 ms, because the cost is
  /// SQLite's row and index writes plus, for JSON, parsing ~5 MB of text;
  /// the number of statements hardly matters.
  Future<void> upsertMods(List<ModUpsert> items) async {
    if (items.isEmpty) return;
    await transaction(() async {
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
        }
      });
      await customUpdate(
        'DELETE FROM mod_assets '
        'WHERE mod_path IN (SELECT value FROM json_each(?))',
        variables: [
          Variable.withString(
            jsonEncode([for (final item in items) item.ref.jsonPath]),
          ),
        ],
        updates: {modAssets},
        updateKind: UpdateKind.delete,
      );
      final rows = _assetRows(items);
      for (var start = 0; start < rows.length; start += assetRowsPerStatement) {
        final end = min(start + assetRowsPerStatement, rows.length);
        await customUpdate(
          'INSERT OR IGNORE INTO mod_assets '
          '(mod_path, url, asset_key, asset_type, file_key) VALUES '
          '${List.filled(end - start, '(?, ?, ?, ?, ?)').join(', ')}',
          variables: [
            for (var i = start; i < end; i++) ...[
              Variable.withString(rows[i].modPath),
              Variable.withString(rows[i].url),
              Variable.withString(rows[i].assetKey),
              Variable.withInt(rows[i].assetType),
              Variable.withString(rows[i].fileKey),
            ],
          ],
          updates: {modAssets},
          updateKind: UpdateKind.insert,
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

  /// One `mod_assets` row per asset, URLs de-duplicated per mod.
  static List<_AssetRow> _assetRows(List<ModUpsert> items) {
    final rows = <_AssetRow>[];
    for (final item in items) {
      final seen = <String>{};
      for (final asset in item.assets) {
        if (!seen.add(asset.url)) continue;
        rows.add((
          modPath: item.ref.jsonPath,
          url: asset.url,
          assetKey: asset.assetKey,
          assetType: asset.type.dbValue,
          fileKey: fileKeyFromUrl(asset.url),
        ));
      }
    }
    return rows;
  }
}

typedef _AssetRow = ({
  String modPath,
  String url,
  String assetKey,
  int assetType,
  String fileKey,
});
