// Integration tests of the per-mod asset deletion (scan + operation)
// against a temporary library on disk with an in-memory store.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/app/providers/infrastructure_providers.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/domain/rules/file_key.dart';
import 'package:tts_mod_vault/features/cleanup/application/delete_assets_service.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';
import 'package:tts_mod_vault/features/operations/application/operation_runner.dart';

import '../library/library_test_harness.dart';

const _imageA = 'https://example.com/a.png';
const _model = 'https://example.com/m.obj';
const _audio = 'https://example.com/s.mp3';
const _missing = 'https://example.com/missing.png';

/// | file                 | name    | assets                                         |
/// | Workshop/111.json    | Alpha   | image a (present, shared), model (present),    |
/// |                      |         | audio (present, hidden), missing image         |
/// | Workshop/333.json    | Gamma   | image a                                        |
/// | Saves/TS_Save_1.json | My Save | image a                                        |
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
        ('FaceURL', _missing),
      ],
    );
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
    imageAFile = library.writeAsset(AssetType.image, _imageA);
    modelFile = library.writeAsset(AssetType.model, _model, extension: '.obj');
    audioFile = library.writeAsset(AssetType.audio, _audio, extension: '.mp3');
  }

  final TempLibrary library;
  late final String alpha;
  late final String gamma;
  late final String save;
  late final String imageAFile;
  late final String modelFile;
  late final String audioFile;
}

void main() {
  late TempLibrary library;
  late _Fixture fixture;
  late ProviderContainer container;
  late DeleteAssetsService service;

  setUp(() async {
    library = TempLibrary.create();
    fixture = _Fixture(library);
    container = makeLibraryContainer(library);
    service = container.read(deleteAssetsServiceProvider);
    await refreshLibrary(container);
  });

  tearDown(() => library.delete());

  Mod modAt(String path) =>
      container.read(libraryControllerProvider).value!.modByPath(path)!;
  Future<String?> indexed(AssetType type, String url) => container
      .read(appDatabaseProvider)
      .existingFilesDao
      .pathFor(type, fileKeyFromUrl(url));

  test('scan splits exclusive from shared and names the sharers', () async {
    final scan = await service.scanModAssets(modAt(fixture.alpha));

    expect(scan.exclusive.map((a) => a.url), [_model]);
    expect(scan.shared.map((a) => a.url), [_imageA]);
    expect(scan.sharedDetails, {
      _imageA: {
        ModType.mod: ['Gamma'],
        ModType.save: ['My Save'],
      },
    });
    expect(scan.sharedWithCounts, {
      ModType.mod: 1,
      ModType.save: 1,
      ModType.savedObject: 0,
    });
    expect(scan.assetsFor(DeleteAssetsScope.all).length, 2);
    expect(scan.isEmpty, isFalse);
  });

  test('scan is empty for a mod without cached files', () async {
    File(fixture.imageAFile).deleteSync();
    await container.read(libraryControllerProvider.notifier).refresh();

    final scan = await service.scanModAssets(modAt(fixture.gamma));

    expect(scan.isEmpty, isTrue);
    expect(scan, same(DeletableAssetsScan.empty));
  });

  test('exclusiveOnly deletes the model and keeps the shared image', () async {
    final alpha = modAt(fixture.alpha);
    expect(alpha.summary.present, 2);
    final progress = <OperationProgress>[];
    container.listen(operationRunnerProvider, (_, next) {
      if (next.progress case final p?) progress.add(p);
    });

    final result = await service.deleteModAssets(
      alpha,
      scope: DeleteAssetsScope.exclusiveOnly,
    );

    expect(result.deleted, 1);
    expect(result.failed, 0);
    expect(File(fixture.modelFile).existsSync(), isFalse);
    expect(File(fixture.imageAFile).existsSync(), isTrue);
    expect(File(fixture.audioFile).existsSync(), isTrue);
    expect(await indexed(AssetType.model, _model), isNull);
    expect(await indexed(AssetType.image, _imageA), fixture.imageAFile);
    expect(modAt(fixture.alpha).summary.present, 1);
    expect(modAt(fixture.gamma).summary.present, 1);
    expect(progress.map((s) => s.label).toSet(), {deleteAssetsLabel});
    expect(container.read(operationRunnerProvider).isRunning, isFalse);
  });

  test('all deletes shared files too and re-summarises the sharers', () async {
    final alpha = modAt(fixture.alpha);
    final scan = await service.scanModAssets(alpha);

    final result = await service.deleteModAssets(
      alpha,
      scope: DeleteAssetsScope.all,
      scan: scan,
    );

    expect(result.deleted, 2);
    expect(File(fixture.modelFile).existsSync(), isFalse);
    expect(File(fixture.imageAFile).existsSync(), isFalse);
    expect(await indexed(AssetType.image, _imageA), isNull);
    expect(modAt(fixture.alpha).summary.present, 0);
    expect(modAt(fixture.gamma).summary.present, 0);
    expect(modAt(fixture.save).summary.present, 0);
  });

  test('PostBackupDeletion maps to the delete scope', () {
    expect(PostBackupDeletion.none.scope, isNull);
    expect(
      PostBackupDeletion.deleteNonSharedAssets.scope,
      DeleteAssetsScope.exclusiveOnly,
    );
    expect(PostBackupDeletion.deleteAllAssets.scope, DeleteAssetsScope.all);
  });
}
