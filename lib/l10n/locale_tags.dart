/// Locale helpers that sit outside the generated localizations: BCP 47 tag
/// parsing for the language setting and the native language names.
library;

import 'dart:ui' show Locale;

/// Each supported language written in itself ("Deutsch", not "German"). Not
/// in the ARB: a name in its own language is never translated. Add an entry
/// when an `app_<locale>.arb` is added; a locale without one is listed by its
/// tag.
const Map<String, String> nativeLanguageNames = {
  'en': 'English',
  'hr': 'Hrvatski',
  'pt': 'Português (Brasil)',
  'ru': 'Русский',
  'es': 'Español',
  'ko': '한국어',
  'zh': '简体中文',
  'de': 'Deutsch',
  'fr': 'Français',
};

/// Parses a BCP 47 [tag] (`de`, `pt-BR`, `zh-Hant-TW`; `_` is accepted too)
/// into a [Locale], or `null` for a null or blank tag.
Locale? localeFromTag(String? tag) {
  if (tag == null) return null;
  final parts = tag.trim().split(RegExp('[-_]')).where((p) => p.isNotEmpty);
  if (parts.isEmpty) return null;
  final language = parts.first;
  String? script;
  String? country;
  for (final part in parts.skip(1)) {
    if (part.length == 4 && script == null && country == null) {
      script = part;
    } else {
      country ??= part;
    }
  }
  return Locale.fromSubtags(
    languageCode: language,
    scriptCode: script,
    countryCode: country,
  );
}

/// The BCP 47 tag of [locale] (`de`, `pt-BR`), as stored in the settings.
String localeTag(Locale locale) => locale.toLanguageTag();

/// The native name shown for [locale] in the language dropdown.
String nativeLanguageName(Locale locale) =>
    nativeLanguageNames[locale.toLanguageTag()] ??
    nativeLanguageNames[locale.languageCode] ??
    locale.toLanguageTag();
