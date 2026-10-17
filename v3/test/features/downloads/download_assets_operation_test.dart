// DownloadAssetsOperation through the DownloadsService: store rows, library
// patches, progress labels, audio visibility, cancellation.

@Timeout(Duration(seconds: 60))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/core/logging/app_log.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/domain/rules/file_key.dart';
import 'package:tts_mod_vault/features/downloads/application/downloads_providers.dart';
import 'package:tts_mod_vault/features/downloads/application/network_options.dart';
import 'package:tts_mod_vault/features/library/application/library_settings.dart';
import 'package:tts_mod_vault/features/operations/application/operation_runner.dart';

import 'downloads_test_harness.dart';

void main() {
  late DownloadsHarness h;
  late Mod alpha;
  late String imgMissing;
  late String imgPresent;
  late String model;
  late String song;
  late String dead;

  /// Alpha: two images (one on disk), one model, one audio, one dead URL.
  Future<void> prepare({
    AudioVisibility audio = AudioVisibility.useGlobalSetting,
  }) async {
    h = await DownloadsHarness.create();
    final server = h.server;
    imgMissing = server.url('/png/missing');
    imgPresent = server.url('/png/present');
    model = server.url('/octet-jpeg');
    song = server.url('/audio/song.mp3');
    dead = server.url('/missing');
    alpha = h.workshopMod('100001', saveName: 'Alpha', audio: audio);
    await h.indexMods(
      [alpha],
      {
        alpha.jsonPath: [
          (imgMissing, AssetType.image),
          (imgPresent, AssetType.image),
          (dead, AssetType.image),
          (model, AssetType.model),
          (song, AssetType.audio),
        ],
      },
    );
    // imgPresent is already cached.
    final presentPath = h.cachePath(AssetType.image, imgPresent);
    h.fs.file(presentPath).writeAsBytesSync(const [1, 2, 3]);
    await h.db.existingFilesDao.upsert(
      AssetType.image,
      fileKeyFromUrl(imgPresent),
      presentPath,
    );
  }

  DownloadsService service() => h.container.read(downloadsServiceProvider);

  group('downloadMod', () {
    setUp(prepare);

    test('downloads the missing images and models, skips hidden audio, '
        'updates the store and patches the library', () async {
      final progress = h.recordProgress();
      final result = await service().downloadMod(alpha);

      expect(result.total, 3);
      expect(result.downloadedCount, 2);
      expect(result.failedCount, 1);
      final byUrl = {for (final o in result.outcomes) o.url: o};
      expect(byUrl[imgMissing]!.status, DownloadStatus.downloaded);
      expect(byUrl[model]!.status, DownloadStatus.downloaded);
      expect(byUrl[dead]!.status, DownloadStatus.failed);
      expect(byUrl[dead]!.httpStatus, 404);
      expect(byUrl.containsKey(imgPresent), isFalse);
      expect(byUrl.containsKey(song), isFalse);
      expect(h.server.requestsTo('/audio/song.mp3'), isEmpty);

      // Files on disk with the right extensions.
      expect(h.cachedFiles(AssetType.image), [
        '${fileNameFromUrl(imgMissing)}.png',
        '${fileNameFromUrl(imgPresent)}.png',
      ]);
      expect(h.cachedFiles(AssetType.model), ['${fileNameFromUrl(model)}.obj']);

      // Store rows for the downloaded files.
      final assets = await h.assetsInStore(alpha);
      final paths = {for (final a in assets) a.url: a.path};
      expect(paths[imgMissing], byUrl[imgMissing]!.path);
      expect(paths[model], byUrl[model]!.path);
      expect(paths[dead], isNull);

      // Library patched once for the shared keys, then the mod itself.
      expect(h.library.assetFileChangeCalls, [
        {fileKeyFromUrl(imgMissing), fileKeyFromUrl(model)},
      ]);
      expect(h.library.resummarizeCalls, [alpha.jsonPath]);

      // Progress labels per type in AssetType order, ending complete.
      final labels = progress.map((p) => p.label).toSet();
      expect(labels, {'downloading.images', 'downloading.models'});
      expect(
        progress.map((p) => p.label).toList().indexOf('downloading.models'),
        greaterThan(
          progress.map((p) => p.label).toList().indexOf('downloading.images'),
        ),
      );
      final lastImages = progress.lastWhere(
        (p) => p.label == 'downloading.images',
      );
      expect(lastImages.done, 2);
      expect(lastImages.total, 2);
      expect(lastImages.value, 1.0);
      expect(
        progress.every((p) => p.kind == OperationKind.downloadAssets),
        isTrue,
      );

      // Runner idle again; summary logged as a warning because one failed.
      expect(h.runnerState, OperationState.idle);
      final summary = h.log.store.entries.lastWhere(
        (e) => e.message.startsWith('Downloaded 2/3 files for "Alpha"'),
      );
      expect(summary.level, LogLevel.warning);
      expect(summary.message, contains('1 failed'));
      expect(summary.modPath, alpha.jsonPath);
    });

    test('downloads audio when the mod shows it', () async {
      await h.db.modsDao.setAudioVisibility(
        alpha.jsonPath,
        AudioVisibility.alwaysShow,
      );
      final result = await service().downloadMod(
        alpha.copyWith(audio: AudioVisibility.alwaysShow),
      );
      expect(result.total, 4);
      final songOutcome = result.outcomes.singleWhere((o) => o.url == song);
      expect(songOutcome.status, DownloadStatus.downloaded);
      expect(p.extension(songOutcome.path!), '.ogg');
      expect(h.cachedFiles(AssetType.audio), ['${fileNameFromUrl(song)}.ogg']);
    });

    test('downloads audio when the global option shows it', () async {
      await h.container
          .read(libraryOptionsProvider.notifier)
          .setIgnoreAudioGlobally(false);
      final result = await service().downloadMod(alpha);
      expect(result.outcomes.map((o) => o.url), contains(song));
    });

    test('logs and returns empty when nothing is missing', () async {
      final beta = h.workshopMod('100002', saveName: 'Beta');
      await h.indexMods(
        [alpha, beta],
        {
          beta.jsonPath: [(imgPresent, AssetType.image)],
        },
      );
      final result = await service().downloadMod(beta);
      expect(result.total, 0);
      expect(h.server.requests, isEmpty);
      expect(
        h.logMessages,
        contains(startsWith('Nothing to download for "Beta"')),
      );
      expect(h.library.resummarizeCalls, isEmpty);
      expect(h.runnerState, OperationState.idle);
    });

    test('honours ignored domains from the network options', () async {
      await h.container.read(networkOptionsProvider.notifier).setIgnoredDomains(
        ['127.0.0.1'],
      );
      final result = await service().downloadMod(alpha);
      expect(
        result.outcomes.map((o) => o.status),
        everyElement(DownloadStatus.skippedIgnoredDomain),
      );
      expect(h.server.requests, isEmpty);
      expect(h.library.assetFileChangeCalls, isEmpty);
      expect(h.library.resummarizeCalls, [alpha.jsonPath]);
    });

    test('rejects a second operation while one runs', () async {
      h.server.flakyFailures = 0;
      final first = service().downloadMod(alpha);
      await Future<void>.delayed(Duration.zero);
      expect(h.container.read(anyOperationRunningProvider), isTrue);
      expect(() => service().downloadMod(alpha), throwsStateError);
      await first;
      expect(h.container.read(anyOperationRunningProvider), isFalse);
    });
  });

  group('downloadType and downloadAsset', () {
    setUp(prepare);

    test('downloadType restricts to one type', () async {
      final result = await service().downloadType(alpha, AssetType.model);
      expect(result.outcomes.map((o) => o.url).toList(), [model]);
      expect(h.cachedFiles(AssetType.image), [
        '${fileNameFromUrl(imgPresent)}.png',
      ]);
      expect(h.library.assetFileChangeCalls, [
        {fileKeyFromUrl(model)},
      ]);
    });

    test(
      'downloadAsset downloads just that asset, even hidden audio',
      () async {
        final assets = await h.assetsInStore(alpha);
        final songAsset = assets.singleWhere((a) => a.url == song);
        final result = await service().downloadAsset(alpha, songAsset);
        expect(result.outcomes.single.status, DownloadStatus.downloaded);
        expect(h.cachedFiles(AssetType.audio), hasLength(1));
        final stored = await h.assetsInStore(alpha);
        expect(stored.singleWhere((a) => a.url == song).exists, isTrue);
      },
    );

    test('downloadAsset of a present asset does nothing', () async {
      final assets = await h.assetsInStore(alpha);
      final present = assets.singleWhere((a) => a.url == imgPresent);
      final result = await service().downloadAsset(alpha, present);
      expect(result.total, 0);
      expect(h.server.requests, isEmpty);
    });
  });

  group('cancellation', () {
    test('cancel mid-download yields cancelled outcomes, no temp files, '
        'idle runner', () async {
      h = await DownloadsHarness.create();
      final server = h.server;
      final slow1 = server.url('/slow/1');
      final slow2 = server.url('/slow/2');
      // Store order is type, then URL: this one downloads first, then the
      // two slow ones occupy both workers until the cancel.
      final first = server.url('/png/first');
      alpha = h.workshopMod('100001', saveName: 'Alpha');
      await h.indexMods(
        [alpha],
        {
          alpha.jsonPath: [
            (slow1, AssetType.image),
            (slow2, AssetType.image),
            (first, AssetType.image),
            (server.url('/octet-jpeg'), AssetType.model),
          ],
        },
      );
      await h.container
          .read(networkOptionsProvider.notifier)
          .setConcurrentDownloads(2);

      final pending = service().downloadMod(alpha);
      while (server.requestsTo('/slow/1').isEmpty ||
          server.requestsTo('/slow/2').isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      service().cancel();
      expect(h.runnerState.cancelRequested, isTrue);

      final result = await pending.timeout(const Duration(seconds: 10));
      expect(result.total, 4);
      expect(result.downloadedCount, 1);
      expect(result.cancelledCount, 3);
      expect(result.wasCancelled, isTrue);
      final byUrl = {for (final o in result.outcomes) o.url: o};
      expect(byUrl[first]!.status, DownloadStatus.downloaded);
      expect(byUrl[slow1]!.status, DownloadStatus.cancelled);
      expect(byUrl[slow2]!.status, DownloadStatus.cancelled);
      // The model type never started: no request, cancelled outcome.
      expect(server.requestsTo('/octet-jpeg'), isEmpty);
      expect(
        byUrl[server.url('/octet-jpeg')]!.status,
        DownloadStatus.cancelled,
      );
      // No temp files: only the finished download is on disk.
      expect(h.cachedFiles(AssetType.image), ['${fileNameFromUrl(first)}.png']);
      expect(h.cachedFiles(AssetType.model), isEmpty);
      expect(h.runnerState, OperationState.idle);
      expect(h.library.assetFileChangeCalls, [
        {fileKeyFromUrl(first)},
      ]);
      expect(h.library.resummarizeCalls, [alpha.jsonPath]);
      expect(
        h.logMessages,
        contains(startsWith('Downloaded 1/4 files for "Alpha", 3 cancelled')),
      );
    });
  });
}
