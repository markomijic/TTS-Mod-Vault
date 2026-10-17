import 'dart:async';
import 'dart:math' show max, min;

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/app/providers/app_log_provider.dart';
import 'package:tts_mod_vault/app/providers/infrastructure_providers.dart';
import 'package:tts_mod_vault/core/logging/app_log.dart';
import 'package:tts_mod_vault/core/workers/worker_pool.dart';
import 'package:tts_mod_vault/data/db/app_database.dart';
import 'package:tts_mod_vault/data/db/daos/backups_dao.dart';
import 'package:tts_mod_vault/data/db/daos/mods_dao.dart';
import 'package:tts_mod_vault/data/fs/fs_tasks.dart';
import 'package:tts_mod_vault/domain/constants.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/domain/rules/backup_rules.dart';
import 'package:tts_mod_vault/features/library/application/library_settings.dart';
import 'package:tts_mod_vault/features/library/application/library_state.dart';
import 'package:tts_mod_vault/features/library/application/refresh_progress.dart';
import 'package:tts_mod_vault/features/library/library_tasks.dart';
import 'package:tts_mod_vault/features/startup/application/directories_controller.dart';

export 'package:tts_mod_vault/features/library/application/library_state.dart';

/// The indexed library. `build` does no IO: startup triggers the first
/// [LibraryController.refresh], later ones come from the Refresh button and
/// from operations that change files.
final libraryControllerProvider =
    AsyncNotifierProvider<LibraryController, LibraryState>(
      LibraryController.new,
    );

/// Prefix of the one info line every refresh logs; the benchmark harness
/// greps for it.
const libraryRefreshFinishedPrefix = 'Library refresh finished';

/// Runs the library refresh pipeline (plan section 4.4) and owns the
/// resulting [LibraryState].
///
/// While a refresh runs the provider is `AsyncLoading` with the previous
/// state still available through `valueOrNull` (Riverpod 3 carries the
/// previous value over), and [refreshProgressProvider] reports the phase.
/// Failures end as `AsyncError` (previous value kept too) plus a log entry;
/// nothing is thrown to the caller.
class LibraryController extends AsyncNotifier<LibraryState> {
  /// Files per parse batch, at most (plan: "~25").
  static const int maxFilesPerBatch = 25;

  /// Bytes per parse batch the batching aims for; a batch closes before it
  /// would exceed this (a single larger file still forms its own batch).
  static const int targetBatchBytes = 50 * 1024 * 1024;

  /// Archives per `countBackupAssets` task, at most.
  static const int maxBackupsPerChunk = 50;

  Future<void>? _running;

  @override
  FutureOr<LibraryState> build() => LibraryState.empty;

  /// Re-indexes the library. With [clearCache] every cached row (mods,
  /// assets, existing files, backups) is dropped first so every JSON is read
  /// again. A call made while a refresh runs awaits that refresh instead of
  /// starting another one.
  Future<void> refresh({bool clearCache = false}) {
    final running = _running;
    if (running != null) return running;
    final future = _refresh(clearCache: clearCache).whenComplete(() {
      _running = null;
    });
    _running = future;
    return future;
  }

  /// Re-reads one mod JSON (after a rename, URL replacement or import),
  /// updates its rows and patches the mod in the current state. Cheap: one
  /// worker read, one upsert, one summary query. Unknown paths are ignored.
  Future<void> refreshMod(String jsonPath) async {
    await _running;
    final current = state.value;
    if (current == null) return;
    final normalized = p.normalize(jsonPath);
    final existing = current.modByPath(normalized);
    if (existing == null) return;

    final options = await ref
        .read(libraryOptionsProvider.notifier)
        .ensureLoaded();
    final pool = ref.read(workerPoolProvider);
    final results = await pool.run(
      parseModFiles,
      ParseModsRequest(
        files: [(jsonPath: normalized, type: existing.ref.type)],
      ),
    );
    final parsed = results.single;
    if (!parsed.isOk) {
      _log.warning(
        LogSource.library,
        'Could not read mod file',
        details: parsed.error,
        modPath: normalized,
      );
      return;
    }
    final imagePath = await pool.run(findModImagePath, normalized);
    await _db.modsDao.upsertMods([
      _upsertFor(
        parsed,
        folder: p.basename(p.dirname(normalized)),
        imagePath: imagePath,
      ),
    ]);
    if (!ref.mounted) return;
    await _patchMods([normalized], options);
  }

