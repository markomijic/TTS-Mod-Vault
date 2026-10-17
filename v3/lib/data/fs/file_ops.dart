/// The injectable [FileSystem] and the small file operations the per-mod
/// edits need (rewrite in place, delete if present, rename keeping the
/// extension).
///
/// Everything here goes through `package:file` so a test can substitute a
/// `MemoryFileSystem`; the worker tasks keep using `dart:io` directly, as
/// they run on other isolates.
library;

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;

/// The file system the application layer writes through. The default is the
/// real one; tests override it with a `MemoryFileSystem` where the code under
/// test does not also need worker isolates.
final fileSystemProvider = Provider<FileSystem>((_) => const LocalFileSystem());

/// File operations shared by the mod edit features.
extension FileOps on FileSystem {
  /// Writes [contents] (UTF-8) to the file at [path] without resetting its
  /// creation time.
  ///
  /// `writeAsString` recreates the file (`CREATE_ALWAYS` on Windows), which
  /// resets the creation timestamp some users sort by. Opening in append
  /// mode (`OPEN_ALWAYS`), truncating and writing keeps it (v2
  /// `_writeStringPreservingCreationTime`). The file is created when absent.
  Future<void> writeStringPreservingCreationTime(
    String path,
    String contents,
  ) async {
    final raf = await file(path).open(mode: FileMode.append);
    try {
      await raf.truncate(0);
      await raf.setPosition(0);
      await raf.writeString(contents);
    } finally {
      await raf.close();
    }
  }

  /// Deletes the file at [path] when it exists. Returns whether a file was
  /// deleted.
  Future<bool> deleteIfExists(String path) async {
    final target = file(path);
    if (!target.existsSync()) return false;
    await target.delete();
    return true;
  }

  /// Renames the file at [path] to [newBaseName] plus the file's current
  /// extension, in the same folder, and returns the new normalised path.
  ///
  /// Returns null without doing anything when the source is gone (the
  /// caller's view of the cache was stale), and [path] itself when the name
  /// does not change. Throws a [FileSystemException] when a different file
  /// already occupies the target name, so nothing is ever overwritten.
  Future<String?> renameKeepingExtension(
    String path,
    String newBaseName,
  ) async {
    final source = file(path);
    if (!source.existsSync()) return null;
    final newPath = p.normalize(
      p.join(p.dirname(path), '$newBaseName${p.extension(path)}'),
    );
    if (p.equals(newPath, path)) return path;
    if (file(newPath).existsSync() || directory(newPath).existsSync()) {
      throw FileSystemException('Target already exists', newPath);
    }
    final renamed = await source.rename(newPath);
    return p.normalize(renamed.path);
  }
}
