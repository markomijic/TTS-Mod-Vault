/// File-system scanners of the library refresh pipeline (plan section 4.4),
/// packaged as `WorkerPool` tasks.
///
/// Every entry point is a top-level function that takes **one** plain,
/// isolate-sendable argument and returns a plain result, so it can be passed
/// straight to `WorkerPool.run` / `WorkerPool.runAll`:
///
/// ```dart
/// final pool = WorkerPool();
///
/// // 1. Mod / save / saved-object JSONs (one task per root).
/// final workshop = await pool.run(
///   scanModFiles,
///   ModFileScanRequest(
///     rootDir: p.join(ttsDir, ttsModsFolder, ttsWorkshopFolder),
///     type: ModType.mod,
///     ignoredSubfolders: settings.ignoredSubfolders,
///   ),
/// );
/// final saves = await pool.run(
///   scanModFiles,
///   ModFileScanRequest(
///     rootDir: p.join(ttsDir, ttsSavesFolder),
///     type: ModType.save,
///     // Saved objects live under Saves/ and are scanned separately.
///     ignoredSubfolders: [ttsSavedObjectsFolder, ...settings.ignoredSubfolders],
///   ),
/// );
///
/// // 2. existing_files index, one task per asset type.
/// final indexes = await pool.runAll(indexAssetDirectory, [
///   for (final type in AssetType.values)
///     AssetIndexRequest(type: type, directory: dirs.assetDirectory(type)),
/// ]);
///
/// // 3. Backups: list, then count assets for the archives the store does
/// //    not know yet (chunk the paths so each worker gets a batch).
/// final backups = await pool.run(
///   scanBackupFiles,
///   BackupScanRequest(backupsDir: settings.backupsDir),
/// );
/// final counts = await pool.runAll(countBackupAssets, chunks);
/// ```
///
/// Phase 4 adds the zip writer / extractor (`zip/zip_writer.dart`,
/// `zip/zip_extractor.dart`: `writeZipArchive`, `listZipEntries`,
/// `readZipEntryBytes`, `extractZipEntries`) and the cleanup listings
/// (`cleanup_directory_scanner.dart`: `scanCleanupDirectory`,
/// `statFileSizes`); the zip tasks also have progress-reporting isolate
/// variants for the operations that need a progress bar.
///
/// Each scanner also has a `...With(request, FileSystem)` variant that runs
/// on any `package:file` file system; tests use `MemoryFileSystem`. Scanners
/// never throw for a missing or unreadable directory: they return empty
/// results and describe the problem in the result's `warnings` list.
library;

export 'package:tts_mod_vault/data/fs/asset_directory_indexer.dart';
export 'package:tts_mod_vault/data/fs/backup_file_scanner.dart';
export 'package:tts_mod_vault/data/fs/cleanup_directory_scanner.dart';
export 'package:tts_mod_vault/data/fs/mod_file_scanner.dart';
export 'package:tts_mod_vault/data/fs/zip/zip_asset_counter.dart';
export 'package:tts_mod_vault/data/fs/zip/zip_central_directory_reader.dart';
export 'package:tts_mod_vault/data/fs/zip/zip_extractor.dart';
export 'package:tts_mod_vault/data/fs/zip/zip_writer.dart';
