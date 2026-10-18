// Integration tests of the bulk operations against a temporary library on
// disk (real worker pool, real zip streams) with an in-memory store and a
// loopback HTTP server for the download steps.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/app/providers/app_log_provider.dart';
import 'package:tts_mod_vault/core/logging/app_log.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/domain/rules/file_key.dart';
import 'package:tts_mod_vault/features/bulk/application/bulk_operations.dart';
import 'package:tts_mod_vault/features/bulk/application/bulk_service.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';
import 'package:tts_mod_vault/features/operations/application/operation_runner.dart';
import 'package:tts_mod_vault/features/startup/application/directories_controller.dart';
import 'package:tts_mod_vault/features/workshop/application/workshop_results.dart';

import '../../data/net/test_http_server.dart';
import '../library/library_test_harness.dart';

/// | file                 | name    | assets                                   |
/// | Workshop/111.json    | Alpha   | image a (served, not cached),            |
/// |                      |         | image dead (404)                         |
/// | Workshop/333.json    | Gamma   | image b (served, cached, exclusive),     |
/// |                      |         | image c (cached, shared with the save)   |
/// | Saves/TS_Save_1.json | My Save | image c (cached)                         |
final class _Fixture {
  _Fixture(this.library, this.server) {
    a = server.url('/png/a');
    dead = server.url('/missing');
    b = server.url('/png/b');
    c = 'https://example.com/c.png';
    alpha = library.writeJson(
      p.join('Mods', 'Workshop', '111.json'),
      saveName: 'Alpha',
      epochTime: epoch2023,
      assets: [('ImageURL', a), ('FaceURL', dead)],
    );
    gamma = library.writeJson(
      p.join('Mods', 'Workshop', '333.json'),
      saveName: 'Gamma',
      epochTime: epoch2023,
      assets: [('ImageURL', b), ('FaceURL', c)],
    );
    save = library.writeJson(
      p.join('Saves', 'TS_Save_1.json'),
      saveName: 'My Save',
      epochTime: epoch2023,
      assets: [('ImageURL', c)],
    );
    bFile = library.writeAsset(AssetType.image, b);
    cFile = library.writeAsset(AssetType.image, c);
  }

  final TempLibrary library;
  final TestHttpServer server;
  late final String a;
  late final String dead;
  late final String b;
  late final String c;
  late final String alpha;
  late final String gamma;
  late final String save;
  late final String bFile;
  late final String cFile;
}

