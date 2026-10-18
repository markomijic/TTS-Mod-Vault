import 'package:tts_mod_vault/domain/constants.dart';

final _nonAlphanumeric = RegExp('[^a-zA-Z0-9]');

/// TTS names a cached asset file after its URL with every non-alphanumeric
/// character removed (no extension). This is the exact v2 `getFileNameFromURL`.
String fileNameFromUrl(String url) => url.replaceAll(_nonAlphanumeric, '');

/// Rewrites the legacy Steam Cloud host to the current one.
String normalizeSteamUrl(String url) =>
    url.replaceAll(oldCloudUrl, newSteamUserContentUrl);

/// Filename prefix of assets downloaded from the legacy host.
final oldCloudFilePrefix = fileNameFromUrl(oldCloudUrl);

/// Filename prefix of assets downloaded from the current host.
final newSteamFilePrefix = fileNameFromUrl(newSteamUserContentUrl);

/// Maps an on-disk file name (without extension) to the key used in the
/// `existing_files` index: legacy-host prefix rewritten, then lower-cased.
String fileKeyFromFileName(String fileNameWithoutExtension) {
  final mapped = fileNameWithoutExtension.startsWith(oldCloudFilePrefix)
      ? fileNameWithoutExtension.replaceFirst(
          oldCloudFilePrefix,
          newSteamFilePrefix,
        )
      : fileNameWithoutExtension;
  return mapped.toLowerCase();
}

/// The index key for a URL: host-normalised, stripped, lower-cased.
///
/// Both [fileKeyFromUrl] and [fileKeyFromFileName] produce the same key for a
/// URL and the file TTS caches for it, which is what makes the
/// `mod_assets.file_key = existing_files.file_key` join work.
String fileKeyFromUrl(String url) =>
    fileNameFromUrl(normalizeSteamUrl(url)).toLowerCase();
