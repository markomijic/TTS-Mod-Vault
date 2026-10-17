import 'package:file/file.dart' show FileSystem;
import 'package:file/local.dart' show LocalFileSystem;
import 'package:tts_mod_vault/data/fs/zip/zip_central_directory_reader.dart';

/// Counts asset files in specific zip subdirectories without reading file
/// data. Ported verbatim from v2.
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
  static Future<int> countAssets(String zipPath) =>
      countAssetsWith(zipPath, const LocalFileSystem());

  /// [countAssets] against an arbitrary [FileSystem].
  static Future<int> countAssetsWith(String zipPath, FileSystem fs) async {
    try {
      final fileNames = await ZipCentralDirectoryReader.readFileNamesWith(
        zipPath,
        fs,
      );
      return countAssetsFromFileNames(fileNames);
    } catch (_) {
      return 0;
    }
  }

  /// Counts assets from an already-parsed list of filenames. Entry names
  /// are expected with `/` separators (as [ZipCentralDirectoryReader]
  /// returns them); directory entries (trailing `/`) are skipped and the
  /// prefix match is case-sensitive.
  static int countAssetsFromFileNames(List<String> fileNames) {
    var count = 0;
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

/// Counts the backup assets of every archive in [zipPaths] on the local file
/// system and returns the counts in the same order; an archive that cannot be
/// read counts as 0.
///
/// Worker entry point (ported from v2 `_countAssetsForFiles`); see
/// `fs_tasks.dart`.
Future<List<int>> countBackupAssets(List<String> zipPaths) =>
    countBackupAssetsWith(zipPaths, const LocalFileSystem());

/// [countBackupAssets] against an arbitrary [FileSystem].
Future<List<int>> countBackupAssetsWith(
  List<String> zipPaths,
  FileSystem fs,
) async {
  final counts = <int>[];
  for (final zipPath in zipPaths) {
    counts.add(await ZipAssetCounter.countAssetsWith(zipPath, fs));
  }
  return counts;
}
