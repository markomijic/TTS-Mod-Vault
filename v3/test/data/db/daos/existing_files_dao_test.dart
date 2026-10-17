import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_mod_vault/data/db/app_database.dart';
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
