import 'dart:async' show Completer;
import 'dart:collection' show Queue;
import 'dart:typed_data' show Uint8List;

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:pdfrx_engine/pdfrx_engine.dart';

/// Default render resolution in DPI.
///
/// The display tile is only 192px, so dpi 36 yields roughly a 400px-tall
/// page for US-letter/A4 (~2x the tile for hi-dpi crispness). dpi is the
/// *quadratic* lever on the pixel buffer's size: halving it quarters that
/// buffer. Lower it first if RAM is still too high.
const double defaultPdfThumbnailDpi = 36;

/// Renders the first page of a PDF file to PNG bytes.
///
/// Implementations return null on any failure (missing or corrupt file, no
/// pages) so the caller can fall back to a placeholder tile. Nothing is
/// cached: callers re-render when a thumbnail re-enters view.
abstract interface class PdfThumbnailRenderer {
  /// PNG bytes of the first page of the PDF at [path], rendered at [dpi],
  /// or null when the file cannot be rendered.
  Future<Uint8List?> renderFirstPage(
    String path, {
    double dpi = defaultPdfThumbnailDpi,
  });
}

/// A counting semaphore that lets at most [maxConcurrent] bodies run at
/// once; the rest wait in FIFO order.
///
/// With the default single permit, only one PDF document and one pixel
/// buffer ever exist at a time, capping peak RAM regardless of how many
/// thumbnails request a render at once.
final class RenderGate {
  /// Creates a gate with [maxConcurrent] permits (at least 1).
  RenderGate({this.maxConcurrent = 1}) : assert(maxConcurrent >= 1);

  /// Number of bodies allowed to run concurrently.
  final int maxConcurrent;

  int _active = 0;
  final Queue<Completer<void>> _waiters = Queue();

  /// Bodies currently running.
  int get active => _active;

  /// Bodies waiting for a permit.
  int get waiting => _waiters.length;

  /// Runs [body] once a permit is free and releases the permit afterwards,
  /// whether [body] completed or threw.
  Future<T> run<T>(Future<T> Function() body) async {
    await _acquire();
    try {
      return await body();
    } finally {
      _release();
    }
  }

  Future<void> _acquire() async {
    if (_active < maxConcurrent) {
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
}

/// Opens a PDF document by path; replaceable in tests.
typedef PdfDocumentOpener = Future<PdfDocument> Function(String path);

/// [PdfThumbnailRenderer] backed by pdfium through `pdfrx_engine`, retaining
/// nothing.
///
/// The PDF is opened *by path*: pdfium reads it incrementally, so the whole
/// file is never loaded into a Dart `Uint8List`. pdfium itself runs in
/// pdfrx_engine's internal worker isolate, so the native rasterization
/// happens off the main isolate; only the resulting pixels return here to be
/// encoded. Each call opens, rasters page 0, encodes and disposes everything
/// immediately. There is no cache: a previous in-memory thumbnail cache was
/// removed on purpose for RAM reasons, callers re-render when a thumbnail
/// re-enters view.
///
/// Renders are serialised through a single-permit [RenderGate] so only one
/// document and one pixel buffer ever exist at a time. Port of 2.x
/// `renderPdfFirstPage`.
final class PdfrxThumbnailRenderer implements PdfThumbnailRenderer {
  /// Creates the renderer. [gate] defaults to a single permit and
  /// [openDocument] to [PdfDocument.openFile].
  PdfrxThumbnailRenderer({RenderGate? gate, PdfDocumentOpener? openDocument})
    : _gate = gate ?? RenderGate(),
      _open = openDocument ?? _openWithPdfrx;

  final RenderGate _gate;
  final PdfDocumentOpener _open;

  static Future<PdfDocument> _openWithPdfrx(String path) =>
      PdfDocument.openFile(path);

  @override
  Future<Uint8List?> renderFirstPage(
    String path, {
    double dpi = defaultPdfThumbnailDpi,
  }) => _gate.run(() => _render(path, dpi));

  Future<Uint8List?> _render(String path, double dpi) async {
    PdfDocument? doc;
    try {
      doc = await _open(path);
      if (doc.pages.isEmpty) return null;

      final page = doc.pages.first;
      final scale = dpi / 72.0; // PDF points are at 72 dpi.
      final image = await page.render(
        fullWidth: page.width * scale,
        fullHeight: page.height * scale,
        backgroundColor:
            0xFFFFFFFF, // opaque white; transparent PDFs not black.
      );
      if (image == null) return null;
      try {
        return img.encodePng(image.createImageNF());
      } finally {
        image.dispose();
      }
    } on Object {
      return null;
    } finally {
      await doc?.dispose();
    }
  }
}

/// The renderer used by the PDF thumbnail tiles; tests override it with a
/// fake.
final pdfThumbnailRendererProvider = Provider<PdfThumbnailRenderer>(
  (ref) => PdfrxThumbnailRenderer(),
);
