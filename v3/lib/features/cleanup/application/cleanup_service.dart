/// Orphaned-asset cleanup (plan Phase 4, v2 `CleanupNotifier`): find the
/// cached files no mod references, in the five asset folders and the two
/// raw folders, and delete the ones the user confirms.
library;

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/app/providers/app_log_provider.dart';
import 'package:tts_mod_vault/app/providers/infrastructure_providers.dart';
import 'package:tts_mod_vault/core/logging/app_log.dart';
import 'package:tts_mod_vault/data/fs/cleanup_directory_scanner.dart';
import 'package:tts_mod_vault/data/fs/file_ops.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/asset_detail/application/mod_assets_provider.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';
import 'package:tts_mod_vault/features/operations/application/operation_runner.dart';
import 'package:tts_mod_vault/features/startup/application/directories_controller.dart';

/// Progress label while orphaned files are being deleted.
const cleanupDeletingLabel = 'cleanup.deleting';

/// Why a file is a cleanup candidate.
enum CleanupReason {
  /// No indexed mod references the file.
  unreferenced,

  /// The file is named after the legacy Steam Cloud host and its
  /// current-host twin exists next to it.
  legacyDuplicate,
}

/// One file the cleanup proposes to delete.
final class CleanupCandidate {
  /// Creates a candidate.
  const CleanupCandidate({
    required this.path,
    required this.type,
    required this.fileKey,
    required this.sizeBytes,
    required this.reason,
    required this.indexed,
    this.twinPath,
  });

  /// Normalised path of the file.
  final String path;

  /// Asset type of the folder it lives in.
  final AssetType type;

  /// Its `existing_files` key.
  final String fileKey;

  /// Size in bytes.
  final int sizeBytes;

  /// Why it is proposed.
  final CleanupReason reason;

  /// Whether the file lives in an indexed cache folder (false for the raw
  /// folders, which have no `existing_files` rows).
  final bool indexed;

  /// For [CleanupReason.legacyDuplicate]: the current-host file that stays.
  final String? twinPath;

  /// File name.
  String get fileName => p.basename(path);

  @override
  String toString() => 'CleanupCandidate($path, ${reason.name})';
}

/// Result of [CleanupService.scanOrphans].
final class CleanupScan {
  /// Creates a scan result.
  const CleanupScan({required this.candidates, required this.warnings});

  /// Files proposed for deletion, by type then path.
  final List<CleanupCandidate> candidates;

  /// Non-fatal problems met while listing (missing folders and the like).
  final List<String> warnings;

  /// Total size of the candidates.
  int get totalBytes =>
      candidates.fold(0, (sum, candidate) => sum + candidate.sizeBytes);

  /// Whether there is nothing to clean.
  bool get isEmpty => candidates.isEmpty;
}

/// Outcome of [CleanupOperation].
final class CleanupResult {
  /// Creates a result.
  const CleanupResult({
    required this.deleted,
    required this.failed,
    required this.bytesFreed,
  });

  /// Nothing deleted.
  static const CleanupResult empty = CleanupResult(
    deleted: 0,
    failed: 0,
    bytesFreed: 0,
  );

  /// Files deleted (a file already gone counts, the index is corrected).
  final int deleted;

  /// Files that could not be deleted.
  final int failed;

  /// Bytes of the deleted files.
  final int bytesFreed;

  @override
  String toString() =>
      'CleanupResult(deleted: $deleted, failed: $failed, '
      'bytesFreed: $bytesFreed)';
}

/// The cleanup facade.
final cleanupServiceProvider = Provider<CleanupService>(CleanupService.new);

/// Finds and deletes orphaned cached files. [deleteCandidates] throws
/// [StateError] when another operation is running. Not `final`, so widget
/// tests can substitute a fake.
class CleanupService {
  /// Creates the service on [ref].
  CleanupService(this.ref);

  /// Supplies the runner and the operations' collaborators.
  final Ref ref;

