/// The backup operations of plan section 6, Phase 4: create a `.ttsmod`
/// for a mod, import `.ttsmod` archives (one or many) and import a bare
/// JSON (+ optional PNG). All of them are `Operation`s run by the
/// `OperationRunner`; `BackupService` is the facade the UI calls.
///
/// Archive layout (shared with v2 and TTS Mod Backup): entries are the
/// files' paths relative to the parent of the `Mods` folder
/// (`Mods/Workshop/123.json`, `Mods/Images/<name>.png`) or of the `Saves`
/// folder (`Saves/TS_Save_1.json`, `Saves/Saved Objects/x.json`).
library;

import 'dart:convert' show utf8;

import 'package:collection/collection.dart' show IterableExtension;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/app/providers/infrastructure_providers.dart';
import 'package:tts_mod_vault/core/cancellation/cancellation_token.dart';
import 'package:tts_mod_vault/core/logging/app_log.dart';
import 'package:tts_mod_vault/core/workers/worker_pool.dart';
import 'package:tts_mod_vault/data/fs/file_ops.dart';
import 'package:tts_mod_vault/data/fs/zip/zip_extractor.dart';
import 'package:tts_mod_vault/data/fs/zip/zip_writer.dart';
import 'package:tts_mod_vault/domain/constants.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/domain/parsing/mod_metadata.dart';
import 'package:tts_mod_vault/domain/rules/backup_rules.dart';
import 'package:tts_mod_vault/domain/rules/file_key.dart';
import 'package:tts_mod_vault/features/asset_detail/application/mod_assets_provider.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';
import 'package:tts_mod_vault/features/library/application/library_settings.dart';
import 'package:tts_mod_vault/features/library/library_tasks.dart';
import 'package:tts_mod_vault/features/operations/application/operation.dart';
import 'package:tts_mod_vault/features/startup/application/directories_controller.dart';

/// Progress label while the backup archive is being written
/// (`done` / `total` are archive entries).
const backupWritingLabel = 'backup.writing';

/// Progress label while an archive's entries are being extracted.
const importExtractingLabel = 'import.extracting';

/// Progress label of a multi-file import (`done` / `total` are files; the
/// fraction includes the current file's extraction).
const importFileLabel = 'import.file';

// --- create backup --------------------------------------------------------

/// Outcome of [CreateBackupOperation].
final class BackupResult {
  /// Creates a result.
  const BackupResult({
    required this.backup,
    required this.assetCount,
    required this.skipped,
  });

  /// The archive as it now appears in the library state.
  final Backup backup;

  /// Asset files stored in the archive (JSON and image excluded).
  final int assetCount;

  /// Files that vanished between the index lookup and the write.
  final int skipped;

  @override
  String toString() =>
      'BackupResult(${backup.path}, assets: $assetCount, skipped: $skipped)';
}

/// Zips the cached asset files of [mod] plus its JSON and sibling image
/// into `<targetDir>/<backupFileName>` and registers the archive.
///
/// Assets follow the mod's audio visibility and the global option, like
/// the asset list; only files that are on disk are added. Entry names are
/// relative to the parent of the `Mods` / `Saves` folder. On success the
/// `backups` row is upserted, the archive is put into the library state and
/// the mod is re-summarised so its status becomes up to date. A cancel
/// deletes the partial archive and rethrows [OperationCancelledException].
final class CreateBackupOperation extends Operation<BackupResult> {
  /// Creates the operation.
  CreateBackupOperation({
    required this.ref,
    required this.mod,
    required this.targetDir,
  });

  /// Supplies the database, directories, options and library.
  final Ref ref;

  /// The mod to back up.
  final Mod mod;

  /// Folder the archive is written into (created when missing).
  final String targetDir;

  @override
  OperationKind get kind => OperationKind.backup;

