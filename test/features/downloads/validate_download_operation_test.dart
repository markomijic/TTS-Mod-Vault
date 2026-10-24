// ValidateDownloadOperation through the DownloadsService and the bulk
// download: still-missing files are split into unreachable hosts and dead
// URLs, the invalid list is saved only when every host answered, a clean
// download clears it, saved objects are skipped.

@Timeout(Duration(seconds: 60))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/bulk/application/bulk_service.dart';
import 'package:tts_mod_vault/features/downloads/application/downloads_providers.dart';
import 'package:tts_mod_vault/features/downloads/application/network_options.dart';
import 'package:tts_mod_vault/features/operations/application/operation_runner.dart';

import '../../data/net/dead_host_adapter.dart';
import 'downloads_test_harness.dart';

void main() {
  late DownloadsHarness h;
  late String live;
  late String missing;
  const dead = 'http://$deadHost/a.png';

  setUp(() async {
    h = await DownloadsHarness.create();
    live = h.server.url('/png');
    missing = h.server.url('/missing');
  });

  DownloadsService service() => h.container.read(downloadsServiceProvider);

  Future<Set<String>> storedInvalid(Mod mod) async => {
    for (final a in await h.assetsInStore(mod))
      if (a.invalid) a.url,
  };

  test('dead URLs left after a download are found and saved', () async {
    final mod = h.workshopMod('200001', saveName: 'Alpha');
    await h.indexMods(
      [mod],
      {
        mod.jsonPath: [(live, AssetType.image), (missing, AssetType.image)],
      },
    );
    final progress = h.recordProgress();
    await service().downloadMod(mod);
    final result = await service().validateDownload(mod);

    expect(result.cancelled, isFalse);
    expect(result.unreachableDomains, isEmpty);
    expect(result.invalidUrls, [missing]);
    expect(result.hasIssues, isTrue);
    expect(await storedInvalid(mod), {missing});
    expect(h.library.resummarizeCalls, contains(mod.jsonPath));
    expect(
      progress.map((p) => p.label),
      containsAll(['checking.domains', 'checking.urls']),
    );
    expect(h.runnerState, OperationState.idle);
  });

  test(
    'files on an unreachable host are reported and nothing is saved',
    () async {
      final mod = h.workshopMod('200002', saveName: 'Beta');
      await h.indexMods(
        [mod],
        {
          mod.jsonPath: [(missing, AssetType.image), (dead, AssetType.model)],
        },
      );
      await h.db.modsDao.setInvalidUrls(mod.jsonPath, [dead]);

      final result = await service().validateDownload(mod);
      expect(result.unreachableDomains, [deadHost]);
      expect(result.invalidUrls, [missing]);
      expect(await storedInvalid(mod), {dead});
      expect(
        h.logMessages,
        contains(startsWith('Domain is not reachable: $deadHost')),
      );
    },
  );

  test('nothing missing clears a stored invalid list', () async {
    final mod = h.workshopMod('200003', saveName: 'Gamma');
    await h.indexMods(
      [mod],
      {
        mod.jsonPath: [(live, AssetType.image)],
      },
    );
    await service().downloadMod(mod);
    await h.db.modsDao.setInvalidUrls(mod.jsonPath, [live]);
    final requestsBefore = h.server.requests.length;

    final result = await service().validateDownload(mod);
    expect(result.hasIssues, isFalse);
    expect(await storedInvalid(mod), isEmpty);
    // Nothing was missing, so nothing was requested.
    expect(h.server.requests, hasLength(requestsBefore));
  });

  test('saved objects are skipped', () async {
    final base = h.workshopMod('200004');
    final saved = base.copyWith(
      ref: ModRef.fromPath(
        ModType.savedObject,
        p.join(h.directories.savedObjectsDir, 'Thing.json'),
      ),
    );
    await h.indexMods(
      [saved],
      {
        saved.jsonPath: [(missing, AssetType.image)],
      },
    );
    final result = await service().validateDownload(saved);
    expect(result.hasIssues, isFalse);
    expect(h.server.requests, isEmpty);
  });

  test('the bulk download validates every mod, each host once', () async {
    final alpha = h.workshopMod('200005', saveName: 'Alpha');
    final beta = h.workshopMod('200006', saveName: 'Beta');
    await h.indexMods(
      [alpha, beta],
      {
        alpha.jsonPath: [(live, AssetType.image), (missing, AssetType.image)],
        beta.jsonPath: [(h.server.url('/missing/2'), AssetType.image)],
      },
    );
    final result = await h.container.read(bulkServiceProvider).downloadMods([
      alpha,
      beta,
    ]);

    expect(result.validations.map((v) => v.mod.displayName), ['Alpha', 'Beta']);
    expect(result.validations.first.invalidUrls, [missing]);
    expect(result.validations.last.invalidUrls, [h.server.url('/missing/2')]);
    expect(h.server.requestsTo('/'), hasLength(1));
    expect(await storedInvalid(beta), {h.server.url('/missing/2')});
  });

  test('with the setting off the bulk download checks nothing', () async {
    final alpha = h.workshopMod('200007', saveName: 'Alpha');
    await h.indexMods(
      [alpha],
      {
        alpha.jsonPath: [(missing, AssetType.image)],
      },
    );
    final options = h.container.read(networkOptionsProvider.notifier);
    await options.set(
      (await options.ensureLoaded()).copyWith(checkAfterDownload: false),
    );
    final result = await h.container.read(bulkServiceProvider).downloadMods([
      alpha,
    ]);
    expect(result.validations, isEmpty);
    expect(h.server.requestsTo('/'), isEmpty);
    expect(await storedInvalid(alpha), isEmpty);
  });
}
