import 'dart:async' show Completer;
import 'dart:collection' show Queue;
import 'dart:typed_data' show Uint8List;

import 'package:image/image.dart' as img;
import 'package:pdfrx_engine/pdfrx_engine.dart';

/// Renders the first page of a PDF to PNG bytes via pdfium (through
/// `pdfrx_engine`), retaining nothing.
///
/// The PDF is opened *by path* — pdfium reads it incrementally, so we never load
/// the whole file into a Dart `Uint8List`. pdfium itself runs in pdfrx_engine's
/// internal worker isolate, so the native rasterization happens off the main
/// isolate; only the resulting pixels return here to be encoded. Each call opens,
/// rasters page 0, encodes, and disposes everything immediately — there is no
/// cache, callers re-render when a thumbnail re-enters view.
///
/// Renders are serialized through a single-permit gate so only one document and
/// one pixel buffer ever exist at a time, capping peak RAM regardless of how many
/// thumbnails request a render at once.

/// Render resolution in DPI. The display tile is only 192px, so dpi 36 yields
/// roughly a 400px-tall page for US-letter/A4 (~2x the tile for hi-dpi
/// crispness). dpi is the *quadratic* lever on the pixel buffer's size: halving
/// it quarters that buffer. Lower it first if RAM is still too high.
const double _renderDpi = 36;

/// Only one render at a time -> one open document + one pixel buffer in RAM.
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
  PdfDocument? doc;
  try {
    doc = await PdfDocument.openFile(path);
    if (doc.pages.isEmpty) return null;

    final page = doc.pages.first;
    const scale = _renderDpi / 72.0; // PDF points are at 72 dpi.
    final image = await page.render(
      fullWidth: page.width * scale,
      fullHeight: page.height * scale,
      backgroundColor: 0xFFFFFFFF, // opaque white; transparent PDFs not black.
    );
    if (image == null) return null;
    try {
      return img.encodePng(image.createImageNF());
    } finally {
      image.dispose();
    }
  } catch (_) {
    return null;
  } finally {
    await doc?.dispose();
    _release();
  }
}
