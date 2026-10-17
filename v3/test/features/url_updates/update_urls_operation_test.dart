// Integration tests of the URL prefix update against a temporary library on
// disk (the rewrite runs on a worker isolate) with an in-memory store.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/app/providers/app_log_provider.dart';
import 'package:tts_mod_vault/app/providers/infrastructure_providers.dart';
import 'package:tts_mod_vault/core/logging/app_log.dart';
import 'package:tts_mod_vault/domain/constants.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/domain/rules/file_key.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';
import 'package:tts_mod_vault/features/operations/application/operation_runner.dart';
import 'package:tts_mod_vault/features/url_updates/application/url_updates_service.dart';

import '../library/library_test_harness.dart';

const _old = 'http://old.example.com/';
const _new = 'https://new.example.com/';
const _a = '${_old}a.png';
const _b = '${_old}b.png';
const _other = 'https://other.example.com/c.png';
const _legacy = '${oldCloudUrl}ugc/1/x.png';

/// | file              | name  | assets                               |
/// | Workshop/111.json | Alpha | a (old host, cached), b (old host)   |
/// | Workshop/333.json | Gamma | c (other host, cached)               |
/// | Workshop/555.json | Delta | x (legacy Steam Cloud host, cached   |
/// |                   |       |    under the Akamai name)            |
final class _Fixture {
  _Fixture(this.library) {
    alpha = library.writeJson(
      p.join('Mods', 'Workshop', '111.json'),
      saveName: 'Alpha',
      epochTime: epoch2023,
      assets: [('ImageURL', _a), ('FaceURL', _b)],
    );
    gamma = library.writeJson(
      p.join('Mods', 'Workshop', '333.json'),
      saveName: 'Gamma',
      epochTime: epoch2023,
      assets: [('ImageURL', _other)],
    );
    delta = library.writeJson(
      p.join('Mods', 'Workshop', '555.json'),
      saveName: 'Delta',
      epochTime: epoch2023,
      assets: [('ImageURL', _legacy)],
    );
    aFile = library.writeAsset(AssetType.image, _a);
    cFile = library.writeAsset(AssetType.image, _other);
    xFile = library.writeAsset(AssetType.image, normalizeSteamUrl(_legacy));
  }

  final TempLibrary library;
  late final String alpha;
  late final String gamma;
  late final String delta;
  late final String aFile;
  late final String cFile;
  late final String xFile;
}

