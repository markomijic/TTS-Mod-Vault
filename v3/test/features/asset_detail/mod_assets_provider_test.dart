// Integration tests of the asset list providers against a temporary library
// on disk (the library controller's workers need real files).

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/app/providers/infrastructure_providers.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/asset_detail/application/asset_detail_filter.dart';
import 'package:tts_mod_vault/features/asset_detail/application/mod_assets_provider.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';
import 'package:tts_mod_vault/features/library/application/library_settings.dart';
import 'package:tts_mod_vault/features/library/application/mod_edit_service.dart';

import '../library/library_test_harness.dart';

const _imageA = 'https://example.com/a.png';
const _model = 'https://example.com/m.obj';
const _audio = 'https://example.com/s.mp3';

void main() {
  late TempLibrary library;
  late ProviderContainer container;
  late String alpha;

  setUp(() {
    library = TempLibrary.create();
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
    library.writeAsset(AssetType.image, _imageA);
    library.writeAsset(AssetType.audio, _audio, extension: '.mp3');
    container = makeLibraryContainer(library);
  });

  tearDown(() => library.delete());

  Future<List<String>> urls() async =>
      (await container.read(modAssetsProvider(alpha).future))
          .map((a) => a.url)
          .toList();

  test('lists the assets with their files, audio hidden by default', () async {
    await refreshLibrary(container);

    final assets = await container.read(modAssetsProvider(alpha).future);

    expect(assets.map((a) => a.url), [_imageA, _model]);
    expect(assets.first.type, AssetType.image);
    expect(assets.first.exists, isTrue);
    expect(assets.last.type, AssetType.model);
    expect(assets.last.exists, isFalse);
    expect(assets.every((a) => !a.invalid), isTrue);
  });

  test('follows the global audio option and the per-mod override', () async {
    await refreshLibrary(container);
    final keepAlive = container.listen(modAssetsProvider(alpha), (_, _) {});
    addTearDown(keepAlive.close);
    expect(await urls(), [_imageA, _model]);

    await container
        .read(libraryOptionsProvider.notifier)
        .setIgnoreAudioGlobally(false);
    expect(await urls(), [_audio, _imageA, _model]);

    final mod = container
        .read(libraryControllerProvider)
        .value!
        .modByPath(alpha)!;
    await container
        .read(modEditServiceProvider)
        .setAudioVisibility(mod, AudioVisibility.alwaysHide);
    expect(await urls(), [_imageA, _model]);

    await container
        .read(libraryOptionsProvider.notifier)
        .setIgnoreAudioGlobally(true);
    final hidden = container
        .read(libraryControllerProvider)
        .value!
        .modByPath(alpha)!;
    await container
        .read(modEditServiceProvider)
        .setAudioVisibility(hidden, AudioVisibility.alwaysShow);
    expect(await urls(), [_audio, _imageA, _model]);
  });

  test('an unknown path yields no assets', () async {
    await refreshLibrary(container);
    expect(
      await container.read(
        modAssetsProvider(p.join(library.workshopDir, 'x.json')).future,
      ),
      isEmpty,
    );
  });

  test(
    'groupedModAssetsProvider applies the filter and invalid flags',
    () async {
      await refreshLibrary(container);
      await container.read(appDatabaseProvider).modsDao.setInvalidUrls(alpha, [
        _model,
      ]);
      await container
          .read(libraryControllerProvider.notifier)
          .resummarizeMod(alpha);
      final keepAlive = container.listen(
        groupedModAssetsProvider(alpha),
        (_, _) {},
      );
      addTearDown(keepAlive.close);

      Future<List<AssetGroup>> groups() async {
        await container.read(modAssetsProvider(alpha).future);
        // Let the derived provider pick up the resolved assets.
        await Future<void>.delayed(Duration.zero);
        return container.read(groupedModAssetsProvider(alpha)).requireValue;
      }

      final all = await groups();
      expect(all.map((g) => g.type), [AssetType.image, AssetType.model]);
      expect(all.first.total, 1);
      expect(all.first.missing, 0);
      expect(all.last.missing, 1);
      expect(all.last.assets.single.invalid, isTrue);

      container.read(assetDetailFilterProvider.notifier).setInvalidOnly(true);
      final invalid = await groups();
      expect(invalid.first.assets, isEmpty);
      expect(invalid.last.assets.map((a) => a.url), [_model]);

      container.read(assetDetailFilterProvider.notifier)
        ..reset()
        ..setStatus(AssetStatusFilter.downloaded);
      final downloaded = await groups();
      expect(downloaded.first.assets.map((a) => a.url), [_imageA]);
      expect(downloaded.last.assets, isEmpty);
      expect(downloaded.last.total, 1, reason: 'totals ignore the filter');
    },
  );
}
