// Integration tests of backup creation, `.ttsmod` / JSON import and the
// backup edits against a temporary library on disk (zip streams and the
// controller's worker tasks need real files) with an in-memory store.

import 'dart:io';

import 'package:archive/archive.dart' show ZipDecoder;
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/app/providers/app_log_provider.dart';
import 'package:tts_mod_vault/app/providers/infrastructure_providers.dart';
import 'package:tts_mod_vault/core/logging/app_log.dart';
import 'package:tts_mod_vault/core/result/result.dart';
import 'package:tts_mod_vault/data/db/app_database.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/domain/rules/file_key.dart';
import 'package:tts_mod_vault/features/backups/application/backup_service.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';
import 'package:tts_mod_vault/features/library/application/library_settings.dart';
import 'package:tts_mod_vault/features/operations/application/operation_runner.dart';

import '../../../data/fs/zip/zip_fixtures.dart';
import '../../library/library_test_harness.dart';

const _imageA = 'https://example.com/a.png';
const _model = 'https://example.com/m.obj';
const _audio = 'https://example.com/s.mp3';
const _newImage = 'https://example.com/new-image.png';

/// The library every test starts from:
///
/// | file                       | name    | assets                           |
/// | Workshop/111.json (+png)   | Alpha   | image a (present), model, audio  |
/// | Workshop/333.json          | Gamma   | image a (present)                |
/// | Saves/TS_Save_1.json (+png)| My Save | image a (present)                |
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
    imageAFile = library.writeAsset(AssetType.image, _imageA);
    audioFile = library.writeAsset(AssetType.audio, _audio, extension: '.mp3');
  }

  final TempLibrary library;
  late final String alpha;
  late final String alphaImage;
  late final String gamma;
  late final String save;
  late final String saveImage;
  late final String imageAFile;
  late final String audioFile;
}

final _imageAEntry = 'Mods/Images/${fileNameFromUrl(_imageA)}.png';
final _newImageEntry = 'Mods/Images/${fileNameFromUrl(_newImage)}.png';

