// AssetDownloader against a real loopback HttpServer, writing into a
// MemoryFileSystem.

@Timeout(Duration(seconds: 60))
library;

import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/core/cancellation/cancellation_token.dart';
import 'package:tts_mod_vault/core/logging/app_log.dart';
import 'package:tts_mod_vault/data/net/asset_downloader.dart';
import 'package:tts_mod_vault/domain/enums/asset_type.dart';
import 'package:tts_mod_vault/domain/rules/file_key.dart';

import 'test_http_server.dart';

void main() {
  late TestHttpServer server;
  late MemoryFileSystem fs;
  late AppLog log;
  late Dio dio;
  late AssetDownloader downloader;
  late String imagesDir;

  setUp(() async {
    server = await TestHttpServer.start();
    fs = MemoryFileSystem(
      style: Platform.isWindows
          ? FileSystemStyle.windows
          : FileSystemStyle.posix,
    );
    imagesDir = fs.path.join(fs.currentDirectory.path, 'Mods', 'Images');
    fs.directory(imagesDir).createSync(recursive: true);
    log = AppLog(store: LogStore());
    dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 5)));
    downloader = AssetDownloader(
      dio: dio,
      fs: fs,
      log: log,
      retryDelays: const [
        Duration(milliseconds: 5),
        Duration(milliseconds: 5),
        Duration(milliseconds: 5),
      ],
    );
  });

  tearDown(() async {
    dio.close(force: true);
    await server.close();
    await log.dispose();
  });

  DownloadRequest image(String url, {String? dir}) => DownloadRequest(
    url: url,
    type: AssetType.image,
    targetDir: dir ?? imagesDir,
  );

  Future<(DownloadBatchResult, List<DownloadBatchProgress>)> run(
    List<DownloadRequest> requests, {
    int concurrency = 3,
    List<String> ignoredDomains = const [],
    CancellationToken? token,
  }) async {
    final progress = <DownloadBatchProgress>[];
    final result = await downloader.downloadAll(
      requests: requests,
      concurrency: concurrency,
      ignoredDomains: ignoredDomains,
      token: token ?? CancellationToken(),
      onProgress: progress.add,
    );
    return (result, progress);
  }

  List<String> filesIn(String dir) => [
    for (final entity in fs.directory(dir).listSync()) p.basename(entity.path),
  ]..sort();

  void expectMonotonicEndingAtOne(List<DownloadBatchProgress> progress) {
    expect(progress, isNotEmpty);
    for (var i = 1; i < progress.length; i++) {
      expect(
        progress[i].fraction,
        greaterThanOrEqualTo(progress[i - 1].fraction),
        reason:
            'progress decreased at $i: ${progress[i - 1]} -> ${progress[i]}',
      );
    }
    expect(progress.last.fraction, 1.0);
    expect(progress.last.done, progress.last.total);
  }

  test('downloads a PNG to <fileName>.png and leaves no temp file', () async {
    final url = server.url('/png');
    final (result, progress) = await run([image(url)]);

    expect(result.downloadedCount, 1);
    final outcome = result.outcomes.single;
    expect(outcome.status, DownloadStatus.downloaded);
    expect(outcome.fileKey, fileKeyFromUrl(url));
    expect(p.basename(outcome.path!), '${fileNameFromUrl(url)}.png');
    expect(fs.file(outcome.path!).readAsBytesSync(), pngBytes);
    expect(filesIn(imagesDir), ['${fileNameFromUrl(url)}.png']);
    expectMonotonicEndingAtOne(progress);
  });

  test('byte progress of a large file is monotonic and ends at 1.0', () async {
    final (result, progress) = await run([image(server.url('/big'))]);
    expect(result.downloadedCount, 1);
    expectMonotonicEndingAtOne(progress);
    // Intermediate byte fractions were reported, not just 0 and 1.
    expect(progress.where((p) => p.fraction > 0 && p.fraction < 1), isNotEmpty);
  });

  test('picks the extension from the content, not the URL', () async {
    final jpegUrl = server.url('/octet-jpeg');
    final oggUrl = server.url('/audio/song.mp3');
    final audioDir = fs.path.join(fs.currentDirectory.path, 'Mods', 'Audio');
    final (result, _) = await run([
      image(jpegUrl),
      DownloadRequest(url: oggUrl, type: AssetType.audio, targetDir: audioDir),
    ]);

    expect(result.downloadedCount, 2);
    expect(p.extension(result.outcomes[0].path!), '.jpg');
    expect(p.extension(result.outcomes[1].path!), '.ogg');
    expect(fs.directory(audioDir).existsSync(), isTrue);
  });

  test('skips URLs whose host matches an ignored domain', () async {
    final (result, progress) = await run(
      [image(server.url('/png'))],
      ignoredDomains: ['127.0.0.1'],
    );
    expect(result.outcomes.single.status, DownloadStatus.skippedIgnoredDomain);
    expect(result.skippedCount, 1);
    expect(server.requests, isEmpty);
    expect(filesIn(imagesDir), isEmpty);
    expectMonotonicEndingAtOne(progress);
  });

  test('an HTML page with status 200 is a failure and the temp file is '
      'deleted', () async {
    final (result, _) = await run([
      image(server.url('/html200')),
      image(server.url('/doctype')),
    ]);
    expect(result.outcomes[0].status, DownloadStatus.htmlErrorPage);
    expect(result.outcomes[1].status, DownloadStatus.htmlErrorPage);
    expect(result.failedCount, 2);
    expect(filesIn(imagesDir), isEmpty);
    final errors = log.store.entries.where((e) => e.level == LogLevel.error);
    expect(errors, hasLength(2));
    expect(errors.first.message, contains('HTML page'));
    expect(errors.first.url, server.url('/html200'));
  });

  test('a 404 fails with the status and is logged, without retrying', () async {
    final url = server.url('/missing');
    final (result, progress) = await run([image(url)]);
    final outcome = result.outcomes.single;
    expect(outcome.status, DownloadStatus.failed);
    expect(outcome.httpStatus, 404);
    expect(server.requestsTo('/missing'), hasLength(1));
    expect(filesIn(imagesDir), isEmpty);
    expectMonotonicEndingAtOne(progress);
    final error = log.store.entries.singleWhere(
      (e) => e.level == LogLevel.error,
    );
    expect(error.message, 'Download failed (404 Not Found): $url');
    expect(error.source, LogSource.download);
    expect(error.url, url);
  });

  test('retries 5xx with back-off and succeeds', () async {
    server.flakyFailures = 2;
    final (result, progress) = await run([image(server.url('/flaky'))]);
    expect(result.outcomes.single.status, DownloadStatus.downloaded);
    expect(server.flakyCalls, 3);
    expect(filesIn(imagesDir), hasLength(1));
    expectMonotonicEndingAtOne(progress);
    final retries = log.store.entries.where(
      (e) => e.message.startsWith('Retrying download'),
    );
    expect(retries, hasLength(2));
  });

  test('gives up after the last retry on a persistent 5xx', () async {
    server.flakyFailures = 100;
    final (result, _) = await run([image(server.url('/flaky'))]);
    final outcome = result.outcomes.single;
    expect(outcome.status, DownloadStatus.failed);
    expect(outcome.httpStatus, 500);
    expect(server.flakyCalls, 4);
    expect(filesIn(imagesDir), isEmpty);
  });

  test('retries a Steam URL with a trailing slash after a 404', () async {
    downloader = AssetDownloader(
      dio: dio,
      fs: fs,
      log: log,
      steamUserContentUrl: server.url('/steam/'),
    );
    final url = server.url('/steam/ugc123');
    final (result, _) = await run([image(url)]);
    expect(result.outcomes.single.status, DownloadStatus.downloaded);
    expect(server.requests.map((r) => r.path).toList(), [
      '/steam/ugc123',
      '/steam/ugc123/',
    ]);
    expect(
      p.basename(result.outcomes.single.path!),
      '${fileNameFromUrl(url)}.png',
    );
  });

  test('does not add a trailing slash for non-Steam hosts', () async {
    final (result, _) = await run([image(server.url('/steam/ugc123'))]);
    expect(result.outcomes.single.status, DownloadStatus.failed);
    expect(server.requests.map((r) => r.path).toList(), ['/steam/ugc123']);
  });

  test('resolves a scheme-less URL before downloading', () async {
    final url = '${server.hostAndPort}/png/noscheme';
    final (result, _) = await run([image(url)]);
    expect(result.outcomes.single.status, DownloadStatus.downloaded);
    expect(
      p.basename(result.outcomes.single.path!),
      '${fileNameFromUrl(url)}.png',
    );
  });

  test('respects the concurrency bound', () async {
    final requests = [
      for (var i = 0; i < 6; i++) image(server.url('/delay/80/$i')),
    ];
    final (result, _) = await run(requests, concurrency: 2);
    expect(result.downloadedCount, 6);
    expect(server.maxConcurrentRequests, 2);
  });

  test('a duplicate file name within a batch is skipped', () async {
    final url = server.url('/png');
    final (result, _) = await run([image(url), image(url)]);
    expect(result.outcomes[0].status, DownloadStatus.downloaded);
    expect(result.outcomes[1].status, DownloadStatus.skippedExists);
    expect(server.requestsTo('/png'), hasLength(1));
  });

  test('cancellation mid-batch marks the rest cancelled and leaves no temp '
      'files', () async {
    final token = CancellationToken();
    final pending = run(
      [
        image(server.url('/slow/1')),
        image(server.url('/slow/2')),
        image(server.url('/png/3')),
        image(server.url('/png/4')),
      ],
      concurrency: 2,
      token: token,
    );
    // Wait until both slow downloads are in flight, then cancel.
    while (server.requestsTo('/slow/1').isEmpty ||
        server.requestsTo('/slow/2').isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    token.cancel('test');

    final (result, progress) = await pending.timeout(
      const Duration(seconds: 10),
    );
    expect(
      result.outcomes.map((o) => o.status),
      everyElement(DownloadStatus.cancelled),
    );
    expect(result.cancelledCount, 4);
    expect(result.wasCancelled, isTrue);
    expect(filesIn(imagesDir), isEmpty);
    expect(server.requestsTo('/png/3'), isEmpty);
    expectMonotonicEndingAtOne(progress);
    expect(
      log.store.entries.where(
        (e) => e.message.startsWith('Download cancelled'),
      ),
      hasLength(1),
    );
  });

  test('an already cancelled token downloads nothing', () async {
    final token = CancellationToken()..cancel();
    final (result, _) = await run([image(server.url('/png'))], token: token);
    expect(result.outcomes.single.status, DownloadStatus.cancelled);
    expect(server.requests, isEmpty);
  });

  test('empty batch returns the empty result', () async {
    final (result, progress) = await run(const []);
    expect(result.total, 0);
    expect(progress, isEmpty);
  });

  test('isRetryableDioError classifies like v2', () {
    final options = RequestOptions(path: 'x');
    DioException withStatus(int status) => DioException.badResponse(
      statusCode: status,
      requestOptions: options,
      response: Response<void>(requestOptions: options, statusCode: status),
    );
    expect(AssetDownloader.isRetryableDioError(withStatus(500)), isTrue);
    expect(AssetDownloader.isRetryableDioError(withStatus(503)), isTrue);
    expect(AssetDownloader.isRetryableDioError(withStatus(404)), isFalse);
    expect(AssetDownloader.isRetryableDioError(withStatus(403)), isFalse);
    expect(
      AssetDownloader.isRetryableDioError(
        DioException.connectionTimeout(
          timeout: const Duration(seconds: 1),
          requestOptions: options,
        ),
      ),
      isTrue,
    );
    expect(
      AssetDownloader.isRetryableDioError(
        DioException.receiveTimeout(
          timeout: const Duration(seconds: 1),
          requestOptions: options,
        ),
      ),
      isTrue,
    );
    expect(
      AssetDownloader.isRetryableDioError(
        DioException.connectionError(requestOptions: options, reason: 'x'),
      ),
      isTrue,
    );
    expect(
      AssetDownloader.isRetryableDioError(
        DioException.requestCancelled(requestOptions: options, reason: 'x'),
      ),
      isFalse,
    );
  });
}
