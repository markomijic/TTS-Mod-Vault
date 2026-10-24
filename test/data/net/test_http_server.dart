// A real `dart:io` HttpServer on the loopback interface for the network
// tests: fixed asset routes (PNG, JPEG, an OGG under a misleading `.mp3`
// name, an HTML "error page" with status 200, a 404, a flaky 500-then-200
// route, a HEAD-rejecting route, a redirect), slow and stalling routes for
// cancellation, a Steam `GetPublishedFileDetails` endpoint with configurable
// items, a BSON file and a preview image, and a GitHub releases stub.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show min;

import 'package:image/image.dart' as img;

/// A 4x4 opaque PNG.
final List<int> pngBytes = img.encodePng(
  img.Image(width: 4, height: 4)..clear(img.ColorRgb8(200, 30, 30)),
);

/// A 4x4 JPEG.
final List<int> jpegBytes = img.encodeJpg(
  img.Image(width: 4, height: 4)..clear(img.ColorRgb8(30, 200, 30)),
);

/// A 300x200 PNG used as a Workshop preview image.
final List<int> previewBytes = img.encodePng(
  img.Image(width: 300, height: 200)..clear(img.ColorRgb8(30, 30, 200)),
);

/// Bytes starting with the Ogg capture pattern.
final List<int> oggBytes = [
  0x4F, 0x67, 0x67, 0x53, // OggS
  ...List<int>.filled(60, 0),
];

/// One recorded request.
typedef RecordedRequest = ({String method, String path});

/// The test server. Start it with [TestHttpServer.start] and close it in
/// `tearDown`.
final class TestHttpServer {
  TestHttpServer._(this._server) {
    _server.listen(_handle, onError: (Object _) {});
  }

