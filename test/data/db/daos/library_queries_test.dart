import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_mod_vault/data/db/app_database.dart';
import 'package:tts_mod_vault/data/db/daos/mods_dao.dart';
import 'package:tts_mod_vault/domain/enums/asset_type.dart';
import 'package:tts_mod_vault/domain/enums/audio_visibility.dart';
import 'package:tts_mod_vault/domain/enums/backup_status.dart';
import 'package:tts_mod_vault/domain/enums/mod_type.dart';
import 'package:tts_mod_vault/domain/models/mod.dart';
import 'package:tts_mod_vault/domain/rules/file_key.dart';

import '../db_test_helpers.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  final pathA = modPath('a');
  final pathB = modPath('b');
  final pathC = modPath('c', type: ModType.save);

  // Mod "a": 2 images (1 present), 1 audio (present), 1 model (missing).
  // Mod "b": no assets. Save "c": 1 pdf (present).
  Future<void> seed() async {
    await db.modsDao.upsertMods([
      modUpsert(
        'a',
        saveName: 'alpha',
        epochTime: 100,
        mtimeMs: 5000,
        sizeBytes: 50,
        imagePath: 'Workshop/a.png',
        assets: [
          image('https://x/img1.png'),
          image('https://x/img2.png'),
          audio('https://x/song.mp3'),
          model('https://x/mesh.obj'),
        ],
      ),
      modUpsert('b', saveName: 'Beta'),
      modUpsert(
        'c',
        type: ModType.save,
        saveName: 'gamma',
        assets: [pdf('https://x/rules.pdf')],
      ),
    ]);
    await db.existingFilesDao.replaceAll(AssetType.image, [
      (fileKey: fileKeyFromUrl('https://x/img1.png'), path: 'Images/img1.png'),
    ]);
    await db.existingFilesDao.replaceAll(AssetType.audio, [
      (fileKey: fileKeyFromUrl('https://x/song.mp3'), path: 'Audio/song.mp3'),
    ]);
    await db.existingFilesDao.replaceAll(AssetType.pdf, [
      (fileKey: fileKeyFromUrl('https://x/rules.pdf'), path: 'PDF/rules.pdf'),
    ]);
  }

  group('modSummaries', () {
    test('returns the mods of one type sorted by save name', () async {
      await seed();
      final mods = await db.libraryQueries.modSummaries(
        ModType.mod,
        ignoreAudioGlobally: false,
      );
      expect(mods.map((m) => m.jsonPath), [pathA, pathB]);

      final saves = await db.libraryQueries.modSummaries(
        ModType.save,
        ignoreAudioGlobally: false,
      );
      expect(saves.map((m) => m.jsonPath), [pathC]);
      expect(
        await db.libraryQueries.modSummaries(
          ModType.savedObject,
          ignoreAudioGlobally: false,
        ),
        isEmpty,
      );
    });

    test('maps every mod column', () async {
      await seed();
      final a = (await db.libraryQueries.modSummaries(
        ModType.mod,
        ignoreAudioGlobally: false,
      )).first;
      expect(a.ref.type, ModType.mod);
      expect(a.ref.id, 'a');
      expect(a.ref.jsonPath, pathA);
      expect(a.saveName, 'alpha');
      expect(a.folder, 'Workshop');
      expect(a.epochTime, 100);
      expect(a.modified, DateTime.fromMillisecondsSinceEpoch(5000));
      expect(a.sizeBytes, 50);
      expect(a.imagePath, 'Workshop/a.png');
      expect(a.audio, AudioVisibility.useGlobalSetting);
      expect(a.backup, isNull);
      expect(a.backupStatus, BackupStatus.none);
      expect(a.invalidUrls, isEmpty);
    });

    test('counts total and present overall and per type', () async {
      await seed();
      final mods = await db.libraryQueries.modSummaries(
        ModType.mod,
        ignoreAudioGlobally: false,
      );
      final a = mods[0].summary;
      expect(a.total, 4);
      expect(a.present, 2);
      expect(a.missing, 2);
      expect(a.hasAudio, isTrue);
      expect(a.totalByType, {
        AssetType.image: 2,
        AssetType.audio: 1,
        AssetType.model: 1,
      });
      expect(a.presentByType, {
        AssetType.image: 1,
        AssetType.audio: 1,
        AssetType.model: 0,
      });

      final b = mods[1].summary;
      expect(b.total, 0);
      expect(b.present, 0);
      expect(b.hasAudio, isFalse);
      expect(b.totalByType, isEmpty);
      expect(b.presentByType, isEmpty);
    });

    test('hides audio per the global flag and per-mod override', () async {
      await seed();

      Future<Mod> a({required bool global}) async =>
          (await db.libraryQueries.modSummaries(
            ModType.mod,
            ignoreAudioGlobally: global,
          )).first;

      var mod = await a(global: true);
      expect(mod.summary.total, 3);
      expect(mod.summary.present, 1);
      expect(mod.summary.totalByType.containsKey(AssetType.audio), isFalse);
      expect(mod.summary.presentByType.containsKey(AssetType.audio), isFalse);
      expect(mod.summary.hasAudio, isTrue, reason: 'hasAudio ignores hiding');

      await db.modsDao.setAudioVisibility(pathA, AudioVisibility.alwaysShow);
      mod = await a(global: true);
      expect(mod.summary.total, 4);
      expect(mod.summary.totalByType[AssetType.audio], 1);

      await db.modsDao.setAudioVisibility(pathA, AudioVisibility.alwaysHide);
      mod = await a(global: false);
      expect(mod.summary.total, 3);
      expect(mod.audio, AudioVisibility.alwaysHide);
    });

    test('decodes invalid urls', () async {
      await seed();
      await db.modsDao.setInvalidUrls(pathA, ['https://x/img2.png']);
      final a = (await db.libraryQueries.modSummaries(
        ModType.mod,
        ignoreAudioGlobally: false,
      )).first;
      expect(a.invalidUrls, ['https://x/img2.png']);
    });

    test('same-basename mods in different folders are separate rows', () async {
      await db.modsDao.upsertMods([
        modUpsert('1', saveName: 'Top', assets: [image('https://x/t.png')]),
        modUpsert(
          '1',
          parentDir: 'Mods/Workshop/Queued',
          saveName: 'Queued',
          assets: [image('https://x/q1.png'), image('https://x/q2.png')],
        ),
      ]);
      final mods = await db.libraryQueries.modSummaries(
        ModType.mod,
        ignoreAudioGlobally: false,
      );
      expect(mods.map((m) => m.saveName), ['Queued', 'Top']);
      expect(mods.map((m) => m.id), ['1', '1']);
      expect(mods[0].summary.total, 2);
      expect(mods[1].summary.total, 1);
    });
  });

  test('modSummary returns one mod or null', () async {
    await seed();
    final c = await db.libraryQueries.modSummary(
      pathC,
      ignoreAudioGlobally: false,
    );
    expect(c, isNotNull);
    expect(c!.ref.type, ModType.save);
    expect(c.ref.id, 'c');
    expect(c.summary.total, 1);
    expect(c.summary.present, 1);
    expect(c.summary.totalByType, {AssetType.pdf: 1});
    expect(
      await db.libraryQueries.modSummary(
        'nope.json',
        ignoreAudioGlobally: false,
      ),
      isNull,
    );
  });

  group('missing invalid count', () {
    test('counts missing assets whose URL is stored as invalid', () async {
      await seed();
      await db.modsDao.upsertMods([
        modUpsert(
          'd',
          saveName: 'delta',
          assets: [image('https://x/dead.png'), audio('https://x/dead.mp3')],
        ),
      ]);
      // img1 and song are on disk: an invalid flag on them is not counted.
      await db.modsDao.setInvalidUrls(pathA, [
        'https://x/img1.png',
        'https://x/img2.png',
        'https://x/song.mp3',
        'https://x/mesh.obj',
      ]);
      await db.modsDao.setInvalidUrls(modPath('d'), [
        'https://x/dead.png',
        'https://x/dead.mp3',
      ]);

      Future<Map<String, int>> counts({required bool ignoreAudio}) async => {
        for (final m in await db.libraryQueries.modSummaries(
          ModType.mod,
          ignoreAudioGlobally: ignoreAudio,
        ))
          m.ref.id: m.missingInvalidCount,
      };

      expect(await counts(ignoreAudio: false), {'a': 2, 'b': 0, 'd': 2});
      // Hidden audio leaves both the missing and the invalid count.
      expect(await counts(ignoreAudio: true), {'a': 2, 'b': 0, 'd': 1});

      final d = await db.libraryQueries.modSummary(
        modPath('d'),
        ignoreAudioGlobally: false,
      );
      // Option (b): missing stays strict even when every missing URL is dead.
      expect(d!.missingCount, 2);
      expect(d.summary.isComplete, isFalse);
    });
  });

  group('assetsForMod', () {
    test('orders by type then url and joins paths', () async {
      await seed();
      final assets = await db.libraryQueries.assetsForMod(pathA);
      expect(assets.map((a) => a.url), [
        'https://x/song.mp3', // audio (1)
        'https://x/img1.png', // image (2)
        'https://x/img2.png',
        'https://x/mesh.obj', // model (3)
      ]);
      expect(assets[0].type, AssetType.audio);
      expect(assets[0].path, 'Audio/song.mp3');
      expect(assets[1].path, 'Images/img1.png');
      expect(assets[1].fileKey, fileKeyFromUrl('https://x/img1.png'));
      expect(assets[2].path, isNull);
      expect(assets[2].exists, isFalse);
      expect(assets[3].type, AssetType.model);
      expect(assets.every((a) => !a.invalid), isTrue);
    });

    test('flags invalid urls', () async {
      await seed();
      await db.modsDao.setInvalidUrls(pathA, ['https://x/mesh.obj']);
      final assets = await db.libraryQueries.assetsForMod(pathA);
      expect(assets.where((a) => a.invalid).map((a) => a.url), [
        'https://x/mesh.obj',
      ]);
    });

    test('includeAudio false drops audio rows', () async {
      await seed();
      final assets = await db.libraryQueries.assetsForMod(
        pathA,
        includeAudio: false,
      );
      expect(assets.map((a) => a.type), isNot(contains(AssetType.audio)));
      expect(assets, hasLength(3));
    });

    test('unknown mod or mod without assets yields an empty list', () async {
      await seed();
      expect(await db.libraryQueries.assetsForMod(pathB), isEmpty);
      expect(await db.libraryQueries.assetsForMod('nope.json'), isEmpty);
    });
  });

  group('distinctAssetUrls', () {
    test('lists each URL of the given mod types once, sorted', () async {
      await seed();
      await db.modsDao.upsertMods([
        // Shares a URL with mod "a"; the saved object's own URL is left out.
        modUpsert('d', assets: [image('https://y/shared.png')]),
        modUpsert(
          'e',
          type: ModType.save,
          assets: [image('https://x/img1.png'), image('https://y/shared.png')],
        ),
        modUpsert(
          'f',
          type: ModType.savedObject,
          assets: [image('https://z/object.png')],
        ),
      ]);

      expect(
        await db.libraryQueries.distinctAssetUrls({ModType.mod, ModType.save}),
        [
          'https://x/img1.png',
          'https://x/img2.png',
          'https://x/mesh.obj',
          'https://x/rules.pdf',
          'https://x/song.mp3',
          'https://y/shared.png',
        ],
      );
      expect(await db.libraryQueries.distinctAssetUrls({ModType.savedObject}), [
        'https://z/object.png',
      ]);
      expect(await db.libraryQueries.distinctAssetUrls(const {}), isEmpty);
    });
  });

  group('modPathsReferencingFileKeys', () {
    test('finds every mod using any key, optionally excluding one', () async {
      await db.modsDao.upsertMods([
        modUpsert('a', assets: [image('https://x/shared.png')]),
        modUpsert(
          'b',
          assets: [image('https://x/shared.png'), image('https://x/b.png')],
        ),
        modUpsert('c', assets: [image('https://x/c.png')]),
      ]);
      final shared = fileKeyFromUrl('https://x/shared.png');
      final c = fileKeyFromUrl('https://x/c.png');

      expect(await db.libraryQueries.modPathsReferencingFileKeys([shared]), {
        pathA,
        pathB,
      });
      expect(
        await db.libraryQueries.modPathsReferencingFileKeys([
          shared,
          c,
        ], excludeModPath: pathA),
        {pathB, modPath('c')},
      );
      expect(
        await db.libraryQueries.modPathsReferencingFileKeys(['nothing']),
        isEmpty,
      );
      expect(await db.libraryQueries.modPathsReferencingFileKeys([]), isEmpty);
    });

    test('handles large key lists in one call', () async {
      await db.modsDao.upsertMods([
        modUpsert('a', assets: [image('https://x/a.png')]),
      ]);
      final keys = [
        for (var i = 0; i < 50000; i++) 'key$i',
        fileKeyFromUrl('https://x/a.png'),
      ];
      expect(await db.libraryQueries.modPathsReferencingFileKeys(keys), {
        pathA,
      });
    });
  });

  test(
    'orphanedExistingFiles lists files no mod references, per type',
    () async {
      await db.modsDao.upsertMods([
        modUpsert('a', assets: [image('https://x/used.png')]),
      ]);
      final used = fileKeyFromUrl('https://x/used.png');
      await db.existingFilesDao.replaceAll(AssetType.image, [
        (fileKey: used, path: 'Images/used.png'),
        (fileKey: 'orphan', path: 'Images/orphan.png'),
      ]);
      // Same key as the image, but in the Models folder: not referenced as a
      // model, so it is an orphan.
      await db.existingFilesDao.replaceAll(AssetType.model, [
        (fileKey: used, path: 'Models/used.obj'),
      ]);

      expect(await db.libraryQueries.orphanedExistingFiles(), [
        (type: AssetType.image, fileKey: 'orphan', path: 'Images/orphan.png'),
        (type: AssetType.model, fileKey: used, path: 'Models/used.obj'),
      ]);
    },
  );

  test('sharedUsageCounts counts distinct mods per key', () async {
    await db.modsDao.upsertMods([
      modUpsert(
        'a',
        assets: [image('https://x/s.png'), image('https://x/a.png')],
      ),
      modUpsert('b', assets: [image('https://x/s.png')]),
      modUpsert('c', assets: [image('https://x/s.png')]),
    ]);
    final s = fileKeyFromUrl('https://x/s.png');
    final a = fileKeyFromUrl('https://x/a.png');
    expect(await db.libraryQueries.sharedUsageCounts([s, a, 'unknown']), {
      s: 3,
      a: 1,
    });
    expect(await db.libraryQueries.sharedUsageCounts([]), isEmpty);
  });

  test(
    'summary query over 2,000 mods x 150 assets completes well under a second',
    () async {
      const modCount = 2000;
      const assetsPerMod = 150;
      final types = [AssetType.image, AssetType.model, AssetType.pdf];
      final presentByType = {
        for (final t in types) t: <({String fileKey, String path})>[],
      };

      const chunk = 100;
      for (var start = 0; start < modCount; start += chunk) {
        final items = <ModUpsert>[];
        for (var i = start; i < start + chunk; i++) {
          final assets = <ModAssetInput>[];
          for (var j = 0; j < assetsPerMod; j++) {
            final type = types[j % types.length];
            final url = 'https://cdn.example.com/m$i/asset$j.bin';
            assets.add((url: url, assetKey: 'URL', type: type));
            if (j.isEven) {
              presentByType[type]!.add((
                fileKey: fileKeyFromUrl(url),
                path: 'Mods/x/m${i}a$j',
              ));
            }
          }
          items.add(modUpsert('$i', saveName: 'Mod ${i % 97}', assets: assets));
        }
        await db.modsDao.upsertMods(items);
      }
      for (final entry in presentByType.entries) {
        await db.existingFilesDao.replaceAll(entry.key, entry.value);
      }

      final stopwatch = Stopwatch()..start();
      final mods = await db.libraryQueries.modSummaries(
        ModType.mod,
        ignoreAudioGlobally: true,
      );
      stopwatch.stop();

      expect(mods, hasLength(modCount));
      expect(mods.first.summary.total, assetsPerMod);
      expect(mods.first.summary.present, assetsPerMod ~/ 2);
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(1000),
        reason: 'summary query took ${stopwatch.elapsedMilliseconds} ms',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
