import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/core/workers/worker_pool.dart';
import 'package:tts_mod_vault/data/fs/mod_file_scanner.dart';
import 'package:tts_mod_vault/domain/constants.dart';
import 'package:tts_mod_vault/domain/enums/asset_type.dart';
import 'package:tts_mod_vault/domain/enums/mod_type.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';
import 'package:tts_mod_vault/features/library/library_tasks.dart';

import 'library_test_harness.dart';

ModFileEntry entry(String name, int sizeBytes) => ModFileEntry(
  jsonPath: '$name.json',
  type: ModType.mod,
  folder: 'Workshop',
  mtimeMs: 0,
  sizeBytes: sizeBytes,
  imagePath: null,
);

void main() {
  group('parseModFiles', () {
    late TempLibrary library;

    setUp(() => library = TempLibrary.create());
    tearDown(() => library.delete());

    test('parses a batch on a worker and captures per-file errors', () async {
      final good = library.writeJson(
        p.join('Mods', 'Workshop', '1.json'),
        saveName: 'Good',
        epochTime: epoch2023,
        assets: [
          ('ImageURL', 'https://x/a.png'),
          ('MeshURL', 'http://cloud-3.steamusercontent.com/ugc/1/m.obj'),
        ],
      );
      final bad = File(p.join(library.workshopDir, '2.json'))
        ..writeAsBytesSync(const [0xFF, 0xFE]);
      final missing = p.join(library.workshopDir, '3.json');
      final pool = WorkerPool(size: 1, debugName: 'parse-test');
      addTearDown(pool.dispose);

      final results = await pool.run(
        parseModFiles,
        ParseModsRequest(
          files: [
            (jsonPath: good, type: ModType.mod),
            (jsonPath: bad.path, type: ModType.mod),
            (jsonPath: missing, type: ModType.save),
          ],
        ),
      );

      expect(results, hasLength(3));
      final first = results[0];
      expect(first.isOk, isTrue);
      expect(first.jsonPath, good);
      expect(first.saveName, 'Good');
      expect(first.epochTime, epoch2023);
      expect(first.sizeBytes, File(good).lengthSync());
      expect(
        first.mtimeMs,
        File(good).lastModifiedSync().millisecondsSinceEpoch,
      );
      expect(first.assets, [
        (url: 'https://x/a.png', assetKey: 'ImageURL', type: AssetType.image),
        (
          url: '${newSteamUserContentUrl}ugc/1/m.obj',
          assetKey: 'MeshURL',
          type: AssetType.model,
        ),
      ]);
      expect(results[1].isOk, isFalse);
      expect(results[1].error, isNotEmpty);
      expect(results[1].assets, isEmpty);
      expect(results[2].isOk, isFalse);
      expect(results[2].type, ModType.save);
      expect(results[2].jsonPath, missing);
    });

    test('findModImagePath prefers the sibling over Thumbnails', () async {
      final json = library.writeJson(
        p.join('Mods', 'Workshop', 'Sub', '9.json'),
        saveName: 'Nine',
      );
      expect(findModImagePath(json), isNull);

      final thumbnail = File(
        p.join(library.workshopDir, 'Sub', ttsThumbnailsFolder, '9.png'),
      )..createSync(recursive: true);
      expect(findModImagePath(json), p.normalize(thumbnail.path));

      final sibling = library.writeSiblingImage(json);
      expect(findModImagePath(json), sibling);
    });
  });

  group('LibraryController.createParseBatches', () {
    const mb = 1024 * 1024;

    test('keeps order and closes at the file limit', () {
      final entries = [for (var i = 0; i < 60; i++) entry('$i', 1000)];
      final batches = LibraryController.createParseBatches(entries);
      expect(batches.map((b) => b.length), [25, 25, 10]);
      expect(batches.expand((b) => b), entries);
    });

    test('closes before exceeding the byte target', () {
      const target = LibraryController.targetBatchBytes;
      final entries = [
        entry('a', target * 6 ~/ 10),
        entry('b', target * 3 ~/ 10),
        entry('c', target * 2 ~/ 10), // would exceed the target: new batch
        entry('d', target + mb), // alone: larger than the target
        entry('e', 1 * mb),
      ];
      final batches = LibraryController.createParseBatches(entries);
      expect(batches.map((b) => b.map((e) => e.jsonPath).toList()), [
        ['a.json', 'b.json'],
        ['c.json'],
        ['d.json'],
        ['e.json'],
      ]);
    });

    test('empty input gives no batches', () {
      expect(LibraryController.createParseBatches(const []), isEmpty);
    });
  });
}
