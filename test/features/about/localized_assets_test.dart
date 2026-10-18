import 'dart:io' show File;
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_mod_vault/features/about/application/localized_assets.dart';
import 'package:tts_mod_vault/features/about/application/translator_credits.dart';

const String _base = 'assets/text/help.md';

/// A loader that serves [files] and throws a [FlutterError] for the rest, as
/// `rootBundle.loadString` does for an unknown asset.
AssetTextLoader _bundle(Map<String, String> files, [List<String>? asked]) =>
    (path) async {
      asked?.add(path);
      final text = files[path];
      if (text == null) throw FlutterError('Unable to load asset: $path');
      return text;
    };

void main() {
  group('localizedAssetPaths', () {
    test('English uses the base file only', () {
      expect(localizedAssetPaths(_base, const Locale('en')), [_base]);
      expect(localizedAssetPaths(_base, const Locale('en', 'GB')), [_base]);
    });

    test('a language tries the language file, then the base', () {
      expect(localizedAssetPaths(_base, const Locale('de')), [
        'assets/text/help_de.md',
        _base,
      ]);
    });

    test('a regional locale tries the regional file first', () {
      expect(localizedAssetPaths(_base, const Locale('pt', 'BR')), [
        'assets/text/help_pt_BR.md',
        'assets/text/help_pt.md',
        _base,
      ]);
    });
  });

  group('loadLocalizedAsset', () {
    const en = 'English help';

    test('uses the locale file when it exists', () async {
      final text = await loadLocalizedAsset(
        _base,
        const Locale('de'),
        load: _bundle({_base: en, 'assets/text/help_de.md': 'Hilfe'}),
      );
      expect(text, 'Hilfe');
    });

    test('falls back to English when the locale has no file', () async {
      final asked = <String>[];
      final text = await loadLocalizedAsset(
        _base,
        const Locale('de'),
        load: _bundle({_base: en}, asked),
      );
      expect(text, en);
      expect(asked, ['assets/text/help_de.md', _base]);
    });

    test('a regional locale falls back to its language file', () async {
      final text = await loadLocalizedAsset(
        _base,
        const Locale('pt', 'BR'),
        load: _bundle({_base: en, 'assets/text/help_pt.md': 'Ajuda'}),
      );
      expect(text, 'Ajuda');
    });

    test('English never asks for a locale file', () async {
      final asked = <String>[];
      await loadLocalizedAsset(
        _base,
        const Locale('en'),
        load: _bundle({_base: en}, asked),
      );
      expect(asked, [_base]);
    });

    test('a missing base file still throws', () {
      expect(
        loadLocalizedAsset(_base, const Locale('de'), load: _bundle({})),
        throwsA(isA<FlutterError>()),
      );
    });
  });

  group('parseTranslatorCredits', () {
    test('reads list lines and ignores everything else', () {
      const markdown = '''
# Translators

Prose with `- de: not a credit` inside.

- de: Jane Doe, John Roe
* pt_BR:  Maria Silva
- zh-Hant-TW: 王小明
- not a credit
<!-- - fr: Hidden -->
''';
      expect(parseTranslatorCredits(markdown), const [
        TranslatorCredit(localeTag: 'de', names: 'Jane Doe, John Roe'),
        TranslatorCredit(localeTag: 'pt-BR', names: 'Maria Silva'),
        TranslatorCredit(localeTag: 'zh-Hant-TW', names: '王小明'),
      ]);
    });

    test('tolerates Windows line endings', () {
      expect(parseTranslatorCredits('- de: Jane\r\n- hr: Ivo\r\n'), const [
        TranslatorCredit(localeTag: 'de', names: 'Jane'),
        TranslatorCredit(localeTag: 'hr', names: 'Ivo'),
      ]);
    });

    test('every credit in the shipped TRANSLATORS.md has an ARB file', () {
      final credits = parseTranslatorCredits(
        File('TRANSLATORS.md').readAsStringSync(),
      );
      for (final credit in credits) {
        final arb = 'lib/l10n/app_${credit.localeTag.replaceAll('-', '_')}.arb';
        expect(
          File(arb).existsSync(),
          isTrue,
          reason: '${credit.localeTag}: $arb',
        );
      }
    });
  });
}
