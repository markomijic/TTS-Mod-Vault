// squarePreviewPng: one decode, one encode, square output.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tts_mod_vault/data/net/preview_image.dart';

import 'test_http_server.dart' show previewBytes;

void main() {
  test('crops and resizes a 300x200 image to a 256x256 PNG', () {
    final png = squarePreviewPng(Uint8List.fromList(previewBytes));
    expect(png, isNotNull);
    // PNG signature.
    expect(png!.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    final decoded = img.decodePng(png)!;
    expect(decoded.width, 256);
    expect(decoded.height, 256);
    // The fill colour survives the resize.
    final pixel = decoded.getPixel(128, 128);
    expect(pixel.r.toInt(), 30);
    expect(pixel.g.toInt(), 30);
    expect(pixel.b.toInt(), 200);
  });

  test('honours a custom size', () {
    final png = squarePreviewPng(Uint8List.fromList(previewBytes), size: 64);
    final decoded = img.decodePng(png!)!;
    expect(decoded.width, 64);
    expect(decoded.height, 64);
  });

  test('returns null for bytes that are not an image', () {
    expect(squarePreviewPng(Uint8List.fromList([1, 2, 3, 4])), isNull);
    expect(squarePreviewPng(Uint8List(0)), isNull);
  });
}
