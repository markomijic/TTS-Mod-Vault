/// Per-locale text assets (the help text) with an English fallback.
library;

import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart' show rootBundle;

/// Reads a text asset; `rootBundle.loadString` by default.
typedef AssetTextLoader = Future<String> Function(String path);

/// The asset paths to try for [basePath] (`assets/text/help.md`) in [locale],
/// most specific first, ending with [basePath] itself:
/// `help_pt_BR.md`, `help_pt.md`, `help.md`. English has no variant of its own;
/// the base file is the English text.
List<String> localizedAssetPaths(String basePath, Locale locale) {
  final dot = basePath.lastIndexOf('.');
  final stem = dot < 0 ? basePath : basePath.substring(0, dot);
  final extension = dot < 0 ? '' : basePath.substring(dot);
  final language = locale.languageCode;
  if (language == 'en') return [basePath];
  final country = locale.countryCode;
  return [
    if (country != null && country.isNotEmpty)
      '${stem}_${language}_$country$extension',
    '${stem}_$language$extension',
    basePath,
  ];
}

/// Loads the first of [localizedAssetPaths] that exists. A missing locale
/// file is an expected case and falls through to the next candidate; the
/// last one ([basePath]) is allowed to throw.
Future<String> loadLocalizedAsset(
  String basePath,
  Locale locale, {
  AssetTextLoader? load,
}) async {
  final loader = load ?? rootBundle.loadString;
  final paths = localizedAssetPaths(basePath, locale);
  for (final path in paths.take(paths.length - 1)) {
    try {
      return await loader(path);
    } on FlutterError {
      continue;
    }
  }
  return loader(paths.last);
}
