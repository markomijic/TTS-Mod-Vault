import 'dart:async' show Completer;
import 'dart:collection' show LinkedHashMap, Queue;
import 'dart:typed_data' show Uint8List;

import 'package:pdfx/pdfx.dart' show PdfDocument, PdfPageImageFormat;

/// In-memory cache for rendered first-page PDF thumbnails.
///
/// Thumbnails are rendered lazily via pdfium, keyed by the PDF's local file
/// path. Results are kept in an LRU map (capped at [_maxEntries]) so scrolling
/// the PDF section in and out of view, or re-selecting a mod, reuses the
/// already-rendered bytes instead of re-rendering. Concurrent renders are
/// limited by [_maxConcurrent] so a section with many PDFs doesn't fire every
/// render in a single frame.
///
/// The cache is in-memory only: it is dropped when the app exits, and keying on
/// the file path alone means replacing a PDF in place won't refresh its
/// thumbnail until the next app launch.
class PdfThumbnailCache {
  static const int _maxEntries = 64;
  static const int _maxConcurrent = 3;

  /// Target render height in pixels (2x the 192px tile for hi-dpi crispness).
  static const double _targetHeight = 384;

  final LinkedHashMap<String, Uint8List> _cache = LinkedHashMap();
  final Map<String, Future<Uint8List?>> _inflight = {};

  int _active = 0;
  final Queue<Completer<void>> _waiters = Queue();

  /// Synchronous cache lookup. Returns null on a miss. On a hit the key is
  /// marked most-recently-used.
  Uint8List? peek(String key) {
    final bytes = _cache.remove(key);
    if (bytes != null) {
      _cache[key] = bytes; // re-insert to move to most-recently-used position
    }
    return bytes;
  }

  /// Returns the cached thumbnail, an in-flight render, or starts a new one.
  Future<Uint8List?> get(String key) {
    final cached = peek(key);
    if (cached != null) return Future.value(cached);

    final existing = _inflight[key];
    if (existing != null) return existing;

    final future = _render(key);
    _inflight[key] = future;
    return future;
  }

  Future<Uint8List?> _render(String key) async {
    await _acquire();
    try {
      final bytes = await _renderFirstPage(key);
      if (bytes != null) _put(key, bytes);
      return bytes;
    } catch (_) {
      return null;
    } finally {
      _release();
      _inflight.remove(key);
    }
  }

  void _put(String key, Uint8List bytes) {
    _cache[key] = bytes;
    while (_cache.length > _maxEntries) {
      _cache.remove(_cache.keys.first); // evict least-recently-used
    }
  }

  Future<void> _acquire() async {
    if (_active < _maxConcurrent) {
      _active++;
      return;
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    await completer.future;
    _active++;
  }

  void _release() {
    _active--;
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
    }
  }

  static Future<Uint8List?> _renderFirstPage(String path) async {
    final doc = await PdfDocument.openFile(path);
    try {
      final page = await doc.getPage(1);
      try {
        final targetWidth = page.width / page.height * _targetHeight;
        final img = await page.render(
          width: targetWidth,
          height: _targetHeight,
          format: PdfPageImageFormat.png,
          backgroundColor: '#FFFFFF',
        );
        return img?.bytes;
      } finally {
        await page.close();
      }
    } finally {
      await doc.close();
    }
  }
}
