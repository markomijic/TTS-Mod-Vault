// Integration tests of the orphaned-asset cleanup (scan + operation)
// against a temporary library on disk with an in-memory store.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/app/providers/infrastructure_providers.dart';
import 'package:tts_mod_vault/core/cancellation/cancellation_token.dart';
import 'package:tts_mod_vault/domain/constants.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/domain/rules/file_key.dart';
import 'package:tts_mod_vault/features/cleanup/application/cleanup_service.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';
import 'package:tts_mod_vault/features/operations/application/operation_runner.dart';

import '../library/library_test_harness.dart';

const _imageA = 'https://example.com/a.png';
const _steamNew = '${newSteamUserContentUrl}ugc/abc/';
const _steamOld = '${oldCloudUrl}ugc/abc/';
const _orphanUrl = 'https://example.com/orphan.png';
const _rawOrphanUrl = 'https://example.com/raw-zzz.png';
const _rawModelUrl = 'https://example.com/raw-model.obj';

/// Alpha references image a and the Steam asset (by its current URL). On
/// disk:
///
/// | folder      | file                                  | expectation          |
/// | Images      | a (referenced)                        | kept                 |
/// | Images      | steam asset, current host             | kept (twin)          |
/// | Images      | steam asset, legacy host (4 bytes)    | legacy duplicate     |
/// | Images      | orphan (10 bytes)                     | unreferenced         |
/// | Images      | file777.png                           | skipped (`file*`)    |
/// | Images Raw  | file123.rawt                          | skipped (`file*`)    |
/// | Images Raw  | a.rawt (key referenced)               | kept                 |
/// | Images Raw  | raw-zzz.rawt (6 bytes)                | unreferenced         |
/// | Models Raw  | raw-model.rawm (3 bytes)              | unreferenced         |
final class _Fixture {
  _Fixture(this.library) {
    final dirs = library.directories;
    alpha = library.writeJson(
      p.join('Mods', 'Workshop', '111.json'),
      saveName: 'Alpha',
      epochTime: epoch2023,
      assets: [('ImageURL', _imageA), ('FaceURL', _steamNew)],
    );
    imageAFile = library.writeAsset(AssetType.image, _imageA);
    steamNewFile = library.writeAsset(AssetType.image, _steamNew);
    steamOldFile = _write(
      p.join(
        dirs.assetDir(AssetType.image),
        '${fileNameFromUrl(_steamOld)}.png',
      ),
      4,
    );
    orphanFile = _write(
      p.join(
        dirs.assetDir(AssetType.image),
        '${fileNameFromUrl(_orphanUrl)}.png',
      ),
      10,
    );
    skippedMain = _write(
      p.join(dirs.assetDir(AssetType.image), 'file777.png'),
      1,
    );
    final imagesRaw = dirs.rawAssetDir(AssetType.image)!;
    final modelsRaw = dirs.rawAssetDir(AssetType.model)!;
    skippedRaw = _write(p.join(imagesRaw, 'file123.rawt'), 1);
    referencedRaw = _write(
      p.join(imagesRaw, '${fileNameFromUrl(_imageA)}.rawt'),
      2,
    );
    rawOrphan = _write(
      p.join(imagesRaw, '${fileNameFromUrl(_rawOrphanUrl)}.rawt'),
      6,
    );
    rawModelOrphan = _write(
      p.join(modelsRaw, '${fileNameFromUrl(_rawModelUrl)}.rawm'),
      3,
    );
  }

  final TempLibrary library;
  late final String alpha;
  late final String imageAFile;
  late final String steamNewFile;
  late final String steamOldFile;
  late final String orphanFile;
  late final String skippedMain;
  late final String skippedRaw;
  late final String referencedRaw;
  late final String rawOrphan;
  late final String rawModelOrphan;

  static String _write(String path, int size) {
    File(path)
      ..createSync(recursive: true)
      ..writeAsBytesSync(List.filled(size, 1));
    return p.normalize(path);
  }
}