  @override
  Future<BackupResult> run(OperationContext ctx) async {
    final log = ctx.log;
    final db = ref.read(appDatabaseProvider);
    final directories = await ref.read(directoriesProvider.future);
    final options = await ref
        .read(libraryOptionsProvider.notifier)
        .ensureLoaded();
    ctx.checkCancelled();

    final assets = await db.libraryQueries.assetsForMod(
      mod.jsonPath,
      includeAudio: !mod.audio.hideAudio(
        ignoreAudioGlobally: options.ignoreAudioGlobally,
      ),
    );
    final assetPaths = <String>[for (final asset in assets) ?asset.path];
    final filePaths = [...assetPaths, mod.jsonPath, ?mod.imagePath];
    final entries = [
      for (final path in filePaths)
        (
          sourcePath: path,
          entryName: backupEntryName(path, directories: directories),
        ),
    ];
    final fileName = backupFileName(
      saveName: mod.saveName,
      modId: mod.id,
      type: mod.ref.type,
      forceIncludeId: options.forceBackupIdInName,
    );
    final targetPath = p.normalize(p.join(targetDir, fileName));
    log.info(
      LogSource.backup,
      'Backing up "${mod.displayName}" (${assetPaths.length} asset files) '
      'to $fileName',
      details: targetPath,
      modPath: mod.jsonPath,
      operationId: ctx.operationId,
    );
    ctx.report(
      OperationProgress(
        kind: kind,
        label: backupWritingLabel,
        total: entries.length,
        detail: mod.displayName,
      ),
    );

    final ZipWriteResult written;
    try {
      written = await BackupZipIsolate.write(
        ZipWriteRequest(targetPath: targetPath, entries: entries),
        token: ctx.token,
        onProgress: (progress) => ctx.report(
          OperationProgress(
            kind: kind,
            label: backupWritingLabel,
            done: progress.done,
            total: progress.total,
            detail: mod.displayName,
          ),
        ),
      );
    } on OperationCancelledException {
      log.warning(
        LogSource.backup,
        'Backup of "${mod.displayName}" cancelled; no archive was written',
        modPath: mod.jsonPath,
        operationId: ctx.operationId,
      );
      rethrow;
    } catch (error, stackTrace) {
      log.error(
        LogSource.backup,
        'Could not write backup $fileName for "${mod.displayName}"',
        error: error,
        stackTrace: stackTrace,
        modPath: mod.jsonPath,
        operationId: ctx.operationId,
      );
      rethrow;
    }
    for (final path in written.skipped) {
      log.warning(
        LogSource.backup,
        'Backup of "${mod.displayName}" is missing a file that vanished '
        'during the write: ${p.basename(path)}',
        details: path,
        modPath: mod.jsonPath,
        operationId: ctx.operationId,
      );
    }

    final stat = ref.read(fileSystemProvider).file(targetPath).statSync();
    final assetCount =
        assetPaths.length - written.skipped.where(assetPaths.contains).length;
    final backup = Backup(
      path: targetPath,
      fileName: fileName,
      folder: p.basename(p.dirname(targetPath)),
      modified: stat.modified,
      sizeBytes: stat.size,
      assetCount: assetCount,
      matchingModPath: mod.jsonPath,
    );
    await db.backupsDao.upsertAll([
      (
        path: targetPath,
        mtimeMs: stat.modified.millisecondsSinceEpoch,
        sizeBytes: stat.size,
        assetCount: assetCount,
      ),
    ]);
    if (!ref.mounted) return _result(backup, assetCount, written);
    final library = ref.read(libraryControllerProvider.notifier);
    library.upsertBackup(backup);
    await library.resummarizeMod(mod.jsonPath);
    log.success(
      LogSource.backup,
      'Backed up "${mod.displayName}": $assetCount asset files, '
      '${backup.fileSizeLabel}',
      details: targetPath,
      modPath: mod.jsonPath,
      operationId: ctx.operationId,
    );
    return _result(backup, assetCount, written);
  }

