import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

// Every translation `lib/l10n/app_<locale>.arb` must stay a subset of the
// English template: no stale keys, and the same placeholder names, since a
// mismatched placeholder is the one translation error that breaks at runtime.

Map<String, Object?> _read(File file) =>
    jsonDecode(file.readAsStringSync()) as Map<String, Object?>;

Iterable<String> _messageKeys(Map<String, Object?> arb) =>
    arb.keys.where((k) => !k.startsWith('@'));

Set<String> _declaredPlaceholders(Map<String, Object?> arb, String key) {
  final meta = arb['@$key'];
  if (meta is! Map) return {};
  final placeholders = meta['placeholders'];
  return placeholders is Map
      ? placeholders.keys.map((k) => k.toString()).toSet()
      : {};
}

/// The placeholder names an ICU [message] refers to: `{name}` and the
/// argument of `{name, plural, ...}`; branch labels (`one{...}`) are not
/// preceded by a brace-and-name pair and so are not matched.
Set<String> _referenced(String message) => {
  for (final match in RegExp(r'\{\s*(\w+)\s*[,}]').allMatches(message))
    match.group(1)!,
};

void main() {
  final dir = Directory('lib/l10n');
  final english = _read(File(p.join(dir.path, 'app_en.arb')));
  final englishKeys = _messageKeys(english).toSet();
  final translations = [
    for (final file in dir.listSync().whereType<File>())
      if (RegExp(r'app_[\w-]+\.arb$').hasMatch(file.path) &&
          p.basename(file.path) != 'app_en.arb')
        file,
  ];

  test('the English template has messages', () {
    expect(englishKeys, isNotEmpty);
  });

  for (final file in translations) {
    final name = p.basename(file.path);
    final arb = _read(file);

    group(name, () {
      test('declares a matching @@locale', () {
        final expected = RegExp(r'app_(.+)\.arb').firstMatch(name)!.group(1);
        expect(arb['@@locale'], expected);
      });

      test('has no keys the English template lacks', () {
        expect(_messageKeys(arb).toSet().difference(englishKeys), isEmpty);
      });

      test('uses the same placeholders as English', () {
        final mismatches = <String>[];
        for (final key in _messageKeys(arb)) {
          if (!englishKeys.contains(key)) continue;
          final expected = _declaredPlaceholders(english, key);
          final declared = _declaredPlaceholders(arb, key);
          if (declared.isNotEmpty && !setEquals(declared, expected)) {
            mismatches.add('$key declares $declared, English has $expected');
          }
          final message = arb[key];
          if (message is String) {
            final used = _referenced(message);
            if (used.difference(expected).isNotEmpty ||
                expected.difference(used).isNotEmpty) {
              mismatches.add('$key uses $used, English has $expected');
            }
          }
        }
        expect(mismatches, isEmpty);
      });

      test('lists messages left identical to English (warning only)', () {
        final identical = [
          for (final key in _messageKeys(arb))
            if (arb[key] == english[key]) key,
        ];
        if (identical.isNotEmpty) {
          // Short words and names can legitimately match, so this never fails.
          // ignore: avoid_print
          print(
            '$name: ${identical.length} message(s) identical to English: '
            '${identical.join(', ')}',
          );
        }
      });
    });
  }
}