  /// Binds to a free loopback port.
  static Future<TestHttpServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return TestHttpServer._(server);
  }

  final HttpServer _server;
  final List<Completer<void>> _releases = [];

  /// Every request received, in order.
  final List<RecordedRequest> requests = [];

  /// Requests currently being handled.
  int activeRequests = 0;

  /// The highest [activeRequests] observed.
  int maxConcurrentRequests = 0;

  /// How many times `/flaky` answers 500 before answering 200.
  int flakyFailures = 2;
  int _flakyCalls = 0;

  /// Steam items served by `/details`, keyed by id. An id absent from the
  /// map answers `result: 9` (not found).
  Map<String, Map<String, Object?>> steamItems = {};

  /// Bytes served by `/bson`.
  List<int> bsonBytes = const [];

  /// When set, `/` holds the connection until [close] (domain reachability
  /// cancellation tests); otherwise it answers 404 like any unknown path.
  bool stallRoot = false;

  /// Tag served by `/release` (`null` makes the route answer 404).
  String? releaseTag = 'v3.2.0';

  /// `http://127.0.0.1:<port>`.
  String get baseUrl => 'http://127.0.0.1:${_server.port}';

  /// `127.0.0.1:<port>` (for scheme-less URL tests).
  String get hostAndPort => '127.0.0.1:${_server.port}';

  /// `baseUrl + path`.
  String url(String path) => '$baseUrl$path';

  /// Requests to [path] (exact match).
  List<RecordedRequest> requestsTo(String path) =>
      requests.where((r) => r.path == path).toList();

  /// Number of calls `/flaky` has received.
  int get flakyCalls => _flakyCalls;

  /// Releases every `/slow` and `/stall` handler and shuts the server down.
  Future<void> close() async {
    for (final release in _releases) {
      if (!release.isCompleted) release.complete();
    }
    await _server.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    requests.add((method: request.method, path: path));
    activeRequests++;
    if (activeRequests > maxConcurrentRequests) {
      maxConcurrentRequests = activeRequests;
    }
    final response = request.response;
    try {
      await _route(request, response);
    } on Object {
      // The client went away (cancellation tests); nothing to do.
    } finally {
      activeRequests--;
      try {
        await response.close();
      } on Object {
        // Already closed or aborted.
      }
    }
  }

  Future<void> _route(HttpRequest request, HttpResponse response) async {
    final path = request.uri.path;
    final segments = request.uri.pathSegments;

    if (path == '/' && stallRoot) {
      await _hold();
      response.statusCode = HttpStatus.notFound;
      return;
    }
    if (path == '/png' || path.startsWith('/png/')) {
      return _bytes(response, pngBytes, 'image/png');
    }
    if (path == '/jpeg') return _bytes(response, jpegBytes, 'image/jpeg');
    if (path == '/octet-jpeg') {
      return _bytes(response, jpegBytes, 'application/octet-stream');
    }
    if (path == '/audio/song.mp3') {
      return _bytes(response, oggBytes, 'application/octet-stream');
    }
    if (path == '/html200') {
      response.statusCode = 200;
      response.headers.contentType = ContentType.html;
      response.write('<html><body><h1>Not found</h1></body></html>');
      return;
    }
    if (path == '/doctype') {
      return _bytes(
        response,
        utf8.encode('<!DOCTYPE html>\n<html><body>Error</body></html>'),
        'application/octet-stream',
      );
    }
    if (path == '/missing') {
      response.statusCode = HttpStatus.notFound;
      response.write('missing');
      return;
    }
    if (path == '/server-error') {
      response.statusCode = HttpStatus.internalServerError;
      response.write('boom');
      return;
    }
    if (path == '/flaky') {
      _flakyCalls++;
      if (_flakyCalls <= flakyFailures) {
        response.statusCode = HttpStatus.internalServerError;
        response.write('try again');
        return;
      }
      return _bytes(response, pngBytes, 'image/png');
    }
    if (path == '/no-head') {
      if (request.method == 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
        return;
      }
      return _bytes(response, pngBytes, 'image/png');
    }
    if (path == '/redirect') {
      response.statusCode = HttpStatus.found;
      response.headers.set(HttpHeaders.locationHeader, '/png');
      return;
    }
    if (segments.isNotEmpty && segments.first == 'slow') {
      // Headers and a first chunk, then hold the connection open.
      response.statusCode = 200;
      response.headers.contentType = ContentType.binary;
      response.contentLength = 1000000;
      response.add(List<int>.filled(1000, 7));
      await response.flush();
      await _hold();
      return;
    }
    if (segments.isNotEmpty && segments.first == 'stall') {
      // Nothing at all until released.
      await _hold();
      response.statusCode = 200;
      return;
    }
    if (segments.length >= 2 && segments.first == 'delay') {
      final ms = int.tryParse(segments[1]) ?? 50;
      await Future<void>.delayed(Duration(milliseconds: ms));
      return _bytes(response, pngBytes, 'image/png');
    }
    if (segments.isNotEmpty && segments.first == 'steam') {
      // Steam CDN behaviour: the asset only answers with a trailing slash.
      if (!path.endsWith('/')) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      return _bytes(response, pngBytes, 'image/png');
    }
    if (path == '/big') {
      final bytes = List<int>.generate(200 * 1024, (i) => i & 0xff);
      response.statusCode = 200;
      response.headers.contentType = ContentType.binary;
      response.contentLength = bytes.length;
      const chunk = 16 * 1024;
      for (var i = 0; i < bytes.length; i += chunk) {
        response.add(bytes.sublist(i, min(i + chunk, bytes.length)));
        await response.flush();
        // Without a pause a fast loopback (Linux) can hand the client the
        // whole body in one read, so no intermediate progress is reported.
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      return;
    }
    if (path == '/details') {
      final body = await utf8.decoder.bind(request).join();
      final form = Uri.splitQueryString(body);
      final count = int.tryParse(form['itemcount'] ?? '') ?? 0;
      final entries = <Map<String, Object?>>[];
      for (var i = 0; i < count; i++) {
        final id = form['publishedfileids[$i]'];
        if (id == null) continue;
        final item = steamItems[id];
        entries.add(
          item == null
              ? {'publishedfileid': id, 'result': 9}
              : {'publishedfileid': id, 'result': 1, ...item},
        );
      }
      response.statusCode = 200;
      response.headers.contentType = ContentType.json;
      response.write(
        jsonEncode({
          'response': {
            'result': 1,
            'resultcount': entries.length,
            'publishedfiledetails': entries,
          },
        }),
      );
      return;
    }
    if (path == '/details-garbage') {
      response.statusCode = 200;
      response.write('this is not json');
      return;
    }
    if (path == '/bson') {
      return _bytes(response, bsonBytes, 'application/octet-stream');
    }
    if (path == '/preview') return _bytes(response, previewBytes, 'image/png');
    if (path == '/release') {
      final tag = releaseTag;
      if (tag == null) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      response.statusCode = 200;
      response.headers.contentType = ContentType.json;
      response.write(jsonEncode({'tag_name': tag, 'name': 'Release $tag'}));
      return;
    }
    response.statusCode = HttpStatus.notFound;
  }

  Future<void> _hold() {
    final release = Completer<void>();
    _releases.add(release);
    return release.future;
  }

  static void _bytes(HttpResponse response, List<int> bytes, String type) {
    response.statusCode = 200;
    response.headers.contentType = ContentType.parse(type);
    response.contentLength = bytes.length;
    response.add(bytes);
  }
}