  static BackupResult _result(
    Backup backup,
    int assetCount,
    ZipWriteResult written,
  ) => BackupResult(
    backup: backup,
    assetCount: assetCount,
    skipped: written.skipped.length,
  );
}

/// The archive entry name of [filePath]: its path relative to the parent of
/// the `Saves` folder when it lies inside it, otherwise relative to the
/// parent of the `Mods` folder (v2 `_backupIsolate`), with `/` separators.
String backupEntryName(String filePath, {required Directories directories}) {
  final normalized = p.normalize(filePath);
  final inSaves = p.isWithin(p.normalize(directories.savesDir), normalized);
  final from = p.dirname(
    p.normalize(inSaves ? directories.savesDir : directories.modsDir),
  );
  return zipEntryName(p.relative(normalized, from: from));
}

// --- import backup --------------------------------------------------------

/// The user's choice when the local JSON is newer than the archive's.
enum JsonConflictChoice {
  /// Keep the local JSON, still restore the archive's asset files.
  keepCurrent,

  /// Overwrite the local JSON with the archive's.
  useBackup,

  /// Import nothing from this archive.
  cancel,
}

/// What the user is shown when deciding which JSON to keep.
final class JsonImportConflict {
  /// Creates the description.
  const JsonImportConflict({
    required this.jsonFileName,
    required this.localEpoch,
    required this.backupEpoch,
    required this.existingAssetCount,
    required this.backupAssetCount,
    required this.targetPath,
  });

  /// File name of the JSON (`123.json`).
  final String jsonFileName;

  /// Save time of the local JSON in Unix seconds.
  final int localEpoch;

  /// Save time of the archive's JSON in Unix seconds.
  final int backupEpoch;

  /// Asset files the local mod has on disk (0 when it is not indexed).
  final int existingAssetCount;

  /// Asset entries in the archive.
  final int backupAssetCount;

  /// Where the JSON would be written.
  final String targetPath;
}

/// Asked once per archive whose local JSON is strictly newer.
typedef JsonConflictResolver = Future<JsonConflictChoice> Function(
  JsonImportConflict conflict,
);

/// Outcome of [ImportBackupOperation].
final class ImportResult {
  /// Creates a result.
  const ImportResult({
    this.jsonPath,
    this.assetsExtracted = 0,
    this.failed = 0,
    this.jsonSkipped = false,
    this.cancelled = false,
  });

  /// Where the mod's JSON now lives (written or kept), or null when the
  /// archive has no JSON or the import was cancelled before writing.
  final String? jsonPath;

  /// Asset files written.
  final int assetsExtracted;

  /// Entries that could not be written.
  final int failed;

  /// Whether the local JSON was kept on the user's request.
  final bool jsonSkipped;

  /// Whether the import stopped early (user chose cancel, or the operation
  /// was cancelled).
  final bool cancelled;

  @override
  String toString() =>
      'ImportResult(json: $jsonPath, assets: $assetsExtracted, '
      'failed: $failed${jsonSkipped ? ', jsonSkipped' : ''}'
      '${cancelled ? ', cancelled' : ''})';
}

/// Restores one `.ttsmod` archive (v2 `importBackupFromPath`, streaming).
///
/// Pre-pass over the entry listing: the mod JSON is the `.json` entry
/// under a `Workshop` segment or at the top of `Saves/` (TTS index files
/// excluded), assets are the entries with an asset folder segment. Only
/// the JSON entry is read to get its save time. The JSON's target folder is
/// [targetJsonDir] when given, else the folder of the single library mod
/// with the same file name (so a mod moved into a sub-folder is not
/// duplicated), else the archive's stored path; its type follows the final
/// path (saved objects folder, saves folder, else mod). When the local JSON
/// is strictly newer, [onJsonConflict] decides. Every entry is then
/// extracted to its mapped path (JSON and its siblings redirected to the
/// target folder, assets under the `Mods` / `Saves` parents), new asset
/// files are indexed, the mod is (re-)indexed and sharing mods
/// re-summarised. Cancellation keeps what was extracted and indexes it.
final class ImportBackupOperation extends Operation<ImportResult> {
  /// Creates the operation.
  ImportBackupOperation({
    required this.ref,
    required this.ttsmodPath,
    required this.onJsonConflict,
    this.targetJsonDir,
  });

