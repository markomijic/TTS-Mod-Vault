/// Streaming creation of `.ttsmod` (zip) archives.
///
/// Every source file is piped through `package:archive`'s deflate encoder
/// straight into the output file (`ZipFileEncoder.addFile` with an
/// `InputFileStream`), so a multi-GB backup never holds more than the
/// encoder's buffers in memory. The archive is written to `<target>.part`
/// and renamed to the final name only after the central directory is
/// complete, so a cancelled or failed run never leaves a half-written
/// `.ttsmod` behind.
///
/// Two ways to run it:
/// * [writeZipArchive] is a plain `WorkerPool` task (one result, no
///   progress), for callers that do not need a progress bar.
/// * [BackupZipIsolate.write] runs the same routine on a dedicated isolate
///   that reports a [ZipProgress] after every entry and stops cooperatively
///   when the [CancellationToken] is cancelled (see
///   `zip_progress_isolate.dart` for why a pool task cannot do that).
///
/// The archive streams need `dart:io` paths; tests use a temp directory.
library;

import 'dart:io';

import 'package:archive/archive_io.dart' show ZipFileEncoder;
import 'package:tts_mod_vault/core/cancellation/cancellation_token.dart';
import 'package:tts_mod_vault/data/fs/zip/zip_progress_isolate.dart';

export 'package:tts_mod_vault/data/fs/zip/zip_progress_isolate.dart'
    show ZipIsolateException, ZipProgress, ZipProgressCallback;

/// Suffix of the temporary file an archive is written to before the rename.
const zipPartSuffix = '.part';

/// One file to add: [sourcePath] on disk, stored as [entryName] (any
/// separator; backslashes become `/`).
typedef ZipWriteEntry = ({String sourcePath, String entryName});

/// Input of [writeZipArchive]: the archive to create and its entries.
final class ZipWriteRequest {
  /// Creates a request.
  const ZipWriteRequest({required this.targetPath, required this.entries});

  /// Final path of the archive; `<targetPath>.part` is used while writing.
  /// An existing file at this path is replaced on success.
  final String targetPath;

  /// Files to add, in archive order.
  final List<ZipWriteEntry> entries;
}

/// Output of [writeZipArchive].
final class ZipWriteResult {
  /// Creates a result.
  const ZipWriteResult({
    required this.written,
    required this.skipped,
    required this.bytes,
  });

  /// Entries added to the archive.
  final int written;

  /// Source paths that did not exist when their turn came (left out).
  final List<String> skipped;

  /// Size of the finished archive in bytes.
  final int bytes;

  @override
  String toString() =>
      'ZipWriteResult(written: $written, skipped: ${skipped.length}, '
      'bytes: $bytes)';
}

/// Zip entry name for [name]: separators normalised to `/`, as the zip
/// format requires (APPNOTE 4.4.17).
String zipEntryName(String name) => name.replaceAll(r'\', '/');

/// Writes the archive described by [req] on the local file system.
///
/// Worker entry point for `WorkerPool.run`; see the library comment.
Future<ZipWriteResult> writeZipArchive(ZipWriteRequest req) =>
    writeZipArchiveWith(req);

/// [writeZipArchive] with hooks: [onProgress] is called after every entry
/// (written or skipped) and [isCancelled] is polled before each one; when it
/// answers `true` the partial archive is deleted and
/// [OperationCancelledException] is thrown. Any other error also deletes the
/// partial archive before propagating.
Future<ZipWriteResult> writeZipArchiveWith(
  ZipWriteRequest req, {
  ZipProgressCallback? onProgress,
  ZipCancelCheck? isCancelled,
}) async {
  final target = File(req.targetPath);
  final part = File('${req.targetPath}$zipPartSuffix');
  await target.parent.create(recursive: true);
  if (part.existsSync()) await part.delete();

  final encoder = ZipFileEncoder()..create(part.path);
  var encoderOpen = true;
  final skipped = <String>[];
  var written = 0;
  final total = req.entries.length;
  try {
    for (var i = 0; i < total; i++) {
      if (isCancelled?.call() ?? false) {
        throw const OperationCancelledException('Backup cancelled');
      }
      final entry = req.entries[i];
      final source = File(entry.sourcePath);
      if (!source.existsSync()) {
        skipped.add(entry.sourcePath);
      } else {
        await encoder.addFile(source, zipEntryName(entry.entryName));
        written++;
      }
      onProgress?.call(
        ZipProgress(done: i + 1, total: total, entryName: entry.entryName),
      );
    }
    await encoder.close();
    encoderOpen = false;
    if (target.existsSync()) await target.delete();
    await part.rename(target.path);
    return ZipWriteResult(
      written: written,
      skipped: skipped,
      bytes: target.lengthSync(),
    );
  } catch (_) {
    if (encoderOpen) {
      try {
        await encoder.close();
      } catch (_) {
        // The output handle is what matters; the archive is deleted next.
      }
    }
    try {
      if (part.existsSync()) await part.delete();
    } catch (_) {
      // Best effort: a leftover `.part` is replaced by the next attempt.
    }
    rethrow;
  }
}

/// Entry point of the progress-reporting writer isolate.
Future<void> zipWriteIsolateMain(ZipIsolateArgs<ZipWriteRequest> args) =>
    runZipIsolateBody<ZipWriteRequest, ZipWriteResult>(
      args,
      writeZipArchiveWith,
    );

/// Writes archives on a dedicated isolate with per-entry progress and
/// cooperative cancellation (the v2 `_backupIsolate` role).
abstract final class BackupZipIsolate {
  /// Runs [writeZipArchive] for [req] on a new isolate. [onProgress]
  /// receives a snapshot after every entry; cancelling [token] stops the
  /// write after the entry in flight, deletes the `.part` file and fails the
  /// future with [OperationCancelledException]. Other failures surface as
  /// [ZipIsolateException].
  static Future<ZipWriteResult> write(
    ZipWriteRequest req, {
    ZipProgressCallback? onProgress,
    CancellationToken? token,
  }) => runZipIsolate<ZipWriteRequest, ZipWriteResult>(
    zipWriteIsolateMain,
    req,
    onProgress: onProgress,
    token: token,
    debugName: 'backup-zip',
  );
}
