import 'dart:async' show Completer;
import 'dart:collection' show LinkedHashMap, Queue;
import 'dart:io' show File;
import 'dart:typed_data' show Uint8List;

import 'package:printing/printing.dart' show Printing;

/// In-memory cache for rendered first-page PDF thumbnails.
///
/// Thumbnails are rendered lazily via pdfium (through the `printing` package),
/// keyed by the PDF's local file path. Results are kept in an LRU map (capped at
/// [_maxEntries]) so scrolling
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

  /// Render resolution. The display tile is only 192px, so dpi 36 yields roughly
  /// a 400px-tall page for US-letter/A4 (~2x the tile for hi-dpi crispness) while
  /// keeping each cached PNG small. Raise it if thumbnails look soft, lower it to
  /// trim cache memory.
  static const double _renderDpi = 36;

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
    final bytes = await File(path).readAsBytes();
    // raster() yields one PdfRaster per requested page; we only want page 0.
    // It rasters onto a white background by default, so transparent PDFs don't
    // render black.
    await for (final page in Printing.raster(bytes, pages: [0], dpi: _renderDpi)) {
      return await page.toPng();
    }
    return null; // empty/invalid PDF -> caller falls back to placeholder tile
  }
}
