/// Downloads asset files for a mod. Port of v2 `DownloadNotifier.downloadFiles`
/// and its helpers (`_downloadUrlWithRetry`, `_isRetryableDioError`, the
/// Steam trailing-slash fallback, HTML error-page detection).
///
/// Temp-file strategy: the response is streamed by this class into the
/// injected `FileSystem` at `<targetDir>/<fileName>_temp` (instead of
/// `dio.download`, which writes through `dart:io` and would bypass a
/// `MemoryFileSystem` in tests). The first 512 bytes are kept in memory for
/// the HTML check and the extension sniff; on success the temp file is
/// renamed to `<fileName><extension>`, on any failure it is deleted.
library;

import 'dart:async';
import 'dart:math' show min;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file/file.dart';
import 'package:tts_mod_vault/core/cancellation/cancellation_token.dart';
import 'package:tts_mod_vault/core/logging/app_log.dart';
import 'package:tts_mod_vault/data/net/url_checker.dart';
import 'package:tts_mod_vault/domain/constants.dart';
import 'package:tts_mod_vault/domain/enums/asset_type.dart';
import 'package:tts_mod_vault/domain/parsing/asset_extension.dart';
import 'package:tts_mod_vault/domain/rules/file_key.dart';

/// One file to download: the asset's [url], its [type] (decides the
/// extension) and the cache folder to put it in.
final class DownloadRequest {
  /// Creates a request.
  const DownloadRequest({
    required this.url,
    required this.type,
    required this.targetDir,
  });

  /// The asset URL as written in the mod JSON (scheme may be missing).
  final String url;

  /// The asset's type.
  final AssetType type;

  /// Folder the file is written to (`Mods/Images`, ...).
  final String targetDir;

  @override
  String toString() => 'DownloadRequest(${type.name} $url -> $targetDir)';
}

/// How a [DownloadRequest] ended.
enum DownloadStatus {
  /// The file is on disk at `DownloadOutcome.path`.
  downloaded,

  /// The URL's host matched an ignored domain; nothing was requested.
  skippedIgnoredDomain,

  /// Another request of the same batch produced the same file.
  skippedExists,

  /// The request failed (HTTP error, network error, write error).
  failed,

  /// The batch was cancelled before or while this file was downloading.
  cancelled,

  /// The server answered with an HTML page instead of the asset.
  htmlErrorPage;

  /// Whether the file ended up on disk.
  bool get isSuccess => this == downloaded;
}

/// Result of one [DownloadRequest].
final class DownloadOutcome {
  /// Creates an outcome.
  const DownloadOutcome({
    required this.url,
    required this.type,
    required this.status,
    this.path,
    this.fileKey,
    this.httpStatus,
    this.error,
  });

  /// The request's URL.
  final String url;

  /// The request's asset type.
  final AssetType type;

  /// How it ended.
  final DownloadStatus status;

  /// Final path of the file when [status] is [DownloadStatus.downloaded].
  final String? path;

  /// `fileKeyFromUrl(url)`: the key for the `existing_files` index.
  final String? fileKey;

  /// HTTP status of the failing response, if there was one.
  final int? httpStatus;

  /// Error description for failures.
  final String? error;

  @override
  String toString() =>
      'DownloadOutcome(${status.name} ${type.name} $url'
      '${path == null ? '' : ' -> $path'}'
      '${httpStatus == null ? '' : ' http=$httpStatus'}'
      '${error == null ? '' : ' error=$error'})';
}

/// Progress of a running batch: files finished (any status) over files in
/// the batch, plus the byte-level [fraction] of the whole batch.
final class DownloadBatchProgress {
  /// Creates a snapshot.
  const DownloadBatchProgress({
    required this.done,
    required this.total,
    required this.fraction,
  });

  /// Requests that finished (downloaded, skipped, failed or cancelled).
  final int done;

  /// Requests in the batch.
  final int total;

  /// `(done + sum of in-flight byte fractions) / total`, clamped to `0..1`
  /// and never decreasing within a batch.
  final double fraction;

  @override
  String toString() =>
      'DownloadBatchProgress($done/$total ${(fraction * 100).round()}%)';
}

/// Every outcome of a batch with the counts the UI and the log summarise.
final class DownloadBatchResult {
  /// Creates a result from its outcomes.
  DownloadBatchResult(List<DownloadOutcome> outcomes)
    : outcomes = List.unmodifiable(outcomes);

  /// Result for an empty batch.
  static final DownloadBatchResult empty = DownloadBatchResult(const []);

