import 'dart:convert' show jsonEncode;
import 'dart:math' show min;

import 'package:drift/drift.dart';
import 'package:tts_mod_vault/data/db/app_database.dart';
import 'package:tts_mod_vault/data/db/tables.dart';
import 'package:tts_mod_vault/domain/enums/asset_type.dart';

part 'existing_files_dao.g.dart';

/// Writes to and reads the `existing_files` index of cached asset files.
@DriftAccessor(tables: [ExistingFiles])
class ExistingFilesDao extends DatabaseAccessor<AppDatabase>
    with _$ExistingFilesDaoMixin {
  ExistingFilesDao(super.db);

  /// Rows per multi-row `INSERT ... VALUES` statement in [replaceAll]:
  /// 3 columns x 333 rows = 999 bound parameters, the limit of older SQLite
  /// builds.
  static const int rowsPerStatement = 333;

  /// Makes the rows of [type] exactly [files] in one transaction. When two
  /// files map to the same key (e.g. `x.png` and `x.jpg`) the last one wins.
  ///
  /// Implemented as a diff inside SQLite rather than delete-and-reinsert:
  /// keys no longer listed are deleted (one `NOT IN` over the key list,
  /// passed as a JSON array and expanded with `json_each`), new keys are
  /// inserted and changed paths updated by multi-row `INSERT ... ON
  /// CONFLICT DO UPDATE` statements of [rowsPerStatement] rows; a row that
  /// already matches is not touched. On an unchanged cache folder (every
  /// warm start) that is a few index lookups per file and no page writes,
  /// where rewriting ~8k rows took ~100 ms and grew the WAL by megabytes
  /// per refresh.
  Future<void> replaceAll(
    AssetType type,
    Iterable<({String fileKey, String path})> files,
  ) async {
    final list = files.toList(growable: false);
    await transaction(() async {
      await customUpdate(
        'DELETE FROM existing_files WHERE asset_type = ? '
        'AND file_key NOT IN (SELECT value FROM json_each(?))',
        variables: [
          Variable.withInt(type.dbValue),
          Variable.withString(jsonEncode([for (final f in list) f.fileKey])),
        ],
        updates: {existingFiles},
        updateKind: UpdateKind.delete,
      );
      for (var start = 0; start < list.length; start += rowsPerStatement) {
        final end = min(start + rowsPerStatement, list.length);
        await customUpdate(
          'INSERT INTO existing_files (asset_type, file_key, path) VALUES '
          '${List.filled(end - start, '(?, ?, ?)').join(', ')} '
          'ON CONFLICT(asset_type, file_key) DO UPDATE SET path = excluded.path '
          'WHERE path != excluded.path',
          variables: [
            for (var i = start; i < end; i++) ...[
              Variable.withInt(type.dbValue),
              Variable.withString(list[i].fileKey),
              Variable.withString(list[i].path),
            ],
          ],
          updates: {existingFiles},
          updateKind: UpdateKind.insert,
        );
      }
    });
  }

  /// Adds or updates one file (after a download or import).
  Future<void> upsert(AssetType type, String fileKey, String path) =>
      into(existingFiles).insertOnConflictUpdate(
        ExistingFilesCompanion.insert(
          assetType: type,
          fileKey: fileKey,
          path: path,
        ),
      );

  /// Removes one file (after a delete or cleanup).
  Future<void> remove(AssetType type, String fileKey) =>
      (delete(existingFiles)..where(
            (t) => t.assetType.equalsValue(type) & t.fileKey.equals(fileKey),
          ))
          .go();

  /// The cached file's path, or null when it is not on disk.
  Future<String?> pathFor(AssetType type, String fileKey) async {
    final query = selectOnly(existingFiles)
      ..addColumns([existingFiles.path])
      ..where(
        existingFiles.assetType.equalsValue(type) &
            existingFiles.fileKey.equals(fileKey),
      );
    final row = await query.getSingleOrNull();
    return row?.read(existingFiles.path);
  }

  /// Number of indexed files per type; every [AssetType] is present.
  Future<Map<AssetType, int>> countByType() async {
    final count = countAll();
    final query = selectOnly(existingFiles)
      ..addColumns([existingFiles.assetType, count])
      ..groupBy([existingFiles.assetType]);
    final rows = await query.get();
    final result = {for (final type in AssetType.values) type: 0};
    for (final row in rows) {
      final type = row.readWithConverter(existingFiles.assetType);
      if (type != null) result[type] = row.read(count) ?? 0;
    }
    return result;
  }
}
