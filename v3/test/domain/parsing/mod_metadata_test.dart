import 'package:flutter_test/flutter_test.dart';
import 'package:tts_mod_vault/domain/parsing/mod_metadata.dart';

void main() {
  group('extractSaveName', () {
    test('reads the value with any spacing', () {
      expect(extractSaveName('{"SaveName":"My Mod"}'), 'My Mod');
      expect(extractSaveName('{\n  "SaveName" :   "My Mod",\n}'), 'My Mod');
    });

    test('returns null when the key is absent', () {
      expect(extractSaveName('{"Nickname": "x"}'), isNull);
      expect(extractSaveName(''), isNull);
    });

    test('returns the empty string for an empty value', () {
      expect(extractSaveName('{"SaveName": ""}'), '');
    });

    test('handles escaped quotes and other JSON escapes', () {
      expect(
        extractSaveName(r'{"SaveName": "My \"Great\" Mod", "Date": ""}'),
        'My "Great" Mod',
      );
      expect(
        extractSaveName(r'{"SaveName": "Back\\slash \u00e9 tab\t"}'),
        'Back\\slash \u00e9 tab\t',
      );
    });

    test('does not swallow following keys', () {
      expect(extractSaveName('{"SaveName": "A", "GameMode": "B"}'), 'A');
    });
  });

  group('extractNickname', () {
    test('reads the first Nickname', () {
      const json = '''
{
  "SaveName": "",
  "ObjectStates": [
    {"Nickname": "Red Die", "Name": "Die_6"},
    {"Nickname": "Blue Die", "Name": "Die_6"}
  ]
}''';
      expect(extractNickname(json), 'Red Die');
    });

    test('returns null when absent', () {
      expect(extractNickname('{"SaveName": "x"}'), isNull);
    });

    test('decodes escapes', () {
      expect(extractNickname(r'{"Nickname": "Say \"hi\""}'), 'Say "hi"');
    });
  });

  group('extractEpochTime', () {
    test('prefers EpochTime over Date', () {
      const json = '''
{
  "Date": "1/1/2000 1:00:00 AM",
  "EpochTime": 1700000000
}''';
      expect(extractEpochTime(json), 1700000000);
      expect(extractEpochTime('{"EpochTime":1700000001}'), 1700000001);
    });

    test('falls back to Date with AM/PM (M/d/yyyy h:mm:ss a)', () {
      const json = '{"Date": "3/5/2024 2:07:09 PM"}';
      final expected = DateTime(2024, 3, 5, 14, 7, 9).millisecondsSinceEpoch;
      expect(extractEpochTime(json), expected ~/ 1000);
    });

    test('falls back to Date with 24h clock (MM/dd/yyyy HH:mm:ss)', () {
      const json = '{"Date": "03/05/2024 14:07:09"}';
      final expected = DateTime(2024, 3, 5, 14, 7, 9).millisecondsSinceEpoch;
      expect(extractEpochTime(json), expected ~/ 1000);
    });

    test('lower-case am/pm selects the 12h format but does not parse (v2)', () {
      // v2 checks for AM/PM case-insensitively only to pick the pattern;
      // intl's `a` field then needs the upper-case marker TTS writes.
      const json = '{"Date": "12/31/2023 11:59:59 pm"}';
      expect(extractEpochTime(json), isNull);
      const upper = '{"Date": "12/31/2023 11:59:59 PM"}';
      final expected = DateTime(
        2023,
        12,
        31,
        23,
        59,
        59,
      ).millisecondsSinceEpoch;
      expect(extractEpochTime(upper), expected ~/ 1000);
    });

    test('returns null when neither key is present', () {
      expect(extractEpochTime('{"SaveName": "x"}'), isNull);
      expect(extractEpochTime(''), isNull);
    });

    test('returns null for an unparseable or empty Date', () {
      expect(extractEpochTime('{"Date": "yesterday"}'), isNull);
      expect(extractEpochTime('{"Date": ""}'), isNull);
    });

    test('non-numeric EpochTime falls through to Date', () {
      const json = '{"EpochTime": "abc", "Date": "03/05/2024 14:07:09"}';
      final expected = DateTime(2024, 3, 5, 14, 7, 9).millisecondsSinceEpoch;
      expect(extractEpochTime(json), expected ~/ 1000);
    });
  });

  group('replaceSaveName', () {
    test('replaces only the value, preserving key, spacing and quotes', () {
      const json = '{\n  "SaveName"  :   "Old Name",\n  "GameMode": "x"\n}';
      expect(
        replaceSaveName(json, 'New Name'),
        '{\n  "SaveName"  :   "New Name",\n  "GameMode": "x"\n}',
      );
    });

    test('JSON-escapes the new value', () {
      const json = '{"SaveName": "Old"}';
      expect(
        replaceSaveName(json, 'Say "hi"\\now\n'),
        r'{"SaveName": "Say \"hi\"\\now\n"}',
      );
    });

    test('replaces a value that itself contains escaped quotes', () {
      const json = r'{"SaveName": "My \"Great\" Mod", "Date": "d"}';
      expect(
        replaceSaveName(json, 'Plain'),
        '{"SaveName": "Plain", "Date": "d"}',
      );
    });

    test('replaces an empty value', () {
      expect(replaceSaveName('{"SaveName": ""}', 'X'), '{"SaveName": "X"}');
    });

    test('returns the input unchanged when SaveName is absent', () {
      const json = '{"Nickname": "obj"}';
      expect(replaceSaveName(json, 'X'), same(json));
    });

    test('only the first SaveName is touched', () {
      const json = '{"SaveName": "A", "Nested": {"SaveName": "B"}}';
      expect(
        replaceSaveName(json, 'C'),
        '{"SaveName": "C", "Nested": {"SaveName": "B"}}',
      );
    });

    test('round-trips with extractSaveName', () {
      final replaced = replaceSaveName('{"SaveName": "x"}', 'Q "uo" te');
      expect(extractSaveName(replaced), 'Q "uo" te');
    });
  });

  group('replaceUrl', () {
    test('replaces every occurrence of the URL', () {
      const json = '{"a": "https://x/1.png", "b": "https://x/1.png"}';
      expect(
        replaceUrl(json, 'https://x/1.png', 'https://y/2.png'),
        '{"a": "https://y/2.png", "b": "https://y/2.png"}',
      );
    });

    test('replaces the legacy-host form when the file still has it', () {
      const json =
          '{"MeshURL": "http://cloud-3.steamusercontent.com/ugc/1/2/"}';
      expect(
        replaceUrl(
          json,
          'https://steamusercontent-a.akamaihd.net/ugc/1/2/',
          'https://new.example.com/m.obj',
        ),
        '{"MeshURL": "https://new.example.com/m.obj"}',
      );
    });

    test('replaces the new-host form when the file already uses it', () {
      const json =
          '{"MeshURL": "https://steamusercontent-a.akamaihd.net/ugc/1/2/"}';
      expect(
        replaceUrl(
          json,
          'https://steamusercontent-a.akamaihd.net/ugc/1/2/',
          'https://new.example.com/m.obj',
        ),
        '{"MeshURL": "https://new.example.com/m.obj"}',
      );
    });

    test('returns the input unchanged when the URL is not present', () {
      const json = '{"MeshURL": "https://x/a.obj"}';
      expect(replaceUrl(json, 'https://x/b.obj', 'https://x/c.obj'), json);
    });
  });
}