void main() {
  late TempLibrary library;
  late _Fixture fixture;
  late ProviderContainer container;
  late BackupService service;

  setUp(() {
    library = TempLibrary.create();
    fixture = _Fixture(library);
    container = makeLibraryContainer(library);
    service = container.read(backupServiceProvider);
  });

  tearDown(() => library.delete());

  LibraryState state() => container.read(libraryControllerProvider).value!;
  Mod modAt(String path) => state().modByPath(path)!;
  Set<String> entriesOf(String zipPath) => {
    for (final file in ZipDecoder().decodeBytes(
      File(zipPath).readAsBytesSync(),
    ))
      if (file.isFile) file.name,
  };
  List<OperationProgress> recordProgress() {
    final snapshots = <OperationProgress>[];
    container.listen(operationRunnerProvider, (_, next) {
      final progress = next.progress;
      if (progress != null) snapshots.add(progress);
    });
    return snapshots;
  }

  Future<List<BackupRow>> backupRows() => container
      .read(appDatabaseProvider)
      .select(container.read(appDatabaseProvider).backups)
      .get();
  Iterable<LogEntry> logAt(LogLevel level) => container
      .read(appLogProvider)
      .store
      .entries
      .where((e) => e.level == level);

  /// Writes a `.ttsmod` outside the library (like a file the user picked).
  String writeArchive(
    String name,
    Map<String, List<int>> files, {
    List<String> backslashNames = const [],
  }) {
    final zip = buildZip(files);
    final path = p.join(library.root.path, 'incoming', name);
    File(path)
      ..createSync(recursive: true)
      ..writeAsBytesSync(
        backslashNames.isEmpty ? zip : withBackslashNames(zip, backslashNames),
      );
    return path;
  }

  Map<String, List<int>> newModFiles({int epochTime = epoch2023}) => {
    'Mods/Workshop/555.json': modJson(
      saveName: 'Delta',
      epochTime: epochTime,
      assets: [('ImageURL', _newImage)],
    ).codeUnits,
    'Mods/Workshop/555.png': const [0x89, 0x50, 0x4E, 0x47],
    _newImageEntry: const [5, 5, 5],
  };

  Future<JsonConflictChoice> noConflict(JsonImportConflict conflict) async =>
      fail('unexpected conflict for ${conflict.jsonFileName}');

  group('createBackup', () {
    test('zips a mod with v2 entry names and marks it up to date', () async {
      await refreshLibrary(container);
      final alpha = modAt(fixture.alpha);
      expect(alpha.backupStatus, BackupStatus.none);
      final progress = recordProgress();

      final result = await service.createBackup(
        alpha,
        targetDir: library.backupsDir,
      );

      final backup = result.backup;
      expect(backup.fileName, 'Alpha (111).ttsmod');
      expect(backup.path, p.join(library.backupsDir, 'Alpha (111).ttsmod'));
      expect(backup.folder, 'Backups');
      expect(backup.matchingModPath, fixture.alpha);
      expect(backup.assetCount, 1);
      expect(result.assetCount, 1);
      expect(result.skipped, 0);
      // Audio is hidden by the default option, the model is not on disk.
      expect(entriesOf(backup.path), {
        'Mods/Workshop/111.json',
        'Mods/Workshop/111.png',
        _imageAEntry,
      });
      expect(File('${backup.path}.part').existsSync(), isFalse);
      expect(backup.sizeBytes, File(backup.path).lengthSync());

      final rows = await backupRows();
      expect(rows.single.path, backup.path);
      expect(rows.single.assetCount, 1);
      expect(state().backups.map((b) => b.path), [backup.path]);
      final refreshed = modAt(fixture.alpha);
      expect(refreshed.backup?.path, backup.path);
      expect(refreshed.backupStatus, BackupStatus.upToDate);
      expect(progress.map((s) => s.label).toSet(), {backupWritingLabel});
      expect(progress.last.done, 3);
      expect(progress.last.total, 3);
      expect(container.read(operationRunnerProvider).isRunning, isFalse);
      expect(
        logAt(LogLevel.success).map((e) => e.message),
        contains(startsWith('Backed up "Alpha": 1 asset files')),
      );
    });

    test('includes audio when the mod shows it', () async {
      await refreshLibrary(container);
      await container
          .read(libraryOptionsProvider.notifier)
          .setIgnoreAudioGlobally(false);

      final result = await service.createBackup(
        modAt(fixture.alpha),
        targetDir: library.backupsDir,
      );

      expect(result.assetCount, 2);
      expect(
        entriesOf(result.backup.path),
        contains('Mods/Audio/${fileNameFromUrl(_audio)}.mp3'),
      );
    });

    test('a save is stored under Saves/ with its id in the name', () async {
      await refreshLibrary(container);

      final result = await service.createBackup(
        modAt(fixture.save),
        targetDir: p.join(library.backupsDir, 'Saves'),
      );

      expect(result.backup.fileName, 'My Save (TS_Save_1).ttsmod');
      expect(result.backup.folder, 'Saves');
      expect(entriesOf(result.backup.path), {
        'Saves/TS_Save_1.json',
        'Saves/TS_Save_1.png',
        _imageAEntry,
      });
      expect(modAt(fixture.save).backupStatus, BackupStatus.upToDate);
    });

    test('backing up again replaces the archive and the state entry', () async {
      await refreshLibrary(container);
      final first = await service.createBackup(
        modAt(fixture.alpha),
        targetDir: library.backupsDir,
      );
      File(fixture.imageAFile).deleteSync();
      await container.read(libraryControllerProvider.notifier).refresh();

      final second = await service.createBackup(
        modAt(fixture.alpha),
        targetDir: library.backupsDir,
      );

      expect(second.backup.path, first.backup.path);
      expect(second.assetCount, 0);
      expect(state().backups.length, 1);
      expect(state().backups.single.assetCount, 0);
      expect((await backupRows()).single.assetCount, 0);
      expect(modAt(fixture.alpha).backupStatus, BackupStatus.upToDate);
    });

    test('a backups folder that does not exist yet is created', () async {
      await refreshLibrary(container);
      final target = p.join(library.backupsDir, 'New', 'Deeper');

      final result = await service.createBackup(
        modAt(fixture.gamma),
        targetDir: target,
      );

      expect(File(result.backup.path).existsSync(), isTrue);
      expect(result.backup.folder, 'Deeper');
    });
  });

  group('backupTargetFor', () {
    test('defaults to the backups folder and reports collisions', () async {
      await refreshLibrary(container);
      final alpha = modAt(fixture.alpha);

      final fresh = await service.backupTargetFor(alpha);
      expect(fresh.dir, library.backupsDir);
      expect(fresh.fileName, 'Alpha (111).ttsmod');
      expect(fresh.replacesExisting, isFalse);
      expect(fresh.currentBackupElsewhere, isFalse);

      final other = p.join(library.backupsDir, 'Other');
      await service.createBackup(alpha, targetDir: other);
      final withBackup = modAt(fixture.alpha);

      final same = await service.backupTargetFor(withBackup);
      expect(same.dir, other);
      expect(same.replacesExisting, isTrue);
      expect(same.currentBackupElsewhere, isFalse);

      final elsewhere = await service.backupTargetFor(
        withBackup,
        chosenDir: library.backupsDir,
      );
      expect(elsewhere.dir, library.backupsDir);
      expect(elsewhere.replacesExisting, isFalse);
      expect(elsewhere.currentBackupElsewhere, isTrue);
      expect(elsewhere.currentBackup?.path, withBackup.backup?.path);
    });
  });

  group('importBackups', () {
    test('a new mod appears with its assets present', () async {
      await refreshLibrary(container);
      final archive = writeArchive('Delta (555).ttsmod', newModFiles());
      final progress = recordProgress();

      final result = await service.importBackups([
        archive,
      ], onJsonConflict: noConflict);

      expect(result.imported, 1);
      expect(result.cancelled, isFalse);
      final imported = result.results.single.result!;
      final jsonPath = p.join(library.workshopDir, '555.json');
      expect(imported.jsonPath, jsonPath);
      expect(imported.assetsExtracted, 1);
      expect(imported.jsonSkipped, isFalse);
      expect(File(jsonPath).existsSync(), isTrue);
      expect(File(p.join(library.workshopDir, '555.png')).existsSync(), isTrue);
      final assetPath = p.join(
        library.directories.assetDir(AssetType.image),
        '${fileNameFromUrl(_newImage)}.png',
      );
      expect(File(assetPath).readAsBytesSync(), [5, 5, 5]);
      expect(
        await container
            .read(appDatabaseProvider)
            .existingFilesDao
            .pathFor(AssetType.image, fileKeyFromUrl(_newImage)),
        assetPath,
      );
      final delta = modAt(jsonPath);
      expect(delta.saveName, 'Delta');
      expect(delta.imagePath, p.join(library.workshopDir, '555.png'));
      expect(delta.summary.total, 1);
      expect(delta.summary.present, 1);
      expect(progress.map((s) => s.label).toSet(), {importFileLabel});
      expect(progress.last.total, 1);
      expect(
        logAt(LogLevel.success).map((e) => e.message),
        contains('Imported Delta (555).ttsmod: 1 asset files'),
      );
    });

    test('restores into the folder the mod currently lives in', () async {
      // Alpha was moved into a sub-folder after the backup was made.
      File(fixture.alpha).deleteSync();
      File(fixture.alphaImage).deleteSync();
      final moved = library.writeJson(
        p.join('Mods', 'Workshop', 'Sub', '111.json'),
        saveName: 'Alpha',
        epochTime: epoch2023,
        assets: [('ImageURL', _imageA)],
      );
      await refreshLibrary(container);
      final archive = writeArchive('Alpha (111).ttsmod', {
        'Mods/Workshop/111.json': File(moved).readAsBytesSync(),
        'Mods/Workshop/111.png': const [1, 1],
        _imageAEntry: const [2, 2],
      });

      final result = await service.importBackups([
        archive,
      ], onJsonConflict: noConflict);

      expect(result.results.single.result!.jsonPath, moved);
      expect(File(fixture.alpha).existsSync(), isFalse);
      expect(
        File(p.join(library.workshopDir, 'Sub', '111.png')).existsSync(),
        isTrue,
      );
      expect(
        modAt(moved).imagePath,
        p.join(library.workshopDir, 'Sub', '111.png'),
      );
      expect(state().mods.where((m) => m.id == '111').length, 1);
    });

    test('an explicit target folder wins', () async {
      await refreshLibrary(container);
      final archive = writeArchive('Delta (555).ttsmod', newModFiles());
      final target = p.join(library.workshopDir, 'Picked');

      await service.importBackups(
        [archive],
        targetJsonDir: target,
        onJsonConflict: noConflict,
      );

      expect(File(p.join(target, '555.json')).existsSync(), isTrue);
      expect(File(p.join(target, '555.png')).existsSync(), isTrue);
      expect(modAt(p.join(target, '555.json')).folder, 'Picked');
    });

    group('date conflict', () {
      late String archive;
      final conflicts = <JsonImportConflict>[];

      setUp(() async {
        conflicts.clear();
        await refreshLibrary(container);
        archive = writeArchive('Alpha (111).ttsmod', {
          'Mods/Workshop/111.json': modJson(
            saveName: 'Alpha from backup',
            epochTime: epoch2020,
            assets: [('ImageURL', _newImage)],
          ).codeUnits,
          _newImageEntry: const [5, 5, 5],
        });
      });

      JsonConflictResolver choose(JsonConflictChoice choice) =>
          (conflict) async {
            conflicts.add(conflict);
            return choice;
          };

      void expectConflictDescribed() {
        final conflict = conflicts.single;
        expect(conflict.jsonFileName, '111.json');
        expect(conflict.localEpoch, epoch2023);
        expect(conflict.backupEpoch, epoch2020);
        expect(conflict.existingAssetCount, 1);
        expect(conflict.backupAssetCount, 1);
        expect(conflict.targetPath, fixture.alpha);
      }

      test('keepCurrent keeps the JSON and restores the assets', () async {
        final before = File(fixture.alpha).readAsStringSync();

        final result = await service.importBackups([
          archive,
        ], onJsonConflict: choose(JsonConflictChoice.keepCurrent));

        expectConflictDescribed();
        final imported = result.results.single.result!;
        expect(imported.jsonSkipped, isTrue);
        expect(imported.jsonPath, fixture.alpha);
        expect(imported.assetsExtracted, 1);
        expect(File(fixture.alpha).readAsStringSync(), before);
        expect(modAt(fixture.alpha).saveName, 'Alpha');
        expect(modAt(fixture.alpha).epochTime, epoch2023);
        expect(
          File(
            p.join(
              library.directories.assetDir(AssetType.image),
              '${fileNameFromUrl(_newImage)}.png',
            ),
          ).existsSync(),
          isTrue,
        );
      });

      test('useBackup overwrites the JSON', () async {
        final result = await service.importBackups([
          archive,
        ], onJsonConflict: choose(JsonConflictChoice.useBackup));

        expectConflictDescribed();
        expect(result.results.single.result!.jsonSkipped, isFalse);
        final alpha = modAt(fixture.alpha);
        expect(alpha.saveName, 'Alpha from backup');
        expect(alpha.epochTime, epoch2020);
        expect(alpha.summary.total, 1);
        expect(alpha.summary.present, 1);
      });

      test('cancel writes nothing', () async {
        final before = File(fixture.alpha).readAsStringSync();

        final result = await service.importBackups([
          archive,
        ], onJsonConflict: choose(JsonConflictChoice.cancel));

        expectConflictDescribed();
        expect(result.cancelled, isTrue);
        expect(result.imported, 0);
        expect(result.results.single.result!.cancelled, isTrue);
        expect(File(fixture.alpha).readAsStringSync(), before);
        expect(
          File(
            p.join(
              library.directories.assetDir(AssetType.image),
              '${fileNameFromUrl(_newImage)}.png',
            ),
          ).existsSync(),
          isFalse,
        );
        expect(container.read(operationRunnerProvider).isRunning, isFalse);
      });

      test('no conflict when the archive is newer', () async {
        final newer = writeArchive('Newer.ttsmod', {
          'Mods/Workshop/111.json': modJson(
            saveName: 'Alpha newer',
            epochTime: epoch2023 + 10,
          ).codeUnits,
        });

        await service.importBackups([newer], onJsonConflict: noConflict);

        expect(modAt(fixture.alpha).saveName, 'Alpha newer');
      });
    });

    test('TTS Mod Backup style archives with backslash names import', () async {
      await refreshLibrary(container);
      final files = newModFiles();
      final archive = writeArchive(
        'Delta.ttsmod',
        files,
        backslashNames: files.keys.toList(),
      );

      final result = await service.importBackups([
        archive,
      ], onJsonConflict: noConflict);

      expect(result.imported, 1);
      expect(result.results.single.result!.assetsExtracted, 1);
      expect(modAt(p.join(library.workshopDir, '555.json')).summary.present, 1);
    });

    test('a save archive is indexed as a save', () async {
      await refreshLibrary(container);
      final archive = writeArchive('Other Save (TS_Save_2).ttsmod', {
        'Saves/TS_Save_2.json': modJson(
          saveName: 'Other Save',
          epochTime: epoch2023,
          assets: [('ImageURL', _imageA)],
        ).codeUnits,
        _imageAEntry: const [1],
      });

      final result = await service.importBackups([
        archive,
      ], onJsonConflict: noConflict);

      final jsonPath = p.join(library.savesDir, 'TS_Save_2.json');
      expect(result.results.single.result!.jsonPath, jsonPath);
      expect(modAt(jsonPath).ref.type, ModType.save);
      expect(state().saves.length, 2);
    });

    test(
      'several archives run in one operation; a bad one is skipped',
      () async {
        await refreshLibrary(container);
        final good = writeArchive('Delta (555).ttsmod', newModFiles());
        final junk = p.join(library.root.path, 'incoming', 'junk.ttsmod');
        File(junk).writeAsBytesSync(List.filled(64, 0));
        final progress = recordProgress();

        final result = await service.importBackups([
          junk,
          good,
        ], onJsonConflict: noConflict);

        expect(result.results.length, 2);
        expect(result.results.first.error, isNotNull);
        expect(result.results.last.succeeded, isTrue);
        expect(result.imported, 1);
        expect(result.failed, 1);
        expect(progress.where((s) => s.done == 1 && s.total == 2), isNotEmpty);
        expect(
          logAt(LogLevel.error).map((e) => e.message),
          contains('Could not read backup junk.ttsmod'),
        );
      },
    );
  });

  group('importJson', () {
    test('copies the JSON and PNG and indexes the mod', () async {
      await refreshLibrary(container);
      final source = File(p.join(library.root.path, 'incoming', 'Zeta.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync(modJson(saveName: 'Zeta', epochTime: epoch2023));
      final png = File(p.join(library.root.path, 'incoming', 'pic.png'))
        ..writeAsBytesSync(const [7]);

      final result = await service.importJson(
        sourceJson: source.path,
        destinationFolder: library.workshopDir,
        type: ModType.mod,
        sourcePng: png.path,
      );

      expect(result.jsonPath, p.join(library.workshopDir, 'Zeta.json'));
      expect(result.imageCopied, isTrue);
      expect(File(p.join(library.workshopDir, 'Zeta.png')).readAsBytesSync(), [
        7,
      ]);
      final zeta = modAt(result.jsonPath);
      expect(zeta.saveName, 'Zeta');
      expect(zeta.imagePath, p.join(library.workshopDir, 'Zeta.png'));
    });

    test('a missing PNG does not fail the import', () async {
      await refreshLibrary(container);
      final source = File(p.join(library.root.path, 'incoming', 'Eta.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync(modJson(saveName: 'Eta'));

      final result = await service.importJson(
        sourceJson: source.path,
        destinationFolder: library.savesDir,
        type: ModType.save,
        sourcePng: p.join(library.root.path, 'incoming', 'nope.png'),
      );

      expect(result.imageCopied, isFalse);
      expect(modAt(result.jsonPath).ref.type, ModType.save);
      expect(logAt(LogLevel.warning), isNotEmpty);
    });
  });

  group('deleteBackup', () {
    test('removes the file, the row and the mod\'s status', () async {
      await refreshLibrary(container);
      final created = await service.createBackup(
        modAt(fixture.alpha),
        targetDir: library.backupsDir,
      );
      expect(modAt(fixture.alpha).backupStatus, BackupStatus.upToDate);

      final result = await service.deleteBackup(modAt(fixture.alpha).backup!);

      expect(result, isA<Ok<void>>());
      expect(File(created.backup.path).existsSync(), isFalse);
      expect(await backupRows(), isEmpty);
      expect(state().backups, isEmpty);
      expect(modAt(fixture.alpha).backup, isNull);
      expect(modAt(fixture.alpha).backupStatus, BackupStatus.none);
    });

    test('a vanished file is still unregistered', () async {
      await refreshLibrary(container);
      final created = await service.createBackup(
        modAt(fixture.alpha),
        targetDir: library.backupsDir,
      );
      File(created.backup.path).deleteSync();

      final result = await service.deleteBackup(created.backup);

      expect(result, isA<Ok<void>>());
      expect(state().backups, isEmpty);
      expect(logAt(LogLevel.warning), isNotEmpty);
    });
  });

  group('renameBackup', () {
    test('renames on disk, in the store and in the state', () async {
      await refreshLibrary(container);
      final created = await service.createBackup(
        modAt(fixture.alpha),
        targetDir: library.backupsDir,
      );

      final renamed = await service.renameBackup(
        modAt(fixture.alpha).backup!,
        'Archived Alpha',
      );

      final backup = (renamed as Ok<Backup>).value;
      expect(backup.fileName, 'Archived Alpha.ttsmod');
      expect(backup.path, p.join(library.backupsDir, 'Archived Alpha.ttsmod'));
      expect(File(backup.path).existsSync(), isTrue);
      expect(File(created.backup.path).existsSync(), isFalse);
      expect((await backupRows()).single.path, backup.path);
      expect(state().backups.map((b) => b.path), [backup.path]);
      // The name no longer matches the mod.
      expect(modAt(fixture.alpha).backupStatus, BackupStatus.none);
      expect(state().backups.single.matchingModPath, isNull);

      // Renaming it back re-attaches it.
      final back = await service.renameBackup(
        state().backups.single,
        'Alpha (111).ttsmod',
      );
      expect(back, isA<Ok<Backup>>());
      expect(modAt(fixture.alpha).backupStatus, BackupStatus.upToDate);
      expect(state().backups.single.matchingModPath, fixture.alpha);
    });

    test('refuses blank names and taken names', () async {
      await refreshLibrary(container);
      await service.createBackup(
        modAt(fixture.alpha),
        targetDir: library.backupsDir,
      );
      await service.createBackup(
        modAt(fixture.gamma),
        targetDir: library.backupsDir,
      );
      final alphaBackup = modAt(fixture.alpha).backup!;

      expect(await service.renameBackup(alphaBackup, '  '), isA<Err<Backup>>());
      expect(
        await service.renameBackup(alphaBackup, 'Gamma (333).ttsmod'),
        isA<Err<Backup>>(),
      );
      expect(File(alphaBackup.path).existsSync(), isTrue);
      expect(state().backups.length, 2);
    });
  });
}
