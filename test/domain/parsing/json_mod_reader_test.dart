import 'dart:convert' show utf8;

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tts_mod_vault/domain/enums/asset_type.dart';
import 'package:tts_mod_vault/domain/enums/mod_type.dart';
import 'package:tts_mod_vault/domain/parsing/json_mod_reader.dart';
import 'package:tts_mod_vault/domain/parsing/url_extraction.dart';

class _MockFileSystem extends Mock implements FileSystem {}

class _MockFile extends Mock implements File {}

const _modJson = '''
{
  "SaveName": "  My Mod  ",
  "EpochTime": 1700000000,
  "Date": "1/1/2000 1:00:00 AM",
  "TableURL": "http://cloud-3.steamusercontent.com/ugc/9/table.jpg",
  "ObjectStates": [
    {
      "Nickname": "Some object",
      "CustomMesh": {
        "MeshURL": "https://x/m.obj",
        "DiffuseURL": "{en}https://a/d.png{fr}https://b/d.png"
      }
    }
  ]
}''';

const _savedObjectJson = '''
{
  "SaveName": "",
  "Date": "03/05/2024 14:07:09",
  "ObjectStates": [
    {
      "Name": "Custom_Model",
      "Nickname": "Red Dragon",
      "CustomMesh": { "MeshURL": "https://x/dragon.obj" }
    }
  ]
}''';

