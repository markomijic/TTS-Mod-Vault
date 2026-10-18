// CheckUrlsOperation through the DownloadsService: invalid URLs persisted,
// library patched, progress, cancellation without persistence.

@Timeout(Duration(seconds: 60))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tts_mod_vault/core/logging/app_log.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/downloads/application/downloads_providers.dart';
import 'package:tts_mod_vault/features/downloads/application/network_options.dart';
import 'package:tts_mod_vault/features/operations/application/operation_runner.dart';

import 'downloads_test_harness.dart';

void main() {
  late DownloadsHarness h;
  late Mod alpha;
  late String live;
  late String noHead;
  late String missing;
  late String html;
  late String song;

  setUp(() async {
    h = await DownloadsHarness.create();
    final server = h.server;
    live = server.url('/png');
    noHead = server.url('/no-head');
    missing = server.url('/missing');
    html = server.url('/html200');
    song = server.url('/audio/song.mp3');
    alpha = h.workshopMod('100001', saveName: 'Alpha');
    await h.indexMods(
      [alpha],
      {
        alpha.jsonPath: [
          (live, AssetType.image),
          (noHead, AssetType.image),
          (missing, AssetType.image),
          (html, AssetType.model),
          (song, AssetType.audio),
        ],
      },
    );
  });

  DownloadsService service() => h.container.read(downloadsServiceProvider);

  test(
    'collects the dead URLs, persists them and patches the library',
    () async {
      final progress = h.recordProgress();
      final result = await service().checkUrls(alpha);

      expect(result.cancelled, isFalse);
      expect(result.total, 4); // audio hidden by the global option
      expect(result.checked, 4);
      expect(result.invalidUrls.toSet(), {missing, html});
      expect(result.allLive, isFalse);
      expect(h.server.requestsTo('/audio/song.mp3'), isEmpty);

      final assets = await h.assetsInStore(alpha);
      final invalid = {
        for (final a in assets)
          if (a.invalid) a.url,
      };
      expect(invalid, {missing, html});
      expect(h.library.resummarizeCalls, [alpha.jsonPath]);

      expect(progress.map((p) => p.label).toSet(), {'checking.urls'});
      expect(progress.last.done, 4);
      expect(progress.last.total, 4);
      expect(progress.every((p) => p.kind == OperationKind.checkUrls), isTrue);
      expect(h.runnerState, OperationState.idle);

      final summary = h.log.store.entries.lastWhere(
        (e) => e.message.startsWith('Checked'),
      );
      expect(summary.level, LogLevel.warning);
      expect(summary.message, 'Checked 4 URL(s) of "Alpha": 2 not reachable');
      expect(
        h.log.store.entries.where(
          (e) => e.message.startsWith('URL is not reachable'),
        ),
        hasLength(2),
      );
    },
  );

  test('a clean check clears previously stored invalid URLs', () async {
    await h.db.modsDao.setInvalidUrls(alpha.jsonPath, [live]);
    final beta = h.workshopMod('100002', saveName: 'Beta');
    await h.indexMods(
      [alpha, beta],
      {
        beta.jsonPath: [(live, AssetType.image), (noHead, AssetType.image)],
      },
    );
    await h.db.modsDao.setInvalidUrls(beta.jsonPath, [live]);

    final result = await service().checkUrls(beta);
    expect(result.allLive, isTrue);
    final assets = await h.assetsInStore(beta);
    expect(assets.any((a) => a.invalid), isFalse);
    expect(
      h.log.store.entries
          .lastWhere((e) => e.message.startsWith('Checked'))
          .level,
      LogLevel.success,
    );
  });

  test(
    'a single-asset check merges its outcome into the stored list',
    () async {
      await h.db.modsDao.setInvalidUrls(alpha.jsonPath, [live, missing]);
      final assets = await h.assetsInStore(alpha);
      Asset byUrl(String url) => assets.singleWhere((a) => a.url == url);
      Future<Set<String>> storedInvalid() async => {
        for (final a in await h.assetsInStore(alpha))
          if (a.invalid) a.url,
      };

      // A live URL is removed from the list, the rest stays.
      final progress = h.recordProgress();
      final first = await service().checkUrl(alpha, byUrl(live));
      expect(first.cancelled, isFalse);
      expect(first.total, 1);
      expect(first.checked, 1);
      expect(first.invalidUrls, isEmpty);
      expect(first.allLive, isTrue);
      expect(await storedInvalid(), {missing});
      expect(progress.last.total, 1);
      expect(progress.every((p) => p.kind == OperationKind.checkUrls), isTrue);
      expect(h.library.resummarizeCalls, [alpha.jsonPath]);

      // A dead URL is added; only that URL was requested.
      final before = h.server.requestsTo('/png').length;
      final second = await service().checkUrl(alpha, byUrl(html));
      expect(second.invalidUrls, [html]);
      expect(second.allLive, isFalse);
      expect(await storedInvalid(), {missing, html});
      expect(h.server.requestsTo('/png'), hasLength(before));

      // Checking it again does not duplicate the entry.
      await service().checkUrl(alpha, byUrl(html));
      final assetsAfter = await h.assetsInStore(alpha);
      expect(assetsAfter.where((a) => a.invalid).map((a) => a.url).toList(), [
        missing,
        html,
      ]);
      expect(h.runnerState, OperationState.idle);
    },
  );

  test('respects the concurrency setting', () async {
    final gamma = h.workshopMod('100003', saveName: 'Gamma');
    await h.indexMods(
      [gamma],
      {
        gamma.jsonPath: [
          for (var i = 0; i < 6; i++)
            (h.server.url('/delay/60/$i'), AssetType.image),
        ],
      },
    );
    await h.container
        .read(networkOptionsProvider.notifier)
        .setConcurrentDownloads(2);
    final result = await service().checkUrls(gamma);
    expect(result.allLive, isTrue);
    expect(h.server.maxConcurrentRequests, 2);
  });

  test(
    'cancellation returns the partial result without persisting it',
    () async {
      final delta = h.workshopMod('100004', saveName: 'Delta');
      final stall1 = h.server.url('/stall/1');
      final stall2 = h.server.url('/stall/2');
      await h.indexMods(
        [delta],
        {
          delta.jsonPath: [
            (missing, AssetType.image),
            (stall1, AssetType.image),
            (stall2, AssetType.image),
            (live, AssetType.image),
          ],
        },
      );
      await h.container
          .read(networkOptionsProvider.notifier)
          .setConcurrentDownloads(2);

      final pending = service().checkUrls(delta);
      while (h.server.requestsTo('/stall/1').isEmpty ||
          h.server.requestsTo('/stall/2').isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      service().cancel();

      final result = await pending.timeout(const Duration(seconds: 10));
      expect(result.cancelled, isTrue);
      expect(result.total, 4);
      expect(result.checked, 2);
      expect(result.invalidUrls, [missing]);

      final assets = await h.assetsInStore(delta);
      expect(assets.any((a) => a.invalid), isFalse);
      expect(h.library.resummarizeCalls, isEmpty);
      expect(h.runnerState, OperationState.idle);
      expect(
        h.logMessages,
        contains(startsWith('URL check of "Delta" cancelled after 2/4')),
      );
    },
  );
}
