// SteamWorkshopClient against the loopback test server's details endpoint.

@Timeout(Duration(seconds: 60))
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_mod_vault/core/cancellation/cancellation_token.dart';
import 'package:tts_mod_vault/data/net/steam_workshop_client.dart';
import 'package:tts_mod_vault/domain/constants.dart';

import 'test_http_server.dart';

void main() {
  late TestHttpServer server;
  late Dio dio;
  late SteamWorkshopClient client;

  setUp(() async {
    server = await TestHttpServer.start();
    dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 5)));
    client = SteamWorkshopClient(dio: dio, apiUrl: server.url('/details'));
    server.steamItems = {
      '111': {
        'title': 'Alpha',
        'file_url': server.url('/bson'),
        'preview_url': server.url('/preview'),
        'time_updated': 1700000000,
        'consumer_app_id': tabletopSimulatorAppId,
      },
      '222': {
        'title': 'Other Game',
        'file_url': server.url('/bson'),
        'time_updated': 1700000000,
        'consumer_app_id': 123,
      },
      '333': {'title': 'Unlisted', 'consumer_app_id': tabletopSimulatorAppId},
    };
  });

  tearDown(() async {
    dio.close(force: true);
    await server.close();
  });

  test('returns one entry per id in order with typed statuses', () async {
    final details = await client.getPublishedFileDetails([
      '111',
      '222',
      '333',
      '444',
    ]);
    expect(details.map((d) => d.id).toList(), ['111', '222', '333', '444']);
    expect(details[0].statusFor(), WorkshopItemStatus.ok);
    expect(details[0].title, 'Alpha');
    expect(details[0].fileUrl, server.url('/bson'));
    expect(details[0].previewUrl, server.url('/preview'));
    expect(details[0].timeUpdated, 1700000000);
    expect(details[0].consumerAppId, tabletopSimulatorAppId);
    expect(details[1].statusFor(), WorkshopItemStatus.wrongApp);
    expect(details[2].statusFor(), WorkshopItemStatus.unlisted);
    expect(details[3].statusFor(), WorkshopItemStatus.notFound);
    expect(details[3].result, 9);
    expect(server.requests, [(method: 'POST', path: '/details')]);
  });

  test('blank ids are dropped and an empty list makes no request', () async {
    expect(await client.getPublishedFileDetails(['', '  ']), isEmpty);
    expect(server.requests, isEmpty);
    final details = await client.getPublishedFileDetails([' 111 ']);
    expect(details.single.id, '111');
  });

  test('malformed JSON throws SteamWorkshopException', () async {
    client = SteamWorkshopClient(
      dio: dio,
      apiUrl: server.url('/details-garbage'),
    );
    await expectLater(
      client.getPublishedFileDetails(['111']),
      throwsA(isA<SteamWorkshopException>()),
    );
  });

  test('a non-200 answer throws SteamWorkshopException', () async {
    client = SteamWorkshopClient(dio: dio, apiUrl: server.url('/missing'));
    await expectLater(
      client.getPublishedFileDetails(['111']),
      throwsA(
        isA<SteamWorkshopException>().having(
          (e) => e.message,
          'message',
          contains('404'),
        ),
      ),
    );
  });

  test('download returns the bytes', () async {
    server.bsonBytes = [1, 2, 3, 4, 5];
    expect(await client.download(server.url('/bson')), [1, 2, 3, 4, 5]);
  });

  test('download of a 404 throws DioException', () async {
    await expectLater(
      client.download(server.url('/missing')),
      throwsA(isA<DioException>()),
    );
  });

  test('a cancelled token throws OperationCancelledException', () async {
    final token = CancellationToken()..cancel();
    await expectLater(
      client.getPublishedFileDetails(['111'], token: token),
      throwsA(isA<OperationCancelledException>()),
    );
    await expectLater(
      client.download(server.url('/bson'), token: token),
      throwsA(isA<OperationCancelledException>()),
    );
  });

  test(
    'WorkshopItemDetails.fromJson tolerates missing and stringly fields',
    () {
      final details = WorkshopItemDetails.fromJson({
        'publishedfileid': 123,
        'result': '1',
        'time_updated': '1700000000',
        'consumer_app_id': 286160.0,
        'file_url': '',
      });
      expect(details.id, '123');
      expect(details.result, 1);
      expect(details.timeUpdated, 1700000000);
      expect(details.consumerAppId, tabletopSimulatorAppId);
      expect(details.fileUrl, isNull);
      expect(details.statusFor(), WorkshopItemStatus.unlisted);
      expect(
        WorkshopItemDetails.fromJson(const {}, fallbackId: 'x').statusFor(),
        WorkshopItemStatus.notFound,
      );
    },
  );
}
