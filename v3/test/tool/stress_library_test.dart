// Tests of `tool/stress_library.dart` on the three-template source of
// `stress_source_fixture.dart`, built in the system temp folder.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/domain/enums/asset_type.dart';
import 'package:tts_mod_vault/domain/parsing/url_extraction.dart';
import 'package:tts_mod_vault/domain/rules/file_key.dart';

import '../../tool/stress_library.dart';
import 'stress_source_fixture.dart';

void main() {
  late Directory temp;
  late String source;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('ttsmv_stress_');
    source = writeStressSource(temp);
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test('rewriteUrlForCopy appends a per-copy query parameter', () {
    expect(rewriteUrlForCopy('https://a/b', 3), 'https://a/b?c3');
    expect(rewriteUrlForCopy('https://a/b?x=1', 3), 'https://a/b?x=1&c3');
    expect(
      fileKeyFromUrl(rewriteUrlForCopy('https://a/b', 3)),
      isNot(fileKeyFromUrl(rewriteUrlForCopy('https://a/b', 4))),
    );
  });

  test('rewriteModText rewrites every scheme URL the extractor finds', () {
    final text = File(p.join(source, 'Workshop', '111.json'))
        .readAsStringSync();
    final result = rewriteModText(text, 7);
    final urls = extractAssetUrlsTyped(result.text).map((a) => a.url).toSet();
    expect(urls, {
      'https://steamusercontent-a.akamaihd.net/ugc/1/A/?c7',
      'https://steamusercontent-a.akamaihd.net/ugc/2/B/?c7',
      'https://x.example/en.png?c7',
      'https://x.example/fr.png?c7',
      'https://docs.example/a.pdf?x=1&c7',
    });
    expect(result.rewritten.map((a) => a.url).toSet(), urls);
    expect(result.notRewritten, 0);
    // Non-URL text is untouched.
    expect(result.text, contains('"SaveName":"Alpha"'));
  });

  test('scheme-less values are left alone and counted', () {
    final text = File(p.join(source, 'Workshop', '333.json'))
        .readAsStringSync();
    final result = rewriteModText(text, 1);
    expect(result.notRewritten, 1);
    expect(result.text, contains('"www.noscheme.example/img.png"'));
    expect(result.text, contains('https://img.example/back.jpg?c1'));
  });

  test('generates N mods with unique keys, placeholders and Saves', () async {
    final out = p.join(temp.path, 'out');
    final lines = <String>[];
    final summary = await generateStressLibrary(
      sourceModsDir: source,
      outDir: out,
      mods: 7,
      presentFraction: 0.5,
      forbiddenRoots: [p.join(temp.path, 'Documents')],
      log: lines.add,
    );

    expect(summary.templates, 3, reason: 'the index file is not a template');
    expect(summary.mods, 7);
    // Copies 0..6 over templates 111, 333, Sub/222 (sorted by path):
    // 111 x3 (5 URLs each), 333 x2 (1 scheme URL each), 222 x2 (3 each).
    expect(summary.urls, 3 * 5 + 2 * 1 + 2 * 3);
    expect(summary.urlsNotRewritten, 2);
    // round(5 * .5) = 3 per 111 copy, round(1 * .5) = 1, round(3 * .5) = 2.
    expect(summary.placeholderFiles, 3 * 3 + 2 * 1 + 2 * 2);
    expect(summary.bytesWritten, greaterThan(summary.placeholderFiles * 1024));
    expect(lines, isNotEmpty);

    final workshop = Directory(p.join(out, 'Mods', 'Workshop'));
    final jsons =
        workshop
            .listSync()
            .whereType<File>()
            .map((f) => p.basename(f.path))
            .toList()
          ..sort();
    expect(jsons, [for (var i = 0; i < 7; i++) '${firstGeneratedId + i}.json']);

    // Every rewritten key is unique across the whole library.
    final keys = <String>[];
    for (final file in workshop.listSync().whereType<File>()) {
      final assets = extractAssetUrlsTyped(file.readAsStringSync());
      for (final asset in assets) {
        if (asset.url.contains('c${jsons.indexOf(p.basename(file.path))}')) {
          keys.add(fileKeyFromUrl(asset.url));
        }
      }
    }
    expect(keys.toSet().length, keys.length);
    expect(keys.length, summary.urls);

    // Placeholders are 1 KB, in the type's folder, with the default
    // extension, and named for a rewritten URL of some copy.
    var placeholders = 0;
    for (final type in AssetType.values) {
      final dir = Directory(p.join(out, 'Mods', type.folderName));
      expect(dir.existsSync(), isTrue, reason: type.folderName);
      for (final file in dir.listSync().whereType<File>()) {
        placeholders++;
        expect(file.lengthSync(), placeholderBytes);
        expect(
          keys,
          contains(fileKeyFromFileName(p.basenameWithoutExtension(file.path))),
        );
      }
    }
    expect(placeholders, summary.placeholderFiles);
    expect(
      File(p.join(out, 'Mods', 'PDF')).parent
          .listSync()
          .whereType<Directory>()
          .map((d) => p.basename(d.path)),
      containsAll(['Images Raw', 'Models Raw']),
    );
    expect(
      Directory(p.join(out, 'Saves', 'Saved Objects')).existsSync(),
      isTrue,
    );
    expect(Directory(p.join(out, 'Saves')).listSync().length, 1);

    // The source was only read.
    expect(
      Directory(p.join(source, 'Workshop')).listSync(recursive: true).length,
      5,
    );
  });

  test('refuses an output folder inside Documents or the source', () async {
    final documents = p.join(temp.path, 'Documents');
    expect(
      () => generateStressLibrary(
        sourceModsDir: source,
        outDir: p.join(documents, 'My Games', 'stress'),
        mods: 1,
        presentFraction: 0.5,
        forbiddenRoots: [documents],
      ),
      throwsArgumentError,
    );
    expect(
      () => generateStressLibrary(
        sourceModsDir: source,
        outDir: p.join(source, 'stress'),
        mods: 1,
        presentFraction: 0.5,
        forbiddenRoots: const [],
      ),
      throwsArgumentError,
    );
    expect(Directory(p.join(documents)).existsSync(), isFalse);
  });

  test('the default forbidden roots are the Documents folders', () {
    final roots = defaultForbiddenRoots();
    expect(roots, isNotEmpty);
    expect(roots.every((r) => p.basename(r) == 'Documents'), isTrue);
  });
}
