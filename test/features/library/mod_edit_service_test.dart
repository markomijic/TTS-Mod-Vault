// Integration tests of the per-mod edit operations against a temporary
// library on disk (the controller's worker tasks need real files) with an
// in-memory SQLite store.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/app/providers/app_log_provider.dart';
import 'package:tts_mod_vault/app/providers/infrastructure_providers.dart';
import 'package:tts_mod_vault/core/logging/app_log.dart';
import 'package:tts_mod_vault/core/result/result.dart';
import 'package:tts_mod_vault/domain/constants.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/domain/parsing/mod_metadata.dart';
import 'package:tts_mod_vault/domain/rules/file_key.dart';
import 'package:tts_mod_vault/features/asset_detail/application/mod_assets_provider.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';
import 'package:tts_mod_vault/features/library/application/library_settings.dart';
import 'package:tts_mod_vault/features/library/application/library_view_providers.dart';
import 'package:tts_mod_vault/features/library/application/mod_edit_service.dart';

import 'library_test_harness.dart';

const _imageA = 'https://example.com/a.png';
const _model = 'https://example.com/m.obj';
const _audio = 'https://example.com/s.mp3';
const _newImage = 'https://example.com/new-image.png';

/// The library every test starts from:
///
/// | file                      | name    | assets                              | backup                 |
/// | Workshop/111.json (+png)  | Alpha   | image a (present), model, audio     | Alpha (111).ttsmod     |
/// | Workshop/333.json         | Gamma   | image a (present)                   | none                   |
/// | Saves/TS_Save_1.json(+png)| My Save | image a (present)                   | none                   |
/// | Saves/Saved Objects/Obj   | (none)  | none; the JSON has no SaveName key  | none                   |
final class _Fixture {
  _Fixture(this.library) {
    alpha = library.writeJson(
      p.join('Mods', 'Workshop', '111.json'),
      saveName: 'Alpha',
      epochTime: epoch2023,
      assets: [
        ('ImageURL', _imageA),
        ('MeshURL', _model),
        ('CurrentAudioURL', _audio),
      ],
    );
    alphaImage = library.writeSiblingImage(alpha);
    gamma = library.writeJson(
      p.join('Mods', 'Workshop', '333.json'),
      saveName: 'Gamma',
      epochTime: epoch2023,
      assets: [('FaceURL', _imageA)],
    );
    save = library.writeJson(
      p.join('Saves', 'TS_Save_1.json'),
      saveName: 'My Save',
      epochTime: epoch2023,
      assets: [('ImageURL', _imageA)],
    );
    saveImage = library.writeSiblingImage(save);
    final objFile = File(p.join(library.savedObjectsDir, 'Obj.json'))
      ..writeAsStringSync('{"ObjectStates":[{"Nickname":"Obj"}]}');
    savedObject = p.normalize(objFile.path);

    imageAFile = library.writeAsset(AssetType.image, _imageA);
    library.writeAsset(AssetType.audio, _audio, extension: '.mp3');
    alphaBackup = library.writeBackup('Alpha (111).ttsmod');
  }

  final TempLibrary library;
  late final String alpha;
  late final String alphaImage;
  late final String gamma;
  late final String save;
  late final String saveImage;
  late final String savedObject;
  late final String imageAFile;
  late final String alphaBackup;
}

