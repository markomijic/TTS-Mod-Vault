import 'package:flutter_test/flutter_test.dart';
import 'package:tts_mod_vault/features/url_updates/application/url_prefix_rules.dart';
import 'package:tts_mod_vault/features/url_updates/application/url_replacement_preset.dart';

const _old = 'http://old.example.com/';
const _new = 'https://new.example.com/';
const _a = '${_old}a.png';
const _b = '${_old}sub/b.obj';
const _other = 'https://other.example.com/c.png';

String _json(List<String> urls) =>
    '{"ObjectStates":[${urls.map((u) => '{"ImageURL":"$u"}').join(',')}]}';

void main() {
  group('applyUrlPrefixes', () {
    test('rewrites every matching URL and records the renames', () {
      final result = applyUrlPrefixes(
        _json([_a, _b, _other, _a]),
        oldPrefixes: [_old],
        newPrefix: _new,
        assetUrls: [_a, _b, _other],
      );

      expect(result.updated, isTrue);
      expect(
        result.text,
        _json(['${_new}a.png', '${_new}sub/b.obj', _other, '${_new}a.png']),
      );
      expect(result.renames, [(_a, '${_new}a.png'), (_b, '${_new}sub/b.obj')]);
    });

    test('leaves the text alone when no URL matches', () {
      final text = _json([_other]);
      final result = applyUrlPrefixes(
        text,
        oldPrefixes: [_old],
        newPrefix: _new,
        assetUrls: [_other],
      );

      expect(result.updated, isFalse);
      expect(result.text, text);
      expect(result.renames, isEmpty);
    });

    test('no asset URLs means no change, even for the legacy host', () {
      const text = '{"ImageURL":"${legacyCloudPrefix}ugc/1/x.png"}';
      final result = applyUrlPrefixes(
        text,
        oldPrefixes: [legacyCloudPrefix],
        newPrefix: akamaiPrefix,
        assetUrls: const [],
      );

      expect(result.updated, isFalse);
      expect(result.text, text);
    });

    test('several old prefixes are tried for every URL', () {
      const second = 'https://second.example.com/';
      final result = applyUrlPrefixes(
        _json([_a, '${second}d.png']),
        oldPrefixes: [_old, second],
        newPrefix: _new,
        assetUrls: [_a, '${second}d.png'],
      );

      expect(result.text, _json(['${_new}a.png', '${_new}d.png']));
      expect(result.renames.length, 2);
    });

    test('a prefix that is only a substring does not match', () {
      final result = applyUrlPrefixes(
        _json([_a]),
        oldPrefixes: ['example.com/'],
        newPrefix: _new,
        assetUrls: [_a],
      );

      expect(result.updated, isFalse);
    });

    test('legacy cloud host to Akamai host rewrites the text globally and '
        'yields no renames', () {
      const text =
          '{"ImageURL":"${legacyCloudPrefix}ugc/1/x.png",'
          '"FaceURL":"${legacyCloudPrefix}ugc/2/y.png"}';
      // The index stores the URLs host-normalised, so none starts with the
      // legacy prefix.
      final result = applyUrlPrefixes(
        text,
        oldPrefixes: [legacyCloudPrefix],
        newPrefix: akamaiPrefix,
        assetUrls: ['${akamaiPrefix}ugc/1/x.png', '${akamaiPrefix}ugc/2/y.png'],
      );

      expect(result.updated, isTrue);
      expect(
        result.text,
        '{"ImageURL":"${akamaiPrefix}ugc/1/x.png",'
        '"FaceURL":"${akamaiPrefix}ugc/2/y.png"}',
      );
      expect(result.renames, isEmpty);
    });

    test('legacy special case needs both hosts', () {
      const text = '{"ImageURL":"${legacyCloudPrefix}ugc/1/x.png"}';
      final result = applyUrlPrefixes(
        text,
        oldPrefixes: [legacyCloudPrefix],
        newPrefix: _new,
        assetUrls: ['${akamaiPrefix}ugc/1/x.png'],
      );

      expect(result.updated, isFalse);
      expect(result.text, text);
    });

    test('the legacy special case can sit next to ordinary prefixes', () {
      const text =
          '{"ImageURL":"${legacyCloudPrefix}ugc/1/x.png","FaceURL":"$_a"}';
      final result = applyUrlPrefixes(
        text,
        oldPrefixes: [legacyCloudPrefix, _old],
        newPrefix: akamaiPrefix,
        assetUrls: ['${akamaiPrefix}ugc/1/x.png', _a],
      );

      expect(
        result.text,
        '{"ImageURL":"${akamaiPrefix}ugc/1/x.png",'
        '"FaceURL":"${akamaiPrefix}a.png"}',
      );
      expect(result.renames, [(_a, '${akamaiPrefix}a.png')]);
    });
  });

  group('parseOldPrefixes', () {
    test('splits on | and trims', () {
      expect(parseOldPrefixes(' a | b ||c'), ['a', 'b', 'c']);
    });

    test('empty input yields no prefixes', () {
      expect(parseOldPrefixes(''), isEmpty);
      expect(parseOldPrefixes(' | '), isEmpty);
    });
  });

  test('isLegacyHostRewrite', () {
    expect(isLegacyHostRewrite([legacyCloudPrefix], akamaiPrefix), isTrue);
    expect(
      isLegacyHostRewrite([_old, legacyCloudPrefix], akamaiPrefix),
      isTrue,
    );
    expect(isLegacyHostRewrite([legacyCloudPrefix], _new), isFalse);
    expect(isLegacyHostRewrite([_old], akamaiPrefix), isFalse);
  });

  group('UrlReplacementPreset', () {
    test('json round trip and equality', () {
      const preset = UrlReplacementPreset(
        label: 'Steam',
        oldUrl: '$legacyCloudPrefix|$_old',
        newUrl: akamaiPrefix,
      );
      final decoded = UrlReplacementPreset.fromJson(preset.toJson());
      expect(decoded, preset);
      expect(decoded.hashCode, preset.hashCode);
      expect(decoded.isBlank, isFalse);
    });

    test('missing fields decode as empty strings', () {
      final preset = UrlReplacementPreset.fromJson({'label': 3});
      expect(
        preset,
        const UrlReplacementPreset(label: '', oldUrl: '', newUrl: ''),
      );
      expect(preset.isBlank, isTrue);
    });
  });
}
