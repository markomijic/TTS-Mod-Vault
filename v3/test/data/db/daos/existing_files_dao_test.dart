import 'package:drift/drift.dart' show OrderingTerm;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_mod_vault/data/db/app_database.dart';
import 'package:tts_mod_vault/data/db/daos/existing_files_dao.dart';
import 'package:tts_mod_vault/domain/enums/asset_type.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  group('replaceAll', () {
    test('replaces only the given type', () async {
      await db.existingFilesDao.replaceAll(AssetType.image, [
        (fileKey: 'a', path: 'Images/a.png'),
        (fileKey: 'b', path: 'Images/b.jpg'),
      ]);
      await db.existingFilesDao.replaceAll(AssetType.model, [
        (fileKey: 'a', path: 'Models/a.obj'),
      ]);
      await db.existingFilesDao.replaceAll(AssetType.image, [
        (fileKey: 'c', path: 'Images/c.png'),
      ]);

      expect(await db.existingFilesDao.pathFor(AssetType.image, 'a'), isNull);
      expect(await db.existingFilesDao.pathFor(AssetType.image, 'b'), isNull);
      expect(
        await db.existingFilesDao.pathFor(AssetType.image, 'c'),
        'Images/c.png',
      );
      expect(
        await db.existingFilesDao.pathFor(AssetType.model, 'a'),
        'Models/a.obj',
      );
    });

    test('the last of two files with the same key wins', () async {
      await db.existingFilesDao.replaceAll(AssetType.image, [
        (fileKey: 'a', path: 'Images/a.png'),
        (fileKey: 'a', path: 'Images/a.jpg'),
      ]);
      expect(
        await db.existingFilesDao.pathFor(AssetType.image, 'a'),
        'Images/a.jpg',
      );
    });

    test('an empty list clears the type', () async {
      await db.existingFilesDao.replaceAll(AssetType.pdf, [
        (fileKey: 'a', path: 'PDF/a.pdf'),
      ]);
      await db.existingFilesDao.replaceAll(AssetType.pdf, []);
      expect((await db.existingFilesDao.countByType())[AssetType.pdf], 0);
    });

    test('diffs against the stored rows: updates, inserts, deletes', () async {
      await db.existingFilesDao.replaceAll(AssetType.image, [
        (fileKey: 'keep', path: 'Images/keep.png'),
        (fileKey: 'change', path: 'Images/change.png'),
        (fileKey: 'drop', path: 'Images/drop.png'),
      ]);
      // Unchanged content leaves the rows exactly as they are.
      await db.existingFilesDao.replaceAll(AssetType.image, [
        (fileKey: 'keep', path: 'Images/keep.png'),
        (fileKey: 'change', path: 'Images/change.png'),
        (fileKey: 'drop', path: 'Images/drop.png'),
      ]);
      expect((await db.existingFilesDao.countByType())[AssetType.image], 3);

      await db.existingFilesDao.replaceAll(AssetType.image, [
        (fileKey: 'keep', path: 'Images/keep.png'),
        (fileKey: 'change', path: 'Images/change.jpg'),
        (fileKey: 'new', path: 'Images/new.png'),
      ]);
      final rows = await (db.select(
        db.existingFiles,
      )..orderBy([(t) => OrderingTerm.asc(t.fileKey)])).get();
      expect(
        [for (final r in rows) (r.fileKey, r.path)],
        [
          ('change', 'Images/change.jpg'),
          ('keep', 'Images/keep.png'),
          ('new', 'Images/new.png'),
        ],
      );
    });

    test('more rows than one statement carries, last duplicate wins across '
        'statements', () async {
      const total = ExistingFilesDao.rowsPerStatement * 2 + 7;
      await db.existingFilesDao.replaceAll(AssetType.image, [
        for (var i = 0; i < total; i++)
          (fileKey: 'k$i', path: 'Images/k$i "q" \\ ü.png'),
        // Repeats a key from the first statement in the last one.
        (fileKey: 'k1', path: 'Images/k1.jpg'),
      ]);
      expect((await db.existingFilesDao.countByType())[AssetType.image], total);
      expect(
        await db.existingFilesDao.pathFor(AssetType.image, 'k1'),
        'Images/k1.jpg',
      );
      expect(
        await db.existingFilesDao.pathFor(AssetType.image, 'k2'),
        'Images/k2 "q" \\ ü.png',
      );
      // Shrinking back to a few rows deletes the rest.
      await db.existingFilesDao.replaceAll(AssetType.image, [
        (fileKey: 'k0', path: 'Images/k0.png'),
      ]);
      expect((await db.existingFilesDao.countByType())[AssetType.image], 1);
    });
  });

  test('upsert adds and then updates a single file', () async {
    await db.existingFilesDao.upsert(AssetType.audio, 'k', 'Audio/k.mp3');
    expect(
      await db.existingFilesDao.pathFor(AssetType.audio, 'k'),
      'Audio/k.mp3',
    );
    await db.existingFilesDao.upsert(AssetType.audio, 'k', 'Audio/k.ogg');
    expect(
      await db.existingFilesDao.pathFor(AssetType.audio, 'k'),
      'Audio/k.ogg',
    );
    expect((await db.existingFilesDao.countByType())[AssetType.audio], 1);
  });

  test('remove deletes one key of one type', () async {
    await db.existingFilesDao.upsert(AssetType.image, 'k', 'Images/k.png');
    await db.existingFilesDao.upsert(AssetType.model, 'k', 'Models/k.obj');
    await db.existingFilesDao.remove(AssetType.image, 'k');
    expect(await db.existingFilesDao.pathFor(AssetType.image, 'k'), isNull);
    expect(
      await db.existingFilesDao.pathFor(AssetType.model, 'k'),
      'Models/k.obj',
    );
    await db.existingFilesDao.remove(AssetType.image, 'missing');
  });

  test('pathFor is type-aware', () async {
    await db.existingFilesDao.upsert(AssetType.image, 'k', 'Images/k.png');
    expect(await db.existingFilesDao.pathFor(AssetType.pdf, 'k'), isNull);
  });

  test('countByType lists every type, zero when empty', () async {
    expect(await db.existingFilesDao.countByType(), {
      for (final t in AssetType.values) t: 0,
    });
    await db.existingFilesDao.replaceAll(AssetType.image, [
      (fileKey: 'a', path: 'a'),
      (fileKey: 'b', path: 'b'),
    ]);
    await db.existingFilesDao.upsert(AssetType.assetBundle, 'x', 'x');
    final counts = await db.existingFilesDao.countByType();
    expect(counts[AssetType.image], 2);
    expect(counts[AssetType.assetBundle], 1);
    expect(counts[AssetType.audio], 0);
    expect(counts.length, AssetType.values.length);
  });
}