  /// Lists the cleanup candidates:
  ///
  /// * in the five asset folders, the indexed files no mod references
  ///   (`existing_files LEFT JOIN mod_assets`), except `file*` names;
  /// * in `Images Raw` and `Models Raw`, the files (except `file*` names)
  ///   whose key no mod references;
  /// * in all seven folders, legacy-host files whose current-host twin
  ///   exists.
  ///
  /// Files that vanished since they were indexed are left out. Never
  /// throws: a failure is logged and comes back as an empty scan with the
  /// error among its warnings.
  Future<CleanupScan> scanOrphans() async {
    final log = ref.read(appLogProvider);
    try {
      final scan = await _scan();
      log.info(
        LogSource.cleanup,
        'Cleanup scan found ${scan.candidates.length} orphaned file(s), '
        '${(scan.totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB',
        details: scan.warnings.isEmpty ? null : scan.warnings.join('\n'),
      );
      return scan;
    } on Object catch (error, stackTrace) {
      log.error(
        LogSource.cleanup,
        'Cleanup scan failed',
        error: error,
        stackTrace: stackTrace,
      );
      return CleanupScan(
        candidates: const [],
        warnings: ['Cleanup scan failed: $error'],
      );
    }
  }

  Future<CleanupScan> _scan() async {
    final db = ref.read(appDatabaseProvider);
    final pool = ref.read(workerPoolProvider);
    final directories = await ref.read(directoriesProvider.future);
    final warnings = <String>[];

    final requests = <CleanupDirScanRequest>[
      for (final type in AssetType.values) ...[
        CleanupDirScanRequest(
          type: type,
          directory: directories.assetDir(type),
          includeFiles: false,
        ),
        if (directories.rawAssetDir(type) case final raw?)
          CleanupDirScanRequest(type: type, directory: raw, includeFiles: true),
      ],
    ];
    final (orphans, listings) = await (
      db.libraryQueries.orphanedExistingFiles(),
      pool.runAll(scanCleanupDirectory, requests),
    ).wait;
    for (final listing in listings) {
      warnings.addAll(listing.warnings);
    }

    // Raw files: candidates unless some mod references their key.
    final rawFiles = <(AssetType, CleanupFileEntry)>[
      for (var i = 0; i < listings.length; i++)
        if (requests[i].includeFiles)
          for (final file in listings[i].files) (listings[i].type, file),
    ];
    final referenced = await db.libraryQueries.sharedUsageCounts({
      for (final (_, file) in rawFiles) file.fileKey,
    });

    final candidates = <CleanupCandidate>[];
    final seen = <String>{};
    void add(CleanupCandidate candidate) {
      if (seen.add(candidate.path)) candidates.add(candidate);
    }

    for (var i = 0; i < listings.length; i++) {
      final listing = listings[i];
      final indexed = !requests[i].includeFiles;
      for (final duplicate in listing.legacyDuplicates) {
        add(
          CleanupCandidate(
            path: duplicate.path,
            type: listing.type,
            fileKey: duplicate.fileKey,
            sizeBytes: duplicate.sizeBytes,
            reason: CleanupReason.legacyDuplicate,
            indexed: indexed,
            twinPath: duplicate.twinPath,
          ),
        );
      }
    }
    for (final (type, file) in rawFiles) {
      if (referenced.containsKey(file.fileKey)) continue;
      add(
        CleanupCandidate(
          path: file.path,
          type: type,
          fileKey: file.fileKey,
          sizeBytes: file.sizeBytes,
          reason: CleanupReason.unreferenced,
          indexed: false,
        ),
      );
    }

    // Indexed orphans: sizes from a worker, `file*` names and vanished
    // files skipped.
    final indexedOrphans = [
      for (final orphan in orphans)
        if (!p
            .basenameWithoutExtension(orphan.path)
            .startsWith(cleanupSkippedPrefix))
          orphan,
    ];
    final sizes = await pool.run(statFileSizes, [
      for (final orphan in indexedOrphans) orphan.path,
    ]);
    for (var i = 0; i < indexedOrphans.length; i++) {
      final orphan = indexedOrphans[i];
      final size = sizes[i];
      if (size < 0) {
        warnings.add('Indexed file is gone: ${orphan.path}');
        continue;
      }
      add(
        CleanupCandidate(
          path: p.normalize(orphan.path),
          type: orphan.type,
          fileKey: orphan.fileKey,
          sizeBytes: size,
          reason: CleanupReason.unreferenced,
          indexed: true,
        ),
      );
    }

    candidates.sort((a, b) {
      final byType = a.type.dbValue.compareTo(b.type.dbValue);
      return byType != 0 ? byType : a.path.compareTo(b.path);
    });
    return CleanupScan(candidates: candidates, warnings: warnings);
  }