  /// Re-queries the summaries of every mod referencing any of [fileKeys]
  /// (after files were downloaded or deleted) and patches them into the
  /// state. The `existing_files` rows must already be updated by the caller.
  Future<void> applyAssetFileChange(Set<String> fileKeys) async {
    if (fileKeys.isEmpty) return;
    await _running;
    if (state.value == null) return;
    final options = await ref
        .read(libraryOptionsProvider.notifier)
        .ensureLoaded();
    final paths = await _db.libraryQueries.modPathsReferencingFileKeys(
      fileKeys,
    );
    if (!ref.mounted || paths.isEmpty) return;
    await _patchMods(paths, options);
  }

  // --- refresh pipeline ----------------------------------------------------

  Future<void> _refresh({required bool clearCache}) async {
    final stopwatch = Stopwatch()..start();
    final progress = ref.read(refreshProgressControllerProvider.notifier);
    final pool = ref.read(workerPoolProvider);
    final db = _db;
    final warnings = <String>[];
    // Riverpod 3 copies the previous value into the loading state, so the UI
    // keeps the old list visible while this runs.
    state = const AsyncLoading();

    try {
      final directories = await ref.read(directoriesProvider.future);
      final options = await ref
          .read(libraryOptionsProvider.notifier)
          .ensureLoaded();

      if (clearCache) {
        await _clearCache(db);
      }

      // b. Scan the mod roots.
      final scanRequests = [
        ModFileScanRequest(
          rootDir: directories.workshopDir,
          type: ModType.mod,
          ignoredSubfolders: options.ignoredSubfolders,
        ),
        ModFileScanRequest(
          rootDir: directories.savesDir,
          type: ModType.save,
          ignoredSubfolders: [
            ttsSavedObjectsFolder,
            ...options.ignoredSubfolders,
          ],
        ),
        if (options.includeSavedObjects)
          ModFileScanRequest(
            rootDir: directories.savedObjectsDir,
            type: ModType.savedObject,
            ignoredSubfolders: options.ignoredSubfolders,
          ),
      ];
      final scans = await _runEach(
        pool,
        scanModFiles,
        scanRequests,
        progress,
        LibraryRefreshPhase.scanning,
      );
      final entries = <String, ModFileEntry>{};
      for (final scan in scans) {
        warnings.addAll(scan.warnings);
        for (final entry in scan.entries) {
          entries[entry.jsonPath] = entry;
        }
      }

      // c. Diff against the store.
      final stored = await db.modsDao.fingerprints();
      final toParse = <ModFileEntry>[];
      for (final entry in entries.values) {
        final fingerprint = stored[entry.jsonPath];
        if (fingerprint == null ||
            fingerprint.mtimeMs != entry.mtimeMs ||
            fingerprint.sizeBytes != entry.sizeBytes) {
          toParse.add(entry);
        }
      }
      final vanished = [
        for (final path in stored.keys)
          if (!entries.containsKey(path)) path,
      ];
      await db.modsDao.deleteByPaths(vanished);
      // TODO(v3): `fingerprints()` does not expose `image_path`, so an image
      // added or removed next to an unchanged JSON is not written back to
      // the store. The state is still right: `_finishMod` below takes folder
      // and image path from the scan entry for every mod.

      // d. Parse the new and changed files.
      var parsedOk = 0;
      if (toParse.isNotEmpty) {
        final batches = createParseBatches(toParse);
        var done = 0;
        progress.set(
          RefreshProgress(
            phase: LibraryRefreshPhase.parsing,
            total: toParse.length,
          ),
        );
        final results = await Future.wait([
          for (final batch in batches)
            pool
                .run(
                  parseModFiles,
                  ParseModsRequest(
                    files: [
                      for (final entry in batch)
                        (jsonPath: entry.jsonPath, type: entry.type),
                    ],
                  ),
                )
                .then((result) {
                  done += batch.length;
                  if (ref.mounted) {
                    progress.set(
                      RefreshProgress(
                        phase: LibraryRefreshPhase.parsing,
                        done: done,
                        total: toParse.length,
                      ),
                    );
                  }
                  return result;
                }),
        ]);
        final upserts = <ModUpsert>[];
        for (final parsed in results.expand((list) => list)) {
          if (!parsed.isOk) {
            final message =
                'Could not read ${parsed.jsonPath}: ${parsed.error}';
            warnings.add(message);
            _log.warning(
              LogSource.library,
              'Could not read mod file',
              details: parsed.error,
              modPath: parsed.jsonPath,
            );
            continue;
          }
          final entry = entries[parsed.jsonPath]!;
          upserts.add(
            _upsertFor(
              parsed,
              folder: entry.folder,
              imagePath: entry.imagePath,
            ),
          );
        }
        parsedOk = upserts.length;
        await db.modsDao.upsertMods(upserts);
      }

      // e. Rebuild the existing-files index.
      final indexes = await _runEach(
        pool,
        indexAssetDirectory,
        [
          for (final type in AssetType.values)
            AssetIndexRequest(
              type: type,
              directory: directories.assetDir(type),
            ),
        ],
        progress,
        LibraryRefreshPhase.indexingFiles,
      );
      final duplicateKeys = <String>[];
      for (final index in indexes) {
        for (final warning in index.warnings) {
          // Two files for one key (`x.png` and `x.jpg`) are routine in a TTS
          // cache; keep them out of the user-facing warnings.
          if (warning.startsWith('Duplicate asset key')) {
            duplicateKeys.add(warning);
          } else {
            warnings.add(warning);
          }
        }
        await db.existingFilesDao.replaceAll(index.type, index.files);
      }
      if (duplicateKeys.isNotEmpty) {
        _log.debugLog(
          LogSource.library,
          '${duplicateKeys.length} duplicate asset keys ignored',
          details: duplicateKeys.join('\n'),
        );
      }

      // f. Backups.
      final backupResult = directories.hasBackupsDir
          ? await _indexBackups(pool, db, directories.backupsDir, progress)
          : (backups: const <Backup>[], counted: 0, warnings: const <String>[]);
      warnings.addAll(backupResult.warnings);

      // g. Summaries and backup matching.
      progress.set(
        const RefreshProgress(phase: LibraryRefreshPhase.summarizing),
      );
      final ignoreAudio = options.ignoreAudioGlobally;
      final mods = await db.libraryQueries.modSummaries(
        ModType.mod,
        ignoreAudioGlobally: ignoreAudio,
      );
      final saves = await db.libraryQueries.modSummaries(
        ModType.save,
        ignoreAudioGlobally: ignoreAudio,
      );
      final savedObjects = options.includeSavedObjects
          ? await db.libraryQueries.modSummaries(
              ModType.savedObject,
              ignoreAudioGlobally: ignoreAudio,
            )
          : const <Mod>[];

      final matcher = _BackupMatcher(backupResult.backups, options);
      List<Mod> finish(List<Mod> list) => [
        for (final mod in list) matcher.attach(_withScanEntry(mod, entries)),
      ];
      final finishedMods = finish(mods);
      final finishedSaves = finish(saves);
      final finishedSavedObjects = finish(savedObjects);

      if (!ref.mounted) return;
      state = AsyncData(
        LibraryState(
          mods: finishedMods,
          saves: finishedSaves,
          savedObjects: finishedSavedObjects,
          backups: matcher.backups,
          lastRefresh: DateTime.now(),
          warnings: List.unmodifiable(warnings),
        ),
      );

      // h. Log.
      stopwatch.stop();
      for (final warning in warnings) {
        _log.warning(LogSource.library, warning);
      }
      _log.info(
        LogSource.library,
        '$libraryRefreshFinishedPrefix: '
        'mods=${finishedMods.length} saves=${finishedSaves.length} '
        'savedObjects=${finishedSavedObjects.length} '
        'backups=${matcher.backups.length} '
        'scanned=${entries.length} parsed=$parsedOk '
        'removed=${vanished.length} backupsCounted=${backupResult.counted} '
        'warnings=${warnings.length} '
        'durationMs=${stopwatch.elapsedMilliseconds}',
      );
    } catch (error, stackTrace) {
      if (!ref.mounted) return;
      _log.error(
        LogSource.library,
        'Library refresh failed',
        error: error,
        stackTrace: stackTrace,
      );
      state = AsyncError(error, stackTrace);
    } finally {
      if (ref.mounted) progress.clear();
    }
  }

