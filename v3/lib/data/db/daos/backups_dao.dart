import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:tts_mod_vault/data/db/app_database.dart';
import 'package:tts_mod_vault/data/db/stat_fingerprint.dart';
import 'package:tts_mod_vault/data/db/tables.dart';

part 'backups_dao.g.dart';

/// One `.ttsmod` file with its stat and counted assets, for
/// [BackupsDao.upsertAll].
typedef BackupUpsert = ({
  String path,
  int mtimeMs,
  int sizeBytes,
  int assetCount,
});

/// Cache of asset counts for `.ttsmod` files, keyed by path.
@DriftAccessor(tables: [Backups])
class BackupsDao extends DatabaseAccessor<AppDatabase> with _$BackupsDaoMixin {
  BackupsDao(super.db);

  /// `path` to stat fingerprint for every cached backup; a backup whose
  /// fingerprint matches does not need its zip re-read.
  Future<Map<String, StatFingerprint>> fingerprints() async {
    final query = selectOnly(backups)
      ..addColumns([backups.path, backups.mtimeMs, backups.sizeBytes]);
    final rows = await query.get();
    return {
      for (final row in rows)
        row.read(backups.path)!: (
          mtimeMs: row.read(backups.mtimeMs)!,
          sizeBytes: row.read(backups.sizeBytes)!,
        ),
    };
  }

  /// Inserts or replaces the given backups in one transaction.
  Future<void> upsertAll(Iterable<BackupUpsert> items) async {
    final companions = [
      for (final item in items)
        BackupsCompanion.insert(
          path: item.path,
          mtimeMs: item.mtimeMs,
          sizeBytes: item.sizeBytes,
          assetCount: item.assetCount,
        ),
    ];
    if (companions.isEmpty) return;
    await batch(
      (b) => b.insertAll(backups, companions, mode: InsertMode.insertOrReplace),
    );
  }

  /// Removes the cached rows for backups that no longer exist.
  Future<void> deleteByPaths(Iterable<String> paths) async {
    final list = paths.toList(growable: false);
    if (list.isEmpty) return;
    await customUpdate(
      'DELETE FROM backups WHERE path IN (SELECT value FROM json_each(?))',
      variables: [Variable.withString(jsonEncode(list))],
      updates: {backups},
      updateKind: UpdateKind.delete,
    );
  }
}