void main() {
  late MemoryFileSystem fs;
  late JsonModReader reader;

  setUp(() {
    fs = MemoryFileSystem.test();
    reader = JsonModReader(fileSystem: fs);
  });

  Future<String> write(String path, String content) async {
    final file = fs.file(path);
    await file.create(recursive: true);
    await file.writeAsString(content);
    return path;
  }

  group('readHeader', () {
    test('mod: trimmed SaveName and EpochTime', () async {
      final path = await write('/Mods/Workshop/123.json', _modJson);
      final header = await reader.readHeader(path, ModType.mod);
      expect(
        header,
        const ModHeader(saveName: 'My Mod', epochTime: 1700000000),
      );
      expect(header.nickname, isNull);
    });

    test('save: same rules as mod', () async {
      final path = await write('/Saves/TS_Save_1.json', _modJson);
      final header = await reader.readHeader(path, ModType.save);
      expect(header.saveName, 'My Mod');
      expect(header.epochTime, 1700000000);
      expect(header.nickname, isNull);
    });

    test(
      'savedObject: name is the basename, Nickname returned separately',
      () async {
        final path = await write(
          '/Saves/Saved Objects/Dragon Mini.json',
          _savedObjectJson,
        );
        final header = await reader.readHeader(path, ModType.savedObject);
        expect(header.saveName, 'Dragon Mini');
        expect(header.nickname, 'Red Dragon');
        expect(
          header.epochTime,
          DateTime(2024, 3, 5, 14, 7, 9).millisecondsSinceEpoch ~/ 1000,
        );
      },
    );

    test('falls back to the basename when SaveName is missing', () async {
      final path = await write('/Mods/Workshop/456.json', '{"EpochTime": 5}');
      final header = await reader.readHeader(path, ModType.mod);
      expect(header, const ModHeader(saveName: '456', epochTime: 5));
    });

    test(
      'falls back to the basename when SaveName is empty or blank',
      () async {
        final empty = await write('/Mods/Workshop/e.json', '{"SaveName": ""}');
        expect((await reader.readHeader(empty, ModType.mod)).saveName, 'e');
        final blank = await write(
          '/Mods/Workshop/b.json',
          '{"SaveName": "  "}',
        );
        expect((await reader.readHeader(blank, ModType.mod)).saveName, 'b');
      },
    );

    test('epochTime is null when no date key exists', () async {
      final path = await write('/Mods/Workshop/x.json', '{"SaveName": "X"}');
      final header = await reader.readHeader(path, ModType.mod);
      expect(header.epochTime, isNull);
    });

    test('finds keys that are further down the file', () async {
      final filler = List.generate(95, (i) => '  "Key$i": $i,').join('\n');
      final path = await write(
        '/Mods/Workshop/deep.json',
        '{\n$filler\n  "SaveName": "Deep",\n  "EpochTime": 42\n}',
      );
      final header = await reader.readHeader(path, ModType.mod);
      expect(header, const ModHeader(saveName: 'Deep', epochTime: 42));
    });

    test('stops reading as soon as SaveName and EpochTime are found', () async {
      // Build a file whose header is in the first lines, followed by a long
      // tail. Serve it through a mocked File that emits 1 KB chunks and
      // counts how many were pulled; the reader must stop long before the end.
      final tail = List.generate(
        20000,
        (i) => '  "Filler$i": "https://example.com/$i.png",',
      ).join('\n');
      final content = '{\n  "SaveName": "Early",\n  "EpochTime": 7,\n$tail\n}';
      final bytes = utf8.encode(content);
      const chunkSize = 1024;
      final totalChunks = (bytes.length / chunkSize).ceil();
      var emitted = 0;

      Stream<List<int>> chunked() async* {
        for (var start = 0; start < bytes.length; start += chunkSize) {
          emitted++;
          final end = start + chunkSize;
          yield bytes.sublist(start, end > bytes.length ? bytes.length : end);
        }
      }

      final file = _MockFile();
      when(file.openRead).thenAnswer((_) => chunked());
      final mockFs = _MockFileSystem();
      when(() => mockFs.file(any<String>())).thenReturn(file);

      final spyReader = JsonModReader(fileSystem: mockFs);
      final header = await spyReader.readHeader('/m/early.json', ModType.mod);

      expect(header, const ModHeader(saveName: 'Early', epochTime: 7));
      expect(totalChunks, greaterThan(100));
      expect(
        emitted,
        lessThan(5),
        reason: 'read $emitted of $totalChunks chunks',
      );
    });

    test('savedObject reads until the Nickname is found', () async {
      final filler = List.generate(40, (i) => '  "Key$i": $i,').join('\n');
      final path = await write(
        '/Saves/Saved Objects/o.json',
        '{\n  "SaveName": "",\n  "EpochTime": 1,\n$filler\n'
            '  "ObjectStates": [{"Nickname": "Late"}]\n}',
      );
      final header = await reader.readHeader(path, ModType.savedObject);
      expect(header.saveName, 'o');
      expect(header.nickname, 'Late');
      expect(header.epochTime, 1);
    });

    test('throws when the file does not exist', () async {
      await expectLater(
        reader.readHeader('/missing.json', ModType.mod),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  group('readFull', () {
    test('returns header, typed assets, size and mtime', () async {
      final path = await write('/Mods/Workshop/123.json', _modJson);
      final result = await reader.readFull(path, ModType.mod);

      expect(
        result.header,
        const ModHeader(saveName: 'My Mod', epochTime: 1700000000),
      );
      expect(result.assets, const [
        AssetUrl(
          url: 'https://steamusercontent-a.akamaihd.net/ugc/9/table.jpg',
          jsonKey: 'TableURL',
          type: AssetType.image,
        ),
        AssetUrl(
          url: 'https://x/m.obj',
          jsonKey: 'MeshURL',
          type: AssetType.model,
        ),
        AssetUrl(
          url: 'https://a/d.png',
          jsonKey: 'DiffuseURL',
          type: AssetType.image,
        ),
        AssetUrl(
          url: 'https://b/d.png',
          jsonKey: 'DiffuseURL',
          type: AssetType.image,
        ),
      ]);
      expect(result.sizeBytes, utf8.encode(_modJson).length);
      expect(result.modified, fs.file(path).statSync().modified);
      expect(result.toString(), contains('4 assets'));
    });

    test('savedObject: basename, nickname, assets', () async {
      final path = await write('/Saves/Saved Objects/d.json', _savedObjectJson);
      final result = await reader.readFull(path, ModType.savedObject);
      expect(result.header.saveName, 'd');
      expect(result.header.nickname, 'Red Dragon');
      expect(result.assets.single.url, 'https://x/dragon.obj');
    });

    test('header matches readHeader for the same file', () async {
      final path = await write('/Mods/Workshop/same.json', _modJson);
      final full = await reader.readFull(path, ModType.mod);
      final head = await reader.readHeader(path, ModType.mod);
      expect(full.header, head);
    });

    test('falls back to basename when SaveName is missing', () async {
      final path = await write('/Mods/Workshop/nb.json', '{"MeshURL": "x"}');
      final result = await reader.readFull(path, ModType.mod);
      expect(result.header.saveName, 'nb');
      expect(result.header.epochTime, isNull);
      expect(result.assets, isEmpty);
    });

    group('header beyond the decoded prefix', () {
      // A first value longer than the prefix pushes every header key past
      // the prefix's last line break; the reader must fall back to the
      // whole file and find the same header as readHeader.
      final filler = 'x' * (JsonModReader.headerPrefixBytes + 1000);

      test('SaveName and EpochTime after a very long first line', () async {
        final path = await write(
          '/Mods/Workshop/late.json',
          '{\n  "Note": "$filler",\n  "SaveName": "Late",\n'
              '  "EpochTime": 1700000001,\n  "MeshURL": "https://x/m.obj"\n}',
        );
        final result = await reader.readFull(path, ModType.mod);
        expect(
          result.header,
          const ModHeader(saveName: 'Late', epochTime: 1700000001),
        );
        expect(result.header, await reader.readHeader(path, ModType.mod));
        expect(result.assets.single.url, 'https://x/m.obj');
      });

      test('EpochTime cut by the prefix is not truncated', () async {
        // The prefix ends at the last line break before 64 KB; put the
        // EpochTime digits exactly across that boundary with no line break
        // in between so a naive prefix match would see fewer digits.
        const head = '{"SaveName": "Cut", "EpochTime": ';
        final pad = 'y' * (JsonModReader.headerPrefixBytes - head.length - 5);
        final path = await write(
          '/Mods/Workshop/cut.json',
          '$head'
              '1700000002, "Note": "$pad", "MeshURL": "https://x/m.obj"}',
        );
        final result = await reader.readFull(path, ModType.mod);
        expect(result.header.epochTime, 1700000002);
        expect(result.header.saveName, 'Cut');
      });

      test('Date fallback is only used when no EpochTime exists', () async {
        final path = await write(
          '/Mods/Workshop/date.json',
          '{\n  "Date": "1/1/2000 1:00:00 AM",\n  "Note": "$filler",\n'
              '  "SaveName": "Dated",\n  "EpochTime": 1700000003\n}',
        );
        final result = await reader.readFull(path, ModType.mod);
        expect(result.header.epochTime, 1700000003);
        expect(result.header, await reader.readHeader(path, ModType.mod));
      });

      test('minified JSON without line breaks', () async {
        final path = await write(
          '/Mods/Workshop/min.json',
          '{"Note":"$filler","SaveName":"Min","EpochTime":5,'
              '"MeshURL":"https://x/m.obj"}',
        );
        final result = await reader.readFull(path, ModType.mod);
        expect(result.header, const ModHeader(saveName: 'Min', epochTime: 5));
        expect(result.assets.single.url, 'https://x/m.obj');
      });

      test('saved object Nickname after a very long first line', () async {
        final path = await write(
          '/Saves/Saved Objects/late.json',
          '{\n  "SaveName": "",\n  "Note": "$filler",\n  "EpochTime": 7,\n'
              '  "ObjectStates": [{"Nickname": "Late Dragon"}]\n}',
        );
        final result = await reader.readFull(path, ModType.savedObject);
        expect(result.header.saveName, 'late');
        expect(result.header.nickname, 'Late Dragon');
        expect(result.header.epochTime, 7);
      });
    });

    test('malformed UTF-8 fails the file as readAsString did', () async {
      final file = fs.file('/Mods/Workshop/bad.json');
      await file.create(recursive: true);
      await file.writeAsBytes([
        ...utf8.encode('{"SaveName": "Bad '),
        0xFF,
        ...utf8.encode('", "EpochTime": 9, "MeshURL": "https://x/m.obj"}'),
      ]);
      await expectLater(
        reader.readFull(file.path, ModType.mod),
        throwsA(
          isA<FileSystemException>()
              .having((e) => e.message, 'message', contains('utf-8'))
              .having((e) => e.path, 'path', file.path),
        ),
      );
      // The same bytes fail readAsString the same way.
      await expectLater(
        file.readAsString(),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('a leading BOM is ignored', () async {
      final path = await write('/Mods/Workshop/bom.json', '﻿$_modJson');
      final result = await reader.readFull(path, ModType.mod);
      expect(result.header.saveName, 'My Mod');
      expect(result.assets, hasLength(4));
    });
  });

  test('ModHeader has value equality', () {
    const a = ModHeader(saveName: 'a', epochTime: 1, nickname: 'n');
    const b = ModHeader(saveName: 'a', epochTime: 1, nickname: 'n');
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(const ModHeader(saveName: 'a', epochTime: 2)));
    expect(a.toString(), contains('nickname: n'));
  });

  test('default constructor uses the local file system', () {
    const defaultReader = JsonModReader();
    expect(defaultReader.fileSystem, isA<FileSystem>());
  });
}
