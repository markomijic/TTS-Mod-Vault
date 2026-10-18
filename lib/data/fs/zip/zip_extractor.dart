/// Streaming inspection and extraction of `.ttsmod` (zip) archives.
///
/// [listZipEntries] decodes only the archive's directory structure through
/// an `InputFileStream` (entry contents stay on disk as lazy views), and
/// [extractZipEntries] inflates each selected entry straight into an
/// `OutputFileStream`, so importing a multi-GB backup keeps memory flat.
/// [readZipEntryBytes] reads one entry (the mod JSON) into memory.
///
/// Like the writer, the plain functions are `WorkerPool` tasks and
/// [ImportZipIsolate.extract] runs the extraction on a dedicated isolate
/// with per-entry progress and cooperative cancellation. The archive
/// streams need `dart:io` paths; tests use a temp directory.
library;

import 'dart:io';
import 'dart:typed_data' show Uint8List;

import 'package:archive/archive.dart'
    show ArchiveFile, InputFileStream, OutputFileStream, ZipDecoder;
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/core/cancellation/cancellation_token.dart';
import 'package:tts_mod_vault/data/fs/zip/zip_progress_isolate.dart';
import 'package:tts_mod_vault/data/fs/zip/zip_writer.dart' show zipEntryName;

export 'package:tts_mod_vault/data/fs/zip/zip_progress_isolate.dart'
    show ZipIsolateException, ZipProgress, ZipProgressCallback;

/// One archive entry as [listZipEntries] reports it.
final class ZipEntryInfo {
  /// Creates an entry description.
  const ZipEntryInfo({
    required this.name,
    required this.size,
    required this.isFile,
  });

  /// Entry name with `/` separators (backslashes normalised).
  final String name;

  /// Uncompressed size in bytes (0 for directories).
  final int size;

  /// Whether the entry is a file (directory entries end in `/`).
  final bool isFile;

  @override
  String toString() => 'ZipEntryInfo($name, $size bytes, file: $isFile)';
}

/// Output of [listZipEntries].
final class ZipEntryListing {
  /// Creates a listing.
  const ZipEntryListing({required this.entries});

  /// Entries in archive order.
  final List<ZipEntryInfo> entries;

  /// File entries only.
  Iterable<ZipEntryInfo> get files => entries.where((e) => e.isFile);
}

/// Lists the entries of the archive at [zipPath] without reading any
/// content. Throws a [FileSystemException] when the file is missing and a
/// [FormatException] when it is not a zip (the decoder itself is lenient
/// and yields an empty archive for arbitrary bytes, which would let a
/// corrupt `.ttsmod` "import" nothing without a word).
///
/// Worker entry point for `WorkerPool.run`.
Future<ZipEntryListing> listZipEntries(String zipPath) async {
  final input = InputFileStream(zipPath);
  try {
    final archive = ZipDecoder().decodeStream(input);
    final entries = <ZipEntryInfo>[
      for (final file in archive)
        ZipEntryInfo(
          name: zipEntryName(file.name),
          size: file.isFile ? file.size : 0,
          isFile: file.isFile,
        ),
    ];
    if (entries.isEmpty && !_hasZipSignature(zipPath)) {
      throw FormatException('Not a zip archive', zipPath);
    }
    return ZipEntryListing(entries: entries);
  } finally {
    await input.close();
  }
}

/// Whether the file starts with a local file header (`PK`) or,
/// for an archive without entries, with the end-of-central-directory
/// record (`PK`).
bool _hasZipSignature(String zipPath) {
  final raf = File(zipPath).openSync();
  try {
    final head = raf.readSync(4);
    if (head.length < 4 || head[0] != 0x50 || head[1] != 0x4b) return false;
    return (head[2] == 0x03 && head[3] == 0x04) ||
        (head[2] == 0x05 && head[3] == 0x06);
  } finally {
    raf.closeSync();
  }
}

/// Input of [readZipEntryBytes].
final class ZipEntryReadRequest {
  /// Creates a request.
  const ZipEntryReadRequest({required this.zipPath, required this.entryName});

  /// The archive.
  final String zipPath;

  /// Entry to read, with `/` separators.
  final String entryName;
}

/// Reads the uncompressed bytes of one entry, or null when the archive has
/// no file entry of that name. Only that entry is inflated.
///
/// Worker entry point for `WorkerPool.run`.
Future<Uint8List?> readZipEntryBytes(ZipEntryReadRequest req) async {
  final input = InputFileStream(req.zipPath);
  try {
    final archive = ZipDecoder().decodeStream(input);
    final wanted = zipEntryName(req.entryName);
    for (final file in archive) {
      if (file.isFile && zipEntryName(file.name) == wanted) {
        return file.readBytes();
      }
    }
    return null;
  } finally {
    await input.close();
  }
}

