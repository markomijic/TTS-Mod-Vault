/// Directory listings for the orphaned-asset cleanup (v2
/// `processDirectoryInIsolate`), packaged as `WorkerPool` tasks.
///
/// The `existing_files` index already knows which cached files no mod
/// references (`LibraryQueries.orphanedExistingFiles`), but it keeps one
/// path per key and does not cover the `Images Raw` / `Models Raw` folders,
/// so the cleanup still lists every folder once to find:
///
/// * legacy-host duplicates: a file named after the old
///   `cloud-3.steamusercontent.com` URL whose current-host twin also exists
///   (both map to one index key, so only the listing sees the pair);
/// * raw-folder files to check against the index by key (files whose name
///   starts with `file` are TTS-generated and never candidates).
library;

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:tts_mod_vault/domain/enums/asset_type.dart';
import 'package:tts_mod_vault/domain/rules/file_key.dart';

/// Base-name prefix of raw files TTS writes itself (`file12345.rawt`).
const cleanupSkippedPrefix = 'file';

/// Input of [scanCleanupDirectory]: one cache folder.
final class CleanupDirScanRequest {
  /// Creates a request.
  const CleanupDirScanRequest({
    required this.type,
    required this.directory,
    required this.includeFiles,
  });

  /// Asset type the folder holds (echoed in the result).
  final AssetType type;

  /// Folder to list (non-recursive).
  final String directory;

  /// Whether [CleanupDirScanResult.files] is filled. The raw folders need
  /// it (they are not indexed); the main folders only need the legacy
  /// duplicates, so a listing of thousands of entries is not sent back.
  final bool includeFiles;
}

/// One listed file: normalised [path], index [fileKey]
/// (`fileKeyFromFileName`) and [sizeBytes].
typedef CleanupFileEntry = ({String path, String fileKey, int sizeBytes});

/// A legacy-host file whose current-host twin exists: [path] is the legacy
/// file, [twinPath] the one that stays.
typedef CleanupLegacyDuplicate = ({
  String path,
  String twinPath,
  String fileKey,
  int sizeBytes,
});

/// Output of [scanCleanupDirectory].
final class CleanupDirScanResult {
  /// Creates a result.
  const CleanupDirScanResult({
    required this.type,
    required this.directory,
    required this.files,
    required this.legacyDuplicates,
    required this.warnings,
  });

  /// Type from the request.
  final AssetType type;

  /// Normalised folder path.
  final String directory;

  /// Every file of the folder except `file*` names and legacy duplicates;
  /// empty unless the request asked for it.
  final List<CleanupFileEntry> files;

  /// Legacy-host files whose current-host twin is in the same folder.
  final List<CleanupLegacyDuplicate> legacyDuplicates;

  /// Non-fatal problems (missing folder, listing or stat errors).
  final List<String> warnings;
}

/// Lists the request's folder on the local file system.
///
/// Worker entry point; see `fs_tasks.dart`.
Future<CleanupDirScanResult> scanCleanupDirectory(CleanupDirScanRequest req) =>
    scanCleanupDirectoryWith(req, const LocalFileSystem());

/// [scanCleanupDirectory] against an arbitrary [FileSystem].
Future<CleanupDirScanResult> scanCleanupDirectoryWith(
  CleanupDirScanRequest req,
  FileSystem fs,
) async {
  final p = fs.path;
  final warnings = <String>[];
  final dirPath = p.normalize(req.directory);
  final directory = fs.directory(dirPath);
  final files = <CleanupFileEntry>[];
  final duplicates = <CleanupLegacyDuplicate>[];

  if (!directory.existsSync()) {
    warnings.add('Directory not found: $dirPath');
    return CleanupDirScanResult(
      type: req.type,
      directory: dirPath,
      files: files,
      legacyDuplicates: duplicates,
      warnings: warnings,
    );
  }

  final candidates = <({String path, String base})>[];
  final presentBases = <String>{};
  try {
    final listing = directory.list(followLinks: false).handleError((
      Object error,
    ) {
      warnings.add('Could not list part of $dirPath: $error');
    });
    await for (final entity in listing) {
      if (entity is! File) continue;
      final filePath = p.normalize(entity.path);
      final base = p.basenameWithoutExtension(filePath);
      presentBases.add(base);
      if (base.startsWith(cleanupSkippedPrefix)) continue;
      candidates.add((path: filePath, base: base));
    }
  } catch (error) {
    warnings.add('Could not list $dirPath: $error');
  }

  for (final candidate in candidates) {
    final int size;
    try {
      size = fs.file(candidate.path).statSync().size;
    } catch (error) {
      warnings.add('Could not stat ${candidate.path}: $error');
      continue;
    }
    final key = fileKeyFromFileName(candidate.base);
    if (candidate.base.startsWith(oldCloudFilePrefix)) {
      final twinBase = candidate.base.replaceFirst(
        oldCloudFilePrefix,
        newSteamFilePrefix,
      );
      if (presentBases.contains(twinBase)) {
        duplicates.add((
          path: candidate.path,
          twinPath: p.join(dirPath, '$twinBase${p.extension(candidate.path)}'),
          fileKey: key,
          sizeBytes: size,
        ));
        continue;
      }
    }
    if (req.includeFiles) {
      files.add((path: candidate.path, fileKey: key, sizeBytes: size));
    }
  }

  return CleanupDirScanResult(
    type: req.type,
    directory: dirPath,
    files: files,
    legacyDuplicates: duplicates,
    warnings: warnings,
  );
}

/// Sizes in bytes of [paths], in order; `-1` for a file that cannot be
/// stat'ed (gone since it was indexed).
///
/// Worker entry point; see `fs_tasks.dart`.
Future<List<int>> statFileSizes(List<String> paths) =>
    statFileSizesWith(paths, const LocalFileSystem());

/// [statFileSizes] against an arbitrary [FileSystem].
Future<List<int>> statFileSizesWith(List<String> paths, FileSystem fs) async {
  final sizes = <int>[];
  for (final path in paths) {
    try {
      final stat = fs.file(path).statSync();
      sizes.add(stat.type == FileSystemEntityType.notFound ? -1 : stat.size);
    } catch (_) {
      sizes.add(-1);
    }
  }
  return sizes;
}
