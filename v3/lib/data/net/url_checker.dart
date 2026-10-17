/// URL liveness checks and scheme resolution. Port of v2 `isUrlLive`,
/// `_checkUrl` and `resolveUrlWithScheme`.
library;

import 'package:dio/dio.dart';
import 'package:tts_mod_vault/core/cancellation/cancellation_token.dart';

/// Checks whether asset URLs still answer.
///
/// A URL is live when a `HEAD` (or, for servers that reject `HEAD`, a
/// one-byte ranged `GET`) answers with a 2xx/3xx status (206 included) whose
/// content type is not `text/html`: Steam/Akamai serve dead UGC assets as an
/// HTML error page, sometimes with status 200, and a real asset never has an
/// HTML content type. Scheme-less URLs are tried as `https://` then
/// `http://` first.
final class UrlChecker {
  /// Creates a checker that issues requests through [dio].
  UrlChecker({required this.dio});

  /// Per-request send and receive timeout.
  static const Duration timeout = Duration(seconds: 15);

  /// The HTTP client requests go through.
  final Dio dio;

  /// Whether [url] answers (see class docs). Never throws, except
  /// [OperationCancelledException] when [token] is cancelled.
  Future<bool> isLive(String url, {CancellationToken? token}) async {
    try {
      final resolved = await resolveUrlWithScheme(url, token: token);
      return await checkUrl(resolved, token: token);
    } on OperationCancelledException {
      rethrow;
    } on Object {
      return false;
    }
  }

  /// Prefixes a scheme-less [url] with `https://` when that answers, else
  /// `http://` when that does, else returns [url] unchanged. URLs that
  /// already carry `http://` or `https://` are returned as they are.
  Future<String> resolveUrlWithScheme(
    String url, {
    CancellationToken? token,
  }) async {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    final httpsUrl = 'https://$url';
    if (await checkUrl(httpsUrl, token: token)) return httpsUrl;
    final httpUrl = 'http://$url';
    if (await checkUrl(httpUrl, token: token)) return httpUrl;
    return url;
  }

  /// The core check without scheme resolution: `HEAD`, then a ranged `GET`
  /// when the `HEAD` fails or is rejected. Returns `false` on any error other
  /// than cancellation.
  Future<bool> checkUrl(String url, {CancellationToken? token}) async {
    final cancelToken = CancelToken();
    final unlisten = token?.onCancel(cancelToken.cancel) ?? () {};
    try {
      try {
        final head = await dio.request<ResponseBody>(
          url,
          cancelToken: cancelToken,
          options: _options('HEAD'),
        );
        await _discardBody(head);
        if (_isLiveResponse(head)) return true;
      } on DioException catch (error) {
        if (error.type == DioExceptionType.cancel) rethrow;
        // Some servers reject HEAD; fall through to the ranged GET.
      }
      final get = await dio.request<ResponseBody>(
        url,
        cancelToken: cancelToken,
        options: _options('GET', headers: {'Range': 'bytes=0-0'}),
      );
      await _discardBody(get);
      return _isLiveResponse(get);
    } on DioException catch (error) {
      if (error.type == DioExceptionType.cancel) {
        throw OperationCancelledException(token?.cancelReason);
      }
      return false;
    } on Object {
      return false;
    } finally {
      unlisten();
    }
  }

  static Options _options(String method, {Map<String, Object?>? headers}) =>
      Options(
        method: method,
        headers: headers,
        validateStatus: (status) => status != null && status < 500,
        followRedirects: true,
        maxRedirects: 5,
        sendTimeout: timeout,
        receiveTimeout: timeout,
        // Do not buffer a body the server sends despite the Range header;
        // the stream is dropped in [_discardBody].
        responseType: ResponseType.stream,
      );

  /// Releases the connection without reading a body the server may send.
  static Future<void> _discardBody(Response<ResponseBody> response) async {
    final body = response.data;
    if (body == null) return;
    try {
      await body.stream.listen((_) {}).cancel();
    } on Object {
      // The connection is being dropped anyway.
    }
  }

  /// 2xx/3xx (206 included) and not an HTML page.
  static bool _isLiveResponse(Response<ResponseBody> response) {
    final status = response.statusCode;
    if (status == null || status >= 400) return false;
    final contentType =
        response.headers.value(Headers.contentTypeHeader)?.toLowerCase() ?? '';
    return !contentType.contains('text/html');
  }
}
