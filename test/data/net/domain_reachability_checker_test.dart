// DomainReachabilityChecker against the loopback test server: any HTTP
// answer means reachable, connection failures mean unreachable, one request
// set per host, the one-minute cache and cancellation.

@Timeout(Duration(seconds: 60))
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_mod_vault/core/cancellation/cancellation_token.dart';
import 'package:tts_mod_vault/data/net/domain_reachability_checker.dart';

import 'test_http_server.dart';

void main() {
  late TestHttpServer server;
  late Dio dio;
  late DateTime now;
  late DomainReachabilityChecker checker;

  // Requests to this host fail at connection level (see _DeadHostAdapter);
  // a real refused port takes about 2 s per attempt on Windows.
  const deadUrl = 'http://dead.test/asset.png';

  setUp(() async {
    server = await TestHttpServer.start();
    dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 5)))
      ..httpClientAdapter = _DeadHostAdapter(IOHttpClientAdapter());
    now = DateTime(2026, 10, 24, 12);
    checker = DomainReachabilityChecker(dio: dio, clock: () => now);
  });

  tearDown(() async {
    dio.close(force: true);
    await server.close();
  });

  group('parseHttpUri / hostOf', () {
    test('keeps http and https URLs and lower-cases the host', () {
      expect(
        DomainReachabilityChecker.parseHttpUri('https://cdn.example/a.png'),
        Uri.parse('https://cdn.example/a.png'),
      );
      expect(DomainReachabilityChecker.hostOf('HTTP://CDN.Host/x'), 'cdn.host');
    });

    test('reads a scheme-less URL as https', () {
      expect(
        DomainReachabilityChecker.parseHttpUri('i.imgur.com/a.png')?.scheme,
        'https',
      );
      expect(
        DomainReachabilityChecker.hostOf('i.imgur.com/a.png'),
        'i.imgur.com',
      );
    });

    test('rejects other schemes and empty input', () {
      expect(DomainReachabilityChecker.parseHttpUri('file:///C:/a'), isNull);
      expect(DomainReachabilityChecker.parseHttpUri('ftp://host/a'), isNull);
      expect(DomainReachabilityChecker.parseHttpUri('   '), isNull);
    });
  });

  test(
    'a host answering 404 at its root is reachable after one HEAD',
    () async {
      expect(await checker.isReachable(Uri.parse(server.url('/png'))), isTrue);
      expect(server.requests, [(method: 'HEAD', path: '/')]);
    },
  );

  test('a refused connection is unreachable', () async {
    expect(await checker.isReachable(Uri.parse(deadUrl)), isFalse);
  });

  test('checkUrls checks each host once and sorts the result', () async {
    final result = await checker.checkUrls([
      deadUrl,
      server.url('/png'),
      server.url('/jpeg'),
      'http://DEAD.test/other.png',
      'file:///C:/local.png',
    ]);
    expect(result.cancelled, isFalse);
    expect(result.domains, [
      (domain: '127.0.0.1', reachable: true),
      (domain: 'dead.test', reachable: false),
    ]);
    expect(result.unreachable, ['dead.test']);
    expect(server.requests, hasLength(1));
  });

  test('no URLs with a host gives an empty result without requests', () async {
    final result = await checker.checkUrls(['', 'file:///x']);
    expect(result.domains, isEmpty);
    expect(result.cancelled, isFalse);
    expect(server.requests, isEmpty);
  });

  test('a result is reused for a minute, then refreshed', () async {
    final urls = [server.url('/png')];
    final progress = <(int, int)>[];
    await checker.checkUrls(urls, onProgress: (d, t) => progress.add((d, t)));
    expect(progress, [(0, 1), (1, 1)]);
    expect(server.requests, hasLength(1));

    now = now.add(const Duration(seconds: 59));
    progress.clear();
    final cached = await checker.checkUrls(
      urls,
      onProgress: (d, t) => progress.add((d, t)),
    );
    expect(cached.domains.single.reachable, isTrue);
    expect(progress, isEmpty);
    expect(server.requests, hasLength(1));

    await checker.checkUrls(urls, forceRefresh: true);
    expect(server.requests, hasLength(2));

    now = now.add(const Duration(minutes: 2));
    await checker.checkUrls(urls);
    expect(server.requests, hasLength(3));
  });

  test('an already cancelled token sends nothing and caches nothing', () async {
    final token = CancellationToken()..cancel('stop');
    final result = await checker.checkUrls([server.url('/png')], token: token);
    expect(result.cancelled, isTrue);
    expect(result.domains, isEmpty);
    expect(server.requests, isEmpty);

    final fresh = await checker.checkUrls([server.url('/png')]);
    expect(fresh.domains.single.reachable, isTrue);
    expect(server.requests, hasLength(1));
  });

  test('cancelling a request in flight ends the check as cancelled', () async {
    server.stallRoot = true;
    final token = CancellationToken();
    final pending = checker.checkUrls([server.url('/png')], token: token);
    while (server.requests.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    token.cancel('stop');
    final result = await pending;
    expect(result.cancelled, isTrue);
    expect(result.domains, isEmpty);
  });

  test('isReachable throws when its token is cancelled mid-request', () async {
    server.stallRoot = true;
    final token = CancellationToken();
    final pending = checker.isReachable(
      Uri.parse(server.url('/png')),
      token: token,
    );
    while (server.requests.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    token.cancel('stop');
    await expectLater(pending, throwsA(isA<OperationCancelledException>()));
  });
}

/// Fails every request to `dead.test` with a connection error, like a host
/// that is down; everything else goes to [_inner].
final class _DeadHostAdapter implements HttpClientAdapter {
  _DeadHostAdapter(this._inner);

  final HttpClientAdapter _inner;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    if (options.uri.host == 'dead.test') {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'host is down',
      );
    }
    return _inner.fetch(options, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) => _inner.close(force: force);
}