  /// Outcomes in request order.
  final List<DownloadOutcome> outcomes;

  /// Requests in the batch.
  int get total => outcomes.length;

  /// Files written.
  int get downloadedCount => _count(DownloadStatus.downloaded);

  /// Requests that failed, HTML error pages included.
  int get failedCount =>
      _count(DownloadStatus.failed) + _count(DownloadStatus.htmlErrorPage);

  /// Requests skipped because of an ignored domain or a duplicate.
  int get skippedCount =>
      _count(DownloadStatus.skippedIgnoredDomain) +
      _count(DownloadStatus.skippedExists);

  /// Requests that did not run or were interrupted by cancellation.
  int get cancelledCount => _count(DownloadStatus.cancelled);

  /// Whether any request was cancelled.
  bool get wasCancelled => cancelledCount > 0;

  /// The downloaded outcomes.
  Iterable<DownloadOutcome> get downloaded =>
      outcomes.where((o) => o.status == DownloadStatus.downloaded);

  /// The failed outcomes (HTML error pages included).
  Iterable<DownloadOutcome> get failed => outcomes.where(
    (o) =>
        o.status == DownloadStatus.failed ||
        o.status == DownloadStatus.htmlErrorPage,
  );

  /// Concatenates several results (per-type batches of one operation).
  DownloadBatchResult merge(DownloadBatchResult other) =>
      DownloadBatchResult([...outcomes, ...other.outcomes]);

  int _count(DownloadStatus status) =>
      outcomes.where((o) => o.status == status).length;

  @override
  String toString() =>
      'DownloadBatchResult(total=$total downloaded=$downloadedCount '
      'failed=$failedCount skipped=$skippedCount cancelled=$cancelledCount)';
}

/// Downloads asset files with a bounded worker pool, retries and progress.
final class AssetDownloader {
  /// Creates a downloader writing through [fs] and logging failures to
  /// [log]. [steamUserContentUrl] is the host prefix that gets the
  /// trailing-slash retry on 404 (tests point it at a local server).
  AssetDownloader({
    required this.dio,
    required this.fs,
    required this.log,
    this.steamUserContentUrl = newSteamUserContentUrl,
    this.retryDelays = defaultRetryDelays,
  }) : _checker = UrlChecker(dio: dio);

  /// Back-off between attempts: 500 ms, 1 s, 2 s (so 4 attempts at most).
  static const List<Duration> defaultRetryDelays = [
    Duration(milliseconds: 500),
    Duration(milliseconds: 1000),
    Duration(milliseconds: 2000),
  ];

  /// Suffix of the temp file a download is streamed into.
  static const String tempSuffix = '_temp';

  /// Idle time between two chunks after which a download fails with a
  /// receive timeout (and is retried).
  static const Duration receiveTimeout = Duration(seconds: 60);

  /// Bytes kept in memory for the HTML check and the extension sniff.
  static const int headerBytesLength = 512;

  /// Bytes inspected for `<html>` / `<!DOCTYPE`.
  static const int htmlProbeLength = 100;

  /// The HTTP client.
  final Dio dio;

  /// The file system files are written to.
  final FileSystem fs;

  /// Where failures, retries and skips are logged.
  final AppLog log;

  /// URLs starting with this prefix get the trailing-slash retry on 404.
  final String steamUserContentUrl;

  /// Delays between attempts; `retryDelays.length + 1` attempts are made.
  final List<Duration> retryDelays;

  final UrlChecker _checker;

