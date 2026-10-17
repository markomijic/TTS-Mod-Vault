import 'dart:io' show stdout;

import 'package:flutter_test/flutter_test.dart';
import 'package:tts_mod_vault/domain/constants.dart';
import 'package:tts_mod_vault/domain/enums/asset_type.dart';
import 'package:tts_mod_vault/domain/parsing/url_extraction.dart';

void main() {
  group('extractAssetUrls', () {
    test('plain JSON key/value for every asset key', () {
      for (final type in AssetType.values) {
        for (final key in type.jsonKeys) {
          final json = '{\n  "$key": "https://example.com/$key.bin"\n}';
          expect(extractAssetUrls(json), {
            'https://example.com/$key.bin': key,
          }, reason: key);
        }
      }
    });

    test('tolerates no whitespace and lots of whitespace around the colon', () {
      expect(extractAssetUrls('{"MeshURL":"https://x/y.obj"}'), {
        'https://x/y.obj': 'MeshURL',
      });
      expect(extractAssetUrls('{"MeshURL"   :\n\t  "https://x/y.obj"}'), {
        'https://x/y.obj': 'MeshURL',
      });
    });

    test('Lua-embedded escaped JSON (spawnObjectJSON)', () {
      const lua = r'''
{
  "LuaScript": "function onLoad()\n  spawnObjectJSON({json = \"{\\\"Name\\\": \\\"Custom_Model\\\", \\\"CustomMesh\\\": {\\\"MeshURL\\\": \\\"https://x/y.obj\\\", \\\"DiffuseURL\\\": \\\"https://x/y.png\\\"}}\"})\nend",
  "Simple": "\"MeshURL\": \"https://x/z.obj\""
}''';
      expect(extractAssetUrls(lua), {
        'https://x/y.obj': 'MeshURL',
        'https://x/y.png': 'DiffuseURL',
        'https://x/z.obj': 'MeshURL',
      });
    });

    test('multi-language value yields one URL per language, prefixes dropped', () {
      const json =
          '{"ImageURL": "{en}https://www.en-example.com/a.png{fr}https://www.fr-example.com/b.png"}';
      expect(extractAssetUrls(json), {
        'https://www.en-example.com/a.png': 'ImageURL',
        'https://www.fr-example.com/b.png': 'ImageURL',
      });
    });

    test('accepts any scheme (steam://, s3://)', () {
      const json = '''
{
  "AssetbundleURL": "steam://url/CommunityFilePage/123",
  "PDFUrl": "s3://bucket/rules.pdf"
}''';
      expect(extractAssetUrls(json), {
        'steam://url/CommunityFilePage/123': 'AssetbundleURL',
        's3://bucket/rules.pdf': 'PDFUrl',
      });
    });

    test('accepts scheme-less domain-shaped values', () {
      const json = '{"FaceURL": "www.example.com/path/to/face.jpg"}';
      expect(extractAssetUrls(json), {
        'www.example.com/path/to/face.jpg': 'FaceURL',
      });
    });

    test(
      'accepts hosts that are not domain-shaped when a scheme is present',
      () {
        const json = '''
{
  "ImageURL": "http://192.168.1.10:8080/img.png?x=1&y=2",
  "BackURL": "https://something",
  "MeshURL": "https://localhost/mesh.obj"
}''';
        expect(extractAssetUrls(json), {
          'http://192.168.1.10:8080/img.png?x=1&y=2': 'ImageURL',
          'https://something': 'BackURL',
          'https://localhost/mesh.obj': 'MeshURL',
        });
      },
    );

    test('skips file:/ values', () {
      const json = '''
{
  "ImageURL": "file:///C:/x.png",
  "BackURL": "file:/tmp/y.png",
  "FaceURL": "https://ok.example.com/z.png"
}''';
      expect(extractAssetUrls(json), {
        'https://ok.example.com/z.png': 'FaceURL',
      });
    });

    test('rewrites the legacy Steam Cloud host', () {
      const json =
          '{"MeshURL": "http://cloud-3.steamusercontent.com/ugc/1/2/"}';
      expect(extractAssetUrls(json), {
        'https://steamusercontent-a.akamaihd.net/ugc/1/2/': 'MeshURL',
      });
      expect(
        extractAssetUrls(json).keys.single,
        startsWith(newSteamUserContentUrl),
      );
      expect(oldCloudUrl, 'http://cloud-3.steamusercontent.com/');
    });

    test('literal backslash-r / backslash-n sequences never reach a URL', () {
      // In the file these are the two-character sequences `\r` and `\n`
      // inside the string value (JSON for CR/LF, which TTS ignores). The
      // combined regex stops its capture at the backslash and `_processUrl`
      // strips any that get through; either way the URL comes out clean.
      const json = r'{"ImageURL": "https://example.com/a.png\r\n"}';
      expect(extractAssetUrls(json), {'https://example.com/a.png': 'ImageURL'});
      const leading = r'{"BackURL": "\r\nhttps://example.com/b.png"}';
      expect(extractAssetUrls(leading), isEmpty);
    });

    test('keys merely containing an asset key as a substring are ignored', () {
      const json = '''
{
  "CustomMeshURLBackup": "https://no.example.com/1.obj",
  "MyImageURL": "https://no.example.com/2.png",
  "URLs": "https://no.example.com/3.png",
  "MeshURL": "https://yes.example.com/4.obj"
}''';
      expect(extractAssetUrls(json), {
        'https://yes.example.com/4.obj': 'MeshURL',
      });
    });

    test('keys are case-sensitive', () {
      expect(extractAssetUrls('{"meshurl": "https://x/y.obj"}'), isEmpty);
      expect(extractAssetUrls('{"url": "https://x/y.png"}'), isEmpty);
    });

    test('Item1 counts as audio (v2 quirk)', () {
      const json = '{"Item1": "https://example.com/track.mp3"}';
      final typed = extractAssetUrlsTyped(json);
      expect(typed.single.jsonKey, 'Item1');
      expect(typed.single.type, AssetType.audio);
    });

    test('empty values are ignored', () {
      expect(extractAssetUrls('{"MeshURL": "", "DiffuseURL": ""}'), isEmpty);
    });

    test('non-URL values are dropped by the second pass', () {
      expect(extractAssetUrls('{"ImageURL": "not a url"}'), isEmpty);
      expect(extractAssetUrls('{"ImageURL": "{en}"}'), isEmpty);
    });

    test('same URL under several keys: last key wins', () {
      const json = '''
{
  "ImageURL": "https://example.com/a.png",
  "BackURL": "https://example.com/a.png"
}''';
      expect(extractAssetUrls(json), {'https://example.com/a.png': 'BackURL'});
    });

    test('scheme-less domain with uppercase letters is accepted', () {
      // The url regex is case-insensitive, the TLD class `[a-z]{2,}` included.
      expect(extractAssetUrls('{"ImageURL": "Www.Example.COM/A.png"}'), {
        'Www.Example.COM/A.png': 'ImageURL',
      });
    });

    test('mixed real-world mod snippet', () {
      const json = r'''
{
  "SaveName": "Test",
  "EpochTime": 1700000000,
  "TableURL": "http://cloud-3.steamusercontent.com/ugc/9/table.jpg",
  "SkyURL": "https://i.imgur.com/sky.jpg",
  "ObjectStates": [
    {
      "Name": "Custom_Model",
      "CustomMesh": {
        "MeshURL": "https://pastebin.com/raw/abc",
        "DiffuseURL": "{en}https://a/d.png{de}https://b/d.png",
        "ColliderURL": ""
      },
      "CustomPDF": { "PDFUrl": "https://x/rules.PDF" },
      "CustomAssetbundle": { "AssetbundleURL": "https://x/b.unity3d" },
      "LuaScript": "spawnObjectJSON({json=\"{\\\"CustomImage\\\":{\\\"ImageURL\\\":\\\"https://lua/i.png\\\"}}\"})"
    }
  ]
}''';
      expect(extractAssetUrls(json), {
        'https://steamusercontent-a.akamaihd.net/ugc/9/table.jpg': 'TableURL',
        'https://i.imgur.com/sky.jpg': 'SkyURL',
        'https://pastebin.com/raw/abc': 'MeshURL',
        'https://a/d.png': 'DiffuseURL',
        'https://b/d.png': 'DiffuseURL',
        'https://x/rules.PDF': 'PDFUrl',
        'https://x/b.unity3d': 'AssetbundleURL',
        'https://lua/i.png': 'ImageURL',
      });
    });
  });

  group('extractAssetUrlsTyped', () {
    test('resolves the type of every key', () {
      for (final type in AssetType.values) {
        for (final key in type.jsonKeys) {
          final typed = extractAssetUrlsTyped('{"$key": "https://x/$key"}');
          expect(typed, [
            AssetUrl(url: 'https://x/$key', jsonKey: key, type: type),
          ]);
        }
      }
    });

    test('AssetUrl has value equality', () {
      const a = AssetUrl(
        url: 'https://x/a',
        jsonKey: 'MeshURL',
        type: AssetType.model,
      );
      const b = AssetUrl(
        url: 'https://x/a',
        jsonKey: 'MeshURL',
        type: AssetType.model,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.toString(), contains('MeshURL'));
    });
  });

  group('performance', () {
    test('~60 MB synthetic JSON with ~200k URLs extracts in a few seconds', () {
      final buffer = StringBuffer('{\n  "SaveName": "Big",\n');
      const keys = ['MeshURL', 'DiffuseURL', 'ImageURL', 'FaceURL', 'BackURL'];
      // ~200k URL entries, each padded with Lua-like filler so the file lands
      // around 60 MB (300 bytes per entry).
      const entries = 200000;
      final filler = 'x' * 180;
      for (var i = 0; i < entries; i++) {
        final key = keys[i % keys.length];
        buffer
          ..write('  "LuaScript$i": "function onLoad() -- $filler end",\n')
          ..write('  "$key": "https://cdn.example.com/assets/$i/file.bin",\n');
      }
      buffer.write('  "End": true\n}');
      final json = buffer.toString();
      expect(json.length, greaterThan(55 * 1024 * 1024));

      final stopwatch = Stopwatch()..start();
      final result = extractAssetUrls(json);
      stopwatch.stop();

      stdout.writeln(
        'extractAssetUrls: ${json.length ~/ (1024 * 1024)} MB, '
        '${result.length} URLs in ${stopwatch.elapsedMilliseconds} ms',
      );
      expect(result.length, entries);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 10)));
    });
  });
}
