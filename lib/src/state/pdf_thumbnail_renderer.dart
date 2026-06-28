import 'dart:async' show Completer;
import 'dart:collection' show Queue;
import 'dart:io' show File;
import 'dart:typed_data' show Uint8List;

import 'package:printing/printing.dart' show Printing;

/// Renders the first page of a PDF to PNG bytes via pdfium (through the
/// `printing` package), retaining nothing.
///
/// There is deliberately no cache: each call reads the file, rasters page 0, and
/// returns the bytes, then lets the large transient buffers (the full PDF and the
/// RGBA raster) go out of scope so the GC can reclaim them immediately. Callers
/// re-render when a thumbnail re-enters view.
///
/// Renders are serialized through a single-permit gate so only one PDF's bytes
/// and one raster buffer ever exist at a time — capping peak RAM regardless of
/// how many thumbnails request a render at once.

/// Render resolution. The display tile is only 192px, so dpi 36 yields roughly a
/// 400px-tall page for US-letter/A4 (~2x the tile for hi-dpi crispness). dpi is
/// the *quadratic* lever on the transient raster buffer's size: halving it
/// quarters that buffer. Lower it first if RAM is still too high.
const double _renderDpi = 36;

/// Only one render at a time -> one PDF buffer + one raster buffer in RAM.
const int _maxConcurrent = 1;

int _active = 0;
final Queue<Completer<void>> _waiters = Queue();

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

/// Returns PNG bytes for the first page, or null on any failure (missing/corrupt
/// file) so the caller can fall back to a placeholder tile.
Future<Uint8List?> renderPdfFirstPage(String path) async {
  await _acquire();
  try {
    final bytes = await File(path).readAsBytes();
    // raster() yields one PdfRaster per requested page; we only want page 0. It
    // rasters onto a white background by default, so transparent PDFs don't
    // render black.
    await for (final page
        in Printing.raster(bytes, pages: [0], dpi: _renderDpi)) {
      return await page.toPng();
    }
    return null; // empty/invalid PDF
  } catch (_) {
    return null;
  } finally {
    _release();
  }
}