  /// Downloads every request with at most [concurrency] in flight.
  ///
  /// Requests whose host contains one of [ignoredDomains] are skipped;
  /// requests that duplicate an earlier request's file name are skipped as
  /// [DownloadStatus.skippedExists]. Cancelling [token] aborts in-flight
  /// downloads (their temp files are deleted) and marks every request not
  /// yet finished as [DownloadStatus.cancelled]. [onProgress] is called on
  /// every change; its fraction ends at 1.0 whenever the batch returns.
  /// Never throws for a single file's failure.
  Future<DownloadBatchResult> downloadAll({
    required List<DownloadRequest> requests,
    required int concurrency,
    required List<String> ignoredDomains,
    required CancellationToken token,
    required void Function(DownloadBatchProgress progress) onProgress,
    String? modPath,
    String? operationId,
  }) async {
    if (requests.isEmpty) return DownloadBatchResult.empty;
    final total = requests.length;
    final outcomes = List<DownloadOutcome?>.filled(total, null);
    final progressByJob = <int, double>{};
    var completed = 0;
    var lastFraction = 0.0;
    final seenFileNames = <String>{};

    void publish() {
      var fractional = 0.0;
      for (final value in progressByJob.values) {
        fractional += value;
      }
      final raw = ((completed + fractional) / total).clamp(0.0, 1.0);
      // A retry restarts a file's bytes from zero; keep the bar monotonic.
      if (raw > lastFraction) lastFraction = raw;
      onProgress(
        DownloadBatchProgress(
          done: completed,
          total: total,
          fraction: lastFraction,
        ),
      );
    }

    Future<void> processOne(int index) async {
      final request = requests[index];
      try {
        outcomes[index] = await _downloadOne(
          request,
          ignoredDomains: ignoredDomains,
          token: token,
          seenFileNames: seenFileNames,
          onFraction: (fraction) {
            final previous = progressByJob[index] ?? 0.0;
            if (fraction > previous) {
              progressByJob[index] = fraction;
              publish();
            }
          },
          modPath: modPath,
          operationId: operationId,
        );
      } on Object catch (error, stackTrace) {
        // _downloadOne reports its own failures; this is a safety net.
        log.error(
          LogSource.download,
          'Download failed: ${request.url}',
          error: error,
          stackTrace: stackTrace,
          modPath: modPath,
          url: request.url,
          operationId: operationId,
        );
        outcomes[index] = DownloadOutcome(
          url: request.url,
          type: request.type,
          status: DownloadStatus.failed,
          fileKey: fileKeyFromUrl(request.url),
          error: error.toString(),
        );
      } finally {
        progressByJob.remove(index);
        completed++;
        publish();
      }
    }

    publish();
    // Hand-rolled worker pool: each worker pulls the next index (safe
    // because Dart is single-threaded), so a slow file never blocks the
    // others and a finished worker immediately picks the next URL.
    var nextIndex = 0;
    final workerCount = min(concurrency < 1 ? 1 : concurrency, total);
    await Future.wait(
      List.generate(workerCount, (_) async {
        while (!token.isCancelled && nextIndex < total) {
          final index = nextIndex++;
          await processOne(index);
        }
      }),
    );

    // Requests the workers never reached.
    var cancelledLate = false;
    for (var i = 0; i < total; i++) {
      if (outcomes[i] != null) continue;
      cancelledLate = true;
      outcomes[i] = DownloadOutcome(
        url: requests[i].url,
        type: requests[i].type,
        status: DownloadStatus.cancelled,
        fileKey: fileKeyFromUrl(requests[i].url),
      );
      completed++;
    }
    if (cancelledLate) publish();

    final result = DownloadBatchResult([for (final o in outcomes) o!]);
    if (result.wasCancelled) {
      log.warning(
        LogSource.download,
        'Download cancelled: ${result.downloadedCount}/${result.total} '
        'files downloaded, ${result.cancelledCount} not downloaded',
        modPath: modPath,
        operationId: operationId,
      );
    }
    return result;
  }