  /// Groups [entries] into parse batches: a batch closes when it holds
  /// [maxFilesPerBatch] files or when adding the next file would push it past
  /// [targetBatchBytes] (a file larger than that forms a batch of its own).
  /// Input order is kept, so neighbouring files on disk stay together.
  static List<List<ModFileEntry>> createParseBatches(
    List<ModFileEntry> entries,
  ) {
    final batches = <List<ModFileEntry>>[];
    var current = <ModFileEntry>[];
    var currentBytes = 0;
    for (final entry in entries) {
      final wouldOverflow =
          current.isNotEmpty &&
          (current.length >= maxFilesPerBatch ||
              currentBytes + entry.sizeBytes > targetBatchBytes);
      if (wouldOverflow) {
        batches.add(current);
        current = <ModFileEntry>[];
        currentBytes = 0;
      }
      current.add(entry);
      currentBytes += entry.sizeBytes;
    }
    if (current.isNotEmpty) batches.add(current);
    return batches;
  }

  Future<void> _clearCache(AppDatabase db) => db.transaction(() async {
    await db.delete(db.modAssets).go();
    await db.delete(db.mods).go();
    await db.delete(db.existingFiles).go();
    await db.delete(db.backups).go();
  });

  /// Runs [task] for each of [args] on the pool, reporting per-item
  /// completion as [phase] progress. Results come back in argument order.
  Future<List<R>> _runEach<A, R>(
    WorkerPool pool,
    FutureOr<R> Function(A arg) task,
    List<A> args,
    RefreshProgressController progress,
    LibraryRefreshPhase phase,
  ) async {
    var done = 0;
    progress.set(RefreshProgress(phase: phase, total: args.length));
    return Future.wait([
      for (final arg in args)
        pool.run(task, arg).then((result) {
          done++;
          if (ref.mounted) {
            progress.set(
              RefreshProgress(phase: phase, done: done, total: args.length),
            );
          }
          return result;
        }),
    ]);
  }

