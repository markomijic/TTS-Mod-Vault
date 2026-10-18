import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:tts_mod_vault/domain/constants.dart';

/// Input of [scanBackupFiles]: the user's backups folder.
final class BackupScanRequest {
  const BackupScanRequest({required this.backupsDir});

  /// Directory to walk recursively for `.ttsmod` archives.
  final String backupsDir;
}

/// One `.ttsmod` archive found by [scanBackupFiles].
final class BackupFileEntry {
  const BackupFileEntry({
    required this.path,
    required this.fileName,
    required this.folder,
    required this.mtimeMs,
    required this.sizeBytes,
  });

  /// Normalised absolute path.
  final String path;

  /// File name including the `.ttsmod` extension.
  final String fileName;

  /// Name of the directory that directly contains the archive.
  final String folder;

  /// Last modification time in milliseconds since epoch.
  final int mtimeMs;

  /// File size in bytes.
  final int sizeBytes;

  @override
  String toString() =>
      'BackupFileEntry($path, folder: $folder, mtimeMs: $mtimeMs, '
      'size: $sizeBytes)';
}

/// Output of [scanBackupFiles].
final class BackupScanResult {
  const BackupScanResult({required this.entries, required this.warnings});

  /// Archives found, in file-system listing order.
  final List<BackupFileEntry> entries;

  /// Non-fatal problems: missing or empty directory path, listing errors,
  /// files that could not be stat'ed (omitted from [entries]).
  final List<String> warnings;
}

/// Lists every `.ttsmod` archive under the backups folder on the local file
/// system.
///
/// Worker entry point; see `fs_tasks.dart`.
Future<BackupScanResult> scanBackupFiles(BackupScanRequest req) =>
    scanBackupFilesWith(req, const LocalFileSystem());

/// [scanBackupFiles] against an arbitrary [FileSystem].
///
/// Ported from v2 `loadExistingBackups`: recursive walk, extension matched
/// case-insensitively against [ttsmodExtension], each file stat'ed once.
/// Asset counts are not computed here; see `zip/zip_asset_counter.dart`.
Future<BackupScanResult> scanBackupFilesWith(
  BackupScanRequest req,
  FileSystem fs,
) async {
  final p = fs.path;
  final warnings = <String>[];

  if (req.backupsDir.trim().isEmpty) {
    warnings.add('Backups directory is not set');
    return BackupScanResult(entries: const [], warnings: warnings);
  }

  final dirPath = p.normalize(req.backupsDir);
  final directory = fs.directory(dirPath);
  if (!directory.existsSync()) {
    warnings.add('Directory not found: $dirPath');
    return BackupScanResult(entries: const [], warnings: warnings);
  }

  final entries = <BackupFileEntry>[];
  try {
    final listing = directory
        .list(recursive: true, followLinks: false)
        .handleError((Object error) {
          warnings.add('Could not list part of $dirPath: $error');
        });
    await for (final entity in listing) {
      if (entity is! File) continue;
      final filePath = p.normalize(entity.path);
      if (p.extension(filePath).toLowerCase() != ttsmodExtension) continue;

      final FileStat stat;
      try {
        stat = entity.statSync();
      } catch (error) {
        warnings.add('Could not stat $filePath: $error');
        continue;
      }
      if (stat.type == FileSystemEntityType.notFound) {
        warnings.add('File disappeared during scan: $filePath');
        continue;
      }

      entries.add(
        BackupFileEntry(
          path: filePath,
          fileName: p.basename(filePath),
          folder: p.basename(p.dirname(filePath)),
          mtimeMs: stat.modified.millisecondsSinceEpoch,
          sizeBytes: stat.size,
        ),
      );
    }
  } catch (error) {
    warnings.add('Could not list $dirPath: $error');
  }

  return BackupScanResult(entries: entries, warnings: warnings);
}
