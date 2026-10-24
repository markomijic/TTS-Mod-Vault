/// Domain reachability checks. Port of 2.x `checkDomainsForUrls`,
/// `_isDomainReachable` and `_domainCandidateResponds` (commit `051741c`).
library;

import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/core/cancellation/cancellation_token.dart';
import 'package:tts_mod_vault/data/net/dio_client.dart';

/// Whether one host answered.
typedef DomainReachability = ({String domain, bool reachable});

/// Outcome of [DomainReachabilityChecker.checkUrls].
final class DomainCheckResult {
  /// Creates a result.
  const DomainCheckResult({required this.domains, required this.cancelled});

  /// One entry per checked host, sorted by host. Partial when [cancelled].
  final List<DomainReachability> domains;

  /// Whether the check stopped before every host was tried.
  final bool cancelled;

  /// Hosts that did not answer, sorted.
  List<String> get unreachable => [
    for (final d in domains)
      if (!d.reachable) d.domain,
  ];

  @override
  String toString() =>
      'DomainCheckResult(domains=${domains.length} '
      'unreachable=${unreachable.length}${cancelled ? ' cancelled' : ''})';
}

/// The app's one checker, so its one-minute cache spans operations (the bulk
/// URL check reuses host results across mods).
final domainReachabilityCheckerProvider = Provider<DomainReachabilityChecker>(
  (ref) => DomainReachabilityChecker(dio: ref.watch(dioProvider)),
);