void main() {
  late TempLibrary library;
  late TestHttpServer server;
  late _Fixture fixture;
  late ProviderContainer container;
  late BulkService service;

  setUp(() async {
    library = TempLibrary.create();
    server = await TestHttpServer.start();
    fixture = _Fixture(library, server);
    container = makeLibraryContainer(library);
    service = container.read(bulkServiceProvider);
    await refreshLibrary(container);
  });

  tearDown(() async {
    await server.close();
    library.delete();
  });

  LibraryState state() => container.read(libraryControllerProvider).value!;
  Mod modAt(String path) => state().modByPath(path)!;
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
  bool cached(String url) =>
      Directory(library.directories.assetDir(AssetType.image))
          .listSync()
          .any((e) => p.basename(e.path).startsWith(fileNameFromUrl(url)));
  String newFolder(String name) {
    final dir = Directory(p.join(library.backupsDir, name))..createSync();
    return dir.path;
  }

  group('download', () {
    test(
      'downloads every mod, counts files and reports bulk.download',
      () async {
        final progress = recordProgress();

        final result = await service.downloadMods([
          modAt(fixture.alpha),
          modAt(fixture.gamma),
        ]);

        expect(result.modsProcessed, 2);
        expect(result.modsFailed, 0);
        expect(result.downloadedFiles, 1, reason: 'a; b and c are cached');
        expect(result.failedFiles, 1, reason: 'the 404');
        expect(result.cancelled, isFalse);
        expect(cached(fixture.a), isTrue);
        expect(modAt(fixture.alpha).summary.present, 1);
        expect(progress.map((s) => s.label).toSet(), {'bulk.download'});
        expect(progress.first.detail, 'Alpha');
        expect(progress.last.done, 2);
        expect(progress.last.total, 2);
        expect(progress.last.value, 1);
        expect(container.read(operationRunnerProvider).isRunning, isFalse);
        expect(
          logAt(LogLevel.success).map((e) => e.message),
          contains(
            startsWith('Bulk download finished: 1 file(s) for 2 mod(s)'),
          ),
        );
      },
    );

    test('cancelling stops after the current mod', () async {
      container.listen(operationRunnerProvider, (_, next) {
        if (next.progress?.label == 'bulk.download' && !next.cancelRequested) {
          service.cancel();
        }
      });

      final result = await service.downloadMods([
        modAt(fixture.alpha),
        modAt(fixture.gamma),
      ]);

      expect(result.cancelled, isTrue);
      expect(result.modsProcessed, lessThanOrEqualTo(1));
      expect(container.read(operationRunnerProvider).isRunning, isFalse);
      expect(
        logAt(LogLevel.warning).map((e) => e.message),
        contains(contains('(cancelled after')),
      );
    });
  });

  group('backup', () {
    test('backs up every mod into the folder', () async {
      final folder = newFolder('New');
      final progress = recordProgress();

      final result = await service.backupMods(
        [modAt(fixture.alpha), modAt(fixture.gamma)],
        folder: folder,
        behavior: BulkBackupBehavior.skip,
      );

      expect(result.backedUp, 2);
      expect(result.skipped, 0);
      expect(result.modsFailed, 0);
      expect(result.backupsDirChanged, isFalse);
      expect(File(p.join(folder, 'Alpha (111).ttsmod')).existsSync(), isTrue);
      expect(File(p.join(folder, 'Gamma (333).ttsmod')).existsSync(), isTrue);
      expect(modAt(fixture.alpha).backupStatus, BackupStatus.upToDate);
      expect(modAt(fixture.gamma).backupStatus, BackupStatus.upToDate);
      expect(progress.map((s) => s.label).toSet(), {'bulk.backup'});
      expect(progress.any((s) => s.detail == 'Gamma'), isTrue);
    });

    test('skip leaves mods with a backup alone', () async {
      final existing = library.writeBackup(
        p.join('Old', 'Alpha (111).ttsmod'),
        assetCount: 0,
        modified: DateTime(2020),
      );
      await refreshLibrary(container);
      expect(modAt(fixture.alpha).backupStatus, BackupStatus.outOfDate);
      final folder = newFolder('New');

      final result = await service.backupMods(
        [modAt(fixture.alpha), modAt(fixture.gamma)],
        folder: folder,
        behavior: BulkBackupBehavior.skip,
      );

      expect(result.backedUp, 1);
      expect(result.skipped, 1);
      expect(result.outcomes.first.value!.skipped, isTrue);
      expect(File(existing).lastModifiedSync().year, 2020);
      expect(File(p.join(folder, 'Alpha (111).ttsmod')).existsSync(), isFalse);
      expect(File(p.join(folder, 'Gamma (333).ttsmod')).existsSync(), isTrue);
      expect(
        logAt(LogLevel.info).map((e) => e.message),
        contains('Skipped backup of "Alpha": it already has a backup'),
      );
    });

    test('replace writes into the existing backup\'s folder', () async {
      library.writeBackup(
        p.join('Old', 'Alpha (111).ttsmod'),
        assetCount: 0,
        modified: DateTime(2020),
      );
      await refreshLibrary(container);
      final folder = newFolder('New');

      final result = await service.backupMods(
        [modAt(fixture.alpha)],
        folder: folder,
        behavior: BulkBackupBehavior.replace,
      );

      expect(result.backedUp, 1);
      final replaced = File(
        p.join(library.backupsDir, 'Old', 'Alpha (111).ttsmod'),
      );
      expect(replaced.lastModifiedSync().year, greaterThan(2020));
      expect(File(p.join(folder, 'Alpha (111).ttsmod')).existsSync(), isFalse);
      expect(modAt(fixture.alpha).backupStatus, BackupStatus.upToDate);
      expect(modAt(fixture.alpha).backup?.path, p.normalize(replaced.path));
    });

    test('replaceIfOutOfDate replaces only out-of-date backups', () async {
      library.writeBackup(
        p.join('Old', 'Alpha (111).ttsmod'),
        assetCount: 0,
        modified: DateTime(2020),
      );
      library.writeBackup(p.join('Old', 'Gamma (333).ttsmod'), assetCount: 2);
      await refreshLibrary(container);
      expect(modAt(fixture.alpha).backupStatus, BackupStatus.outOfDate);
      expect(modAt(fixture.gamma).backupStatus, BackupStatus.upToDate);
      final gammaBefore = File(
        p.join(library.backupsDir, 'Old', 'Gamma (333).ttsmod'),
      ).lengthSync();

      final result = await service.backupMods(
        [modAt(fixture.alpha), modAt(fixture.gamma)],
        folder: newFolder('New'),
        behavior: BulkBackupBehavior.replaceIfOutOfDate,
      );

      expect(result.backedUp, 1);
      expect(result.skipped, 1);
      expect(modAt(fixture.alpha).backupStatus, BackupStatus.upToDate);
      expect(
        File(p.join(library.backupsDir, 'Old', 'Gamma (333).ttsmod'))
            .lengthSync(),
        gammaBefore,
      );
      expect(
        logAt(LogLevel.info).map((e) => e.message),
        contains('Skipped backup of "Gamma": its backup is up to date'),
      );
    });

    test('post-backup deletion removes the exclusive files only', () async {
      final result = await service.backupMods(
        [modAt(fixture.gamma)],
        folder: newFolder('New'),
        behavior: BulkBackupBehavior.skip,
        postBackupDeletion: PostBackupDeletion.deleteNonSharedAssets,
      );

      expect(result.backedUp, 1);
      expect(result.filesDeleted, 1);
      expect(result.deleteFailed, 0);
      expect(File(fixture.bFile).existsSync(), isFalse);
      expect(File(fixture.cFile).existsSync(), isTrue);
      expect(modAt(fixture.gamma).summary.present, 1);
      expect(modAt(fixture.save).summary.present, 1);
    });

    test('deletion runs even when the backup is skipped (v2 rule)', () async {
      library.writeBackup(p.join('Old', 'Gamma (333).ttsmod'), assetCount: 2);
      await refreshLibrary(container);

      final result = await service.backupMods(
        [modAt(fixture.gamma)],
        folder: newFolder('New'),
        behavior: BulkBackupBehavior.skip,
        postBackupDeletion: PostBackupDeletion.deleteAllAssets,
      );

      expect(result.backedUp, 0);
      expect(result.skipped, 1);
      expect(result.filesDeleted, 2);
      expect(File(fixture.bFile).existsSync(), isFalse);
      expect(File(fixture.cFile).existsSync(), isFalse);
      expect(modAt(fixture.save).summary.present, 0);
    });

    test('setAsDefaultFolder persists the folder and refreshes', () async {
      final folder = newFolder('New');
      final strayBackup = library.writeBackup(p.join('New', 'Stray.ttsmod'));
      final refreshesBefore = refreshFinishedLines(container);

      final result = await service.backupMods(
        [modAt(fixture.alpha)],
        folder: folder,
        behavior: BulkBackupBehavior.skip,
        setAsDefaultFolder: true,
      );

      expect(result.backupsDirChanged, isTrue);
      expect(container.read(directoriesProvider).value!.backupsDir, folder);
      expect(refreshFinishedLines(container), refreshesBefore + 1);
      expect(state().backups.map((b) => b.path), contains(strayBackup));
      expect(
        logAt(LogLevel.info).map((e) => e.message),
        contains(startsWith('Backups folder set to')),
      );
    });
  });

  group('download and backup', () {
    test('downloads then backs up each mod with the new files', () async {
      final folder = newFolder('New');
      final progress = recordProgress();

      final result = await service.downloadAndBackupMods(
        [modAt(fixture.alpha)],
        folder: folder,
        behavior: BulkBackupBehavior.skip,
      );

      expect(result.downloadedFiles, 1);
      expect(result.failedFiles, 1);
      expect(result.backedUp, 1);
      expect(result.skipped, 0);
      expect(result.outcomes.single.value!.backup!.backup!.assetCount, 1);
      expect(modAt(fixture.alpha).backupStatus, BackupStatus.upToDate);
      expect(progress.map((s) => s.label).toSet(), {'bulk.downloadAndBackup'});
    });
  });

  group('delete assets', () {
    test('deletes the files of every mod and counts once per file', () async {
      final result = await service.deleteModAssets([
        modAt(fixture.gamma),
        modAt(fixture.save),
      ], scope: DeleteAssetsScope.all);

      expect(result.modsProcessed, 2);
      expect(result.filesDeleted, 2);
      expect(result.deleteFailed, 0);
      expect(File(fixture.bFile).existsSync(), isFalse);
      expect(File(fixture.cFile).existsSync(), isFalse);
      expect(modAt(fixture.gamma).summary.present, 0);
      expect(modAt(fixture.save).summary.present, 0);
      expect(
        logAt(LogLevel.success).map((e) => e.message),
        contains(startsWith('Bulk asset deletion finished: 2 file(s)')),
      );
    });

    test('exclusiveOnly keeps shared files', () async {
      final result = await service.deleteModAssets([
        modAt(fixture.gamma),
      ], scope: DeleteAssetsScope.exclusiveOnly);

      expect(result.filesDeleted, 1);
      expect(File(fixture.cFile).existsSync(), isTrue);
    });
  });

  group('check URLs', () {
    test('checks every mod and collects the dead URLs', () async {
      final progress = recordProgress();

      final result = await service.checkUrls([
        modAt(fixture.alpha),
        modAt(fixture.gamma),
      ]);

      expect(result.modsChecked, 2);
      expect(result.cancelled, isFalse);
      expect(result.invalidUrlCount, greaterThanOrEqualTo(1));
      final alphaResult = result.results
          .singleWhere((r) => r.$1.jsonPath == fixture.alpha)
          .$2;
      expect(alphaResult.invalidUrls, contains(fixture.dead));
      expect(alphaResult.cancelled, isFalse);
      expect(modAt(fixture.alpha).invalidUrls, contains(fixture.dead));
      expect(progress.map((s) => s.label).toSet(), {'bulk.checkUrls'});
    });
  });

  group('delegating wrappers', () {
    test('update from Workshop keeps the inner kind and cancelled shape', () {
      final op = BulkUpdateWorkshopOperation(
        ref: _refOf(container),
        mods: [modAt(fixture.alpha)],
        force: true,
      );
      expect(op.kind, OperationKind.updateWorkshop);
      final cancelled = op.cancelledResult()!;
      expect(cancelled.total, 1);
      expect(cancelled.results.single.status, WorkshopUpdateStatus.cancelled);
    });

    test('update URLs runs the inner operation', () async {
      final result = await service.updateUrls(
        [modAt(fixture.alpha)],
        oldPrefixes: [server.baseUrl],
        newPrefix: 'https://moved.example.com',
      );

      expect(result.modsUpdated, 1);
      expect(
        File(fixture.alpha).readAsStringSync(),
        contains('https://moved.example.com/png/a'),
      );
    });
  });
}

/// A `Ref` for constructing operations directly in tests.
Ref _refOf(ProviderContainer container) => container.read(_refProvider);

final _refProvider = Provider<Ref>((ref) => ref);