  /// Supplies the database, directories, pool and library.
  final Ref ref;

  /// The archive to import.
  final String ttsmodPath;

  /// Folder the JSON (and its sibling image) is restored into; null to
  /// resolve it from the library or the archive.
  final String? targetJsonDir;

  /// Decides a date conflict.
  final JsonConflictResolver onJsonConflict;

  ImportResult _partial = const ImportResult(cancelled: true);

  @override
  OperationKind get kind => OperationKind.importBackup;

  @override
  ImportResult? cancelledResult() => _partial;

  @override
  Future<ImportResult> run(OperationContext ctx) async {
    final log = ctx.log;
    final db = ref.read(appDatabaseProvider);
    final pool = ref.read(workerPoolProvider);
    final directories = await ref.read(directoriesProvider.future);
    final fileName = p.basename(ttsmodPath);
    ctx.report(
      OperationProgress(
        kind: kind,
        label: importExtractingLabel,
        detail: fileName,
      ),
    );

    final ZipEntryListing listing;
    try {
      listing = await pool.run(listZipEntries, ttsmodPath, token: ctx.token);
    } on OperationCancelledException {
      rethrow;
    } catch (error, stackTrace) {
      log.error(
        LogSource.import,
        'Could not read backup $fileName',
        error: error,
        stackTrace: stackTrace,
        details: ttsmodPath,
        operationId: ctx.operationId,
      );
      rethrow;
    }
    final files = listing.files.toList(growable: false);
    final jsonEntry = files.where((e) => isBackupJsonEntry(e.name)).firstOrNull;
    final backupAssetCount = files
        .where((e) => assetTypeFromEntryName(e.name) != null)
        .length;

    final modsParent = p.dirname(p.normalize(directories.modsDir));
    final savesParent = p.dirname(p.normalize(directories.savesDir));
    String parentFor(String entryName) =>
        entryName.startsWith(ttsSavesFolder) ? savesParent : modsParent;

    // Where the JSON goes, and what type the mod is there.
    String? effectiveTargetDir = targetJsonDir;
    String? jsonEntryDir;
    String? jsonTargetPath;
    ModType? modType;
    int? backupEpoch;
    if (jsonEntry != null) {
      jsonEntryDir = p.posix.dirname(jsonEntry.name);
      final jsonBase = p.posix.basename(jsonEntry.name);
      if (effectiveTargetDir == null) {
        final lower = jsonBase.toLowerCase();
        final matches = [
          for (final mod in _libraryState?.all ?? const <Mod>[])
            if (p.basename(mod.jsonPath).toLowerCase() == lower) mod,
        ];
        if (matches.length == 1) {
          effectiveTargetDir = p.dirname(matches.single.jsonPath);
        }
      }
      jsonTargetPath = p.normalize(
        effectiveTargetDir != null
            ? p.join(effectiveTargetDir, jsonBase)
            : p.join(parentFor(jsonEntry.name), jsonEntry.name),
      );
      modType = modTypeForPath(jsonTargetPath, directories: directories);
      try {
        final bytes = await pool.run(
          readZipEntryBytes,
          ZipEntryReadRequest(zipPath: ttsmodPath, entryName: jsonEntry.name),
          token: ctx.token,
        );
        if (bytes != null) {
          backupEpoch = extractEpochTime(
            utf8.decode(bytes, allowMalformed: true),
          );
        }
      } on OperationCancelledException {
        rethrow;
      } catch (error, stackTrace) {
        log.warning(
          LogSource.import,
          'Could not read the save date of the JSON in $fileName; '
          'importing without a date check',
          details: '$error\n$stackTrace',
          operationId: ctx.operationId,
        );
      }
    } else {
      log.warning(
        LogSource.import,
        'Backup $fileName has no mod JSON; only its asset files are restored',
        details: ttsmodPath,
        operationId: ctx.operationId,
      );
    }
    ctx.checkCancelled();

    // Date conflict: local JSON strictly newer than the archive's.
    var skipJsonWrite = false;
    final fs = ref.read(fileSystemProvider);
    if (jsonTargetPath != null &&
        modType != null &&
        backupEpoch != null &&
        fs.file(jsonTargetPath).existsSync()) {
      final localEpoch = await _localEpochTime(pool, jsonTargetPath, modType);
      if (localEpoch != null && localEpoch > backupEpoch) {
        final existing = _libraryState?.modByPath(jsonTargetPath);
        final choice = await onJsonConflict(
          JsonImportConflict(
            jsonFileName: p.basename(jsonTargetPath),
            localEpoch: localEpoch,
            backupEpoch: backupEpoch,
            existingAssetCount: existing?.summary.present ?? 0,
            backupAssetCount: backupAssetCount,
            targetPath: jsonTargetPath,
          ),
        );
        switch (choice) {
          case JsonConflictChoice.cancel:
            log.info(
              LogSource.import,
              'Import of $fileName cancelled: the local '
              '${p.basename(jsonTargetPath)} is newer',
              modPath: jsonTargetPath,
              operationId: ctx.operationId,
            );
            return const ImportResult(cancelled: true);
          case JsonConflictChoice.keepCurrent:
            skipJsonWrite = true;
          case JsonConflictChoice.useBackup:
            break;
        }
      }
    }
    ctx.checkCancelled();

    // Map every entry to its output path.
    final outputs = <String, String?>{};
    for (final entry in files) {
      final redirect =
          effectiveTargetDir != null &&
          jsonEntryDir != null &&
          p.posix.dirname(entry.name) == jsonEntryDir;
      final base = redirect ? effectiveTargetDir : parentFor(entry.name);
      final output = p.normalize(
        redirect
            ? p.join(base, p.posix.basename(entry.name))
            : p.join(base, entry.name),
      );
      if (!p.isWithin(p.normalize(base), output)) {
        log.warning(
          LogSource.import,
          'Skipped entry "${entry.name}" of $fileName: it would be written '
          'outside the library',
          operationId: ctx.operationId,
        );
        outputs[entry.name] = null;
        continue;
      }
      final isJson = jsonEntry != null && entry.name == jsonEntry.name;
      outputs[entry.name] = isJson && skipJsonWrite ? null : output;
    }
    _partial = ImportResult(
      jsonPath: skipJsonWrite ? jsonTargetPath : null,
      jsonSkipped: skipJsonWrite,
      cancelled: true,
    );

    log.info(
      LogSource.import,
      'Importing $fileName: ${files.length} entries, $backupAssetCount '
      'asset files${skipJsonWrite ? ', keeping the local JSON' : ''}',
      details: jsonTargetPath,
      modPath: jsonTargetPath,
      operationId: ctx.operationId,
    );
    final ZipExtractResult extracted;
    try {
      extracted = await ImportZipIsolate.extract(
        ZipExtractRequest(zipPath: ttsmodPath, outputs: outputs),
        token: ctx.token,
        onProgress: (progress) => ctx.report(
          OperationProgress(
            kind: kind,
            label: importExtractingLabel,
            done: progress.done,
            total: progress.total,
            detail: fileName,
          ),
        ),
      );
    } catch (error, stackTrace) {
      log.error(
        LogSource.import,
        'Could not extract backup $fileName',
        error: error,
        stackTrace: stackTrace,
        details: ttsmodPath,
        operationId: ctx.operationId,
      );
      rethrow;
    }
    for (final failure in extracted.failed) {
      log.error(
        LogSource.import,
        'Could not write "${failure.entryName}" from $fileName',
        details: failure.error,
        operationId: ctx.operationId,
      );
    }

    // Index what arrived.
    final keys = <String>{};
    var assetsExtracted = 0;
    var jsonWritten = false;
    for (final item in extracted.extracted) {
      if (jsonEntry != null && item.entryName == jsonEntry.name) {
        jsonWritten = true;
        continue;
      }
      final type = assetTypeFromEntryName(item.entryName);
      if (type == null) continue;
      assetsExtracted++;
      // Only files in the real cache folder of their type are index rows;
      // anything else (a raw folder, a stray sub-folder) is just restored.
      if (!p.equals(p.dirname(item.outputPath), directories.assetDir(type))) {
        continue;
      }
      final key = fileKeyFromFileName(
        p.basenameWithoutExtension(item.outputPath),
      );
      await db.existingFilesDao.upsert(type, key, item.outputPath);
      keys.add(key);
    }
    final jsonPath =
        jsonTargetPath != null &&
            (jsonWritten ||
                (skipJsonWrite && fs.file(jsonTargetPath).existsSync()))
        ? jsonTargetPath
        : null;
    final result = ImportResult(
      jsonPath: jsonPath,
      assetsExtracted: assetsExtracted,
      failed: extracted.failed.length,
      jsonSkipped: skipJsonWrite,
      cancelled: extracted.cancelled,
    );
    _partial = result;
    if (!ref.mounted) return result;

    final library = ref.read(libraryControllerProvider.notifier);
    if (jsonPath != null && modType != null) {
      await library.refreshMod(jsonPath, type: modType);
    }
    await library.applyAssetFileChange(keys);
    if (ref.mounted) ref.invalidate(modAssetsProvider);

    if (extracted.cancelled) {
      log.warning(
        LogSource.import,
        'Import of $fileName cancelled after $assetsExtracted asset files',
        modPath: jsonPath,
        operationId: ctx.operationId,
      );
    } else {
      log.success(
        LogSource.import,
        'Imported $fileName: $assetsExtracted asset files'
        '${extracted.failed.isEmpty ? '' : ', ${extracted.failed.length} failed'}',
        details: jsonPath,
        modPath: jsonPath,
        operationId: ctx.operationId,
      );
    }
    return result;
  }

