// Integration test: the fs tasks run through the real WorkerPool against a
// temporary directory on the local file system.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/core/workers/worker_pool.dart';
import 'package:tts_mod_vault/data/fs/fs_tasks.dart';
import 'package:tts_mod_vault/domain/constants.dart';
import 'package:tts_mod_vault/domain/enums/asset_type.dart';
import 'package:tts_mod_vault/domain/enums/mod_type.dart';

import 'zip/zip_fixtures.dart';

void main() {
  late Directory temp;
  late WorkerPool pool;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('ttsmv_fs_tasks_');
    pool = WorkerPool(size: 2, debugName: 'fs-test');
  });

  tearDown(() async {
    await pool.dispose();
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  });

  File write(String relative, [List<int> bytes = const [0x7b, 0x7d]]) =>
      File(p.join(temp.path, relative))
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes);

  test('scanModFiles runs on a worker and scans the local disk', () async {
    final workshop = p.join(temp.path, ttsModsFolder, ttsWorkshopFolder);
    write(p.join(ttsModsFolder, ttsWorkshopFolder, '123.json'));
    write(p.join(ttsModsFolder, ttsWorkshopFolder, '123.png'));
    write(p.join(ttsModsFolder, ttsWorkshopFolder, 'Sub', '456.JSON'));
    write(
      p.join(
        ttsModsFolder,
        ttsWorkshopFolder,
        'Sub',
        ttsThumbnailsFolder,
        '456.png',
      ),
    );
    write(p.join(ttsModsFolder, ttsWorkshopFolder, 'Old', '789.json'));
    write(p.join(ttsModsFolder, ttsWorkshopFolder, ttsIndexFileNames.first));

    final result = await pool.run(
      scanModFiles,
      ModFileScanRequest(
        rootDir: workshop,
        type: ModType.mod,
        ignoredSubfolders: const ['Old'],
      ),
    );

    expect(result.warnings, isEmpty);
    expect(
      result.entries.map((e) => e.jsonPath),
      unorderedEquals([
        p.normalize(p.join(workshop, '123.json')),
        p.normalize(p.join(workshop, 'Sub', '456.JSON')),
      ]),
    );
    final first = result.entries.singleWhere(
      (e) => e.jsonPath.endsWith('123.json'),
    );
    expect(first.imagePath, p.normalize(p.join(workshop, '123.png')));
    expect(first.sizeBytes, 2);
    expect(first.mtimeMs, greaterThan(0));
    final second = result.entries.singleWhere(
      (e) => e.jsonPath.endsWith('456.JSON'),
    );
    expect(
      second.imagePath,
      p.normalize(p.join(workshop, 'Sub', ttsThumbnailsFolder, '456.png')),
    );
    expect(second.folder, 'Sub');
  });

  test('indexAssetDirectory, scanBackupFiles and countBackupAssets run on '
      'workers', () async {
    final images = p.join(temp.path, ttsModsFolder, AssetType.image.folderName);
    write(p.join(ttsModsFolder, AssetType.image.folderName, 'httpsXyz.png'));
    final backups = p.join(temp.path, 'Backups');
    write(
      p.join('Backups', 'Mod (1).ttsmod'),
      buildZip({
        'Mods/Workshop/1.json': [1],
        'Mods/Images/a.png': [2],
        'Mods/Models/b.obj': [3],
      }),
    );

    final index = await pool.run(
      indexAssetDirectory,
      AssetIndexRequest(type: AssetType.image, directory: images),
    );
    expect(index.type, AssetType.image);
    expect(index.files.single.fileKey, 'httpsxyz');

    final scanned = await pool.run(
      scanBackupFiles,
      BackupScanRequest(backupsDir: backups),
    );
    expect(scanned.warnings, isEmpty);
    expect(scanned.entries.single.fileName, 'Mod (1).ttsmod');

    final counts = await pool.run(countBackupAssets, [
      scanned.entries.single.path,
      p.join(backups, 'missing.ttsmod'),
    ]);
    expect(counts, [2, 0]);
  });

  test('a missing root yields a warning instead of an error', () async {
    final result = await pool.run(
      scanModFiles,
      ModFileScanRequest(
        rootDir: p.join(temp.path, 'does-not-exist'),
        type: ModType.save,
      ),
    );
    expect(result.entries, isEmpty);
    expect(result.warnings.single, contains('Directory not found'));
  });
}
