// updateCheckProvider against the loopback releases stub.

@Timeout(Duration(seconds: 60))
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/data/net/dio_client.dart';
import 'package:tts_mod_vault/features/about/application/update_check.dart';

import '../../data/net/test_http_server.dart';

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

  ProviderContainer makeContainer(String currentVersion, {String? apiPath}) =>
      ProviderContainer.test(
        overrides: [
          dioProvider.overrideWithValue(dio),
          githubReleasesApiUrlProvider.overrideWithValue(
            server.url(apiPath ?? '/release'),
          ),
          currentAppVersionProvider.overrideWith((ref) async => currentVersion),
        ],
      );

  test('returns the newer version', () async {
    server.releaseTag = 'v3.2.0';
    final container = makeContainer('3.0.0');
    expect(await container.read(updateCheckProvider.future), '3.2.0');
  });

  test('returns null when up to date or ahead', () async {
    server.releaseTag = 'v3.2.0';
    expect(
      await makeContainer('3.2.0').read(updateCheckProvider.future),
      isNull,
    );
    expect(
      await makeContainer('3.3.0-dev').read(updateCheckProvider.future),
      isNull,
    );
  });

  test('returns null when the release lookup fails', () async {
    server.releaseTag = null;
    expect(
      await makeContainer('3.0.0').read(updateCheckProvider.future),
      isNull,
    );
    expect(
      await makeContainer(
        '3.0.0',
        apiPath: '/details-garbage',
      ).read(updateCheckProvider.future),
      isNull,
    );
    expect(server.requestsTo('/release'), hasLength(1));
  });
}