void main() {
  late TempLibrary library;
  late _Fixture fixture;
  late ProviderContainer container;
  late CleanupService service;

  setUp(() async {
    library = TempLibrary.create();
    fixture = _Fixture(library);
    container = makeLibraryContainer(library);
    service = container.read(cleanupServiceProvider);
    await refreshLibrary(container);
  });

  tearDown(() => library.delete());

  Future<String?> indexed(AssetType type, String url) => container
      .read(appDatabaseProvider)
      .existingFilesDao
      .pathFor(type, fileKeyFromUrl(url));

  test('scan finds orphans, raw orphans and legacy duplicates only', () async {
    final scan = await service.scanOrphans();

    expect(
      scan.candidates.map((c) => c.path),
      unorderedEquals([
        fixture.steamOldFile,
        fixture.orphanFile,
        fixture.rawOrphan,
        fixture.rawModelOrphan,
      ]),
    );
    expect(scan.totalBytes, 4 + 10 + 6 + 3);
    final byPath = {for (final c in scan.candidates) c.path: c};
    final legacy = byPath[fixture.steamOldFile]!;
    expect(legacy.reason, CleanupReason.legacyDuplicate);
    expect(legacy.twinPath, fixture.steamNewFile);
    expect(legacy.indexed, isTrue);
    expect(legacy.type, AssetType.image);
    expect(byPath[fixture.orphanFile]!.reason, CleanupReason.unreferenced);
    expect(byPath[fixture.orphanFile]!.indexed, isTrue);
    expect(byPath[fixture.rawOrphan]!.indexed, isFalse);
    expect(byPath[fixture.rawModelOrphan]!.type, AssetType.model);
    // Sorted by type then path: images before models.
    expect(scan.candidates.last.path, fixture.rawModelOrphan);
  });

  test(
    'a cancelled token aborts the scan with the cancellation error',
    () async {
      final token = CancellationToken()..cancel('test');
      await expectLater(
        service.scanOrphans(token: token),
        throwsA(isA<OperationCancelledException>()),
      );
    },
  );

  test('cancelling during the scan aborts it', () async {
    final token = CancellationToken();
    final pending = service.scanOrphans(token: token);
    token.cancel('test');
    await expectLater(pending, throwsA(isA<OperationCancelledException>()));
    expect(File(fixture.orphanFile).existsSync(), isTrue);
  });

  test('scan tolerates missing raw folders', () async {
    Directory(library.directories.rawAssetDir(AssetType.model)!)
        .deleteSync(recursive: true);

    final scan = await service.scanOrphans();

    expect(
      scan.candidates.map((c) => c.path),
      isNot(contains(fixture.rawModelOrphan)),
    );
    expect(scan.warnings, contains(startsWith('Directory not found')));
  });

  test('delete frees the candidates and fixes the index', () async {
    final scan = await service.scanOrphans();
    final progress = <OperationProgress>[];
    container.listen(operationRunnerProvider, (_, next) {
      if (next.progress case final p?) progress.add(p);
    });

    final result = await service.deleteCandidates(scan.candidates);

    expect(result.deleted, 4);
    expect(result.failed, 0);
    expect(result.bytesFreed, scan.totalBytes);
    for (final path in [
      fixture.steamOldFile,
      fixture.orphanFile,
      fixture.rawOrphan,
      fixture.rawModelOrphan,
    ]) {
      expect(File(path).existsSync(), isFalse, reason: path);
    }
    for (final path in [
      fixture.imageAFile,
      fixture.steamNewFile,
      fixture.skippedMain,
      fixture.skippedRaw,
      fixture.referencedRaw,
    ]) {
      expect(File(path).existsSync(), isTrue, reason: path);
    }
    // The referenced key now points at the surviving twin; the orphan's
    // row is gone.
    expect(await indexed(AssetType.image, _steamNew), fixture.steamNewFile);
    expect(await indexed(AssetType.image, _orphanUrl), isNull);
    expect(await indexed(AssetType.image, _imageA), fixture.imageAFile);
    final alpha = container
        .read(libraryControllerProvider)
        .value!
        .modByPath(fixture.alpha)!;
    expect(alpha.summary.present, 2);
    expect(progress.map((s) => s.label).toSet(), {cleanupDeletingLabel});
    expect(progress.last.done, 4);
    expect(container.read(operationRunnerProvider).isRunning, isFalse);

    // A second scan has nothing left.
    expect((await service.scanOrphans()).isEmpty, isTrue);
  });

  test('a file that vanished before the delete still counts', () async {
    final scan = await service.scanOrphans();
    File(fixture.orphanFile).deleteSync();

    final result = await service.deleteCandidates(scan.candidates);

    expect(result.deleted, 4);
    expect(await indexed(AssetType.image, _orphanUrl), isNull);
  });
}