/// Input of [extractZipEntries]: the archive and, per entry name (with `/`
/// separators), the path to write it to. Entries absent from [outputs] or
/// mapped to null are skipped; directory entries are never written.
final class ZipExtractRequest {
  /// Creates a request.
  const ZipExtractRequest({required this.zipPath, required this.outputs});

  /// The archive.
  final String zipPath;

  /// `entryName -> outputPath`, null to skip.
  final Map<String, String?> outputs;
}

/// One extracted entry.
typedef ZipExtractedEntry = ({String entryName, String outputPath});

/// One entry that could not be written.
typedef ZipExtractFailure = ({String entryName, String error});

/// Output of [extractZipEntries].
final class ZipExtractResult {
  /// Creates a result.
  const ZipExtractResult({
    required this.extracted,
    required this.failed,
    this.cancelled = false,
  });

  /// Entries written, in archive order.
  final List<ZipExtractedEntry> extracted;

  /// Entries whose output could not be written (the partial file is
  /// deleted); extraction continues with the next entry.
  final List<ZipExtractFailure> failed;

  /// Whether the run stopped early because cancellation was requested;
  /// [extracted] then holds what was written before.
  final bool cancelled;

  @override
  String toString() =>
      'ZipExtractResult(extracted: ${extracted.length}, '
      'failed: ${failed.length}${cancelled ? ', cancelled' : ''})';
}

/// Extracts the selected entries of [req] on the local file system,
/// creating parent folders and overwriting existing files.
///
/// Worker entry point for `WorkerPool.run`.
Future<ZipExtractResult> extractZipEntries(ZipExtractRequest req) =>
    extractZipEntriesWith(req);

/// [extractZipEntries] with hooks: [onProgress] after every file entry
/// (written or skipped), [isCancelled] polled before each one. A cancel
/// does not throw: the result comes back with `cancelled: true` and the
/// entries written so far, so the caller can still index them.
Future<ZipExtractResult> extractZipEntriesWith(
  ZipExtractRequest req, {
  ZipProgressCallback? onProgress,
  ZipCancelCheck? isCancelled,
}) async {
  final extracted = <ZipExtractedEntry>[];
  final failed = <ZipExtractFailure>[];
  final input = InputFileStream(req.zipPath);
  try {
    final archive = ZipDecoder().decodeStream(input);
    final files = <ArchiveFile>[
      for (final file in archive)
        if (file.isFile) file,
    ];
    final total = files.length;
    for (var i = 0; i < total; i++) {
      if (isCancelled?.call() ?? false) {
        return ZipExtractResult(
          extracted: extracted,
          failed: failed,
          cancelled: true,
        );
      }
      final file = files[i];
      final name = zipEntryName(file.name);
      final outputPath = req.outputs[name];
      if (outputPath != null) {
        try {
          _writeEntry(file, outputPath);
          extracted.add((entryName: name, outputPath: outputPath));
        } catch (error) {
          failed.add((entryName: name, error: error.toString()));
        }
      }
      onProgress?.call(ZipProgress(done: i + 1, total: total, entryName: name));
    }
    return ZipExtractResult(extracted: extracted, failed: failed);
  } finally {
    await input.close();
  }
}

/// Inflates [file] into [outputPath] through an `OutputFileStream`; a
/// partial file is deleted when the write fails.
void _writeEntry(ArchiveFile file, String outputPath) {
  Directory(p.dirname(outputPath)).createSync(recursive: true);
  final output = OutputFileStream(
    outputPath,
    bufferSize: file.size < OutputFileStream.kDefaultBufferSize
        ? (file.size < 1 ? 1 : file.size)
        : OutputFileStream.kDefaultBufferSize,
  );
  try {
    file.writeContent(output);
  } catch (_) {
    output.closeSync();
    try {
      File(outputPath).deleteSync();
    } catch (_) {
      // Nothing more to do; the failure itself is reported.
    }
    rethrow;
  }
  output.closeSync();
}

/// Entry point of the progress-reporting extractor isolate.
Future<void> zipExtractIsolateMain(ZipIsolateArgs<ZipExtractRequest> args) =>
    runZipIsolateBody<ZipExtractRequest, ZipExtractResult>(
      args,
      extractZipEntriesWith,
    );

/// Extracts archives on a dedicated isolate with per-entry progress and
/// cooperative cancellation.
abstract final class ImportZipIsolate {
  /// Runs [extractZipEntries] for [req] on a new isolate. [onProgress]
  /// receives a snapshot after every file entry; cancelling [token] stops
  /// the extraction after the entry in flight and the result comes back
  /// with `cancelled: true`. Failures surface as [ZipIsolateException].
  static Future<ZipExtractResult> extract(
    ZipExtractRequest req, {
    ZipProgressCallback? onProgress,
    CancellationToken? token,
  }) => runZipIsolate<ZipExtractRequest, ZipExtractResult>(
    zipExtractIsolateMain,
    req,
    onProgress: onProgress,
    token: token,
    debugName: 'import-zip',
  );
}