  LibraryState? get _libraryState => ref.read(libraryControllerProvider).value;

  /// Save time of the local JSON through the library's parser (reads only
  /// the file head), or null when it has none or cannot be read.
  Future<int?> _localEpochTime(
    WorkerPool pool,
    String jsonPath,
    ModType type,
  ) async {
    try {
      final parsed = await pool.run(
        parseModFiles,
        ParseModsRequest(files: [(jsonPath: jsonPath, type: type)]),
      );
      return parsed.single.isOk ? parsed.single.epochTime : null;
    } catch (_) {
      return null;
    }
  }
}

/// Whether [entryName] (with `/` separators) is the mod JSON of a backup:
/// a `.json` under a `Workshop` segment (Workshop mods, as v2) or directly
/// under the top-level `Saves` tree (saves and saved objects), excluding
/// TTS's own index files.
bool isBackupJsonEntry(String entryName) {
  final segments = p.posix.split(entryName);
  if (segments.isEmpty) return false;
  final base = segments.last;
  if (p.posix.extension(base).toLowerCase() != '.json') return false;
  if (ttsIndexFileNames.contains(base)) return false;
  return segments.contains(ttsWorkshopFolder) ||
      segments.first == ttsSavesFolder;
}

/// The asset type of an archive entry from its folder segment
/// (`Mods/Images/x.png` → image), case-insensitive; null for the JSON, the
/// image next to it and anything else.
AssetType? assetTypeFromEntryName(String entryName) {
  for (final segment in p.posix.split(entryName)) {
    final type = AssetType.fromFolderName(segment);
    if (type != null) return type;
  }
  return null;
}

