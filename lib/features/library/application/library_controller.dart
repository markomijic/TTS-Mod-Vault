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
import 'package:tts_mod_vault/features/library/application/library_view_providers.dart'
    show selectionProvider;
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
  ///
  /// Small enough that the reference library (272 MB in 99 files) yields
  /// about as many batches as the pool has workers, so the parse phase ends
  /// when the largest single file does rather than when one worker finishes
  /// a 50 MB pile of small ones.
  static const int targetBatchBytes = 16 * 1024 * 1024;

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
  /// worker read, one upsert, one summary query.
  ///
  /// A path that is not in the state is ignored unless [type] is given, in
  /// which case the file is indexed as a new mod of that type and inserted
  /// into the state (save-as-mod, imports). [type] is ignored for a known
  /// path.
  Future<void> refreshMod(String jsonPath, {ModType? type}) async {
    await _running;
    final current = state.value;
    if (current == null) return;
    final normalized = p.normalize(jsonPath);
    final existing = current.modByPath(normalized);
    final modType = existing?.ref.type ?? type;
    if (modType == null) return;

    final options = await ref
        .read(libraryOptionsProvider.notifier)
        .ensureLoaded();
    final pool = ref.read(workerPoolProvider);
    final results = await pool.run(
      parseModFiles,
      ParseModsRequest(files: [(jsonPath: normalized, type: modType)]),
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
    await _patchMods([normalized], options, addMissing: existing == null);
  }

  /// Re-runs the summary query for the mod at [jsonPath] and patches it
  /// into the state, without re-reading the file. For changes that only
  /// touch the store's user-owned columns (audio visibility, invalid URLs).
  /// Unknown paths are ignored.
  Future<void> resummarizeMod(String jsonPath) async {
    await _running;
    final current = state.value;
    if (current == null) return;
    final normalized = p.normalize(jsonPath);
    if (current.modByPath(normalized) == null) return;
    final options = await ref
        .read(libraryOptionsProvider.notifier)
        .ensureLoaded();
    if (!ref.mounted) return;
    await _patchMods([normalized], options);
  }

  /// Drops the mod at [jsonPath] from the state (its store rows must already
  /// be deleted by the caller) and from the selection; a backup matched to
  /// it loses its `matchingModPath`. Unknown paths are ignored.
  Future<void> removeMod(String jsonPath) async {
    await _running;
    if (!ref.mounted) return;
    final current = state.value;
    if (current == null) return;
    final normalized = p.normalize(jsonPath);
    final next = current.withoutMod(normalized);
    if (identical(next, current)) return;
    state = AsyncData(next);
    final selection = ref.read(selectionProvider);
    if (selection.contains(normalized)) {
      ref
          .read(selectionProvider.notifier)
          .selectMany(selection.where((path) => path != normalized));
    }
  }

  /// Replaces the backup at [oldPath] in the state with [replacement] (after
  /// a rename on disk; the `backups` rows must already be updated by the
  /// caller). The mods matched to it are not re-attached here; a following
  /// [refreshMod] or [resummarizeMod] of the mod does that.
  void replaceBackup(String oldPath, Backup replacement) {
    final current = state.value;
    if (current == null) return;
    final next = current.withBackupReplaced(oldPath, replacement);
    if (!identical(next, current)) state = AsyncData(next);
  }

  /// Adds [backup] to the state or replaces the stored backup at its path
  /// (after a backup was written; the `backups` row must already be
  /// upserted by the caller). The matching mod is not re-attached here; a
  /// following [resummarizeMod] of it does that.
  void upsertBackup(Backup backup) {
    final current = state.value;
    if (current == null) return;
    final next = current.withBackupUpserted(backup);
    if (!identical(next, current)) state = AsyncData(next);
  }

  /// Drops the backup at [path] from the state (after it was deleted on
  /// disk; the `backups` row must already be removed by the caller). The
  /// mod that pointed at it keeps its stale `backup` until it is
  /// re-summarised with [resummarizeMod].
  void removeBackup(String path) {
    final current = state.value;
    if (current == null) return;
    final next = current.withoutBackup(path);
    if (!identical(next, current)) state = AsyncData(next);
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

  /// The pipeline of plan section 4.4. Steps b (scan), e (asset index) and
  /// f (backups) only read disjoint folders and write disjoint tables, so e
  /// and f are started right after b is dispatched and run while b-d do
  /// their work; the main flow collects their results after d. Step d
  /// upserts each parse batch as soon as it returns, so the database writes
  /// overlap the parsing of the remaining batches. Phases are still
  /// *reported* in pipeline order (see [_ProgressGate]).
  Future<void> _refresh({required bool clearCache}) async {
    final stopwatch = Stopwatch()..start();
    final progress = ref.read(refreshProgressControllerProvider.notifier);
    final gate = _ProgressGate(progress, () => ref.mounted);
    final pool = ref.read(workerPoolProvider);
    final db = _db;
    final warnings = <String>[];
    // Per-phase durations for the `Library refresh finished` line. Each
    // phase's number is the time the main flow spent waiting on it, so
    // concurrent work shows up only where it was not hidden.
    final phases = <String, int>{};
    var phaseStart = 0;
    void endPhase(String name) {
      final now = stopwatch.elapsedMilliseconds;
      phases[name] = (phases[name] ?? 0) + (now - phaseStart);
      phaseStart = now;
    }

    // Riverpod 3 copies the previous value into the loading state, so the UI
    // keeps the old list visible while this runs.
    state = const AsyncLoading();

    try {
      final directories = await ref.read(directoriesProvider.future);
      final options = await ref
          .read(libraryOptionsProvider.notifier)
          .ensureLoaded();
      endPhase('options');

      if (clearCache) {
        await _clearCache(db);
      }
      // Spawning the isolates is the first `run`'s hidden cost; measure it
      // on its own so the scan phase is just the scan.
      await pool.start();
      // Checkpoint the WAL once after the refresh instead of on every bulk
      // commit below (resumed in `finally`).
      await db.deferWalCheckpoints();
      endPhase('poolStart');

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
      gate.advance(const RefreshProgress(phase: LibraryRefreshPhase.scanning));
      final scanFuture = _runEach(
        pool,
        scanModFiles,
        scanRequests,
        gate,
        LibraryRefreshPhase.scanning,
      );
      // e. and f. start now and run alongside the scan and the parse; they
      // are awaited (and their phases shown) after d. `ignore()` only stops
      // an early failure from being reported as unhandled before the await.
      final indexFuture = _indexAssets(pool, db, directories, gate)..ignore();
      final backupsFuture = directories.hasBackupsDir
          ? (_indexBackups(pool, db, directories.backupsDir, gate)..ignore())
          : Future.value((
              backups: const <Backup>[],
              counted: 0,
              warnings: const <String>[],
            ));

      final scans = await scanFuture;
      final entries = <String, ModFileEntry>{};
      for (final scan in scans) {
        warnings.addAll(scan.warnings);
        for (final entry in scan.entries) {
          entries[entry.jsonPath] = entry;
        }
      }
      endPhase('scan');

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
      endPhase('diff');
      // TODO(v3): `fingerprints()` does not expose `image_path`, so an image
      // added or removed next to an unchanged JSON is not written back to
      // the store. The state is still right: `_finishMod` below takes folder
      // and image path from the scan entry for every mod.

      // d. Parse the new and changed files, largest batches first (LPT: the
      //    biggest file bounds the phase, so it must start immediately), and
      //    write parsed batches to the store while the rest still parse.
      var parsedOk = 0;
      var upsertWorkMs = 0;
      var upsertTransactions = 0;
      if (toParse.isNotEmpty) {
        final batches = createParseBatches(toParse)
          ..sort((a, b) => _batchBytes(b).compareTo(_batchBytes(a)));
        var done = 0;
        gate.advance(
          RefreshProgress(
            phase: LibraryRefreshPhase.parsing,
            total: toParse.length,
          ),
        );
        // One upsert runs at a time (the database is one isolate anyway);
        // batches that finish while it runs are written together next.
        final upserts = _UpsertQueue((items) async {
          final started = stopwatch.elapsedMilliseconds;
          await db.modsDao.upsertMods(items);
          upsertWorkMs += stopwatch.elapsedMilliseconds - started;
          upsertTransactions++;
        });
        await Future.wait([
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
                .then((results) {
                  done += batch.length;
                  gate.report(
                    RefreshProgress(
                      phase: LibraryRefreshPhase.parsing,
                      done: done,
                      total: toParse.length,
                    ),
                  );
                  final items = _upsertsFor(results, entries, warnings);
                  parsedOk += items.length;
                  upserts.add(items);
                }),
        ]);
        endPhase('parse');
        await upserts.drain();
        endPhase('upsert');
      }

      // e. Collect the existing-files index (running since b).
      gate.advance(
        const RefreshProgress(phase: LibraryRefreshPhase.indexingFiles),
      );
      warnings.addAll(await indexFuture);
      endPhase('indexFiles');

      // f. Collect the backups (running since b).
      gate.advance(
        const RefreshProgress(phase: LibraryRefreshPhase.indexingBackups),
      );
      final backupResult = await backupsFuture;
      warnings.addAll(backupResult.warnings);
      endPhase('backups');

      // g. Summaries and backup matching.
      gate.advance(
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
      endPhase('summary');

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
        'durationMs=${stopwatch.elapsedMilliseconds} '
        '${[for (final e in phases.entries) '${e.key}Ms=${e.value}'].join(' ')}'
        '${upsertWorkMs == 0 ? '' : ' upsertWorkMs=$upsertWorkMs '
                  'upsertTransactions=$upsertTransactions'}',
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
      // The result is published; now fold the WAL back into the database
      // file off the critical path. Errors here must not surface as a
      // failed refresh.
      unawaited(_checkpoint(db));
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

  /// Re-enables automatic WAL checkpoints and runs one now (see
  /// `AppDatabase.deferWalCheckpoints`).
  Future<void> _checkpoint(AppDatabase db) async {
    try {
      final started = DateTime.now();
      await db.resumeWalCheckpoints();
      await db.checkpointWal();
      _log.debugLog(
        LogSource.library,
        'WAL checkpoint after refresh: '
        '${DateTime.now().difference(started).inMilliseconds} ms',
      );
    } on Object catch (error, stackTrace) {
      _log.debugLog(
        LogSource.library,
        'WAL checkpoint after refresh failed',
        details: '$error\n$stackTrace',
      );
    }
  }

  /// Total bytes of the files in [batch].
  static int _batchBytes(List<ModFileEntry> batch) =>
      batch.fold(0, (sum, entry) => sum + entry.sizeBytes);

  /// Turns one batch's parse results into store upserts; files that could
  /// not be read become warnings (list and log) instead.
  List<ModUpsert> _upsertsFor(
    List<ParsedMod> results,
    Map<String, ModFileEntry> entries,
    List<String> warnings,
  ) {
    final upserts = <ModUpsert>[];
    for (final parsed in results) {
      if (!parsed.isOk) {
        warnings.add('Could not read ${parsed.jsonPath}: ${parsed.error}');
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
        _upsertFor(parsed, folder: entry.folder, imagePath: entry.imagePath),
      );
    }
    return upserts;
  }

  /// Step e: lists every asset cache folder on the pool and syncs each
  /// listing into `existing_files` as soon as it arrives. Returns the
  /// user-facing warnings; duplicate-key notes go to the debug log.
  Future<List<String>> _indexAssets(
    WorkerPool pool,
    AppDatabase db,
    Directories directories,
    _ProgressGate gate,
  ) async {
    const phase = LibraryRefreshPhase.indexingFiles;
    final requests = [
      for (final type in AssetType.values)
        AssetIndexRequest(type: type, directory: directories.assetDir(type)),
    ];
    final warnings = <String>[];
    final duplicateKeys = <String>[];
    var done = 0;
    var writes = Future<void>.value();
    gate.report(RefreshProgress(phase: phase, total: requests.length));
    await Future.wait([
      for (final request in requests)
        pool.run(indexAssetDirectory, request).then((index) {
          for (final warning in index.warnings) {
            // Two files for one key (`x.png` and `x.jpg`) are routine in a
            // TTS cache; keep them out of the user-facing warnings.
            if (warning.startsWith('Duplicate asset key')) {
              duplicateKeys.add(warning);
            } else {
              warnings.add(warning);
            }
          }
          writes = writes.then(
            (_) => db.existingFilesDao.replaceAll(index.type, index.files),
          );
          done++;
          gate.report(
            RefreshProgress(phase: phase, done: done, total: requests.length),
          );
        }),
    ]);
    await writes;
    if (duplicateKeys.isNotEmpty) {
      _log.debugLog(
        LogSource.library,
        '${duplicateKeys.length} duplicate asset keys ignored',
        details: duplicateKeys.join('\n'),
      );
    }
    return warnings;
  }

  /// Runs [task] for each of [args] on the pool, reporting per-item
  /// completion as [phase] progress. Results come back in argument order.
  Future<List<R>> _runEach<A, R>(
    WorkerPool pool,
    FutureOr<R> Function(A arg) task,
    List<A> args,
    _ProgressGate gate,
    LibraryRefreshPhase phase,
  ) async {
    var done = 0;
    gate.report(RefreshProgress(phase: phase, total: args.length));
    return Future.wait([
      for (final arg in args)
        pool.run(task, arg).then((result) {
          done++;
          gate.report(
            RefreshProgress(phase: phase, done: done, total: args.length),
          );
          return result;
        }),
    ]);
  }

  Future<({List<Backup> backups, int counted, List<String> warnings})>
  _indexBackups(
    WorkerPool pool,
    AppDatabase db,
    String backupsDir,
    _ProgressGate gate,
  ) async {
    gate.report(
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
        gate,
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

  /// Re-queries the summaries of [paths] and patches them into the state.
  /// With [addMissing] a summary for a path not yet in the state is inserted
  /// as a new mod (folder and image as the store has them).
  Future<void> _patchMods(
    Iterable<String> paths,
    LibraryOptions options, {
    bool addMissing = false,
  }) async {
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
      if (previous == null) {
        if (addMissing) replacements.add(matcher.attach(summary));
        continue;
      }
      // The scan is the authority for folder and image; keep what it found.
      final carried = summary.copyWith(
        folder: previous.folder,
        imagePath: previous.imagePath ?? summary.imagePath,
      );
      final attached = matcher.attach(carried);
      final previousBackup = previous.backup;
      if (previousBackup != null &&
          attached.backup?.path != previousBackup.path) {
        // Renamed away from its backup: the backup no longer has a mod.
        matcher.detach(previousBackup.path, previous.jsonPath);
      }
      replacements.add(attached);
    }
    state = AsyncData(
      latest
          .withMods(replacements, addMissing: addMissing)
          .copyWith(backups: matcher.backups),
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

/// Serialises store writes behind the parse phase: [add] queues a batch's
/// upserts; one write runs at a time and takes everything queued since the
/// previous one, so a dozen parse batches become a few transactions without
/// anyone waiting for the parsing to finish first.
final class _UpsertQueue {
  _UpsertQueue(this._write);

  final Future<void> Function(List<ModUpsert> items) _write;
  final List<ModUpsert> _pending = [];
  Future<void>? _inFlight;
  Object? _error;
  StackTrace? _stackTrace;

  /// Queues [items] and starts a write if none is running.
  void add(List<ModUpsert> items) {
    _pending.addAll(items);
    _flush();
  }

  /// Completes when everything queued so far is written; rethrows the first
  /// write error.
  Future<void> drain() async {
    _flush();
    while (_inFlight != null) {
      await _inFlight;
    }
    if (_error != null) Error.throwWithStackTrace(_error!, _stackTrace!);
  }

  void _flush() {
    if (_inFlight != null || _pending.isEmpty || _error != null) return;
    final items = List<ModUpsert>.of(_pending);
    _pending.clear();
    _inFlight = _write(items)
        .catchError((Object error, StackTrace stackTrace) {
          _error ??= error;
          _stackTrace ??= stackTrace;
        })
        .whenComplete(() {
          _inFlight = null;
          _flush();
        });
  }
}

/// Publishes [RefreshProgress] in pipeline order while the phases themselves
/// overlap. [report] records a phase's latest snapshot and publishes it only
/// when that phase is the active one; [advance] makes a phase active and
/// publishes its latest snapshot (or the given initial one), so a phase that
/// already finished in the background still appears, complete, in its turn.
final class _ProgressGate {
  _ProgressGate(this._controller, this._mounted);

  final RefreshProgressController _controller;
  final bool Function() _mounted;
  final Map<LibraryRefreshPhase, RefreshProgress> _latest = {};
  LibraryRefreshPhase? _active;

  /// Records [progress] and shows it if its phase is active.
  void report(RefreshProgress progress) {
    _latest[progress.phase] = progress;
    if (progress.phase == _active) _publish(progress);
  }

  /// Makes [initial]'s phase the active one and shows the latest snapshot
  /// recorded for it, or [initial] when there is none yet.
  void advance(RefreshProgress initial) {
    _active = initial.phase;
    _publish(_latest[initial.phase] ?? initial);
  }

  void _publish(RefreshProgress progress) {
    if (_mounted()) _controller.set(progress);
  }
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

  /// Clears `matchingModPath` of the backup at [backupPath] when it points
  /// at [modPath] (the mod no longer produces that backup's name).
  void detach(String backupPath, String modPath) {
    final index = _backups.indexWhere((b) => b.path == backupPath);
    if (index < 0 || _backups[index].matchingModPath != modPath) return;
    _backups[index] = _backups[index].copyWith(matchingModPath: null);
  }
}