  Future<DownloadOutcome> _downloadOne(
    DownloadRequest request, {
    required List<String> ignoredDomains,
    required CancellationToken token,
    required Set<String> seenFileNames,
    required void Function(double fraction) onFraction,
    required String? modPath,
    required String? operationId,
  }) async {
    final originalUrl = request.url;
    final type = request.type;
    final fileKey = fileKeyFromUrl(originalUrl);

    DownloadOutcome outcome(
      DownloadStatus status, {
      String? path,
      int? httpStatus,
      String? error,
    }) => DownloadOutcome(
      url: originalUrl,
      type: type,
      status: status,
      path: path,
      fileKey: fileKey,
      httpStatus: httpStatus,
      error: error,
    );

    if (token.isCancelled) return outcome(DownloadStatus.cancelled);

    if (ignoredDomains.isNotEmpty) {
      final host = Uri.tryParse(_withScheme(originalUrl))?.host ?? '';
      if (host.isNotEmpty && ignoredDomains.any(host.contains)) {
        log.info(
          LogSource.download,
          'Skipped (ignored domain $host): $originalUrl',
          modPath: modPath,
          url: originalUrl,
          operationId: operationId,
        );
        return outcome(DownloadStatus.skippedIgnoredDomain);
      }
    }

    final fileName = fileNameFromUrl(originalUrl);
    if (fileName.isEmpty) {
      log.error(
        LogSource.download,
        'Download failed (URL yields an empty file name): $originalUrl',
        modPath: modPath,
        url: originalUrl,
        operationId: operationId,
      );
      return outcome(
        DownloadStatus.failed,
        error: 'URL yields an empty file name',
      );
    }
    if (!seenFileNames.add('${type.name}/$fileName')) {
      log.info(
        LogSource.download,
        'Skipped (same file as an earlier URL in this batch): $originalUrl',
        modPath: modPath,
        url: originalUrl,
        operationId: operationId,
      );
      return outcome(DownloadStatus.skippedExists);
    }

    final tempPath = fs.path.join(request.targetDir, '$fileName$tempSuffix');
    final tempFile = fs.file(tempPath);
    var url = originalUrl;
    try {
      url = await _checker.resolveUrlWithScheme(originalUrl, token: token);
      if (token.isCancelled) return outcome(DownloadStatus.cancelled);
      await fs.directory(request.targetDir).create(recursive: true);

      Uint8List header;
      try {
        header = await _downloadWithRetry(
          url,
          tempFile,
          token: token,
          onFraction: onFraction,
          modPath: modPath,
          operationId: operationId,
        );
      } on DioException catch (error) {
        // Steam CDN: a URL missing its trailing '/' answers 404.
        if (error.response?.statusCode == 404 &&
            url.startsWith(steamUserContentUrl) &&
            !url.endsWith('/')) {
          log.info(
            LogSource.download,
            'Retrying with a trailing slash: $url/',
            modPath: modPath,
            url: originalUrl,
            operationId: operationId,
          );
          url = '$url/';
          header = await _downloadWithRetry(
            url,
            tempFile,
            token: token,
            onFraction: onFraction,
            modPath: modPath,
            operationId: operationId,
          );
        } else {
          rethrow;
        }
      }

      if (token.isCancelled) {
        await _deleteQuietly(tempFile);
        return outcome(DownloadStatus.cancelled);
      }

      if (_looksLikeHtml(header)) {
        await _deleteQuietly(tempFile);
        log.error(
          LogSource.download,
          'Download failed (server returned an HTML page instead of the '
          '${type.folderName} file): $url',
          modPath: modPath,
          url: originalUrl,
          operationId: operationId,
        );
        return outcome(
          DownloadStatus.htmlErrorPage,
          error: 'Server returned an HTML page',
        );
      }

      final extension = extensionForAsset(
        type,
        path: tempPath,
        headerBytes: header,
      );
      final finalPath = fs.path.join(request.targetDir, '$fileName$extension');
      final renamed = await tempFile.rename(finalPath);
      return outcome(
        DownloadStatus.downloaded,
        path: fs.path.normalize(renamed.path),
      );
    } on DioException catch (error) {
      await _deleteQuietly(tempFile);
      if (error.type == DioExceptionType.cancel || token.isCancelled) {
        return outcome(DownloadStatus.cancelled);
      }
      final status = error.response?.statusCode;
      final description = _describe(error);
      log.error(
        LogSource.download,
        'Download failed ($description): $url',
        details: 'type: ${type.folderName}',
        modPath: modPath,
        url: originalUrl,
        operationId: operationId,
      );
      return outcome(
        DownloadStatus.failed,
        httpStatus: status,
        error: description,
      );
    } on OperationCancelledException {
      await _deleteQuietly(tempFile);
      return outcome(DownloadStatus.cancelled);
    } on Object catch (error, stackTrace) {
      await _deleteQuietly(tempFile);
      if (token.isCancelled) return outcome(DownloadStatus.cancelled);
      log.error(
        LogSource.download,
        'Download failed ($error): $url',
        details: 'type: ${type.folderName}',
        error: error,
        stackTrace: stackTrace,
        modPath: modPath,
        url: originalUrl,
        operationId: operationId,
      );
      return outcome(DownloadStatus.failed, error: error.toString());
    }
  }