/// The mod type a JSON at [jsonPath] has: saved object inside
/// `Saves/Saved Objects`, save inside `Saves`, otherwise mod.
ModType modTypeForPath(String jsonPath, {required Directories directories}) {
  final normalized = p.normalize(jsonPath);
  if (p.isWithin(p.normalize(directories.savedObjectsDir), normalized)) {
    return ModType.savedObject;
  }
  if (p.isWithin(p.normalize(directories.savesDir), normalized)) {
    return ModType.save;
  }
  return ModType.mod;
}

// --- import several backups -----------------------------------------------

/// One file of an [ImportBackupsOperation].
final class ImportFileResult {
  /// Creates a per-file result.
  const ImportFileResult({required this.path, this.result, this.error});

  /// The archive.
  final String path;

  /// The import's outcome, or null when it failed before producing one.
  final ImportResult? result;

  /// Why the import failed, or null.
  final String? error;

  /// Whether the archive was imported (possibly partially).
  bool get succeeded => result != null && !result!.cancelled;
}

/// Outcome of [ImportBackupsOperation].
final class ImportBackupsResult {
  /// Creates a result.
  const ImportBackupsResult({required this.results, required this.cancelled});

  /// One entry per archive attempted, in order; archives not reached after
  /// a cancel are absent.
  final List<ImportFileResult> results;

