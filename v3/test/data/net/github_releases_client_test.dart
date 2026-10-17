// latestReleaseVersion against the loopback test server.

@Timeout(Duration(seconds: 60))
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_mod_vault/data/net/github_releases_client.dart';

import 'test_http_server.dart';

void main() {
  late TestHttpServer server;
  late Dio dio;

  setUp(() async {
    server = await TestHttpServer.start();
    dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 5)));
  });

  tearDown(() async {
    dio.close(force: true);
    await server.close();
  });

  test('returns the tag without its leading v', () async {
    server.releaseTag = 'v3.2.0';
    expect(
      await latestReleaseVersion(dio, apiUrl: server.url('/release')),
      '3.2.0',
    );
    server.releaseTag = '4.0.1';
    expect(
      await latestReleaseVersion(dio, apiUrl: server.url('/release')),
      '4.0.1',
    );
  });

  test('returns null on a non-200 answer', () async {
    server.releaseTag = null;
    expect(
      await latestReleaseVersion(dio, apiUrl: server.url('/release')),
      isNull,
    );
  });

  test('returns null on a body without tag_name or a network error', () async {
    expect(
      await latestReleaseVersion(dio, apiUrl: server.url('/details-garbage')),
      isNull,
    );
    expect(
      await latestReleaseVersion(dio, apiUrl: 'http://127.0.0.1:1/release'),
      isNull,
    );
  });
}