/// Checks whether the hosts of asset URLs can be reached at all, so a URL on
/// a host that is down or blocked from the current network is not mistaken
/// for a dead asset.
///
/// A host is reachable when *any* HTTP response comes back (403, 404 and 5xx
/// included) for one of: `https://host/`, `http://host/`, a representative
/// URL on that host; each tried with `HEAD` then a one-byte ranged `GET`,
/// 10 s timeouts, redirects not followed. Only connection-level failures
/// make a host unreachable. Results are cached for [cacheTtl].
final class DomainReachabilityChecker {
  /// Creates a checker that issues requests through [dio]. [clock] is for
  /// tests of the cache.
  DomainReachabilityChecker({required this.dio, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// Per-request send and receive timeout.
  static const Duration timeout = Duration(seconds: 10);

  /// How long a host result is reused without [checkUrls]'s `forceRefresh`.
  static const Duration cacheTtl = Duration(minutes: 1);

  /// The HTTP client requests go through.
  final Dio dio;

  final DateTime Function() _clock;
  final Map<String, ({bool reachable, DateTime checkedAt})> _cache = {};

  /// [url] as an `http`/`https` URI with a host; a scheme-less URL is read
  /// as `https://`. `null` for anything else (other schemes, no host).
  static Uri? parseHttpUri(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;
    final parsed = Uri.tryParse(trimmed);
    if (parsed != null &&
        (parsed.scheme == 'http' || parsed.scheme == 'https') &&
        parsed.host.isNotEmpty) {
      return parsed;
    }
    if (parsed?.hasScheme ?? false) return null;
    final withHttps = Uri.tryParse('https://$trimmed');
    if (withHttps != null && withHttps.host.isNotEmpty) return withHttps;
    return null;
  }

  /// The lower-cased host of [url], or `null` (see [parseHttpUri]).
  static String? hostOf(String url) => parseHttpUri(url)?.host.toLowerCase();

  /// Checks one host per unique (lower-cased) host among [urls] with
  /// [concurrency] workers. Cached results younger than [cacheTtl] are reused
  /// unless [forceRefresh]. [onProgress] gets `(done, total)` for the hosts
  /// that need a request. Never throws; a cancelled [token] ends the check
  /// with [DomainCheckResult.cancelled] set and nothing cached for the hosts
  /// still running.
  Future<DomainCheckResult> checkUrls(
    Iterable<String> urls, {
    int concurrency = 5,
    bool forceRefresh = false,
    CancellationToken? token,
    void Function(int done, int total)? onProgress,
  }) async {
    final representatives = <String, Uri>{};
    for (final url in urls) {
      final parsed = parseHttpUri(url);
      if (parsed != null) {
        representatives.putIfAbsent(parsed.host.toLowerCase(), () => parsed);
      }
    }

    final results = <DomainReachability>[];
    final now = _clock();
    final pending = <MapEntry<String, Uri>>[];
    for (final entry in representatives.entries) {
      final cached = _cache[entry.key];
      if (!forceRefresh &&
          cached != null &&
          now.difference(cached.checkedAt) < cacheTtl) {
        results.add((domain: entry.key, reachable: cached.reachable));
      } else {
        pending.add(entry);
      }
    }

    var cancelled = token?.isCancelled ?? false;
    if (pending.isNotEmpty && !cancelled) {
      onProgress?.call(0, pending.length);
      var nextIndex = 0;
      var done = 0;
      final workerCount = concurrency < 1
          ? 1
          : (concurrency < pending.length ? concurrency : pending.length);
      await Future.wait(
        List.generate(workerCount, (_) async {
          while (!(token?.isCancelled ?? false) && nextIndex < pending.length) {
            final entry = pending[nextIndex++];
            final bool reachable;
            try {
              reachable = await isReachable(entry.value, token: token);
            } on OperationCancelledException {
              return;
            }
            if (token?.isCancelled ?? false) return;
            results.add((domain: entry.key, reachable: reachable));
            _cache[entry.key] = (reachable: reachable, checkedAt: _clock());
            done++;
            onProgress?.call(done, pending.length);
          }
        }),
      );
      cancelled = token?.isCancelled ?? false;
    }

    results.sort((a, b) => a.domain.compareTo(b.domain));
    return DomainCheckResult(
      domains: List.unmodifiable(results),
      cancelled: cancelled,
    );
  }

  /// Whether the host of [representative] answers (see class docs). Throws
  /// only [OperationCancelledException] when [token] is cancelled.
  Future<bool> isReachable(
    Uri representative, {
    CancellationToken? token,
  }) async {
    final schemes = <String>{representative.scheme, 'https', 'http'};
    final candidates = <String>{
      for (final scheme in schemes)
        Uri(
          scheme: scheme,
          host: representative.host,
          port: representative.hasPort ? representative.port : null,
          path: '/',
        ).toString(),
      representative.toString(),
    };
    for (final candidate in candidates) {
      if (await _responds(candidate, token)) return true;
    }
    return false;
  }

  /// `HEAD`, then a ranged `GET`: whether either got any HTTP response.
  Future<bool> _responds(String url, CancellationToken? token) async {
    final cancelToken = CancelToken();
    final unlisten = token?.onCancel(cancelToken.cancel) ?? () {};
    try {
      for (final method in const ['HEAD', 'GET']) {
        try {
          final response = await dio.request<ResponseBody>(
            url,
            cancelToken: cancelToken,
            options: Options(
              method: method,
              headers: method == 'GET' ? {'Range': 'bytes=0-0'} : null,
              validateStatus: (_) => true,
              followRedirects: false,
              sendTimeout: timeout,
              receiveTimeout: timeout,
              responseType: ResponseType.stream,
            ),
          );
          await _discardBody(response);
          return true;
        } on DioException catch (error) {
          if (error.type == DioExceptionType.cancel) {
            throw OperationCancelledException(token?.cancelReason);
          }
          if (error.response != null) return true;
        } on Object {
          // Not an HTTP answer; try the next method.
        }
      }
      return false;
    } finally {
      unlisten();
    }
  }

  static Future<void> _discardBody(Response<ResponseBody> response) async {
    final body = response.data;
    if (body == null) return;
    try {
      await body.stream.listen((_) {}).cancel();
    } on Object {
      // The connection is being dropped anyway.
    }
  }
}