  /// Whether the run stopped early.
  final bool cancelled;

  /// Archives imported.
  int get imported => results.where((r) => r.succeeded).length;

  /// Archives that failed.
  int get failed => results.where((r) => r.error != null).length;

  @override
  String toString() =>
      'ImportBackupsResult(imported: $imported, failed: $failed, '
      'of ${results.length}${cancelled ? ', cancelled' : ''})';
}

/// Imports [paths] one after another with one progress bar
/// (`import.file`, `done` files of `total`, fraction including the current
/// file's extraction). A failing archive is logged and skipped; a cancel
/// (token or user choice on a conflict) stops the run.
final class ImportBackupsOperation extends Operation<ImportBackupsResult> {
  /// Creates the operation.
  ImportBackupsOperation({
    required this.ref,
    required this.paths,
    required this.onJsonConflict,
    this.targetJsonDir,
  });

  /// Supplies the per-file operations' collaborators.
  final Ref ref;

  /// Archives to import, in order.
  final List<String> paths;

  /// Folder every JSON is restored into; null to resolve per archive.
  final String? targetJsonDir;

  /// Decides date conflicts.
  final JsonConflictResolver onJsonConflict;

  final List<ImportFileResult> _results = [];

  @override
  OperationKind get kind => OperationKind.importBackup;

  @override
  ImportBackupsResult? cancelledResult() => ImportBackupsResult(
    results: List.unmodifiable(_results),
    cancelled: true,
  );

  @override
  Future<ImportBackupsResult> run(OperationContext ctx) async {
    final total = paths.length;
    var cancelled = false;
    for (var i = 0; i < total; i++) {
      final path = paths[i];
      if (ctx.isCancelled) {
        cancelled = true;
        break;
      }
      final name = p.basename(path);
      ctx.report(
        OperationProgress(
          kind: kind,
          label: importFileLabel,
          done: i,
          total: total,
          fraction: i / total,
          detail: name,
        ),
      );
      final child = OperationContext(
        token: ctx.token,
        log: ctx.log,
        operationId: ctx.operationId,
        onProgress: (inner) => ctx.report(
          OperationProgress(
            kind: kind,
            label: importFileLabel,
            done: i,
            total: total,
            fraction: (i + (inner.value ?? 0)) / total,
            detail: inner.detail ?? name,
          ),
        ),
      );
      final op = ImportBackupOperation(
        ref: ref,
        ttsmodPath: path,
        targetJsonDir: targetJsonDir,
        onJsonConflict: onJsonConflict,
      );
      try {
        final result = await op.run(child);
        _results.add(ImportFileResult(path: path, result: result));
        if (result.cancelled) {
          cancelled = true;
          break;
        }
      } on OperationCancelledException {
        _results.add(
          ImportFileResult(path: path, result: op.cancelledResult()),
        );
        cancelled = true;
        break;
      } catch (error) {
        // Already logged by the per-file operation with its context.
        _results.add(ImportFileResult(path: path, error: error.toString()));
      }
    }
    final result = ImportBackupsResult(
      results: List.unmodifiable(_results),
      cancelled: cancelled,
    );
    ctx.log.info(
      LogSource.import,
      'Imported ${result.imported} of $total backup(s)'
      '${result.failed == 0 ? '' : ', ${result.failed} failed'}'
      '${cancelled ? ' (cancelled)' : ''}',
      operationId: ctx.operationId,
    );
    return result;
  }
}