  /// Deletes [candidates] (normally `scan.candidates`, possibly filtered by
  /// the user).
  Future<CleanupResult> deleteCandidates(List<CleanupCandidate> candidates) =>
      ref
          .read(operationRunnerProvider.notifier)
          .run(CleanupOperation(ref: ref, candidates: candidates));
}

/// Deletes the given candidates with progress (`cleanup.deleting`), fixes
/// the `existing_files` rows (an unreferenced indexed file loses its row; a
/// legacy duplicate's row is pointed at the surviving twin) and
/// re-summarises mods referencing the touched keys. Per-file failures are
/// logged and counted; a cancel stops before the next file and returns
/// what was done.
final class CleanupOperation extends Operation<CleanupResult> {
  /// Creates the operation.
  CleanupOperation({required this.ref, required this.candidates});

  /// Supplies the database, file system and library.
  final Ref ref;

  /// Files to delete.
  final List<CleanupCandidate> candidates;

  CleanupResult _partial = CleanupResult.empty;

  @override
  OperationKind get kind => OperationKind.cleanup;

  @override
  CleanupResult? cancelledResult() => _partial;

  @override
  Future<CleanupResult> run(OperationContext ctx) async {
    final log = ctx.log;
    final db = ref.read(appDatabaseProvider);
    final fs = ref.read(fileSystemProvider);
    final total = candidates.length;
    var deleted = 0;
    var failed = 0;
    var bytes = 0;
    final keys = <String>{};
    var cancelled = false;

    Future<void> syncIndex() async {
      // Done once at the end (or on cancel) so a long delete is not slowed
      // by one write per file.
      for (final candidate in candidates.take(deleted + failed)) {
        if (!candidate.indexed) continue;
        final twin = candidate.twinPath;
        if (candidate.reason == CleanupReason.legacyDuplicate && twin != null) {
          if (fs.file(twin).existsSync()) {
            await db.existingFilesDao.upsert(
              candidate.type,
              candidate.fileKey,
              twin,
            );
            continue;
          }
        }
        if (!fs.file(candidate.path).existsSync()) {
          await db.existingFilesDao.remove(candidate.type, candidate.fileKey);
        }
      }
    }

    try {
      for (var i = 0; i < total; i++) {
        if (ctx.isCancelled) {
          cancelled = true;
          break;
        }
        final candidate = candidates[i];
        ctx.report(
          OperationProgress(
            kind: kind,
            label: cleanupDeletingLabel,
            done: i,
            total: total,
            detail: candidate.fileName,
          ),
        );
        try {
          await fs.deleteIfExists(candidate.path);
          deleted++;
          bytes += candidate.sizeBytes;
          keys.add(candidate.fileKey);
        } catch (error, stackTrace) {
          failed++;
          log.error(
            LogSource.cleanup,
            'Could not delete ${candidate.fileName}',
            error: error,
            stackTrace: stackTrace,
            details: candidate.path,
            operationId: ctx.operationId,
          );
        }
        _partial = CleanupResult(
          deleted: deleted,
          failed: failed,
          bytesFreed: bytes,
        );
      }
    } finally {
      await syncIndex();
      if (ref.mounted) {
        await ref
            .read(libraryControllerProvider.notifier)
            .applyAssetFileChange(keys);
        if (ref.mounted) ref.invalidate(modAssetsProvider);
      }
    }
    ctx.report(
      OperationProgress(
        kind: kind,
        label: cleanupDeletingLabel,
        done: deleted + failed,
        total: total,
      ),
    );
    final result = CleanupResult(
      deleted: deleted,
      failed: failed,
      bytesFreed: bytes,
    );
    _partial = result;
    log.success(
      LogSource.cleanup,
      'Cleanup deleted $deleted of $total file(s), '
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB freed'
      '${failed == 0 ? '' : ', $failed failed'}'
      '${cancelled ? ' (cancelled)' : ''}',
      operationId: ctx.operationId,
    );
    return result;
  }
}