void main() {
  late TempLibrary library;
  late _Fixture fixture;
  late ProviderContainer container;
  late ModEditService service;

  setUp(() {
    library = TempLibrary.create();
    fixture = _Fixture(library);
    container = makeLibraryContainer(library);
    service = container.read(modEditServiceProvider);
  });

  tearDown(() => library.delete());

  LibraryState state() => container.read(libraryControllerProvider).value!;
  Mod modAt(String path) => state().modByPath(path)!;
  Future<Asset> assetOf(String jsonPath, String url) async {
    final assets = await container.read(modAssetsProvider(jsonPath).future);
    return assets.singleWhere((a) => a.url == url);
  }

  Iterable<LogEntry> logAt(LogLevel level) => container
      .read(appLogProvider)
      .store
      .entries
      .where((e) => e.level == level);

  group('renameMod', () {
    test('rewrites SaveName, updates store and state, no full refresh', () async {
      await refreshLibrary(container);
      final alpha = modAt(fixture.alpha);
      final before = File(fixture.alpha).readAsStringSync();

      final result = await service.renameMod(alpha, '  Alpha Two ');

      final renamed = (result as Ok<Mod>).value;
      expect(renamed.saveName, 'Alpha Two');
      expect(modAt(fixture.alpha).saveName, 'Alpha Two');
      final after = File(fixture.alpha).readAsStringSync();
      expect(extractSaveName(after), 'Alpha Two');
      // Only the value changed; the rest of the file is byte-identical.
      expect(after.replaceFirst('Alpha Two', 'Alpha'), before);
      expect(refreshFinishedLines(container), 1);
      // Counts and type are untouched.
      expect(renamed.summary, alpha.summary);
      expect(renamed.ref, alpha.ref);
      // The store agrees with the file, so the next refresh re-parses nothing.
      await refreshLibrary(container);
      expect(lastRefreshCounts(container)['parsed'], 0);
      expect(modAt(fixture.alpha).saveName, 'Alpha Two');
      expect(
        logAt(LogLevel.success).map((e) => e.message),
        contains('Renamed "Alpha" to "Alpha Two"'),
      );
    });

    test('without renameBackup the backup is detached, not touched', () async {
      await refreshLibrary(container);
      final alpha = modAt(fixture.alpha);
      expect(alpha.backup, isNotNull);

      final result = await service.renameMod(alpha, 'Alpha Two');

      final renamed = (result as Ok<Mod>).value;
      expect(renamed.backup, isNull);
      expect(renamed.backupStatus, BackupStatus.none);
      expect(File(fixture.alphaBackup).existsSync(), isTrue);
      final backup = state().backups.single;
      expect(backup.path, fixture.alphaBackup);
      expect(backup.matchingModPath, isNull);
    });

    test('renameBackup renames the archive and keeps it matched', () async {
      await refreshLibrary(container);
      final alpha = modAt(fixture.alpha);
      final newBackupPath = p.join(
        library.backupsDir,
        'Alpha Two (111).ttsmod',
      );

      final result = await service.renameMod(
        alpha,
        'Alpha Two',
        renameBackup: true,
      );

      final renamed = (result as Ok<Mod>).value;
      expect(File(newBackupPath).existsSync(), isTrue);
      expect(File(fixture.alphaBackup).existsSync(), isFalse);
      expect(renamed.backup?.path, newBackupPath);
      expect(renamed.backup?.fileName, 'Alpha Two (111).ttsmod');
      expect(renamed.backup?.folder, 'Backups');
      expect(renamed.backup?.assetCount, 1);
      expect(renamed.backup?.matchingModPath, fixture.alpha);
      expect(renamed.backupStatus, BackupStatus.upToDate);
      expect(state().backups.single.path, newBackupPath);
      final db = container.read(appDatabaseProvider);
      final rows = await db.backupsDao.fingerprints();
      expect(rows.keys, [newBackupPath]);
      expect(
        logAt(LogLevel.info).map((e) => e.message),
        contains(
          'Renamed backup "Alpha (111).ttsmod" to "Alpha Two (111).ttsmod"',
        ),
      );
      // A full refresh reuses the cached count and sees the same state.
      final refreshed = await refreshLibrary(container);
      expect(lastRefreshCounts(container)['backupsCounted'], 0);
      expect(refreshed.modByPath(fixture.alpha)!.backup?.path, newBackupPath);
    });

    test('a backup keeps the forced-id or standard form it used', () async {
      await container
          .read(libraryOptionsProvider.notifier)
          .set(const LibraryOptions(forceBackupIdInName: true));
      final forced = library.writeJson(
        p.join('Mods', 'Workshop', 'abc.json'),
        saveName: 'Custom',
        epochTime: epoch2023,
      );
      final standard = library.writeJson(
        p.join('Mods', 'Workshop', 'def.json'),
        saveName: 'Plain',
        epochTime: epoch2023,
      );
      library.writeBackup('Custom (abc).ttsmod');
      library.writeBackup('Plain.ttsmod');
      await refreshLibrary(container);
      expect(modAt(forced).backup?.fileName, 'Custom (abc).ttsmod');
      expect(modAt(standard).backup?.fileName, 'Plain.ttsmod');

      final forcedResult = await service.renameMod(
        modAt(forced),
        'Custom 2',
        renameBackup: true,
      );
      final standardResult = await service.renameMod(
        modAt(standard),
        'Plain 2',
        renameBackup: true,
      );

      expect(
        (forcedResult as Ok<Mod>).value.backup?.fileName,
        'Custom 2 (abc).ttsmod',
      );
      expect(
        (standardResult as Ok<Mod>).value.backup?.fileName,
        'Plain 2.ttsmod',
      );
      expect(
        Directory(library.backupsDir)
            .listSync()
            .whereType<File>()
            .map((f) => p.basename(f.path)),
        unorderedEquals([
          'Alpha (111).ttsmod',
          'Custom 2 (abc).ttsmod',
          'Plain 2.ttsmod',
        ]),
      );
    });

    test('an occupied backup name is a warning; the rename succeeds', () async {
      final taken = library.writeBackup(
        'Alpha Two (111).ttsmod',
        assetCount: 3,
      );
      await refreshLibrary(container);
      final alpha = modAt(fixture.alpha);

      final result = await service.renameMod(
        alpha,
        'Alpha Two',
        renameBackup: true,
      );

      final renamed = (result as Ok<Mod>).value;
      expect(renamed.saveName, 'Alpha Two');
      expect(File(fixture.alphaBackup).existsSync(), isTrue);
      expect(File(taken).existsSync(), isTrue);
      expect(
        logAt(LogLevel.warning).map((e) => e.message),
        contains(
          'Backup not renamed: a file named "Alpha Two (111).ttsmod" already '
          'exists',
        ),
      );
      // The pre-existing archive now carries the mod's new name.
      expect(renamed.backup?.path, taken);
      expect(state().backups, hasLength(2));
    });

    test('a file without SaveName (saved object) is an Err', () async {
      await container
          .read(libraryOptionsProvider.notifier)
          .set(const LibraryOptions(includeSavedObjects: true));
      await refreshLibrary(container);
      final obj = modAt(fixture.savedObject);
      final before = File(fixture.savedObject).readAsStringSync();

      final result = await service.renameMod(obj, 'Renamed');

      expect(result, isA<Err<Mod>>());
      expect(result.failureOrNull!.message, contains('no SaveName'));
      expect(File(fixture.savedObject).readAsStringSync(), before);
      expect(modAt(fixture.savedObject).saveName, obj.saveName);
      expect(logAt(LogLevel.warning), isNotEmpty);
    });

    test('a blank name is an Err', () async {
      await refreshLibrary(container);
      final result = await service.renameMod(modAt(fixture.alpha), '   ');
      expect(result, isA<Err<Mod>>());
      expect(extractSaveName(File(fixture.alpha).readAsStringSync()), 'Alpha');
    });
  });

  group('deleteMod', () {
    test('removes files, store rows, state entry and selection', () async {
      await refreshLibrary(container);
      container.read(selectionProvider.notifier).selectMany([
        fixture.alpha,
        fixture.gamma,
      ]);

      final result = await service.deleteMod(modAt(fixture.alpha));

      expect(result, isA<Ok<void>>());
      expect(File(fixture.alpha).existsSync(), isFalse);
      expect(File(fixture.alphaImage).existsSync(), isFalse);
      expect(state().modByPath(fixture.alpha), isNull);
      expect(state().mods.map((m) => m.saveName), ['Gamma']);
      expect(state().saves, hasLength(1));
      expect(container.read(selectionProvider), {fixture.gamma});
      final db = container.read(appDatabaseProvider);
      expect(
        (await db.modsDao.fingerprints()).keys,
        isNot(contains(fixture.alpha)),
      );
      // The backup stays on disk and no longer has a mod.
      expect(File(fixture.alphaBackup).existsSync(), isTrue);
      expect(state().backups.single.matchingModPath, isNull);
      expect(refreshFinishedLines(container), 1);
      expect(
        logAt(LogLevel.success).map((e) => e.message),
        contains('Deleted "Alpha"'),
      );
      // Nothing left for the next refresh to remove.
      await refreshLibrary(container);
      expect(lastRefreshCounts(container)['removed'], 0);
    });

    test('a mod without an image deletes only the JSON', () async {
      await refreshLibrary(container);
      final result = await service.deleteMod(modAt(fixture.gamma));
      expect(result, isA<Ok<void>>());
      expect(File(fixture.gamma).existsSync(), isFalse);
      expect(File(fixture.alpha).existsSync(), isTrue);
    });
  });

  group('saveAsMod', () {
    test('copies JSON and image, indexes and selects the new mod', () async {
      await refreshLibrary(container);
      final save = modAt(fixture.save);
      final targetPath = p.normalize(
        p.join(library.workshopDir, 'Copy Of Save.json'),
      );

      final result = await service.saveAsMod(
        save,
        targetFolder: library.workshopDir,
        fileName: 'Copy Of Save.json',
      );

      final mod = (result as Ok<Mod>).value;
      expect(mod.ref.type, ModType.mod);
      expect(mod.ref.id, 'Copy Of Save');
      expect(mod.jsonPath, targetPath);
      expect(mod.saveName, 'My Save');
      expect(mod.folder, ttsWorkshopFolder);
      expect(mod.imagePath, p.normalize(p.setExtension(targetPath, '.png')));
      expect(mod.summary.total, 1);
      expect(mod.summary.present, 1);
      expect(File(targetPath).existsSync(), isTrue);
      expect(File(mod.imagePath!).existsSync(), isTrue);
      expect(
        File(targetPath).readAsStringSync(),
        File(fixture.save).readAsStringSync(),
      );
      // Inserted in save-name order between Alpha and Gamma.
      expect(state().mods.map((m) => m.saveName), [
        'Alpha',
        'Gamma',
        'My Save',
      ]);
      expect(state().saves, hasLength(1), reason: 'the save is still a save');
      expect(container.read(selectionProvider), {targetPath});
      expect(refreshFinishedLines(container), 1);
      // The store agrees with the disk, so the next refresh has no work.
      final refreshed = await refreshLibrary(container);
      expect(lastRefreshCounts(container)['parsed'], 0);
      expect(refreshed.mods.map((m) => m.saveName), [
        'Alpha',
        'Gamma',
        'My Save',
      ]);
    });

    test('a target folder that does not exist yet is created', () async {
      await refreshLibrary(container);
      final folder = p.join(library.workshopDir, 'Converted');

      final result = await service.saveAsMod(
        modAt(fixture.save),
        targetFolder: folder,
        fileName: 'converted',
      );

      final mod = (result as Ok<Mod>).value;
      expect(mod.folder, 'Converted');
      expect(File(p.join(folder, 'converted.json')).existsSync(), isTrue);
    });

    test('an existing target is an Err and nothing is written', () async {
      await refreshLibrary(container);
      final taken = File(p.join(library.workshopDir, 'Taken.json'))
        ..writeAsStringSync('{}');

      final result = await service.saveAsMod(
        modAt(fixture.save),
        targetFolder: library.workshopDir,
        fileName: 'Taken',
      );

      expect(result, isA<Err<Mod>>());
      expect(result.failureOrNull!.message, contains('already exists'));
      expect(taken.readAsStringSync(), '{}');
      expect(state().mods, hasLength(2));
      expect(container.read(selectionProvider), isEmpty);
    });

    test('a blank name is an Err', () async {
      await refreshLibrary(container);
      final result = await service.saveAsMod(
        modAt(fixture.save),
        targetFolder: library.workshopDir,
        fileName: ' .json ',
      );
      expect(result, isA<Err<Mod>>());
      expect(
        Directory(library.workshopDir).listSync().whereType<File>(),
        hasLength(3),
        reason: 'the two mod JSONs and the image',
      );
    });
  });

  group('setAudioVisibility', () {
    test('changes the counts without re-reading the file', () async {
      await refreshLibrary(container);
      final alpha = modAt(fixture.alpha);
      expect(alpha.summary.total, 2, reason: 'audio hidden by default');
      final assets = container.listen(
        modAssetsProvider(fixture.alpha),
        (_, _) {},
      );
      addTearDown(assets.close);
      expect(
        await container.read(modAssetsProvider(fixture.alpha).future),
        hasLength(2),
      );
      // No worker may be used: a re-parse would fail without the pool.
      await container.read(workerPoolProvider).dispose();

      final shown = await service.setAudioVisibility(
        alpha,
        AudioVisibility.alwaysShow,
      );

      final shownMod = (shown as Ok<Mod>).value;
      expect(shownMod.audio, AudioVisibility.alwaysShow);
      expect(shownMod.summary.total, 3);
      expect(shownMod.summary.present, 2);
      expect(shownMod.summary.totalOf(AssetType.audio), 1);
      expect(modAt(fixture.alpha), shownMod);
      // 1 asset in the backup vs 2 present: the status follows the counts.
      expect(shownMod.backupStatus, BackupStatus.assetCountMismatch);
      expect(
        (await container.read(modAssetsProvider(fixture.alpha).future))
            .map((a) => a.url),
        contains(_audio),
      );

      final hidden = await service.setAudioVisibility(
        shownMod,
        AudioVisibility.alwaysHide,
      );
      expect((hidden as Ok<Mod>).value.summary.total, 2);
      expect(
        (await container.read(modAssetsProvider(fixture.alpha).future))
            .map((a) => a.url),
        isNot(contains(_audio)),
      );
      expect(refreshFinishedLines(container), 1);
      expect(logAt(LogLevel.error), isEmpty);
    });
  });

  group('replaceAssetUrl', () {
    test(
      'rewrites the URL; the cached file stays for the other mods',
      () async {
        await refreshLibrary(container);
        final alpha = modAt(fixture.alpha);
        final asset = await assetOf(fixture.alpha, _imageA);
        expect(asset.path, fixture.imageAFile);

        final result = await service.replaceAssetUrl(alpha, asset, _newImage);

        final updated = (result as Ok<Mod>).value;
        final text = File(fixture.alpha).readAsStringSync();
        expect(text, contains(_newImage));
        expect(text, isNot(contains(_imageA)));
        // The new URL has no cached file: image missing, model missing.
        expect(updated.summary.total, 2);
        expect(updated.summary.present, 0);
        expect(File(fixture.imageAFile).existsSync(), isTrue);
        expect(modAt(fixture.gamma).summary.present, 1);
        final assets = await container.read(
          modAssetsProvider(fixture.alpha).future,
        );
        expect(assets.map((a) => a.url), isNot(contains(_imageA)));
        final replaced = assets.singleWhere((a) => a.url == _newImage);
        expect(replaced.exists, isFalse);
        expect(replaced.fileKey, fileKeyFromUrl(_newImage));
        expect(refreshFinishedLines(container), 1);
        final entry = logAt(LogLevel.success).single;
        expect(entry.message, 'Replaced URL in "Alpha"');
        expect(entry.url, _newImage);
        expect(entry.modPath, fixture.alpha);
      },
    );

    test(
      'renameFile renames the cached file and moves the index entry',
      () async {
        await refreshLibrary(container);
        final alpha = modAt(fixture.alpha);
        final asset = await assetOf(fixture.alpha, _imageA);
        final newPath = p.normalize(
          p.join(
            library.directories.assetDir(AssetType.image),
            '${fileNameFromUrl(_newImage)}.png',
          ),
        );

        final result = await service.replaceAssetUrl(
          alpha,
          asset,
          _newImage,
          renameFile: true,
        );

        final updated = (result as Ok<Mod>).value;
        expect(File(newPath).existsSync(), isTrue);
        expect(File(fixture.imageAFile).existsSync(), isFalse);
        final db = container.read(appDatabaseProvider);
        expect(
          await db.existingFilesDao.pathFor(
            AssetType.image,
            fileKeyFromUrl(_newImage),
          ),
          newPath,
        );
        expect(
          await db.existingFilesDao.pathFor(
            AssetType.image,
            fileKeyFromUrl(_imageA),
          ),
          isNull,
        );
        expect(updated.summary.present, 1, reason: 'the renamed file is found');
        // The mods that shared the old file lost it.
        expect(modAt(fixture.gamma).summary.present, 0);
        expect(modAt(fixture.save).summary.present, 0);
        final replaced = await assetOf(fixture.alpha, _newImage);
        expect(replaced.path, newPath);
        expect(
          logAt(LogLevel.success).single.message,
          'Replaced URL in "Alpha" and renamed the cached file',
        );
      },
    );

    test('an occupied cached name is an Err before anything changes', () async {
      final taken = library.writeAsset(AssetType.image, _newImage);
      await refreshLibrary(container);
      final alpha = modAt(fixture.alpha);
      final asset = await assetOf(fixture.alpha, _imageA);
      final before = File(fixture.alpha).readAsStringSync();

      final result = await service.replaceAssetUrl(
        alpha,
        asset,
        _newImage,
        renameFile: true,
      );

      expect(result, isA<Err<Mod>>());
      expect(result.failureOrNull!.message, contains('already exists'));
      expect(File(fixture.alpha).readAsStringSync(), before);
      expect(File(fixture.imageAFile).existsSync(), isTrue);
      expect(File(taken).existsSync(), isTrue);
      expect(modAt(fixture.alpha).summary.present, 1);
    });

    test('a URL that is not in the file is an Err', () async {
      await refreshLibrary(container);
      final alpha = modAt(fixture.alpha);
      final asset = (await assetOf(
        fixture.alpha,
        _imageA,
      )).copyWith(url: 'https://example.com/not-in-file.png');
      final result = await service.replaceAssetUrl(alpha, asset, _newImage);
      expect(result, isA<Err<Mod>>());
      expect(result.failureOrNull!.message, contains('not found'));
      expect(File(fixture.alpha).readAsStringSync(), contains(_imageA));
    });

    test('the legacy Steam host form in the file is replaced too', () async {
      const legacy = '${oldCloudUrl}ugc/1/2/';
      const current = '${newSteamUserContentUrl}ugc/1/2/';
      final legacyMod = library.writeJson(
        p.join('Mods', 'Workshop', '777.json'),
        saveName: 'Legacy',
        assets: [('ImageURL', legacy)],
      );
      await refreshLibrary(container);
      final asset = await assetOf(legacyMod, current);
      expect(asset.url, current, reason: 'URLs are normalised when read');

      final result = await service.replaceAssetUrl(
        modAt(legacyMod),
        asset,
        _newImage,
      );

      expect(result, isA<Ok<Mod>>());
      final text = File(legacyMod).readAsStringSync();
      expect(text, contains(_newImage));
      expect(text, isNot(contains(legacy)));
      expect(text, isNot(contains(current)));
    });

    test('a gone cached file is skipped silently', () async {
      await refreshLibrary(container);
      final alpha = modAt(fixture.alpha);
      final asset = await assetOf(fixture.alpha, _imageA);
      File(fixture.imageAFile).deleteSync();

      final result = await service.replaceAssetUrl(
        alpha,
        asset,
        _newImage,
        renameFile: true,
      );

      expect(result, isA<Ok<Mod>>());
      expect(File(fixture.alpha).readAsStringSync(), contains(_newImage));
      expect(logAt(LogLevel.warning), isEmpty);
      expect(logAt(LogLevel.error), isEmpty);
    });
  });

  group('deleteAssetFile', () {
    test('deletes the file and re-summarises every sharing mod', () async {
      await refreshLibrary(container);
      final alpha = modAt(fixture.alpha);
      final asset = await assetOf(fixture.alpha, _imageA);
      expect(modAt(fixture.gamma).summary.present, 1);
      expect(modAt(fixture.save).summary.present, 1);

      final result = await service.deleteAssetFile(alpha, asset);

      expect(result, isA<Ok<void>>());
      expect(File(fixture.imageAFile).existsSync(), isFalse);
      final db = container.read(appDatabaseProvider);
      expect(
        await db.existingFilesDao.pathFor(AssetType.image, asset.fileKey),
        isNull,
      );
      expect(modAt(fixture.alpha).summary.present, 0);
      expect(modAt(fixture.gamma).summary.present, 0);
      expect(modAt(fixture.save).summary.present, 0);
      expect((await assetOf(fixture.alpha, _imageA)).exists, isFalse);
      expect((await assetOf(fixture.gamma, _imageA)).exists, isFalse);
      expect(refreshFinishedLines(container), 1);
      final entry = logAt(LogLevel.success).single;
      expect(entry.message, startsWith('Deleted cached file'));
      expect(entry.url, _imageA);
    });

    test('an asset without a cached file is an Err', () async {
      await refreshLibrary(container);
      final alpha = modAt(fixture.alpha);
      final asset = await assetOf(fixture.alpha, _model);
      expect(asset.path, isNull);

      final result = await service.deleteAssetFile(alpha, asset);

      expect(result, isA<Err<void>>());
      expect(logAt(LogLevel.warning), hasLength(1));
    });

    test(
      'a file that already vanished is still dropped from the index',
      () async {
        await refreshLibrary(container);
        final alpha = modAt(fixture.alpha);
        final asset = await assetOf(fixture.alpha, _imageA);
        File(fixture.imageAFile).deleteSync();

        final result = await service.deleteAssetFile(alpha, asset);

        expect(result, isA<Ok<void>>());
        expect(modAt(fixture.alpha).summary.present, 0);
        expect(
          logAt(LogLevel.warning).single.message,
          contains('was already gone'),
        );
      },
    );
  });

  group('modsSharingAsset', () {
    test('groups the other mods by type, sorted by name', () async {
      await refreshLibrary(container);
      final alpha = modAt(fixture.alpha);
      final shared = await assetOf(fixture.alpha, _imageA);
      final unshared = await assetOf(fixture.alpha, _model);

      expect(await service.modsSharingAsset(alpha, shared), {
        ModType.mod: ['Gamma'],
        ModType.save: ['My Save'],
      });
      expect((await service.modsSharingAsset(alpha, shared)).keys, [
        ModType.mod,
        ModType.save,
      ]);
      expect(await service.modsSharingAsset(alpha, unshared), isEmpty);
      // From Gamma's side Alpha shows up instead.
      final gammaAsset = await assetOf(fixture.gamma, _imageA);
      expect(await service.modsSharingAsset(modAt(fixture.gamma), gammaAsset), {
        ModType.mod: ['Alpha'],
        ModType.save: ['My Save'],
      });
    });
  });
}
