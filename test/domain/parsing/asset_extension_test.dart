import 'package:flutter_test/flutter_test.dart';
import 'package:tts_mod_vault/domain/enums/asset_type.dart';
import 'package:tts_mod_vault/domain/parsing/asset_extension.dart';

// Magic bytes recognised by package:mime's header sniffing.
const _pngHeader = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0];
const _jpegHeader = [0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0, 0, 0, 0, 0];
const _gifHeader = [0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0, 0, 0, 0, 0, 0];
const _webpHeader = [
  0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, // RIFF....
  0x57, 0x45, 0x42, 0x50, // WEBP
];
const _mp3Header = [0x49, 0x44, 0x33, 0x04, 0, 0, 0, 0, 0, 0, 0, 0];
const _oggHeader = [0x4F, 0x67, 0x67, 0x53, 0, 0, 0, 0, 0, 0, 0, 0];
const _opusHeader = [
  0x4F,
  0x70,
  0x75,
  0x73,
  0x48,
  0x65,
  0x61,
  0x64,
  0,
  0,
  0,
  0,
];
const _wavHeader = [
  0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, // RIFF....
  0x57, 0x41, 0x56, 0x45, // WAVE
];

void main() {
  group('fixed extensions', () {
    test('asset bundles are .unity3d regardless of hints', () {
      expect(extensionForAsset(AssetType.assetBundle), '.unity3d');
      expect(
        extensionForAsset(
          AssetType.assetBundle,
          path: 'bundle.png',
          headerBytes: _pngHeader,
        ),
        '.unity3d',
      );
    });

    test('models are .obj', () {
      expect(extensionForAsset(AssetType.model), '.obj');
      expect(extensionForAsset(AssetType.model, path: 'x.stl'), '.obj');
    });

    test('PDFs are upper-case .PDF', () {
      expect(extensionForAsset(AssetType.pdf), '.PDF');
      expect(extensionForAsset(AssetType.pdf, path: 'rules.pdf'), '.PDF');
    });
  });

  group('audio', () {
    test('defaults to .mp3 with no hints', () {
      expect(extensionForAsset(AssetType.audio), '.mp3');
    });

    test('maps MIME types from the path', () {
      expect(extensionForAsset(AssetType.audio, path: 'a.mp3'), '.mp3');
      expect(extensionForAsset(AssetType.audio, path: 'a.ogg'), '.ogg');
      expect(extensionForAsset(AssetType.audio, path: 'a.oga'), '.ogg');
      expect(extensionForAsset(AssetType.audio, path: 'a.ogv'), '.ogv');
    });

    test('.wav resolves from path and from a RIFF/WAVE header', () {
      // package:mime reports `audio/x-wav`; v2's table only had `audio/wav`
      // and `audio/vnd.wave`, so .wav fell through to .mp3. Fixed in v3.
      expect(extensionForAsset(AssetType.audio, path: 'a.wav'), '.wav');
      expect(
        extensionForAsset(AssetType.audio, headerBytes: _wavHeader),
        '.wav',
      );
    });

    test('maps MIME types from header bytes', () {
      expect(
        extensionForAsset(AssetType.audio, headerBytes: _mp3Header),
        '.mp3',
      );
      expect(
        extensionForAsset(AssetType.audio, headerBytes: _opusHeader),
        '.ogg',
      );
    });

    test('a bare OggS page header is .ogg even without a path', () {
      // package:mime only knows the Opus magic, so the OggS capture pattern
      // is checked explicitly before sniffing (v2 fell through to .mp3).
      expect(
        extensionForAsset(AssetType.audio, headerBytes: _oggHeader),
        '.ogg',
      );
      expect(
        extensionForAsset(
          AssetType.audio,
          path: 'a.ogg',
          headerBytes: _oggHeader,
        ),
        '.ogg',
      );
      // OggS beats a misleading path.
      expect(
        extensionForAsset(
          AssetType.audio,
          path: 'a.mp3',
          headerBytes: _oggHeader,
        ),
        '.ogg',
      );
      // Too short or different bytes do not trigger the check.
      expect(
        extensionForAsset(AssetType.audio, headerBytes: const [0x4F, 0x67]),
        '.mp3',
      );
      // The OggS check applies to audio only; images still sniff normally.
      expect(
        extensionForAsset(AssetType.image, headerBytes: _oggHeader),
        '.png',
      );
    });

    test('unknown MIME falls back to .mp3', () {
      expect(extensionForAsset(AssetType.audio, path: 'a.flac'), '.mp3');
      expect(extensionForAsset(AssetType.audio, path: 'a.png'), '.mp3');
      expect(
        extensionForAsset(AssetType.audio, headerBytes: _pngHeader),
        '.mp3',
      );
    });
  });

  group('image', () {
    test('defaults to .png with no hints', () {
      expect(extensionForAsset(AssetType.image), '.png');
    });

    test('maps MIME types from the path', () {
      expect(extensionForAsset(AssetType.image, path: 'i.png'), '.png');
      expect(extensionForAsset(AssetType.image, path: 'i.jpg'), '.jpg');
      expect(extensionForAsset(AssetType.image, path: 'i.jpeg'), '.jpg');
      expect(extensionForAsset(AssetType.image, path: 'i.webp'), '.webp');
      expect(extensionForAsset(AssetType.image, path: 'i.gif'), '.gif');
      expect(extensionForAsset(AssetType.image, path: 'i.bmp'), '.bmp');
      expect(extensionForAsset(AssetType.image, path: 'i.svg'), '.svg');
      expect(extensionForAsset(AssetType.image, path: 'i.tiff'), '.tiff');
      expect(extensionForAsset(AssetType.image, path: 'i.tif'), '.tiff');
      expect(extensionForAsset(AssetType.image, path: 'i.ico'), '.ico');
      expect(extensionForAsset(AssetType.image, path: 'i.avif'), '.avif');
    });

    test('maps MIME types from header bytes', () {
      expect(
        extensionForAsset(AssetType.image, headerBytes: _pngHeader),
        '.png',
      );
      expect(
        extensionForAsset(AssetType.image, headerBytes: _jpegHeader),
        '.jpg',
      );
      expect(
        extensionForAsset(AssetType.image, headerBytes: _gifHeader),
        '.gif',
      );
      expect(
        extensionForAsset(AssetType.image, headerBytes: _webpHeader),
        '.webp',
      );
    });

    test('header bytes win over a misleading path', () {
      expect(
        extensionForAsset(
          AssetType.image,
          path: 'actually.png',
          headerBytes: _jpegHeader,
        ),
        '.jpg',
      );
    });

    test('unknown MIME falls back to .png', () {
      expect(extensionForAsset(AssetType.image, path: 'i.bin'), '.png');
      expect(extensionForAsset(AssetType.image, path: 'i.mp3'), '.png');
    });
  });
}