// --- import JSON ----------------------------------------------------------

/// Outcome of [ImportJsonOperation].
final class ImportJsonResult {
  /// Creates a result.
  const ImportJsonResult({required this.jsonPath, required this.imageCopied});

  /// Where the JSON was written.
  final String jsonPath;

  /// Whether the optional PNG was copied next to it.
  final bool imageCopied;
}

/// Copies a mod JSON (and optionally a PNG, renamed to the JSON's base
/// name) into [destinationFolder] and indexes it as [type]
/// (v2 `importJson`). A PNG that cannot be copied is logged and does not
/// fail the import.
final class ImportJsonOperation extends Operation<ImportJsonResult> {
  /// Creates the operation.
  ImportJsonOperation({
    required this.ref,
    required this.sourceJson,
    required this.destinationFolder,
    required this.type,
    this.sourcePng,
  });

  /// Supplies the file system and library.
  final Ref ref;

  /// The JSON to copy.
  final String sourceJson;

  /// Folder it is copied into (created when missing).
  final String destinationFolder;

  /// How the copy is indexed.
  final ModType type;

  /// Optional image copied as `<json base>.png`.
  final String? sourcePng;

  @override
  OperationKind get kind => OperationKind.importBackup;

  @override
  Future<ImportJsonResult> run(OperationContext ctx) async {
    final log = ctx.log;
    final fs = ref.read(fileSystemProvider);
    final targetPath = p.normalize(
      p.join(destinationFolder, p.basename(sourceJson)),
    );
    try {
      await fs.directory(destinationFolder).create(recursive: true);
      await fs.file(sourceJson).copy(targetPath);
    } catch (error, stackTrace) {
      log.error(
        LogSource.import,
        'Could not import ${p.basename(sourceJson)}',
        error: error,
        stackTrace: stackTrace,
        details: '$sourceJson -> $targetPath',
        operationId: ctx.operationId,
      );
      rethrow;
    }
    var imageCopied = false;
    final png = sourcePng;
    if (png != null && png.isNotEmpty) {
      final pngTarget = p.join(
        destinationFolder,
        '${p.basenameWithoutExtension(targetPath)}.png',
      );
      try {
        await fs.file(png).copy(pngTarget);
        imageCopied = true;
      } catch (error, stackTrace) {
        log.warning(
          LogSource.import,
          'Imported ${p.basename(sourceJson)} without its image: the PNG '
          'could not be copied',
          details: '$png -> $pngTarget\n$error\n$stackTrace',
          modPath: targetPath,
          operationId: ctx.operationId,
        );
      }
    }
    if (ref.mounted) {
      await ref
          .read(libraryControllerProvider.notifier)
          .refreshMod(targetPath, type: type);
    }
    log.success(
      LogSource.import,
      'Imported ${p.basename(sourceJson)} as ${type.name}'
      '${imageCopied ? ' with its image' : ''}',
      details: targetPath,
      modPath: targetPath,
      operationId: ctx.operationId,
    );
    return ImportJsonResult(jsonPath: targetPath, imageCopied: imageCopied);
  }
}
