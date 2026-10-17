/// File extension to give a downloaded asset. Port of v2 `getExtensionByType`.
library;

import 'package:mime/mime.dart' show lookupMimeType;
import 'package:tts_mod_vault/domain/enums/asset_type.dart';

// "OggS": the capture pattern that opens every Ogg page.
const _oggSMagic = [0x4F, 0x67, 0x67, 0x53];

bool _hasOggSMagic(List<int>? headerBytes) {
  if (headerBytes == null || headerBytes.length < _oggSMagic.length) {
    return false;
  }
  for (var i = 0; i < _oggSMagic.length; i++) {
    if (headerBytes[i] != _oggSMagic[i]) return false;
  }
  return true;
}

/// The extension (with leading dot) TTS expects for an asset of [type].
///
/// Asset bundles, models and PDFs have fixed extensions (`.unity3d`, `.obj`,
/// `.PDF` upper-case, exactly as TTS writes them). Audio and images are
/// sniffed with `package:mime` from [path] and the first [headerBytes] of the
/// download; unknown or missing types fall back to `.mp3` and `.png`.
String extensionForAsset(
  AssetType type, {
  String path = '',
  List<int>? headerBytes,
}) {
  switch (type) {
    case AssetType.assetBundle:
      return '.unity3d';

    case AssetType.audio:
      // package:mime only knows the Opus magic for audio/ogg; a plain Ogg
      // Vorbis page starts with "OggS", so check that before sniffing.
      if (_hasOggSMagic(headerBytes)) return '.ogg';

      final mimeType = lookupMimeType(path, headerBytes: headerBytes);

      switch (mimeType) {
        case 'audio/ogg':
        case 'audio/vorbis':
          return '.ogg';

        case 'audio/wav':
        case 'audio/x-wav':
        case 'audio/wave':
        case 'audio/vnd.wave':
          return '.wav';

        case 'video/ogg':
        case 'video/ogv':
          return '.ogv';

        case 'audio/mpeg':
        default:
          return '.mp3';
      }

    case AssetType.image:
      final mimeType = lookupMimeType(path, headerBytes: headerBytes);

      switch (mimeType) {
        // Unsupported by TTS 14.0
        case 'image/gif':
          return '.gif';

        case 'image/bmp':
        case 'image/x-windows-bmp':
          return '.bmp';

        case 'image/svg+xml':
          return '.svg';

        case 'image/tiff':
          return '.tiff';

        case 'image/x-icon':
          return '.ico';

        case 'image/avif':
          return '.avif';

        // Supported by TTS 14.0
        case 'image/jpeg':
          return '.jpg';

        case 'image/webp':
          return '.webp';

        case 'image/png':
        default:
          return '.png';
      }

    case AssetType.model:
      return '.obj';

    case AssetType.pdf:
      return '.PDF';
  }
}
