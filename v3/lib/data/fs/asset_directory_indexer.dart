import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:tts_mod_vault/domain/enums/asset_type.dart';
import 'package:tts_mod_vault/domain/rules/file_key.dart';

/// Input of [indexAssetDirectory]: one TTS asset cache folder
/// (`Mods/Images`, `Mods/Models`, ...).
final class AssetIndexRequest {
  const AssetIndexRequest({required this.type, required this.directory});

  /// Asset type the folder holds; echoed in the result.
  final AssetType type;

  /// Directory to list (non-recursive).
  final String directory;
}

/// Output of [indexAssetDirectory].
final class AssetIndexResult {
  const AssetIndexResult({
    required this.type,
    required this.files,
    required this.warnings,
  });

  /// Type from the request.
  final AssetType type;

  /// One record per file: `fileKey` is `fileKeyFromFileName(basename without
  /// extension)` (legacy host rewritten, lower-cased); `path` is the
  /// normalised absolute path. Keys are unique within the list.
  final List<({String fileKey, String path})> files;

  /// Non-fatal problems: missing directory, listing errors, and one entry per
  /// key collision (the first file wins, later ones are dropped).
  final List<String> warnings;
}

/// Indexes every file directly inside the request's directory on the local
/// file system.
///
/// Worker entry point; see `fs_tasks.dart`.
Future<AssetIndexResult> indexAssetDirectory(AssetIndexRequest req) =>
    indexAssetDirectoryWith(req, const LocalFileSystem());

/// [indexAssetDirectory] against an arbitrary [FileSystem].
///
/// Like v2 `_getDirectoryFileNamesAndPaths`, nothing is filtered: `_temp`
/// download leftovers and raw `file*` entries are kept and left to callers.
/// Sub-directories are not entered. When two files map to the same key (for
/// example `x.png` and `x.PNG` on a case-sensitive file system) the first one
/// listed is kept and a warning is added.
Future<AssetIndexResult> indexAssetDirectoryWith(
  AssetIndexRequest req,
  FileSystem fs,
) async {
  final p = fs.path;
  final warnings = <String>[];
  final dirPath = p.normalize(req.directory);
  final directory = fs.directory(dirPath);

  if (!directory.existsSync()) {
    warnings.add('Directory not found: $dirPath');
    return AssetIndexResult(
      type: req.type,
      files: const [],
      warnings: warnings,
    );
  }

  final files = <({String fileKey, String path})>[];
  final firstPathByKey = <String, String>{};

  try {
    final listing = directory.list(followLinks: false).handleError((
      Object error,
    ) {
      warnings.add('Could not list part of $dirPath: $error');
    });
    await for (final entity in listing) {
      if (entity is! File) continue;
      final filePath = p.normalize(entity.path);
      final key = fileKeyFromFileName(p.basenameWithoutExtension(filePath));
      final existing = firstPathByKey[key];
      if (existing != null) {
        warnings.add(
          'Duplicate asset key "$key": keeping $existing, ignoring $filePath',
        );
        continue;
      }
      firstPathByKey[key] = filePath;
      files.add((fileKey: key, path: filePath));
    }
  } catch (error) {
    warnings.add('Could not list $dirPath: $error');
  }

  return AssetIndexResult(type: req.type, files: files, warnings: warnings);
}
