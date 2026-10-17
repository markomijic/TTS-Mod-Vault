import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_mod_vault/data/db/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('upsertAll then fingerprints', () async {
    await db.backupsDao.upsertAll([
      (path: 'B/a.ttsmod', mtimeMs: 10, sizeBytes: 100, assetCount: 3),
      (path: 'B/b.ttsmod', mtimeMs: 20, sizeBytes: 200, assetCount: 0),
    ]);
    expect(await db.backupsDao.fingerprints(), {
      'B/a.ttsmod': (mtimeMs: 10, sizeBytes: 100),
      'B/b.ttsmod': (mtimeMs: 20, sizeBytes: 200),
    });
  });

  test('upsertAll replaces an existing path', () async {
    await db.backupsDao.upsertAll([
      (path: 'B/a.ttsmod', mtimeMs: 10, sizeBytes: 100, assetCount: 3),
    ]);
    await db.backupsDao.upsertAll([
      (path: 'B/a.ttsmod', mtimeMs: 11, sizeBytes: 101, assetCount: 4),
    ]);
    final rows = await db.select(db.backups).get();
    expect(rows, hasLength(1));
    expect(rows.single.mtimeMs, 11);
    expect(rows.single.sizeBytes, 101);
    expect(rows.single.assetCount, 4);
  });

  test('deleteByPaths removes only the given rows', () async {
    await db.backupsDao.upsertAll([
      (path: 'B/a.ttsmod', mtimeMs: 1, sizeBytes: 1, assetCount: 1),
      (path: 'B/b.ttsmod', mtimeMs: 1, sizeBytes: 1, assetCount: 1),
      (path: 'B/c.ttsmod', mtimeMs: 1, sizeBytes: 1, assetCount: 1),
    ]);
    await db.backupsDao.deleteByPaths(['B/a.ttsmod', 'B/c.ttsmod', 'nope']);
    expect((await db.backupsDao.fingerprints()).keys, ['B/b.ttsmod']);
  });

  test('empty inputs are no-ops', () async {
    await db.backupsDao.upsertAll([]);
    await db.backupsDao.deleteByPaths([]);
    expect(await db.backupsDao.fingerprints(), isEmpty);
  });
}
