import 'package:tts_mod_vault/core/storage/key_value_store.dart';
import 'package:tts_mod_vault/data/db/app_database.dart';

/// [KeyValueStore] backed by the `kv` table of [AppDatabase].
final class DriftKeyValueStore implements KeyValueStore {
  DriftKeyValueStore(this._db);

  final AppDatabase _db;

  @override
  Future<String?> read(String key) async {
    final row = await (_db.select(
      _db.kv,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  @override
  Future<void> write(String key, String value) async {
    await _db
        .into(_db.kv)
        .insertOnConflictUpdate(KvCompanion.insert(key: key, value: value));
  }

  @override
  Future<void> delete(String key) async {
    await (_db.delete(_db.kv)..where((t) => t.key.equals(key))).go();
  }
}