  Future<({List<Backup> backups, int counted, List<String> warnings})>
  _indexBackups(
    WorkerPool pool,
    AppDatabase db,
    String backupsDir,
    RefreshProgressController progress,
  ) async {
    progress.set(
      const RefreshProgress(phase: LibraryRefreshPhase.indexingBackups),
    );
    final scan = await pool.run(
      scanBackupFiles,
      BackupScanRequest(backupsDir: backupsDir),
    );
    final storedRows = await db.select(db.backups).get();
    final stored = {for (final row in storedRows) row.path: row};

    final toCount = <BackupFileEntry>[];
    final counts = <String, int>{};
    for (final entry in scan.entries) {
      final row = stored[entry.path];
      if (row != null &&
          row.mtimeMs == entry.mtimeMs &&
          row.sizeBytes == entry.sizeBytes) {
        counts[entry.path] = row.assetCount;
      } else {
        toCount.add(entry);
      }
    }

    if (toCount.isNotEmpty) {
      final chunks = _chunk([
        for (final entry in toCount) entry.path,
      ], pool.size);
      final results = await _runEach(
        pool,
        countBackupAssets,
        chunks,
        progress,
        LibraryRefreshPhase.indexingBackups,
      );
      final upserts = <BackupUpsert>[];
      for (var i = 0; i < chunks.length; i++) {
        for (var j = 0; j < chunks[i].length; j++) {
          counts[chunks[i][j]] = results[i][j];
        }
      }
      for (final entry in toCount) {
        upserts.add((
          path: entry.path,
          mtimeMs: entry.mtimeMs,
          sizeBytes: entry.sizeBytes,
          assetCount: counts[entry.path] ?? 0,
        ));
      }
      await db.backupsDao.upsertAll(upserts);
    }

    final scannedPaths = {for (final entry in scan.entries) entry.path};
    await db.backupsDao.deleteByPaths([
      for (final path in stored.keys)
        if (!scannedPaths.contains(path)) path,
    ]);

    return (
      backups: [
        for (final entry in scan.entries)
          Backup(
            path: entry.path,
            fileName: entry.fileName,
            folder: entry.folder,
            modified: DateTime.fromMillisecondsSinceEpoch(entry.mtimeMs),
            sizeBytes: entry.sizeBytes,
            assetCount: counts[entry.path] ?? 0,
          ),
      ],
      counted: toCount.length,
      warnings: scan.warnings,
    );
  }

  /// Splits [paths] into at most `workers * 2` chunks of at most
  /// [maxBackupsPerChunk] items, so every worker gets work and progress
  /// still moves in visible steps.
  static List<List<String>> _chunk(List<String> paths, int workers) {
    if (paths.isEmpty) return const [];
    final perChunk = max(
      1,
      min(maxBackupsPerChunk, (paths.length / (workers * 2)).ceil()),
    );
    return [
      for (var i = 0; i < paths.length; i += perChunk)
        paths.sublist(i, min(i + perChunk, paths.length)),
    ];
  }

