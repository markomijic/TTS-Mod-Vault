/// Square preview thumbnails for downloaded Workshop mods.
library;

import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Decodes [bytes], crops and resizes the image to a [size] x [size] square
/// with cubic interpolation and returns it PNG-encoded. Returns `null` when
/// the bytes are not a decodable image.
///
/// v2 encoded the decoded image to an uncompressed PNG, read it back and
/// resized that copy; the intermediate round trip changed nothing (PNG is
/// lossless), so this decodes once and encodes once.
Uint8List? squarePreviewPng(Uint8List bytes, {int size = 256}) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final square = img.copyResizeCropSquare(
    decoded,
    size: size,
    interpolation: img.Interpolation.cubic,
  );
  return img.encodePng(square);
}
