// Workshop operations through the WorkshopService against the loopback
// Steam stub: download by id, update with the 60 s tolerance, force.

@Timeout(Duration(seconds: 60))
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:bson/bson.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/core/logging/app_log.dart';
import 'package:tts_mod_vault/domain/constants.dart';
import 'package:tts_mod_vault/features/operations/application/operation_runner.dart';
import 'package:tts_mod_vault/features/workshop/application/workshop_service.dart';

import '../downloads/downloads_test_harness.dart';

const int steamEpoch = 1700000000;

void main() {
  late DownloadsHarness h;

  Map<String, Object?> okItem(String title) => {
    'title': title,
    'file_url': h.server.url('/bson'),
    'preview_url': h.server.url('/preview'),
    'time_updated': steamEpoch,
    'consumer_app_id': tabletopSimulatorAppId,
  };

  setUp(() async {
    h = await DownloadsHarness.create();
    h.server.bsonBytes = BsonCodec.serialize({
      'SaveName': 'Local Name',
      'GameMode': 'Chess',
      'ObjectStates': <Object?>[],
    }).byteList;
    h.server.steamItems = {
      '111': okItem('Alpha From Steam'),
      '222': {
        'title': 'Other Game',
        'file_url': h.server.url('/bson'),
        'time_updated': steamEpoch,
        'consumer_app_id': 123,
      },
      '333': {'title': 'Unlisted', 'consumer_app_id': tabletopSimulatorAppId},
      '555': {
        'title': 'Broken File',
        'file_url': h.server.url('/missing'),
        'preview_url': h.server.url('/preview'),
        'time_updated': steamEpoch,
        'consumer_app_id': tabletopSimulatorAppId,
      },
    };
  });

  WorkshopService service() => h.container.read(workshopServiceProvider);

  Map<String, Object?> readJson(String path) =>
      jsonDecode(h.fs.file(path).readAsStringSync()) as Map<String, Object?>;

  group('downloadByIds', () {
    test('happy path writes JSON with EpochTime and title, a square preview, '
        'and refreshes the library', () async {
      final progress = h.recordProgress();
      final result = await service().downloadByIds([
        '111',
      ], targetDir: h.directories.workshopDir);

      expect(result.total, 1);
      expect(result.successCount, 1);
      final item = result.results.single;
      expect(item.status, WorkshopItemStatus.ok);
      expect(item.isSuccess, isTrue);
      expect(item.title, 'Alpha From Steam');
      final jsonPath = p.normalize(
        p.join(h.directories.workshopDir, '111.json'),
      );
      expect(item.jsonPath, jsonPath);

      final json = readJson(jsonPath);
      expect(json.keys.toList(), [
        'SaveName',
        'EpochTime',
        'GameMode',
        'ObjectStates',
      ]);
      expect(json['SaveName'], 'Alpha From Steam');
      expect(json['EpochTime'], steamEpoch);

      final pngPath = p.join(h.directories.workshopDir, '111.png');
      final preview = img.decodePng(
        Uint8List.fromList(h.fs.file(pngPath).readAsBytesSync()),
      )!;
      expect(preview.width, 256);
      expect(preview.height, 256);

      expect(h.library.refreshModCalls, [jsonPath]);
      expect(h.runnerState, OperationState.idle);
      expect(progress.map((p) => p.label).toSet(), {
        'workshop.fetchingDetails',
        'workshop.downloading',
      });
      expect(progress.last.value, 1.0);
      expect(progress.where((p) => p.detail == 'Alpha From Steam'), isNotEmpty);
      final summary = h.log.store.entries.lastWhere(
        (e) => e.message.startsWith('Downloaded 1/1'),
      );
      expect(summary.level, LogLevel.success);
      expect(summary.message, 'Downloaded 1/1 Workshop item(s)');
    });

    test('wrong app id, unlisted, not found and a failing file download are '
        'typed failures', () async {
      final result = await service().downloadByIds([
        '111',
        '222',
        '333',
        '444',
        '555',
        ' ',
      ], targetDir: h.directories.workshopDir);
      expect(result.total, 5);
      expect(result.successCount, 1);
      expect(result.failedCount, 4);
      final byId = {for (final r in result.results) r.id: r};
      expect(byId['222']!.status, WorkshopItemStatus.wrongApp);
      expect(byId['222']!.isSuccess, isFalse);
      expect(byId['333']!.status, WorkshopItemStatus.unlisted);
      expect(byId['444']!.status, WorkshopItemStatus.notFound);
      expect(byId['555']!.status, WorkshopItemStatus.ok);
      expect(byId['555']!.isSuccess, isFalse);
      expect(byId['555']!.error, contains('404'));

      expect(
        h.fs.file(p.join(h.directories.workshopDir, '222.json')).existsSync(),
        isFalse,
      );
      expect(
        h.fs.file(p.join(h.directories.workshopDir, '555.json')).existsSync(),
        isFalse,
      );
      expect(h.library.refreshModCalls, hasLength(1));
      // One details call for every id.
      expect(h.server.requestsTo('/details'), hasLength(1));
      final summary = h.log.store.entries.lastWhere(
        (e) => e.message.startsWith('Downloaded 1/5'),
      );
      expect(summary.level, LogLevel.warning);
      expect(summary.message, 'Downloaded 1/5 Workshop item(s), 4 failed');
      expect(summary.details, contains('[222]'));
    });

    test('a missing preview image does not fail the item', () async {
      h.server.steamItems['111'] = {
        ...okItem('No Preview'),
        'preview_url': h.server.url('/missing'),
      };
      final result = await service().downloadByIds([
        '111',
      ], targetDir: h.directories.workshopDir);
      expect(result.successCount, 1);
      expect(
        h.fs.file(p.join(h.directories.workshopDir, '111.png')).existsSync(),
        isFalse,
      );
      expect(
        h.logMessages,
        contains('Preview image of 111 could not be downloaded'),
      );
    });

    test('creates the target folder and preserves the JSON creation time '
        'semantics (overwrite in place)', () async {
      final target = p.join(h.directories.modsDir, 'Fresh');
      final existing = h.fs.file(p.join(target, '111.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync('old');
      final result = await service().downloadByIds(['111'], targetDir: target);
      expect(result.successCount, 1);
      expect(existing.readAsStringSync(), isNot('old'));
      expect(readJson(existing.path)['SaveName'], 'Alpha From Steam');
    });

    test('empty id list does nothing', () async {
      final result = await service().downloadByIds([
        '',
        '  ',
      ], targetDir: h.directories.workshopDir);
      expect(result.total, 0);
      expect(h.server.requests, isEmpty);
    });
  });

  group('updateMods', () {
    test(
      'skips a mod within the 60 s tolerance and updates an older one',
      () async {
        final fresh = h.workshopMod(
          '111',
          saveName: 'Fresh',
          epochTime: steamEpoch - 30,
        );
        h.server.steamItems['666'] = okItem('Stale From Steam');
        final stale = h.workshopMod(
          '666',
          saveName: 'Stale',
          epochTime: steamEpoch - 100,
        );
        final ahead = h.workshopMod(
          '777',
          saveName: 'Ahead',
          epochTime: steamEpoch + 500,
        );
        h.server.steamItems['777'] = okItem('Ahead From Steam');
        await h.indexMods([fresh, stale, ahead], const {});

        final result = await service().updateMods([fresh, stale, ahead]);
        expect(result.total, 3);
        expect(result.updatedCount, 1);
        expect(result.upToDateCount, 2);
        final byId = {for (final r in result.results) r.id: r};
        expect(byId['111']!.status, WorkshopUpdateStatus.upToDate);
        expect(byId['777']!.status, WorkshopUpdateStatus.upToDate);
        expect(byId['666']!.status, WorkshopUpdateStatus.updated);
        expect(byId['666']!.modName, 'Stale');

        expect(h.fs.file(fresh.jsonPath).existsSync(), isFalse);
        expect(h.fs.file(stale.jsonPath).existsSync(), isTrue);
        expect(readJson(stale.jsonPath)['SaveName'], 'Stale From Steam');
        expect(readJson(stale.jsonPath)['EpochTime'], steamEpoch);
        expect(h.library.refreshModCalls, [stale.jsonPath]);
        expect(h.server.requestsTo('/bson'), hasLength(1));
        expect(h.server.requestsTo('/details'), hasLength(1));
        expect(
          h.logMessages,
          contains('Updated 1/3 Workshop mod(s), 2 already up to date'),
        );
      },
    );

    test('force updates even when Steam is not newer', () async {
      final fresh = h.workshopMod(
        '111',
        saveName: 'Fresh',
        epochTime: steamEpoch,
      );
      await h.indexMods([fresh], const {});
      final result = await service().updateMods([fresh], force: true);
      expect(result.results.single.status, WorkshopUpdateStatus.updated);
      expect(h.fs.file(fresh.jsonPath).existsSync(), isTrue);
    });

    test('a mod with no EpochTime counts as outdated', () async {
      final undated = h.workshopMod('111', saveName: 'Undated');
      await h.indexMods([undated], const {});
      final result = await service().updateMods([undated]);
      expect(result.results.single.status, WorkshopUpdateStatus.updated);
    });

    test('items Steam cannot serve fail with the item status', () async {
      final wrong = h.workshopMod('222', saveName: 'Wrong', epochTime: 1);
      final unlisted = h.workshopMod('333', saveName: 'Unlisted', epochTime: 1);
      final gone = h.workshopMod('444', saveName: 'Gone', epochTime: 1);
      await h.indexMods([wrong, unlisted, gone], const {});
      final result = await service().updateMods([wrong, unlisted, gone]);
      expect(result.failedCount, 3);
      final byId = {for (final r in result.results) r.id: r};
      expect(byId['222']!.itemStatus, WorkshopItemStatus.wrongApp);
      expect(byId['333']!.itemStatus, WorkshopItemStatus.unlisted);
      expect(byId['444']!.itemStatus, WorkshopItemStatus.notFound);
      expect(byId['333']!.error, contains('unlisted'));
      expect(h.library.refreshModCalls, isEmpty);
      expect(
        h.log.store.entries
            .lastWhere((e) => e.message.startsWith('Updated 0/3'))
            .level,
        LogLevel.warning,
      );
    });

    test('a details endpoint failure fails every mod as invalid', () async {
      h = await DownloadsHarness.create(steamDetailsPath: '/details-garbage');
      final mod = h.workshopMod('111', saveName: 'X', epochTime: 1);
      await h.indexMods([mod], const {});
      final result = await service().updateMods([mod]);
      expect(result.failedCount, 1);
      expect(result.results.single.itemStatus, WorkshopItemStatus.invalid);
      expect(h.server.requestsTo('/bson'), isEmpty);
      expect(h.logMessages, contains('Could not fetch Workshop item details'));
      expect(h.runnerState, OperationState.idle);
    });

    test('empty mod list does nothing', () async {
      final result = await service().updateMods(const []);
      expect(result.total, 0);
      expect(h.server.requests, isEmpty);
    });
  });

  test('result models expose counts', () {
    final batch = WorkshopDownloadBatchResult([
      const WorkshopDownloadResult(
        id: '1',
        status: WorkshopItemStatus.ok,
        jsonPath: 'x',
      ),
      const WorkshopDownloadResult(
        id: '2',
        status: WorkshopItemStatus.notFound,
      ),
      const WorkshopDownloadResult(
        id: '3',
        status: WorkshopItemStatus.ok,
        cancelled: true,
      ),
    ]);
    expect(batch.successCount, 1);
    expect(batch.failedCount, 1);
    expect(batch.cancelledCount, 1);
    expect(batch.wasCancelled, isTrue);
    expect(batch.results[0].displayName, '1');
    final updates = WorkshopUpdateBatchResult([
      for (final status in WorkshopUpdateStatus.values)
        WorkshopUpdateResult(
          id: status.name,
          modName: status.name,
          jsonPath: 'p',
          status: status,
        ),
    ]);
    expect(updates.updatedCount, 1);
    expect(updates.upToDateCount, 1);
    expect(updates.failedCount, 1);
    expect(updates.cancelledCount, 1);
  });
}
