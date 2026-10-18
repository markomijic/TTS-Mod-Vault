import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_mod_vault/data/fs/asset_directory_indexer.dart';
import 'package:tts_mod_vault/domain/enums/asset_type.dart';
import 'package:tts_mod_vault/domain/rules/file_key.dart';

File writeFile(FileSystem fs, String path, [String content = 'x']) =>
    fs.file(path)
      ..createSync(recursive: true)
      ..writeAsStringSync(content);

void main() {
  group('indexAssetDirectoryWith (posix memory fs)', () {
    late MemoryFileSystem fs;
    const images = '/tts/Mods/Images';

    setUp(() {
      fs = MemoryFileSystem.test();
      fs.directory(images).createSync(recursive: true);
    });

    Future<AssetIndexResult> index([
      String dir = images,
      AssetType type = AssetType.image,
    ]) => indexAssetDirectoryWith(
      AssetIndexRequest(type: type, directory: dir),
      fs,
    );

    test('lists files non-recursively with lower-cased keys', () async {
      writeFile(fs, '$images/httpsexamplecomAbc.png');
      writeFile(fs, '$images/httpsexamplecomDef.jpg');
      writeFile(fs, '$images/Sub/httpsexamplecomNested.png');
      fs.directory('$images/EmptyDir').createSync();

      final result = await index();

      expect(result.type, AssetType.image);
      expect(result.warnings, isEmpty);
      expect(
        result.files,
        unorderedEquals([
          (
            fileKey: 'httpsexamplecomabc',
            path: '$images/httpsexamplecomAbc.png',
          ),
          (
            fileKey: 'httpsexamplecomdef',
            path: '$images/httpsexamplecomDef.jpg',
          ),
        ]),
      );
    });

    test('rewrites the legacy Steam Cloud prefix in the key', () async {
      const legacyName = 'httpcloud3steamusercontentcomABC123';
      writeFile(fs, '$images/$legacyName.png');

      final result = await index();

      final key = result.files.single.fileKey;
      expect(key, fileKeyFromFileName(legacyName));
      expect(key, 'httpssteamusercontentaakamaihdnetabc123');
      expect(key, fileKeyFromUrl('http://cloud-3.steamusercontent.com/ABC123'));
    });

    test('keeps _temp leftovers and raw file* entries', () async {
      writeFile(fs, '$images/httpsexamplecomabc.png_temp');
      writeFile(fs, '$images/file123456.png');

      final result = await index();

      expect(
        result.files.map((f) => f.fileKey),
        unorderedEquals(['httpsexamplecomabc', 'file123456']),
      );
    });

    test('keeps the first file on a key collision and warns', () async {
      writeFile(fs, '$images/x.png');
      writeFile(fs, '$images/x.PNG');
      writeFile(fs, '$images/y.png');
      writeFile(fs, '$images/y.png_temp');

      final result = await index();

      expect(result.files.map((f) => f.fileKey), unorderedEquals(['x', 'y']));
      expect(result.warnings, hasLength(2));
      expect(
        result.warnings,
        everyElement(startsWith('Duplicate asset key "')),
      );
      final xWarning = result.warnings.singleWhere((w) => w.contains('"x"'));
      final kept = result.files.singleWhere((f) => f.fileKey == 'x').path;
      expect(xWarning, contains('keeping $kept'));
    });

    test('echoes the type for every asset folder', () async {
      for (final type in AssetType.values) {
        final dir = '/tts/Mods/${type.folderName}';
        writeFile(fs, '$dir/a.bin');
        final result = await index(dir, type);
        expect(result.type, type);
        expect(result.files.single.fileKey, 'a');
      }
    });

    test('missing directory returns empty files and a warning', () async {
      final result = await index('/tts/Mods/Nope', AssetType.pdf);

      expect(result.type, AssetType.pdf);
      expect(result.files, isEmpty);
      expect(result.warnings.single, contains('Directory not found'));
    });

    test('normalises directory and paths', () async {
      writeFile(fs, '$images/a.png');

      final result = await index('/tts/Mods/../Mods/Images/');

      expect(result.files.single.path, '$images/a.png');
    });
  });

  group('indexAssetDirectoryWith (windows memory fs)', () {
    test('returns backslash paths', () async {
      final fs = MemoryFileSystem.test(style: FileSystemStyle.windows);
      final models = fs.path.join(r'C:\', 'TTS', 'Mods', 'Models');
      writeFile(fs, fs.path.join(models, 'httpsexamplecomModel.obj'));
      writeFile(fs, fs.path.join(models, 'Sub', 'ignored.obj'));

      final result = await indexAssetDirectoryWith(
        const AssetIndexRequest(
          type: AssetType.model,
          directory: 'C:/TTS/Mods/Models',
        ),
        fs,
      );

      expect(result.warnings, isEmpty);
      expect(result.files.single, (
        fileKey: 'httpsexamplecommodel',
        path: r'C:\TTS\Mods\Models\httpsexamplecomModel.obj',
      ));
    });
  });
}
