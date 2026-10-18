import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:path/path.dart' show Context;
import 'package:tts_mod_vault/domain/constants.dart';
import 'package:tts_mod_vault/domain/enums/mod_type.dart';

/// Input of [scanModFiles]: one TTS root to walk for mod/save JSON files.
///
/// Plain data so it can be sent to a worker isolate.
final class ModFileScanRequest {
  const ModFileScanRequest({
    required this.rootDir,
    required this.type,
    this.ignoredSubfolders = const [],
  });

  /// Directory to walk recursively (`Mods/Workshop`, `Saves`,
  /// `Saves/Saved Objects`).
  final String rootDir;

  /// The [ModType] every JSON found under [rootDir] is reported as.
  final ModType type;

  /// Folder names whose contents are skipped. A JSON is skipped when any
  /// segment of its directory path *relative to [rootDir]* equals one of
  /// these names exactly (case-sensitive, whole segment, not substring).
  ///
  /// Callers scanning the `Saves` root must include [ttsSavedObjectsFolder]
  /// here, because saved objects live in `Saves/Saved Objects` and are
  /// scanned separately with [ModType.savedObject].
  final List<String> ignoredSubfolders;
}

/// One mod/save JSON file found by [scanModFiles], with the file metadata
/// the refresh pipeline diffs against the store.
final class ModFileEntry {
  const ModFileEntry({
    required this.jsonPath,
    required this.type,
    required this.folder,
    required this.mtimeMs,
    required this.sizeBytes,
    required this.imagePath,
  });

  /// Normalised absolute path of the JSON file.
  final String jsonPath;

  /// Type requested in [ModFileScanRequest.type].
  final ModType type;

  /// Name of the directory that directly contains the JSON file.
  final String folder;

  /// Last modification time in milliseconds since epoch.
  final int mtimeMs;

  /// File size in bytes.
  final int sizeBytes;

  /// Normalised path of the sibling image, if one exists: `<dir>/<name>.png`
  /// is preferred over `<dir>/Thumbnails/<name>.png` (v2 behaviour). The
  /// match is case-insensitive (so `Foo.PNG` is found, as v2's `exists()`
  /// did on Windows) and the real on-disk path is returned.
  final String? imagePath;

  @override
  String toString() =>
      'ModFileEntry($jsonPath, $type, folder: $folder, mtimeMs: $mtimeMs, '
      'size: $sizeBytes, image: $imagePath)';
}

/// Output of [scanModFiles].
final class ModFileScanResult {
  const ModFileScanResult({required this.entries, required this.warnings});

  /// Files found, in file-system listing order.
  final List<ModFileEntry> entries;

  /// Non-fatal problems: missing root directory, directories that could not
  /// be listed, files that could not be stat'ed (those files are omitted
  /// from [entries]). Empty when everything was read.
  final List<String> warnings;
}

/// Lists every mod/save JSON under [req]'s root on the local file system.
///
/// Worker entry point: top-level, one sendable argument, sendable result.
/// See `fs_tasks.dart` for usage with `WorkerPool.run`.
Future<ModFileScanResult> scanModFiles(ModFileScanRequest req) =>
    scanModFilesWith(req, const LocalFileSystem());

/// [scanModFiles] against an arbitrary [FileSystem] (tests use
/// `MemoryFileSystem`).
///
/// Rules (ported from v2 `getJsonFilesInDirectory`):
/// * recursive walk, symlinks not followed;
/// * `.json` extension matched case-insensitively;
/// * [ttsIndexFileNames] (`WorkshopFileInfos.json`, `SaveFileInfos.json`)
///   are skipped wherever they appear;
/// * JSONs under an ignored subfolder segment are skipped (see
///   [ModFileScanRequest.ignoredSubfolders]);
/// * each JSON is stat'ed once; the image lookup reuses the directory
///   listing instead of touching the disk again.
///
/// Never throws for a missing or unreadable directory: such problems are
/// reported in [ModFileScanResult.warnings].
Future<ModFileScanResult> scanModFilesWith(
  ModFileScanRequest req,
  FileSystem fs,
) async {
  final p = fs.path;
  final warnings = <String>[];
  final rootPath = p.normalize(req.rootDir);
  final root = fs.directory(rootPath);

  if (!root.existsSync()) {
    warnings.add('Directory not found: $rootPath');
    return ModFileScanResult(entries: const [], warnings: warnings);
  }

  // Every file seen during the walk, keyed by its lower-cased normalised path
  // (value: the real path), so the sibling-image lookup is a case-insensitive
  // map lookup instead of two existence checks per JSON.
  final allFiles = <String, String>{};
  final jsonPaths = <String>[];

  try {
    final listing = root.list(recursive: true, followLinks: false).handleError((
      Object error,
    ) {
      warnings.add('Could not list part of $rootPath: $error');
    });
    await for (final entity in listing) {
      if (entity is! File) continue;
      final filePath = p.normalize(entity.path);
      allFiles.putIfAbsent(filePath.toLowerCase(), () => filePath);

      if (p.extension(filePath).toLowerCase() != '.json') continue;
      if (ttsIndexFileNames.contains(p.basename(filePath))) continue;
      if (_isUnderIgnoredFolder(p, filePath, rootPath, req.ignoredSubfolders)) {
        continue;
      }
      jsonPaths.add(filePath);
    }
  } catch (error) {
    warnings.add('Could not list $rootPath: $error');
  }

  final entries = <ModFileEntry>[];
  for (final jsonPath in jsonPaths) {
    final FileStat stat;
    try {
      stat = fs.file(jsonPath).statSync();
    } catch (error) {
      warnings.add('Could not stat $jsonPath: $error');
      continue;
    }
    if (stat.type == FileSystemEntityType.notFound) {
      warnings.add('File disappeared during scan: $jsonPath');
      continue;
    }

    final dir = p.dirname(jsonPath);
    final name = p.basenameWithoutExtension(jsonPath);
    entries.add(
      ModFileEntry(
        jsonPath: jsonPath,
        type: req.type,
        folder: p.basename(dir),
        mtimeMs: stat.modified.millisecondsSinceEpoch,
        sizeBytes: stat.size,
        imagePath: _findImage(p, allFiles, dir, name),
      ),
    );
  }

  return ModFileScanResult(entries: entries, warnings: warnings);
}

bool _isUnderIgnoredFolder(
  Context p,
  String filePath,
  String rootPath,
  List<String> ignoredSubfolders,
) {
  if (ignoredSubfolders.isEmpty) return false;
  final relativeDir = p.dirname(p.relative(filePath, from: rootPath));
  if (relativeDir == '.') return false;
  return p.split(relativeDir).any(ignoredSubfolders.contains);
}

/// [allFiles] maps lower-cased normalised paths to real paths.
String? _findImage(
  Context p,
  Map<String, String> allFiles,
  String dir,
  String name,
) {
  final beside = p.join(dir, '$name.png').toLowerCase();
  final thumbnail = p.join(dir, ttsThumbnailsFolder, '$name.png').toLowerCase();
  return allFiles[beside] ?? allFiles[thumbnail];
}