void main() {
  late TempLibrary library;
  late _Fixture fixture;
  late ProviderContainer container;
  late UrlUpdatesService service;

  setUp(() async {
    library = TempLibrary.create();
    fixture = _Fixture(library);
    container = makeLibraryContainer(library);
    service = container.read(urlUpdatesServiceProvider);
    await refreshLibrary(container);
  });

  tearDown(() => library.delete());

  Mod modAt(String path) =>
      container.read(libraryControllerProvider).value!.modByPath(path)!;
  Future<String?> indexed(String url) => container
      .read(appDatabaseProvider)
      .existingFilesDao
      .pathFor(AssetType.image, fileKeyFromUrl(url));
  List<OperationProgress> recordProgress() {
    final snapshots = <OperationProgress>[];
    container.listen(operationRunnerProvider, (_, next) {
      if (next.progress case final progress?) snapshots.add(progress);
    });
    return snapshots;
  }

  Iterable<LogEntry> logAt(LogLevel level) => container
      .read(appLogProvider)
      .store
      .entries
      .where((e) => e.level == level);

  test(
    'rewrites matching URLs, renames the cached file and re-indexes',
    () async {
      expect(modAt(fixture.alpha).summary.present, 1);
      final progress = recordProgress();

      final result = await service.updateUrls(
        [modAt(fixture.alpha), modAt(fixture.gamma)],
        oldPrefixes: [_old],
        newPrefix: _new,
        renameFiles: true,
      );

      expect(result.modsProcessed, 2);
      expect(result.modsUpdated, 1);
      expect(result.filesRenamed, 1);
      expect(result.failed, isEmpty);
      expect(result.cancelled, isFalse);

      final text = File(fixture.alpha).readAsStringSync();
      expect(text, contains('${_new}a.png'));
      expect(text, contains('${_new}b.png'));
      expect(text, isNot(contains(_old)));
      expect(File(fixture.gamma).readAsStringSync(), contains(_other));

      final renamed = p.join(
        library.directories.assetDir(AssetType.image),
        '${fileNameFromUrl('${_new}a.png')}.png',
      );
      expect(File(fixture.aFile).existsSync(), isFalse);
      expect(File(renamed).existsSync(), isTrue);
      expect(await indexed('${_new}a.png'), p.normalize(renamed));
      expect(await indexed(_a), isNull);

      final alpha = modAt(fixture.alpha);
      expect(alpha.summary.present, 1, reason: 'the renamed file still counts');
      expect(alpha.summary.total, 2);
      final assets = await container
          .read(appDatabaseProvider)
          .libraryQueries
          .assetsForMod(fixture.alpha);
      expect(assets.map((a) => a.url), ['${_new}a.png', '${_new}b.png']);
      expect(progress.map((s) => s.label).toSet(), {updateUrlsProgressLabel});
      expect(progress.first.detail, 'Alpha');
      expect(progress.last.done, 2);
      expect(progress.last.total, 2);
      expect(container.read(operationRunnerProvider).isRunning, isFalse);
      expect(
        logAt(LogLevel.success).map((e) => e.message),
        containsAll([
          'Updated URLs in "Alpha": 2 URL(s) changed',
          'Updated URLs in 1 of 2 mod(s), renamed 1 file(s)',
        ]),
      );
    },
  );

  test('without renameFiles the cached file keeps its old name and the '
      'asset counts as missing', () async {
    final result = await service.updateUrls(
      [modAt(fixture.alpha)],
      oldPrefixes: [_old],
      newPrefix: _new,
    );

    expect(result.modsUpdated, 1);
    expect(result.filesRenamed, 0);
    expect(File(fixture.aFile).existsSync(), isTrue);
    expect(modAt(fixture.alpha).summary.present, 0);
    expect(modAt(fixture.alpha).summary.total, 2);
  });

  test(
    'a mod without matching URLs is left alone and logged as such',
    () async {
      final before = File(fixture.gamma).readAsStringSync();

      final result = await service.updateUrls(
        [modAt(fixture.gamma)],
        oldPrefixes: [_old],
        newPrefix: _new,
        renameFiles: true,
      );

      expect(result.modsUpdated, 0);
      expect(File(fixture.gamma).readAsStringSync(), before);
      expect(File(fixture.cFile).existsSync(), isTrue);
      expect(
        logAt(LogLevel.info).map((e) => e.message),
        contains('No URLs to update in "Gamma"'),
      );
    },
  );

  test('legacy Steam Cloud host to Akamai rewrites the file globally and '
      'keeps the cached file', () async {
    expect(modAt(fixture.delta).summary.present, 1);

    final result = await service.updateUrls(
      [modAt(fixture.delta)],
      oldPrefixes: service.parseOldPrefixes(oldCloudUrl),
      newPrefix: newSteamUserContentUrl,
      renameFiles: true,
    );

    expect(result.modsUpdated, 1);
    expect(result.filesRenamed, 0);
    final text = File(fixture.delta).readAsStringSync();
    expect(text, contains(normalizeSteamUrl(_legacy)));
    expect(text, isNot(contains(oldCloudUrl)));
    expect(File(fixture.xFile).existsSync(), isTrue);
    expect(modAt(fixture.delta).summary.present, 1);
  });

  test('a mod whose file vanished is reported in failed and the run goes '
      'on', () async {
    final alpha = modAt(fixture.alpha);
    File(fixture.alpha).deleteSync();

    final result = await service.updateUrls(
      [alpha, modAt(fixture.gamma)],
      oldPrefixes: [_old],
      newPrefix: _new,
    );

    expect(result.modsProcessed, 2);
    expect(result.failed.length, 1);
    expect(result.failed.single.$1, fixture.alpha);
    expect(
      logAt(LogLevel.error).map((e) => e.message),
      contains('Could not update URLs in "Alpha"'),
    );
    expect(
      logAt(LogLevel.warning).map((e) => e.message),
      contains(startsWith('Updated URLs in 0 of 2 mod(s), 1 failed')),
    );
  });

  test('empty prefixes do nothing', () async {
    final before = File(fixture.alpha).readAsStringSync();

    final result = await service.updateUrls(
      [modAt(fixture.alpha)],
      oldPrefixes: service.parseOldPrefixes(' | '),
      newPrefix: _new,
    );

    expect(result.modsProcessed, 0);
    expect(File(fixture.alpha).readAsStringSync(), before);
    expect(
      logAt(LogLevel.warning).map((e) => e.message),
      contains('URL update skipped: old or new prefix is empty'),
    );
  });

  test('a rename whose target is taken is logged and the URL still '
      'changes', () async {
    final taken = p.join(
      library.directories.assetDir(AssetType.image),
      '${fileNameFromUrl('${_new}a.png')}.png',
    );
    File(taken).writeAsBytesSync(const [9]);

    final result = await service.updateUrls(
      [modAt(fixture.alpha)],
      oldPrefixes: [_old],
      newPrefix: _new,
      renameFiles: true,
    );

    expect(result.modsUpdated, 1);
    expect(result.filesRenamed, 0);
    expect(File(fixture.aFile).existsSync(), isTrue);
    expect(File(fixture.alpha).readAsStringSync(), contains('${_new}a.png'));
    expect(
      logAt(LogLevel.warning).map((e) => e.message),
      contains(startsWith('Cached file ')),
    );
  });
}
