import 'dart:convert' show utf8;
import 'dart:io' show stdout;
import 'dart:typed_data';

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

  group('extractAssetUrlsFromBytes', () {
    Uint8List bytesOf(String text) => Uint8List.fromList(utf8.encode(text));

    // Every input the regex front end is specified against, plus the
    // boundary cases a byte scanner can get wrong: whitespace outside ASCII,
    // multi-byte characters in and around values, backslash runs, matches
    // touching the end of input, and values that look like keys.
    const corpus = [
      '{"MeshURL":"https://x/y.obj"}',
      '{"MeshURL"   :\n\t  "https://x/y.obj"}',
      '{"MeshURL"\u000b:\u000c"https://x/vt.obj"}',
      '{"MeshURL"\u00a0:\u00a0"https://x/nbsp.obj"}',
      '{"MeshURL"\u2028:\u3000"https://x/u2028.obj"}',
      '{"MeshURL"\ufeff:\u2003"https://x/bom-ws.obj"}',
      '{"MeshURL"\u200b:"https://x/zwsp-is-not-space.obj"}',
      '{"MeshURL"\u0085:"https://x/nel-is-not-space.obj"}',
      '{"MeshURL"\u180e:"https://x/mvs-is-not-space.obj"}',
      r'"LuaScript": "spawnObjectJSON({json = [[{\"MeshURL\": \"https://x/l.obj\"}]]})"',
      r'\\\"FaceURL\\\":\\\"https://x/double-escaped.png\\\"',
      r'"FaceURL\": "https://x/odd-backslash.png"',
      r'"FaceURL"\: "https://x/backslash-before-colon.png"',
      '"FaceURL": "{en}https://a.com/x.png{fr}https://b.com/x.png"',
      '"FaceURL": "https://ünïcode.example/ß.png"',
      '"FaceURL": "https://x/\u{1F600}.png"',
      '"FaceURL": "\ufeffhttps://x/bom-inside-value.png"',
      '"FaceURL": "https://x/a.png", "FaceURL": "https://x/a.png"',
      '"FaceURL": "https://x/a.png", "MeshURL": "https://x/a.png"',
      '"FaceURL": ""MeshURL": "https://x/empty-then-key.png"',
      '"FaceURL": "MeshURL": "https://x/value-looks-like-key.png"',
      '"FaceURL": "https://x/unterminated',
      '"FaceURL": "',
      '"FaceURL"',
      '"FaceURL":',
      '"FaceURL"\\',
      '"',
      '',
      '"URL": "https://x/short-key.png", "URLs": "https://x/not-a-key.png"',
      '"XFaceURL": "https://x/prefixed-key.png", "FaceURLX": "https://x/suffixed.png"',
      '"faceurl": "https://x/lowercase.png"',
      '"Item1": "https://x/audio.mp3"',
      '"FaceURL": "file:///C:/local.png", "BackURL": "https://x/kept.png"',
      '"FaceURL": "http://cloud-3.steamusercontent.com/ugc/1/2/"',
      r'"FaceURL": "https://x/a.png\r\n"',
      '"FaceURL": "not a url at all"',
      '"FaceURL": "www.example.com/scheme-less.png"',
      '"FaceURL": "https://x/a.png"\n"FaceURL" : "https://x/b.png"\n"FaceURL"\n:\n"https://x/c.png"',
      '\ufeff{"SaveName": "with leading BOM", "FaceURL": "https://x/bom.png"}',
    ];

    test('matches extractAssetUrls on every corpus entry', () {
      for (final text in corpus) {
        final expected = extractAssetUrls(text);
        expect(
          extractAssetUrlsFromBytes(bytesOf(text)),
          expected,
          reason: text,
        );
        // Map order (first occurrence) must match too.
        expect(
          extractAssetUrlsFromBytes(bytesOf(text)).keys.toList(),
          expected.keys.toList(),
          reason: 'order of $text',
        );
      }
    });

    test('matches extractAssetUrls on every asset key, escaped or not', () {
      for (final type in AssetType.values) {
        for (final key in type.jsonKeys) {
          for (final text in [
            '{"$key": "https://example.com/$key.bin"}',
            '"\\"$key\\": \\"https://example.com/$key-escaped.bin\\""',
          ]) {
            expect(
              extractAssetUrlsFromBytes(bytesOf(text)),
              extractAssetUrls(text),
              reason: text,
            );
          }
        }
      }
    });

    test('a corpus concatenation matches too (resume-after-match)', () {
      final text = corpus.join('\n');
      expect(extractAssetUrlsFromBytes(bytesOf(text)), extractAssetUrls(text));
    });

    test('typed variant resolves the same types', () {
      const text =
          '{"MeshURL": "https://x/m.obj", "PDFUrl": "https://x/p.pdf"}';
      expect(
        extractAssetUrlsTypedFromBytes(bytesOf(text)),
        extractAssetUrlsTyped(text),
      );
    });

    test('malformed UTF-8 throws like utf8.decode, wherever it sits', () {
      final tail = utf8.encode('"FaceURL": "https://x/ok.png"');
      for (final bad in [
        [0xFF], // not a lead byte
        [0x80], // stray continuation byte
        [0xC0, 0x80], // overlong NUL
        [0xE0, 0x80, 0x80], // overlong
        [0xED, 0xA0, 0x80], // UTF-16 surrogate
        [0xF4, 0x90, 0x80, 0x80], // above U+10FFFF
        [0xF5, 0x80, 0x80, 0x80], // invalid lead
        [0xC3], // truncated at end of input
      ]) {
        for (final text in [
          // outside any match
          [
            ...utf8.encode('{"Note": "'),
            ...bad,
            ...utf8.encode('", '),
            ...tail,
          ],
          // inside a URL value
          [
            ...utf8.encode('{"FaceURL": "https://x/'),
            ...bad,
            ...utf8.encode('.png"}'),
          ],
          // between key and value
          [
            ...utf8.encode('{"FaceURL"'),
            ...bad,
            ...utf8.encode(': "https://x/a.png"}'),
          ],
          // at the very end
          [...utf8.encode('{"FaceURL": "https://x/a.png"'), ...bad],
        ]) {
          final bytes = Uint8List.fromList(text);
          expect(
            () => utf8.decode(bytes),
            throwsFormatException,
            reason: '$text',
          );
          expect(
            () => extractAssetUrlsFromBytes(bytes),
            throwsFormatException,
            reason: '$text',
          );
        }
      }
    });

    test('well-formed multi-byte sequences of every length pass', () {
      const text =
          '{"Note": "\u00E9 \u07FF \u0800 \uD800\uDC00 \u{10FFFF} \uD7FF \uE000", '
          '"FaceURL": "https://x/\u{1F600}.png"}';
      final bytes = bytesOf(text);
      expect(extractAssetUrlsFromBytes(bytes), extractAssetUrls(text));
    });

    test('~60 MB synthetic JSON scans the bytes faster than the regex', () {
      final text = _bigJson();
      final bytes = bytesOf(text);
      final stopwatch = Stopwatch()..start();
      final result = extractAssetUrlsFromBytes(bytes);
      stopwatch.stop();
      stdout.writeln(
        'extractAssetUrlsFromBytes: ${bytes.length ~/ (1024 * 1024)} MB, '
        '${result.length} URLs in ${stopwatch.elapsedMilliseconds} ms',
      );
      expect(result.length, _bigJsonEntries);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 10)));
    });
  });

  group('performance', () {
    test('~60 MB synthetic JSON with ~200k URLs extracts in a few seconds', () {
      final json = _bigJson();
      expect(json.length, greaterThan(55 * 1024 * 1024));

      final stopwatch = Stopwatch()..start();
      final result = extractAssetUrls(json);
      stopwatch.stop();

      stdout.writeln(
        'extractAssetUrls: ${json.length ~/ (1024 * 1024)} MB, '
        '${result.length} URLs in ${stopwatch.elapsedMilliseconds} ms',
      );
      expect(result.length, _bigJsonEntries);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 10)));
    });
  });
}

/// URL entries in [_bigJson].
const int _bigJsonEntries = 200000;

/// ~200k URL entries, each padded with Lua-like filler so the text lands
/// around 60 MB (300 bytes per entry).
String _bigJson() {
  final buffer = StringBuffer('{\n  "SaveName": "Big",\n');
  const keys = ['MeshURL', 'DiffuseURL', 'ImageURL', 'FaceURL', 'BackURL'];
  final filler = 'x' * 180;
  for (var i = 0; i < _bigJsonEntries; i++) {
    final key = keys[i % keys.length];
    buffer
      ..write('  "LuaScript$i": "function onLoad() -- $filler end",\n')
      ..write('  "$key": "https://cdn.example.com/assets/$i/file.bin",\n');
  }
  buffer.write('  "End": true\n}');
  return buffer.toString();
}
