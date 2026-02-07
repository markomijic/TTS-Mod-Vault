import 'package:tts_mod_vault/src/utils/zip_central_directory_reader.dart'
    show ZipCentralDirectoryReader;

/// Counts asset files in specific zip subdirectories without reading file data.
class ZipAssetCounter {
  static const List<String> _assetFolderPrefixes = [
    'Mods/Assetbundles/',
    'Mods/Audio/',
    'Mods/Images/',
    'Mods/PDF/',
    'Mods/Models/',
  ];

  /// Returns the total count of asset files across all asset folders.
  /// Returns 0 if the zip cannot be read or has no assets.
  static Future<int> countAssets(String zipPath) async {
    try {
      final fileNames =
          await ZipCentralDirectoryReader.readFileNames(zipPath);
      return countAssetsFromFileNames(fileNames);
    } catch (_) {
      return 0;
    }
  }

  /// Counts assets from an already-parsed list of filenames.
  static int countAssetsFromFileNames(List<String> fileNames) {
    int count = 0;
    for (final name in fileNames) {
      if (name.endsWith('/')) continue; // Skip directories
      for (final prefix in _assetFolderPrefixes) {
        if (name.startsWith(prefix)) {
          count++;
          break; // Don't double-count
        }
      }
    }
    return count;
  }
}