  Future<void> _patchMods(
    Iterable<String> paths,
    LibraryOptions options,
  ) async {
    final current = state.value;
    if (current == null) return;
    final summaries = await Future.wait([
      for (final path in paths)
        _db.libraryQueries.modSummary(
          path,
          ignoreAudioGlobally: options.ignoreAudioGlobally,
        ),
    ]);
    if (!ref.mounted) return;
    final latest = state.value ?? current;
    final matcher = _BackupMatcher(latest.backups, options);
    final replacements = <Mod>[];
    for (final summary in summaries) {
      if (summary == null) continue;
      final previous = latest.modByPath(summary.jsonPath);
      if (previous == null) continue;
      // The scan is the authority for folder and image; keep what it found.
      final carried = summary.copyWith(
        folder: previous.folder,
        imagePath: previous.imagePath ?? summary.imagePath,
      );
      replacements.add(matcher.attach(carried));
    }
    state = AsyncData(
      latest.withMods(replacements).copyWith(backups: matcher.backups),
    );
  }

  static ModUpsert _upsertFor(
    ParsedMod parsed, {
    required String folder,
    required String? imagePath,
  }) => ModUpsert(
    ref: ModRef.fromPath(parsed.type, parsed.jsonPath),
    folder: folder,
    saveName: parsed.saveName,
    epochTime: parsed.epochTime,
    mtimeMs: parsed.mtimeMs,
    sizeBytes: parsed.sizeBytes,
    imagePath: imagePath,
    assets: parsed.assets,
  );

  /// Overrides folder and image path with what the scan saw, which is also
  /// right for unchanged JSONs whose sibling image appeared or vanished.
  static Mod _withScanEntry(Mod mod, Map<String, ModFileEntry> entries) {
    final entry = entries[mod.jsonPath];
    if (entry == null) return mod;
    if (entry.folder == mod.folder && entry.imagePath == mod.imagePath) {
      return mod;
    }
    return mod.copyWith(folder: entry.folder, imagePath: entry.imagePath);
  }

  AppDatabase get _db => ref.read(appDatabaseProvider);

  AppLog get _log => ref.read(appLogProvider);
}

/// Matches mods to backups by file name (v2 `getBackupByMod`): the first
/// candidate name with any backup wins, and among backups with that name the
/// most recently modified one. The first mod matched to a backup sets its
/// `matchingModPath`.
final class _BackupMatcher {
  _BackupMatcher(List<Backup> backups, this._options)
    : _backups = List.of(backups) {
    for (var i = 0; i < _backups.length; i++) {
      final backup = _backups[i];
      _indexesByName.putIfAbsent(backup.fileName, () => []).add(i);
    }
    for (final indexes in _indexesByName.values) {
      indexes.sort(
        (a, b) => _backups[b].modified.compareTo(_backups[a].modified),
      );
    }
  }

  final LibraryOptions _options;
  final List<Backup> _backups;
  final Map<String, List<int>> _indexesByName = {};

  /// Backups with `matchingModPath` set for every mod attached so far.
  List<Backup> get backups => List.unmodifiable(_backups);

  /// Returns [mod] with its backup and backup status filled in.
  Mod attach(Mod mod) {
    final candidates = backupFileNameCandidates(
      ref: mod.ref,
      saveName: mod.saveName,
      forceIncludeId: _options.forceBackupIdInName,
    );
    int? index;
    for (final name in candidates) {
      final indexes = _indexesByName[name];
      if (indexes != null && indexes.isNotEmpty) {
        index = indexes.first;
        break;
      }
    }
    if (index == null) {
      return mod.backup == null && mod.backupStatus == BackupStatus.none
          ? mod
          : mod.copyWith(backup: null, backupStatus: BackupStatus.none);
    }
    var backup = _backups[index];
    if (backup.matchingModPath == null) {
      backup = backup.copyWith(matchingModPath: mod.jsonPath);
      _backups[index] = backup;
    }
    return mod.copyWith(
      backup: backup,
      backupStatus: backupStatusFor(
        backup: backup,
        epochTime: mod.epochTime,
        presentAssetCount: mod.summary.present,
      ),
    );
  }
}
