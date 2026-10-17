import 'dart:typed_data' show Uint8List;

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_mod_vault/data/fs/zip/zip_central_directory_reader.dart';

import 'zip_fixtures.dart';

void main() {
  late MemoryFileSystem fs;

  setUp(() {
    fs = MemoryFileSystem.test();
    fs.directory('/zips').createSync();
  });

  String write(String name, List<int> bytes) {
    final path = '/zips/$name';
    fs.file(path).writeAsBytesSync(bytes);
    return path;
  }

  final sample = <String, List<int>>{
    'Mods/Workshop/123.json': List<int>.filled(300, 0x41),
    'Mods/Images/httpsexamplecomimg.png': List<int>.filled(1000, 0x7),
    'Mods/Models/httpsexamplecommodel.obj': [1, 2, 3],
  };

  test('reads entry names from a plain archive', () async {
    final path = write(
      'plain.zip',
      buildZip(sample, directories: ['Mods/PDF']),
    );

    final names = await ZipCentralDirectoryReader.readFileNamesWith(path, fs);

    expect(
      names,
      unorderedEquals([
        'Mods/Workshop/123.json',
        'Mods/Images/httpsexamplecomimg.png',
        'Mods/Models/httpsexamplecommodel.obj',
        'Mods/PDF/',
      ]),
    );
  });

  test('finds the EOCD behind an archive comment', () async {
    final comment = 'TTS Mod Vault backup ${'x' * 500}';
    final path = write('comment.zip', buildZip(sample, comment: comment));

    final names = await ZipCentralDirectoryReader.readFileNamesWith(path, fs);

    expect(names, unorderedEquals(sample.keys));
  });

  test('normalises backslash entry names to forward slashes', () async {
    final zip = withBackslashNames(buildZip(sample), sample.keys.toList());
    final path = write('backslash.zip', zip);

    final names = await ZipCentralDirectoryReader.readFileNamesWith(path, fs);

    expect(names, unorderedEquals(sample.keys));
    expect(names, everyElement(isNot(contains(r'\'))));
  });

  test('follows the ZIP64 locator when the EOCD is saturated', () async {
    final path = write('zip64.zip', toZip64(buildZip(sample)));

    final names = await ZipCentralDirectoryReader.readFileNamesWith(path, fs);

    expect(names, unorderedEquals(sample.keys));
  });

  test('returns an empty list for an empty archive', () async {
    final path = write('empty.zip', buildZip(const {}));

    final names = await ZipCentralDirectoryReader.readFileNamesWith(path, fs);

    expect(names, isEmpty);
  });

  test('returns an empty list for a file smaller than an EOCD', () async {
    final path = write('tiny.zip', Uint8List.fromList([0x50, 0x4b, 3, 4]));

    final names = await ZipCentralDirectoryReader.readFileNamesWith(path, fs);

    expect(names, isEmpty);
  });

  test('returns an empty list when no EOCD signature exists', () async {
    final path = write('garbage.zip', List<int>.filled(4096, 0x5a));

    final names = await ZipCentralDirectoryReader.readFileNamesWith(path, fs);

    expect(names, isEmpty);
  });

  test('throws for a missing file', () async {
    await expectLater(
      ZipCentralDirectoryReader.readFileNamesWith('/zips/missing.zip', fs),
      throwsA(isA<FileSystemException>()),
    );
  });
}
