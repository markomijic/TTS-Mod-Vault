/// The translator credits of the About tab, read from `TRANSLATORS.md`.
library;

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart' show rootBundle;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:meta/meta.dart';

/// Asset path of the credits file (the repository's `TRANSLATORS.md`).
const String translatorsAssetPath = 'TRANSLATORS.md';

/// The people who translated one language.
@immutable
final class TranslatorCredit {
  /// Creates a credit.
  const TranslatorCredit({required this.localeTag, required this.names});

  /// BCP 47 tag of the language (`de`, `pt-BR`).
  final String localeTag;

  /// The translators, as written in the file.
  final String names;

  @override
  bool operator ==(Object other) =>
      other is TranslatorCredit &&
      other.localeTag == localeTag &&
      other.names == names;

  @override
  int get hashCode => Object.hash(localeTag, names);

  @override
  String toString() => 'TranslatorCredit($localeTag: $names)';
}

final RegExp _creditLine = RegExp(
  r'^\s*[-*]\s+([A-Za-z]{2,3}(?:[-_]\w+)*)\s*:\s*(\S.*?)\s*$',
);

/// Parses `TRANSLATORS.md`: every list line `- <locale tag>: Name, Name`
/// is one credit; everything else (headings, prose, comments) is ignored.
List<TranslatorCredit> parseTranslatorCredits(String markdown) => [
  for (final line in markdown.split('\n'))
    if (_creditLine.firstMatch(line) case final match?)
      TranslatorCredit(
        localeTag: match.group(1)!.replaceAll('_', '-'),
        names: match.group(2)!,
      ),
];

/// The credits listed in `TRANSLATORS.md`; empty when the file is missing.
/// Overridable in tests.
final translatorCreditsProvider = FutureProvider<List<TranslatorCredit>>((
  ref,
) async {
  try {
    return parseTranslatorCredits(
      await rootBundle.loadString(translatorsAssetPath),
    );
  } on FlutterError {
    return const [];
  }
});
