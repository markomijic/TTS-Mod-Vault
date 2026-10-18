// UrlChecker liveness matrix against the loopback test server.

@Timeout(Duration(seconds: 60))
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_mod_vault/core/cancellation/cancellation_token.dart';
import 'package:tts_mod_vault/data/net/url_checker.dart';

import 'test_http_server.dart';

void main() {
  late TestHttpServer server;
  late Dio dio;
  late UrlChecker checker;

  setUp(() async {
    server = await TestHttpServer.start();
    dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 5)));
    checker = UrlChecker(dio: dio);
  });

  tearDown(() async {
    dio.close(force: true);
    await server.close();
  });

  test('a 200 asset is live after a single HEAD', () async {
    expect(await checker.isLive(server.url('/png')), isTrue);
    expect(server.requests, [(method: 'HEAD', path: '/png')]);
  });

  test('a 404 is dead (HEAD then ranged GET both tried)', () async {
    expect(await checker.isLive(server.url('/missing')), isFalse);
    expect(server.requests.map((r) => r.method).toList(), ['HEAD', 'GET']);
  });

  test('an HTML page with status 200 is dead', () async {
    expect(await checker.isLive(server.url('/html200')), isFalse);
  });

  test('a server rejecting HEAD is live through the ranged GET', () async {
    expect(await checker.isLive(server.url('/no-head')), isTrue);
    expect(server.requests.map((r) => r.method).toList(), ['HEAD', 'GET']);
    expect(server.requests.last.path, '/no-head');
  });

  test('a redirect to a live asset is live', () async {
    expect(await checker.isLive(server.url('/redirect')), isTrue);
  });

  test('a 5xx is dead', () async {
    expect(await checker.isLive(server.url('/server-error')), isFalse);
  });

  test('an unreachable host is dead', () async {
    expect(await checker.isLive('http://127.0.0.1:1/nothing'), isFalse);
  });

  test('a scheme-less URL is resolved (https probe, then http)', () async {
    final url = '${server.hostAndPort}/png';
    expect(await checker.resolveUrlWithScheme(url), 'http://$url');
    expect(await checker.isLive(url), isTrue);
  });

  test('a URL with a scheme is returned unchanged by the resolver', () async {
    expect(
      await checker.resolveUrlWithScheme('https://example.com/a'),
      'https://example.com/a',
    );
    expect(server.requests, isEmpty);
  });

  test(
    'a cancelled token makes isLive throw OperationCancelledException',
    () async {
      final token = CancellationToken()..cancel('stop');
      await expectLater(
        checker.isLive(server.url('/png'), token: token),
        throwsA(isA<OperationCancelledException>()),
      );
    },
  );
}