  /// Streams [url] into [tempFile] with back-off retries on transient
  /// failures (connection / receive timeout, connection error, 5xx), never
  /// on cancellation or 4xx. Returns the first [headerBytesLength] bytes.
  Future<Uint8List> _downloadWithRetry(
    String url,
    File tempFile, {
    required CancellationToken token,
    required void Function(double fraction) onFraction,
    required String? modPath,
    required String? operationId,
  }) async {
    var attempt = 0;
    while (true) {
      attempt++;
      try {
        return await _downloadToFile(
          url,
          tempFile,
          token: token,
          onFraction: onFraction,
        );
      } on DioException catch (error) {
        if (attempt > retryDelays.length ||
            token.isCancelled ||
            !isRetryableDioError(error)) {
          rethrow;
        }
        final delay = retryDelays[attempt - 1];
        log.warning(
          LogSource.download,
          'Retrying download (attempt ${attempt + 1}/'
          '${retryDelays.length + 1}) after ${delay.inMilliseconds} ms: $url',
          details: _describe(error),
          modPath: modPath,
          url: url,
          operationId: operationId,
        );
        await _deleteQuietly(tempFile);
        await Future<void>.delayed(delay);
      }
    }
  }

  /// Whether a failed attempt is worth retrying: timeouts, connection
  /// errors and 5xx answers; never cancellation or 4xx.
  static bool isRetryableDioError(DioException error) {
    if (error.type == DioExceptionType.cancel) return false;
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError) {
      return true;
    }
    final code = error.response?.statusCode;
    return code != null && code >= 500 && code < 600;
  }

  /// One attempt: GET [url] as a stream and write it to [tempFile].
  Future<Uint8List> _downloadToFile(
    String url,
    File tempFile, {
    required CancellationToken token,
    required void Function(double fraction) onFraction,
  }) async {
    final cancelToken = CancelToken();
    final unlisten = token.onCancel(cancelToken.cancel);
    try {
      final response = await dio.get<ResponseBody>(
        url,
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          receiveTimeout: receiveTimeout,
        ),
      );
      final body = response.data;
      if (body == null) {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          error: 'Empty response',
        );
      }
      final total = body.contentLength;
      final header = BytesBuilder();
      var received = 0;
      final sink = await tempFile.open(mode: FileMode.write);
      try {
        final chunks = body.stream.timeout(
          receiveTimeout,
          onTimeout: (sink) {
            sink.addError(
              DioException.receiveTimeout(
                timeout: receiveTimeout,
                requestOptions: response.requestOptions,
              ),
            );
            sink.close();
          },
        );
        await for (final chunk in chunks) {
          token.throwIfCancelled();
          if (header.length < headerBytesLength) {
            header.add(chunk.sublist(0, min(chunk.length, headerBytesLength)));
          }
          await sink.writeFrom(chunk);
          received += chunk.length;
          if (total > 0) onFraction(received / total);
        }
      } finally {
        await sink.close();
      }
      final bytes = header.takeBytes();
      return bytes.length > headerBytesLength
          ? Uint8List.sublistView(bytes, 0, headerBytesLength)
          : bytes;
    } on DioException {
      rethrow;
    } on OperationCancelledException {
      rethrow;
    } on Object catch (error, stackTrace) {
      // A connection dropped mid-stream surfaces as a raw IO error; treat it
      // like dio's connection error so the retry logic applies.
      Error.throwWithStackTrace(
        DioException.connectionError(
          requestOptions: RequestOptions(path: url),
          reason: error.toString(),
          error: error,
        ),
        stackTrace,
      );
    } finally {
      unlisten();
    }
  }

  static bool _looksLikeHtml(Uint8List header) {
    final probe = String.fromCharCodes(
      header.sublist(0, min(header.length, htmlProbeLength)),
    ).toLowerCase();
    return probe.contains('<html') || probe.contains('<!doctype');
  }

  static String _withScheme(String url) =>
      url.startsWith('http://') || url.startsWith('https://')
      ? url
      : 'https://$url';

  static String _describe(DioException error) {
    final response = error.response;
    if (response?.statusCode != null) {
      final message = response!.statusMessage;
      return message == null || message.isEmpty
          ? '${response.statusCode}'
          : '${response.statusCode} $message';
    }
    return switch (error.type) {
      DioExceptionType.connectionTimeout => 'connection timed out',
      DioExceptionType.receiveTimeout => 'receive timed out',
      DioExceptionType.sendTimeout => 'send timed out',
      DioExceptionType.connectionError =>
        'connection error: ${error.error ?? error.message ?? ''}'.trim(),
      DioExceptionType.badCertificate => 'bad certificate',
      DioExceptionType.cancel => 'cancelled',
      DioExceptionType.badResponse => 'bad response',
      DioExceptionType.unknown || DioExceptionType.transformTimeout =>
        '${error.error ?? error.message ?? 'unknown error'}',
    };
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (file.existsSync()) await file.delete();
    } on Object {
      // Nothing more to do; the next download overwrites it.
    }
  }
}
