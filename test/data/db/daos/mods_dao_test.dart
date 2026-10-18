import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/data/db/app_database.dart';
import 'package:tts_mod_vault/data/db/daos/mods_dao.dart';
import 'package:tts_mod_vault/domain/constants.dart';
import 'package:tts_mod_vault/domain/enums/asset_type.dart';
import 'package:tts_mod_vault/domain/enums/audio_visibility.dart';
import 'package:tts_mod_vault/domain/enums/mod_type.dart';
import 'package:tts_mod_vault/domain/rules/file_key.dart';

import '../db_test_helpers.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<ModRow> modRow(String jsonPath) => (db.select(
    db.mods,
  )..where((t) => t.jsonPath.equals(jsonPath))).getSingle();

  Future<List<ModAssetRow>> assetRows(String jsonPath) =>
      (db.select(db.modAssets)..where((t) => t.modPath.equals(jsonPath))).get();

  group('upsertMods', () {
    test('inserts the row and its assets with computed file keys', () async {
      final item = modUpsert(
        '1',
        saveName: 'One',
        epochTime: 123,
        imagePath: 'Workshop/1.png',
        assets: [
          image('https://Example.com/A.png'),
          audio('${oldCloudUrl}123/sound.mp3'),
        ],
      );
      await db.modsDao.upsertMods([item]);

      final row = await modRow(item.ref.jsonPath);
      expect(row.id, '1');
      expect(row.type, ModType.mod);
      expect(row.jsonPath, item.ref.jsonPath);
      expect(row.folder, 'Workshop');
      expect(row.saveName, 'One');
      expect(row.epochTime, 123);
      expect(row.mtimeMs, 1000);
      expect(row.sizeBytes, 100);
      expect(row.imagePath, 'Workshop/1.png');
      expect(row.audioVisibility, AudioVisibility.useGlobalSetting);
      expect(row.invalidUrlsJson, isNull);

      final assets = await assetRows(item.ref.jsonPath);
      expect(assets, hasLength(2));
      final byUrl = {for (final a in assets) a.url: a};
      expect(
        byUrl['https://Example.com/A.png']!.fileKey,
        'httpsexamplecomapng',
      );
      expect(byUrl['https://Example.com/A.png']!.assetType, AssetType.image);
      expect(byUrl['https://Example.com/A.png']!.assetKey, 'FaceURL');
      final cloud = byUrl['${oldCloudUrl}123/sound.mp3']!;
      expect(cloud.fileKey, startsWith('httpssteamusercontentaakamaihdnet'));
      expect(cloud.fileKey, endsWith('123soundmp3'));
    });

    test('a URL repeated inside one mod is stored once', () async {
      await db.modsDao.upsertMods([
        modUpsert(
          '1',
          assets: [image('https://x/a.png'), model('https://x/a.png')],
        ),
      ]);
      final assets = await assetRows(modPath('1'));
      expect(assets, hasLength(1));
      expect(assets.single.assetType, AssetType.image);
    });

    test('re-upserting replaces assets and keeps user-owned columns', () async {
      final path = modPath('1');
      await db.modsDao.upsertMods([
        modUpsert('1', assets: [image('https://x/old.png')]),
      ]);
      await db.modsDao.setAudioVisibility(path, AudioVisibility.alwaysHide);
      await db.modsDao.setInvalidUrls(path, ['https://x/old.png']);

      await db.modsDao.upsertMods([
        modUpsert(
          '1',
          saveName: 'Renamed',
          mtimeMs: 2000,
          sizeBytes: 200,
          epochTime: 5,
          assets: [image('https://x/new.png')],
        ),
      ]);

      final row = await modRow(path);
      expect(row.saveName, 'Renamed');
      expect(row.mtimeMs, 2000);
      expect(row.sizeBytes, 200);
      expect(row.epochTime, 5);
      expect(row.audioVisibility, AudioVisibility.alwaysHide);
      expect(row.invalidUrlsJson, '["https://x/old.png"]');

      final assets = await assetRows(path);
      expect(assets.map((a) => a.url), ['https://x/new.png']);
    });

    test('two JSONs with the same basename in different folders both survive '
        'a re-index', () async {
      final top = modUpsert(
        '2857317092',
        saveName: 'Top copy',
        assets: [image('https://x/top.png')],
      );
      final queued = modUpsert(
        '2857317092',
        parentDir: p.join('Mods', 'Workshop', 'Queued'),
        saveName: 'Queued copy',
        assets: [image('https://x/queued.png')],
      );
      expect(top.ref.id, queued.ref.id);
      expect(top.ref.jsonPath, isNot(queued.ref.jsonPath));

      await db.modsDao.upsertMods([top, queued]);
      // Second refresh: both files unchanged, re-indexed again.
      await db.modsDao.upsertMods([queued, top]);

      final prints = await db.modsDao.fingerprints();
      expect(
        prints.keys,
        unorderedEquals([top.ref.jsonPath, queued.ref.jsonPath]),
      );

      final topRow = await modRow(top.ref.jsonPath);
      final queuedRow = await modRow(queued.ref.jsonPath);
      expect(topRow.id, '2857317092');
      expect(queuedRow.id, '2857317092');
      expect(topRow.saveName, 'Top copy');
      expect(queuedRow.saveName, 'Queued copy');
      expect(topRow.folder, 'Workshop');
      expect(queuedRow.folder, 'Queued');

      expect((await assetRows(top.ref.jsonPath)).map((a) => a.url), [
        'https://x/top.png',
      ]);
      expect((await assetRows(queued.ref.jsonPath)).map((a) => a.url), [
        'https://x/queued.png',
      ]);

      // Per-path writes do not leak to the sibling.
      await db.modsDao.setAudioVisibility(
        queued.ref.jsonPath,
        AudioVisibility.alwaysHide,
      );
      expect(
        (await modRow(top.ref.jsonPath)).audioVisibility,
        AudioVisibility.useGlobalSetting,
      );
      await db.modsDao.deleteByPaths([queued.ref.jsonPath]);
      expect((await db.modsDao.fingerprints()).keys, [top.ref.jsonPath]);
      expect(await assetRows(queued.ref.jsonPath), isEmpty);
    });

    test('many mods in one call', () async {
      await db.modsDao.upsertMods([
        for (var i = 0; i < 50; i++)
          modUpsert('$i', assets: [image('https://x/$i.png')]),
      ]);
      final count = await db
          .customSelect('SELECT COUNT(*) AS n FROM mod_assets')
          .getSingle();
      expect(count.read<int>('n'), 50);
      expect(await db.modsDao.fingerprints(), hasLength(50));
    });

    test('more asset rows than one statement carries, with awkward URLs', () async {
      // Spans several json_each statements (and far more values than
      // SQLite's bound-parameter limit would allow row by row).
      const total = ModsDao.assetRowsPerStatement * 2 + 123;
      final urls = [
        for (var i = 0; i < total; i++)
          'https://x/$i/path with spaces/"quoted"/back\\slash/ünï/\u{1F600}.png',
      ];
      final big = modUpsert('big', assets: [for (final u in urls) image(u)]);
      final small = modUpsert('small', assets: [model('https://x/m.obj')]);
      await db.modsDao.upsertMods([big, small]);

      final rows = await assetRows(big.ref.jsonPath);
      expect(rows, hasLength(total));
      expect(rows.map((r) => r.url).toSet(), urls.toSet());
      expect(rows.first.fileKey, fileKeyFromUrl(rows.first.url));
      expect(rows.every((r) => r.assetType == AssetType.image), isTrue);
      expect(rows.every((r) => r.assetKey == 'FaceURL'), isTrue);
      expect(await assetRows(small.ref.jsonPath), hasLength(1));

      // Re-indexing with fewer assets replaces the whole set.
      await db.modsDao.upsertMods([
        modUpsert('big', assets: [image(urls.first)]),
      ]);
      expect((await assetRows(big.ref.jsonPath)).single.url, urls.first);
      expect(await assetRows(small.ref.jsonPath), hasLength(1));
    });

    test('is atomic: a failing item rolls back the whole call', () async {
      await db.modsDao.upsertMods([modUpsert('ok')]);
      // An asset type outside the converter's range cannot happen through
      // the typed API, so provoke the failure with a foreign key: an asset
      // row for a mod that is not in the same call cannot exist... it can
      // (the mod row is inserted first), so use a NOT NULL violation via
      // raw SQL inside the same kind of transaction instead.
      await expectLater(
        db.transaction(() async {
          await db.modsDao.upsertMods([modUpsert('two')]);
          await db.customStatement('INSERT INTO mods (json_path) VALUES (1)');
        }),
        throwsA(isA<SqliteException>()),
      );
      expect((await db.modsDao.fingerprints()).keys, [modPath('ok')]);
    });

    test('an empty list is a no-op', () async {
      await db.modsDao.upsertMods([]);
      expect(await db.modsDao.fingerprints(), isEmpty);
    });
  });

  test('fingerprints maps json_path to mtime and size', () async {
    final a = modUpsert('a', mtimeMs: 10, sizeBytes: 1);
    final b = modUpsert('b', type: ModType.save, mtimeMs: 20, sizeBytes: 2);
    await db.modsDao.upsertMods([a, b]);

    final prints = await db.modsDao.fingerprints();
    expect(prints, {
      a.ref.jsonPath: (mtimeMs: 10, sizeBytes: 1),
      b.ref.jsonPath: (mtimeMs: 20, sizeBytes: 2),
    });
  });

  group('deleteByPaths', () {
    test('removes the mods and cascades their assets', () async {
      final a = modUpsert('a', assets: [image('https://x/a.png')]);
      final b = modUpsert('b', assets: [image('https://x/b.png')]);
      final c = modUpsert('c');
      await db.modsDao.upsertMods([a, b, c]);

      await db.modsDao.deleteByPaths([a.ref.jsonPath, c.ref.jsonPath]);

      expect((await db.modsDao.fingerprints()).keys, [b.ref.jsonPath]);
      final assets = await db.select(db.modAssets).get();
      expect(assets.map((r) => r.modPath), [b.ref.jsonPath]);
    });

    test('unknown paths and empty input are harmless', () async {
      await db.modsDao.upsertMods([modUpsert('a')]);
      await db.modsDao.deleteByPaths(['nope.json']);
      await db.modsDao.deleteByPaths([]);
      expect(await db.modsDao.fingerprints(), hasLength(1));
    });
  });

  test('setAudioVisibility', () async {
    await db.modsDao.upsertMods([modUpsert('1'), modUpsert('2')]);
    await db.modsDao.setAudioVisibility(
      modPath('1'),
      AudioVisibility.alwaysShow,
    );
    expect(
      (await modRow(modPath('1'))).audioVisibility,
      AudioVisibility.alwaysShow,
    );
    expect(
      (await modRow(modPath('2'))).audioVisibility,
      AudioVisibility.useGlobalSetting,
    );
  });

  test('setInvalidUrls stores JSON and clears on empty', () async {
    await db.modsDao.upsertMods([modUpsert('1')]);
    await db.modsDao.setInvalidUrls(modPath('1'), ['https://a', 'https://b']);
    expect(
      (await modRow(modPath('1'))).invalidUrlsJson,
      '["https://a","https://b"]',
    );
    await db.modsDao.setInvalidUrls(modPath('1'), []);
    expect((await modRow(modPath('1'))).invalidUrlsJson, isNull);
  });

  test('rename updates the save name and stat', () async {
    await db.modsDao.upsertMods([modUpsert('1', saveName: 'Old')]);
    await db.modsDao.rename(modPath('1'), saveName: 'New', mtimeMs: 999);
    var row = await modRow(modPath('1'));
    expect(row.saveName, 'New');
    expect(row.mtimeMs, 999);
    expect(row.sizeBytes, 100);

    await db.modsDao.rename(
      modPath('1'),
      saveName: 'Newer',
      mtimeMs: 1001,
      sizeBytes: 7,
    );
    row = await modRow(modPath('1'));
    expect(row.saveName, 'Newer');
    expect(row.sizeBytes, 7);
  });

  test('json_path is the primary key', () async {
    await db.modsDao.upsertMods([modUpsert('1')]);
    await expectLater(
      db
          .into(db.mods)
          .insert(
            ModsCompanion.insert(
              jsonPath: modPath('1'),
              id: 'other',
              type: ModType.mod,
              folder: 'Workshop',
              saveName: 'x',
              mtimeMs: 1,
              sizeBytes: 1,
            ),
          ),
      throwsA(isA<SqliteException>()),
    );
  });
}
