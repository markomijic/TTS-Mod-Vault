import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:tts_mod_vault/app/app.dart';
import 'package:tts_mod_vault/features/library/presentation/mod_badges.dart'
    show formatModDate;
import 'package:tts_mod_vault/l10n/locale_tags.dart';

void main() {
  group('resolveLocale', () {
    const en = Locale('en');
    const pt = Locale('pt');
    const ptBr = Locale('pt', 'BR');
    const de = Locale('de');

    test('prefers an exact match', () {
      expect(resolveLocale(ptBr, [en, pt, ptBr]), ptBr);
    });

    test('falls back from a regional locale to its language', () {
      expect(resolveLocale(ptBr, [en, pt]), pt);
      expect(resolveLocale(const Locale('de', 'AT'), [en, de]), de);
    });

    test('falls back from a bare language to a regional variant', () {
      expect(resolveLocale(pt, [en, ptBr]), ptBr);
    });

    test('falls back to English', () {
      expect(resolveLocale(const Locale('fr'), [en, de]), en);
      expect(resolveLocale(null, [de]), en);
    });
  });

  group('locale tags', () {
    test('parse language, script and country', () {
      expect(localeFromTag('de'), const Locale('de'));
      expect(localeFromTag('pt-BR'), const Locale('pt', 'BR'));
      expect(localeFromTag('pt_BR'), const Locale('pt', 'BR'));
      expect(
        localeFromTag('zh-Hant-TW'),
        const Locale.fromSubtags(
          languageCode: 'zh',
          scriptCode: 'Hant',
          countryCode: 'TW',
        ),
      );
      expect(localeFromTag(null), isNull);
      expect(localeFromTag(' '), isNull);
    });

    test('native names fall back to the tag', () {
      expect(nativeLanguageName(const Locale('en')), 'English');
      expect(nativeLanguageName(const Locale('xx')), 'xx');
    });
  });

  group('formatModDate', () {
    final date = DateTime(2024, 3, 5, 9, 15);

    setUpAll(() => initializeDateFormatting('de'));

    test('follows the locale', () {
      expect(formatModDate('en', date), isNot(formatModDate('de', date)));
      expect(formatModDate('de', date), contains('Mär'));
    });

    test('falls back to English for a locale without date symbols', () {
      expect(formatModDate('xx', date), formatModDate('en', date));
    });
  });
}
