import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_mod_vault/data/db/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('schema version 1 creates only the kv table', () async {
    final rows = await db
        .customSelect(
          'SELECT name FROM sqlite_master '
          "WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
        )
        .get();
    final names = rows.map((r) => r.read<String>('name')).toList()..sort();
    expect(names, ['kv']);

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), AppDatabase.latestSchemaVersion);
    expect(AppDatabase.latestSchemaVersion, 1);
  });

  test('kv has key TEXT PRIMARY KEY and value TEXT NOT NULL', () async {
    final columns = await db.customSelect('PRAGMA table_info(kv)').get();
    final byName = {for (final c in columns) c.read<String>('name'): c};
    expect(byName.keys, unorderedEquals(['key', 'value']));

    final key = byName['key']!;
    expect(key.read<String>('type').toUpperCase(), 'TEXT');
    expect(key.read<int>('pk'), 1);
    expect(key.read<int>('notnull'), 1);

    final value = byName['value']!;
    expect(value.read<String>('type').toUpperCase(), 'TEXT');
    expect(value.read<int>('pk'), 0);
    expect(value.read<int>('notnull'), 1);
  });

  test('beforeOpen enables foreign keys', () async {
    final row = await db.customSelect('PRAGMA foreign_keys').getSingle();
    expect(row.read<int>('foreign_keys'), 1);
  });

  test('duplicate key is rejected by the primary key', () async {
    await db.into(db.kv).insert(KvCompanion.insert(key: 'a', value: '1'));
    await expectLater(
      db.into(db.kv).insert(KvCompanion.insert(key: 'a', value: '2')),
      throwsA(isA<SqliteException>()),
    );
  });
}
