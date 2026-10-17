import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_mod_vault/data/fs/mod_file_scanner.dart';
import 'package:tts_mod_vault/domain/constants.dart';
import 'package:tts_mod_vault/domain/enums/mod_type.dart';

File writeFile(FileSystem fs, String path, [String content = '{}']) =>
    fs.file(path)
      ..createSync(recursive: true)
      ..writeAsStringSync(content);

void main() {
  group('scanModFilesWith (posix memory fs)', () {
    late MemoryFileSystem fs;
    late String workshop;

    setUp(() {
      fs = MemoryFileSystem.test();
      workshop = fs.path.join('/tts', ttsModsFolder, ttsWorkshopFolder);
      fs.directory(workshop).createSync(recursive: true);
    });

    Future<ModFileScanResult> scan({
      String? root,
      ModType type = ModType.mod,
      List<String> ignored = const [],
    }) => scanModFilesWith(
      ModFileScanRequest(
        rootDir: root ?? workshop,
        type: type,
        ignoredSubfolders: ignored,
      ),
      fs,
    );

    test('finds JSONs recursively with folder, type and stats', () async {
      final a = writeFile(fs, '$workshop/111.json', '{"SaveName":"A"}');
      writeFile(fs, '$workshop/Nested/Deeper/222.json', '0123456789');
      a.setLastModifiedSync(DateTime.utc(2024, 1, 2, 3, 4, 5));

      final result = await scan();

      expect(result.warnings, isEmpty);
      expect(
        result.entries.map((e) => e.jsonPath),
        unorderedEquals([
          '/tts/Mods/Workshop/111.json',
          '/tts/Mods/Workshop/Nested/Deeper/222.json',
        ]),
      );
      final first = result.entries.singleWhere(
        (e) => e.jsonPath.endsWith('111.json'),
      );
      expect(first.type, ModType.mod);
      expect(first.folder, 'Workshop');
      expect(first.sizeBytes, '{"SaveName":"A"}'.length);
      expect(
        first.mtimeMs,
        DateTime.utc(2024, 1, 2, 3, 4, 5).millisecondsSinceEpoch,
      );
      final second = result.entries.singleWhere(
        (e) => e.jsonPath.endsWith('222.json'),
      );
      expect(second.folder, 'Deeper');
      expect(second.sizeBytes, 10);
    });

    test('reports the requested type on every entry', () async {
      writeFile(fs, '$workshop/1.json');
      final result = await scan(type: ModType.savedObject);
      expect(result.entries.single.type, ModType.savedObject);
    });

    test('matches the .json extension case-insensitively', () async {
      writeFile(fs, '$workshop/upper.JSON');
      writeFile(fs, '$workshop/mixed.Json');
      writeFile(fs, '$workshop/notjson.jsonx');
      writeFile(fs, '$workshop/image.png');

      final result = await scan();

      expect(
        result.entries.map((e) => fs.path.basename(e.jsonPath)),
        unorderedEquals(['upper.JSON', 'mixed.Json']),
      );
    });

    test('skips TTS index files at any depth', () async {
      writeFile(fs, '$workshop/WorkshopFileInfos.json');
      writeFile(fs, '$workshop/SaveFileInfos.json');
      writeFile(fs, '$workshop/sub/WorkshopFileInfos.json');
      writeFile(fs, '$workshop/real.json');

      final result = await scan();

      expect(result.entries.map((e) => fs.path.basename(e.jsonPath)), [
        'real.json',
      ]);
    });

    test('ignores subfolders by whole path segment, not substring', () async {
      writeFile(fs, '$workshop/Old/skipped.json');
      writeFile(fs, '$workshop/Deep/Old/skipped_nested.json');
      writeFile(fs, '$workshop/Older/kept_substring.json');
      writeFile(fs, '$workshop/NotOld/kept_suffix.json');
      writeFile(fs, '$workshop/Old.json'); // file named like the folder
      writeFile(fs, '$workshop/old/kept_case.json'); // case-sensitive

      final result = await scan(ignored: ['Old']);

      expect(
        result.entries.map((e) => fs.path.basename(e.jsonPath)),
        unorderedEquals([
          'kept_substring.json',
          'kept_suffix.json',
          'Old.json',
          'kept_case.json',
        ]),
      );
    });

    test('Saves root with Saved Objects ignored only yields saves', () async {
      final saves = fs.path.join('/tts', ttsSavesFolder);
      writeFile(fs, '$saves/TS_Save_1.json');
      writeFile(fs, '$saves/Folder/TS_Save_2.json');
      writeFile(fs, '$saves/$ttsSavedObjectsFolder/obj.json');
      writeFile(fs, '$saves/$ttsSavedObjectsFolder/Bag/obj2.json');

      final result = await scan(
        root: saves,
        type: ModType.save,
        ignored: [ttsSavedObjectsFolder],
      );

      expect(
        result.entries.map((e) => fs.path.basename(e.jsonPath)),
        unorderedEquals(['TS_Save_1.json', 'TS_Save_2.json']),
      );

      final objects = await scan(
        root: '$saves/$ttsSavedObjectsFolder',
        type: ModType.savedObject,
      );
      expect(
        objects.entries.map((e) => fs.path.basename(e.jsonPath)),
        unorderedEquals(['obj.json', 'obj2.json']),
      );
    });

    group('image lookup', () {
      test('prefers the PNG beside the JSON', () async {
        writeFile(fs, '$workshop/123.json');
        writeFile(fs, '$workshop/123.png');
        writeFile(fs, '$workshop/$ttsThumbnailsFolder/123.png');

        final result = await scan();

        expect(result.entries.single.imagePath, '/tts/Mods/Workshop/123.png');
      });

      test('falls back to Thumbnails/<name>.png', () async {
        writeFile(fs, '$workshop/sub/123.json');
        writeFile(fs, '$workshop/sub/$ttsThumbnailsFolder/123.png');
        writeFile(fs, '$workshop/123.png'); // wrong directory

        final result = await scan();

        expect(
          result.entries.single.imagePath,
          '/tts/Mods/Workshop/sub/Thumbnails/123.png',
        );
      });

      test('is null when no matching PNG exists', () async {
        writeFile(fs, '$workshop/123.json');
        writeFile(fs, '$workshop/124.png');
        writeFile(fs, '$workshop/123.jpg');

        final result = await scan();

        expect(result.entries.single.imagePath, isNull);
      });

      test('matches case-insensitively and returns the real path', () async {
        writeFile(fs, '$workshop/Foo.json');
        writeFile(fs, '$workshop/Foo.PNG');
        writeFile(fs, '$workshop/sub/Bar.json');
        writeFile(fs, '$workshop/sub/thumbnails/bar.Png');

        final result = await scan();

        final foo = result.entries.singleWhere(
          (e) => e.jsonPath.endsWith('Foo.json'),
        );
        expect(foo.imagePath, '/tts/Mods/Workshop/Foo.PNG');
        final bar = result.entries.singleWhere(
          (e) => e.jsonPath.endsWith('Bar.json'),
        );
        expect(bar.imagePath, '/tts/Mods/Workshop/sub/thumbnails/bar.Png');
      });
    });

    test('missing root returns empty entries and a warning', () async {
      final result = await scan(root: '/tts/Mods/DoesNotExist');

      expect(result.entries, isEmpty);
      expect(result.warnings, hasLength(1));
      expect(result.warnings.single, contains('Directory not found'));
      expect(result.warnings.single, contains('/tts/Mods/DoesNotExist'));
    });

    test('empty root returns empty entries without warnings', () async {
      final result = await scan();
      expect(result.entries, isEmpty);
      expect(result.warnings, isEmpty);
    });

    test('normalises the root and the returned paths', () async {
      writeFile(fs, '$workshop/1.json');
      writeFile(fs, '$workshop/1.png');

      final result = await scan(root: '/tts/Mods/../Mods/Workshop/');

      expect(result.entries.single.jsonPath, '/tts/Mods/Workshop/1.json');
      expect(result.entries.single.imagePath, '/tts/Mods/Workshop/1.png');
    });
  });

  group('scanModFilesWith (windows memory fs)', () {
    late MemoryFileSystem fs;
    late String workshop;

    setUp(() {
      fs = MemoryFileSystem.test(style: FileSystemStyle.windows);
      workshop = fs.path.join(r'C:\', 'TTS', ttsModsFolder, ttsWorkshopFolder);
      fs.directory(workshop).createSync(recursive: true);
    });

    test('returns backslash paths and finds thumbnails', () async {
      writeFile(fs, fs.path.join(workshop, '123.json'));
      writeFile(fs, fs.path.join(workshop, ttsThumbnailsFolder, '123.png'));
      writeFile(fs, fs.path.join(workshop, 'Sub', '456.json'));
      writeFile(fs, fs.path.join(workshop, 'Sub', '456.png'));

      final result = await scanModFilesWith(
        ModFileScanRequest(rootDir: workshop, type: ModType.mod),
        fs,
      );

      expect(result.warnings, isEmpty);
      final a = result.entries.singleWhere(
        (e) => e.jsonPath.endsWith('123.json'),
      );
      expect(a.jsonPath, r'C:\TTS\Mods\Workshop\123.json');
      expect(a.imagePath, r'C:\TTS\Mods\Workshop\Thumbnails\123.png');
      expect(a.folder, 'Workshop');
      final b = result.entries.singleWhere(
        (e) => e.jsonPath.endsWith('456.json'),
      );
      expect(b.jsonPath, r'C:\TTS\Mods\Workshop\Sub\456.json');
      expect(b.imagePath, r'C:\TTS\Mods\Workshop\Sub\456.png');
      expect(b.folder, 'Sub');
    });

    test('matches image case-insensitively, returning the real path', () async {
      writeFile(fs, fs.path.join(workshop, 'Foo.json'));
      writeFile(fs, fs.path.join(workshop, 'Foo.PNG'));
      writeFile(fs, fs.path.join(workshop, 'Sub', 'Bar.json'));
      writeFile(fs, fs.path.join(workshop, 'Sub', 'thumbnails', 'BAR.png'));

      final result = await scanModFilesWith(
        ModFileScanRequest(rootDir: workshop, type: ModType.mod),
        fs,
      );

      final foo = result.entries.singleWhere(
        (e) => e.jsonPath.endsWith('Foo.json'),
      );
      expect(foo.imagePath, r'C:\TTS\Mods\Workshop\Foo.PNG');
      final bar = result.entries.singleWhere(
        (e) => e.jsonPath.endsWith('Bar.json'),
      );
      expect(bar.imagePath, r'C:\TTS\Mods\Workshop\Sub\thumbnails\BAR.png');
    });

    test('accepts a forward-slash root and ignores segments', () async {
      writeFile(fs, fs.path.join(workshop, 'Old', 'skip.json'));
      writeFile(fs, fs.path.join(workshop, 'Older', 'keep.json'));

      final result = await scanModFilesWith(
        const ModFileScanRequest(
          rootDir: 'C:/TTS/Mods/Workshop',
          type: ModType.mod,
          ignoredSubfolders: ['Old'],
        ),
        fs,
      );

      expect(
        result.entries.single.jsonPath,
        r'C:\TTS\Mods\Workshop\Older\keep.json',
      );
    });

    test('missing root warns with the normalised path', () async {
      final result = await scanModFilesWith(
        const ModFileScanRequest(
          rootDir: r'C:\Nope\Workshop',
          type: ModType.mod,
        ),
        fs,
      );
      expect(result.entries, isEmpty);
      expect(result.warnings.single, contains(r'C:\Nope\Workshop'));
    });
  });
}
