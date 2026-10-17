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

  /// Replaces every row of [type] with [files] in one transaction. When two
  /// files map to the same key (e.g. `x.png` and `x.jpg`) the last one wins.
  Future<void> replaceAll(
    AssetType type,
    Iterable<({String fileKey, String path})> files,
  ) async {
    await batch((b) {
      b.deleteWhere(existingFiles, (t) => t.assetType.equalsValue(type));
      b.insertAll(existingFiles, [
        for (final file in files)
          ExistingFilesCompanion.insert(
            assetType: type,
            fileKey: file.fileKey,
            path: file.path,
          ),
      ], mode: InsertMode.insertOrReplace);
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
