import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/data/db/app_database.dart';
import 'package:tts_mod_vault/domain/enums/asset_type.dart';
import 'package:tts_mod_vault/domain/enums/audio_visibility.dart';
import 'package:tts_mod_vault/domain/enums/mod_type.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<Map<String, QueryRow>> tableInfo(String table) async {
    final columns = await db.customSelect('PRAGMA table_info($table)').get();
    return {for (final c in columns) c.read<String>('name'): c};
  }

  Future<Set<String>> indexNames(String table) async {
    final rows = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'index' "
          "AND tbl_name = '$table' AND name NOT LIKE 'sqlite_%'",
        )
        .get();
    return rows.map((r) => r.read<String>('name')).toSet();
  }

  ModsCompanion mod(String jsonPath, {String id = '1'}) => ModsCompanion.insert(
    jsonPath: jsonPath,
    id: id,
    type: ModType.mod,
    folder: 'Workshop',
    saveName: 'One',
    mtimeMs: 1,
    sizeBytes: 1,
  );

  ModAssetsCompanion asset(String modPath, String url) =>
      ModAssetsCompanion.insert(
        modPath: modPath,
        url: url,
        assetKey: 'FaceURL',
        assetType: AssetType.image,
        fileKey: 'httpsxapng',
      );

  test('schema version 1 creates every table of plan 4.3', () async {
    final rows = await db
        .customSelect(
          'SELECT name FROM sqlite_master '
          "WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
        )
        .get();
    final names = rows.map((r) => r.read<String>('name')).toList()..sort();
    expect(names, ['backups', 'existing_files', 'kv', 'mod_assets', 'mods']);

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), AppDatabase.latestSchemaVersion);
    expect(AppDatabase.latestSchemaVersion, 1);
  });

  test(
    'indexes: mods.id, mod_assets.file_key, mod_assets.asset_type',
    () async {
      expect(await indexNames('mods'), contains('mods_id'));
      expect(
        await indexNames('mod_assets'),
        containsAll(['mod_assets_file_key', 'mod_assets_type']),
      );
    },
  );

  test('mods is keyed by json_path with a non-unique derived id', () async {
    final cols = await tableInfo('mods');
    expect(
      cols.keys,
      unorderedEquals([
        'json_path',
        'id',
        'type',
        'folder',
        'save_name',
        'epoch_time',
        'mtime_ms',
        'size_bytes',
        'image_path',
        'audio_visibility',
        'invalid_urls_json',
      ]),
    );
    expect(cols['json_path']!.read<int>('pk'), 1);
    expect(cols['json_path']!.read<String>('type').toUpperCase(), 'TEXT');
    expect(cols['id']!.read<int>('pk'), 0);
    expect(cols['id']!.read<int>('notnull'), 1);
    expect(cols['type']!.read<String>('type').toUpperCase(), 'INTEGER');
    expect(cols['epoch_time']!.read<int>('notnull'), 0);
    expect(cols['image_path']!.read<int>('notnull'), 0);
    expect(cols['invalid_urls_json']!.read<int>('notnull'), 0);
    expect(cols['mtime_ms']!.read<int>('notnull'), 1);
    expect(cols['audio_visibility']!.read<String>('dflt_value'), '0');

    // Two rows may share an id as long as their paths differ.
    await db.into(db.mods).insert(mod('Workshop/1.json'));
    await db.into(db.mods).insert(mod('Workshop/Queued/1.json'));
    final ids = await (db.selectOnly(db.mods)..addColumns([db.mods.id])).get();
    expect(ids.map((r) => r.read(db.mods.id)), ['1', '1']);

    await expectLater(
      db.into(db.mods).insert(mod('Workshop/1.json', id: 'other')),
      throwsA(isA<SqliteException>()),
    );
  });

  test('mod_assets, existing_files and backups keys match the plan', () async {
    final assets = await tableInfo('mod_assets');
    expect(
      assets.keys,
      unorderedEquals([
        'mod_path',
        'url',
        'asset_key',
        'asset_type',
        'file_key',
      ]),
    );
    expect(assets['mod_path']!.read<int>('pk'), 1);
    expect(assets['url']!.read<int>('pk'), 2);

    final fks = await db
        .customSelect('PRAGMA foreign_key_list(mod_assets)')
        .get();
    expect(fks, hasLength(1));
    expect(fks.single.read<String>('table'), 'mods');
    expect(fks.single.read<String>('from'), 'mod_path');
    expect(fks.single.read<String>('to'), 'json_path');
    expect(fks.single.read<String>('on_delete').toUpperCase(), 'CASCADE');

    final files = await tableInfo('existing_files');
    expect(files.keys, unorderedEquals(['asset_type', 'file_key', 'path']));
    expect(files['asset_type']!.read<int>('pk'), 1);
    expect(files['file_key']!.read<int>('pk'), 2);

    final backups = await tableInfo('backups');
    expect(
      backups.keys,
      unorderedEquals(['path', 'mtime_ms', 'size_bytes', 'asset_count']),
    );
    expect(backups['path']!.read<int>('pk'), 1);

    final kv = await tableInfo('kv');
    expect(kv.keys, unorderedEquals(['key', 'value']));
    expect(kv['key']!.read<int>('pk'), 1);
  });

  test('beforeOpen enables foreign keys', () async {
    final row = await db.customSelect('PRAGMA foreign_keys').getSingle();
    expect(row.read<int>('foreign_keys'), 1);
  });

  test('deleting a mod cascades to its assets only', () async {
    await db.into(db.mods).insert(mod('Workshop/1.json'));
    await db.into(db.mods).insert(mod('Workshop/Queued/1.json'));
    await db.into(db.modAssets).insert(asset('Workshop/1.json', 'https://x/a'));
    await db
        .into(db.modAssets)
        .insert(asset('Workshop/Queued/1.json', 'https://x/a'));

    await (db.delete(
      db.mods,
    )..where((t) => t.jsonPath.equals('Workshop/1.json'))).go();

    final left = await db.select(db.modAssets).get();
    expect(left.map((r) => r.modPath), ['Workshop/Queued/1.json']);
  });

  test('an asset for an unknown mod is rejected by the foreign key', () async {
    await expectLater(
      db.into(db.modAssets).insert(asset('ghost.json', 'https://x/a')),
      throwsA(isA<SqliteException>()),
    );
  });

  test('enum columns round-trip through their dbValue', () async {
    await db
        .into(db.mods)
        .insert(
          ModsCompanion.insert(
            jsonPath: 'Saves/Saved Objects/s.json',
            id: 's',
            type: ModType.savedObject,
            folder: 'Saved Objects',
            saveName: 'S',
            mtimeMs: 1,
            sizeBytes: 1,
            audioVisibility: const Value(AudioVisibility.alwaysHide),
          ),
        );
    final raw = await db
        .customSelect("SELECT type, audio_visibility FROM mods WHERE id = 's'")
        .getSingle();
    expect(raw.read<int>('type'), ModType.savedObject.dbValue);
    expect(
      raw.read<int>('audio_visibility'),
      AudioVisibility.alwaysHide.dbValue,
    );

    final row = await db.select(db.mods).getSingle();
    expect(row.type, ModType.savedObject);
    expect(row.audioVisibility, AudioVisibility.alwaysHide);
    expect(row.epochTime, isNull);
  });

  test('audio_visibility defaults to useGlobalSetting', () async {
    await db.into(db.mods).insert(mod('Workshop/1.json'));
    final row = await db.select(db.mods).getSingle();
    expect(row.audioVisibility, AudioVisibility.useGlobalSetting);
  });

  test('duplicate kv key is rejected by the primary key', () async {
    await db.into(db.kv).insert(KvCompanion.insert(key: 'a', value: '1'));
    await expectLater(
      db.into(db.kv).insert(KvCompanion.insert(key: 'a', value: '2')),
      throwsA(isA<SqliteException>()),
    );
  });

  test('a file-backed database runs in WAL mode with NORMAL sync', () async {
    final dir = await Directory.systemTemp.createTemp('ttsmv_db_test');
    final fileDb = AppDatabase(
      NativeDatabase(File(p.join(dir.path, 'v.sqlite'))),
    );
    try {
      final journal = await fileDb
          .customSelect('PRAGMA journal_mode')
          .getSingle();
      expect(journal.read<String>('journal_mode').toLowerCase(), 'wal');
      final sync = await fileDb.customSelect('PRAGMA synchronous').getSingle();
      expect(sync.read<int>('synchronous'), 1); // NORMAL
      final fk = await fileDb.customSelect('PRAGMA foreign_keys').getSingle();
      expect(fk.read<int>('foreign_keys'), 1);
    } finally {
      await fileDb.close();
      await dir.delete(recursive: true);
    }
  });
}
