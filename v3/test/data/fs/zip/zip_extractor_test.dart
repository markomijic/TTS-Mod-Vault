// The streaming zip lister / extractor against a temp directory (archive
// streams need dart:io paths).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/core/cancellation/cancellation_token.dart';
import 'package:tts_mod_vault/data/fs/zip/zip_extractor.dart';

import 'zip_fixtures.dart';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('ttsmv_zipx_'));
  tearDown(() => temp.deleteSync(recursive: true));

  final files = <String, List<int>>{
    'Mods/Workshop/123.json': '{"SaveName":"X","EpochTime":5}'.codeUnits,
    'Mods/Workshop/123.png': [0x89, 0x50],
    'Mods/Images/httpsexamplecomapng.png': List.filled(70000, 3),
    'Mods/Models/deep/nested/m.obj': [1, 2, 3, 4],
  };

  String writeZip(String name, List<int> bytes) {
    final path = p.join(temp.path, name);
    File(path).writeAsBytesSync(bytes);
    return path;
  }

  group('listZipEntries', () {
    test('names with / separators, sizes and directory flags', () async {
      final zip = writeZip(
        'a.ttsmod',
        withBackslashNames(buildZip(files, directories: ['Mods/Audio/']), [
          'Mods/Models/deep/nested/m.obj',
        ]),
      );

      final listing = await listZipEntries(zip);

      final byName = {for (final e in listing.entries) e.name: e};
      expect(byName.keys, containsAll(files.keys));
      expect(byName['Mods/Models/deep/nested/m.obj']!.size, 4);
      expect(byName['Mods/Images/httpsexamplecomapng.png']!.size, 70000);
      expect(byName['Mods/Audio/']!.isFile, isFalse);
      expect(listing.files.map((e) => e.name), unorderedEquals(files.keys));
    });

    test('throws for a file that is not a zip', () async {
      final junk = writeZip('junk.ttsmod', List.filled(100, 0));
      await expectLater(listZipEntries(junk), throwsFormatException);
      final empty = writeZip('empty.ttsmod', buildZip(const {}));
      expect((await listZipEntries(empty)).entries, isEmpty);
      await expectLater(
        listZipEntries(p.join(temp.path, 'missing.ttsmod')),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  group('readZipEntryBytes', () {
    test('returns one entry and null for an unknown name', () async {
      final zip = writeZip('b.ttsmod', buildZip(files));
      expect(
        await readZipEntryBytes(
          ZipEntryReadRequest(
            zipPath: zip,
            entryName: r'Mods\Workshop\123.json',
          ),
        ),
        files['Mods/Workshop/123.json'],
      );
      expect(
        await readZipEntryBytes(
          ZipEntryReadRequest(zipPath: zip, entryName: 'Mods/nope.json'),
        ),
        isNull,
      );
    });
  });

  group('extractZipEntries', () {
    test(
      'writes mapped entries into nested folders, skips null, overwrites',
      () async {
        final zip = writeZip(
          'c.ttsmod',
          withBackslashNames(buildZip(files), ['Mods/Workshop/123.png']),
        );
        final out = p.join(temp.path, 'out');
        final existing = File(p.join(out, 'Images', 'a.png'))
          ..createSync(recursive: true)
          ..writeAsBytesSync([0]);
        final outputs = <String, String?>{
          'Mods/Workshop/123.json': p.join(out, 'Sub', 'Deeper', '123.json'),
          'Mods/Workshop/123.png': p.join(out, 'Sub', 'Deeper', '123.png'),
          'Mods/Images/httpsexamplecomapng.png': existing.path,
          'Mods/Models/deep/nested/m.obj': null,
        };
        final progress = <ZipProgress>[];

        final result = await extractZipEntriesWith(
          ZipExtractRequest(zipPath: zip, outputs: outputs),
          onProgress: progress.add,
        );

        expect(result.cancelled, isFalse);
        expect(result.failed, isEmpty);
        expect(
          result.extracted.map((e) => e.entryName),
          unorderedEquals([
            'Mods/Workshop/123.json',
            'Mods/Workshop/123.png',
            'Mods/Images/httpsexamplecomapng.png',
          ]),
        );
        expect(
          File(p.join(out, 'Sub', 'Deeper', '123.json')).readAsBytesSync(),
          files['Mods/Workshop/123.json'],
        );
        expect(
          File(p.join(out, 'Sub', 'Deeper', '123.png')).readAsBytesSync(),
          files['Mods/Workshop/123.png'],
        );
        expect(existing.readAsBytesSync(), List.filled(70000, 3));
        expect(File(p.join(out, 'm.obj')).existsSync(), isFalse);
        expect(progress.length, 4);
        expect(progress.last.done, 4);
        expect(progress.last.total, 4);
      },
    );

    test('a cancel returns what was written so far', () async {
      final zip = writeZip('d.ttsmod', buildZip(files));
      final out = p.join(temp.path, 'out');
      var done = 0;

      final result = await extractZipEntriesWith(
        ZipExtractRequest(
          zipPath: zip,
          outputs: {
            for (final name in files.keys) name: p.join(out, p.basename(name)),
          },
        ),
        onProgress: (progress) => done = progress.done,
        isCancelled: () => done >= 2,
      );

      expect(result.cancelled, isTrue);
      expect(result.extracted.length, 2);
      expect(Directory(out).listSync().length, 2);
    });

    test('an unwritable output is reported, the rest continues', () async {
      final zip = writeZip('e.ttsmod', buildZip(files));
      final out = p.join(temp.path, 'out');
      final blocker = File(p.join(temp.path, 'blocker'))..writeAsBytesSync([0]);

      final result = await extractZipEntries(
        ZipExtractRequest(
          zipPath: zip,
          outputs: {
            'Mods/Workshop/123.json': p.join(blocker.path, 'x', '123.json'),
            'Mods/Workshop/123.png': p.join(out, '123.png'),
          },
        ),
      );

      expect(result.failed.map((f) => f.entryName), ['Mods/Workshop/123.json']);
      expect(result.extracted.map((e) => e.entryName), [
        'Mods/Workshop/123.png',
      ]);
    });
  });

  group('ImportZipIsolate', () {
    test('extracts with progress on a dedicated isolate', () async {
      final zip = writeZip('f.ttsmod', buildZip(files));
      final out = p.join(temp.path, 'iso');
      final progress = <ZipProgress>[];

      final result = await ImportZipIsolate.extract(
        ZipExtractRequest(
          zipPath: zip,
          outputs: {for (final name in files.keys) name: p.join(out, name)},
        ),
        onProgress: progress.add,
      );

      expect(result.extracted.length, 4);
      expect(progress.map((p) => p.done), [1, 2, 3, 4]);
      for (final entry in files.entries) {
        expect(File(p.join(out, entry.key)).readAsBytesSync(), entry.value);
      }
    });

    test('a token cancelled up front fails before extracting', () async {
      final zip = writeZip('g.ttsmod', buildZip(files));
      final token = CancellationToken()..cancel();
      await expectLater(
        ImportZipIsolate.extract(
          ZipExtractRequest(zipPath: zip, outputs: const {}),
          token: token,
        ),
        throwsA(isA<OperationCancelledException>()),
      );
    });
  });
}
