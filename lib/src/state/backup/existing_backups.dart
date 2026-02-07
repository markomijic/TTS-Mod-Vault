import 'dart:io' show Directory, File, Platform;
import 'dart:isolate' show Isolate;
import 'dart:math' show max, min;

import 'package:flutter/material.dart' show debugPrint;
import 'package:hooks_riverpod/hooks_riverpod.dart' show Ref, StateNotifier;
import 'package:path/path.dart' as path;
import 'package:tts_mod_vault/src/state/backup/backup_cache.dart'
    show BackupCache;
import 'package:tts_mod_vault/src/state/backup/existing_backups_state.dart'
    show ExistingBackupsState;
import 'package:tts_mod_vault/src/state/backup/models/existing_backup_model.dart'
    show ExistingBackup;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart'
    show Mod, ModTypeEnum;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        backupCacheProvider,
        directoriesProvider,
        loadingMessageProvider,
        settingsProvider,
        modsProvider;
import 'package:tts_mod_vault/src/utils.dart' show getBackupFilenameByMod;
import 'package:tts_mod_vault/src/utils/zip_asset_counter.dart'
    show ZipAssetCounter;

class ExistingBackupsStateNotifier extends StateNotifier<ExistingBackupsState> {
  final Ref ref;

  ExistingBackupsStateNotifier(this.ref) : super(ExistingBackupsState.empty());

  Future<void> loadExistingBackups() async {
    debugPrint('loadExistingBackups - started at ${DateTime.now()}');

    final backupsDir = ref.read(directoriesProvider).backupsDir;
    final directory = Directory(backupsDir);

    if (backupsDir.isEmpty || !directory.existsSync()) {
      debugPrint(
          'loadExistingBackups - finished at ${DateTime.now()} - backups dir is not set or directory does not exist');
      state = ExistingBackupsState(backups: []);
      return;
    }

    final files = await directory
        .list(recursive: true)
        .where((entity) => entity is File)
        .cast<File>()
        .where((file) => path.extension(file.path).toLowerCase() == '.ttsmod')
        .toList();

    if (files.isEmpty) {
      debugPrint(
          'loadExistingBackups - finished at ${DateTime.now()} - files are empty');
      state = ExistingBackupsState(backups: []);
      return;
    }

    ref.read(loadingMessageProvider.notifier).state = 'Loading backup files';

    // Stat all files to get filesystem metadata
    final fileMetas = <_FileMeta>[];
    for (final file in files) {
      try {
        final stat = await file.stat();
        fileMetas.add(_FileMeta(
          filepath: path.normalize(file.path),
          filename: path.basename(file.path),
          lastModified: stat.modified.millisecondsSinceEpoch ~/ 1000,
          fileSize: stat.size,
        ));
      } catch (e) {
        debugPrint('loadExistingBackups - stat error: $e');
      }
    }

    // Load cache
    final cache = ref.read(backupCacheProvider);

    // Separate cached vs uncached files
    final backups = <ExistingBackup>[];
    final uncachedMetas = <_FileMeta>[];
    final uncachedIndices = <int>[]; // Index into backups list

    for (final meta in fileMetas) {
      final key =
          BackupCache.cacheKey(meta.filepath, meta.lastModified, meta.fileSize);
      final cachedCount = cache.get(key);

      if (cachedCount != null) {
        backups.add(ExistingBackup(
          filename: meta.filename,
          filepath: meta.filepath,
          fileSize: meta.fileSize,
          lastModifiedTimestamp: meta.lastModified,
          totalAssetCount: cachedCount,
        ));
      } else {
        uncachedIndices.add(backups.length);
        // Placeholder — will be replaced after isolate processing
        backups.add(ExistingBackup(
          filename: meta.filename,
          filepath: meta.filepath,
          fileSize: meta.fileSize,
          lastModifiedTimestamp: meta.lastModified,
          totalAssetCount: 0,
        ));
        uncachedMetas.add(meta);
      }
    }

    debugPrint(
        'loadExistingBackups - ${fileMetas.length - uncachedMetas.length} cache hits, '
        '${uncachedMetas.length} cache misses');

    if (uncachedMetas.isNotEmpty) {
      // Chunk uncached file paths across isolates
      final uncachedPaths = uncachedMetas.map((m) => m.filepath).toList();
      final numberOfIsolates = max(Platform.numberOfProcessors - 2, 2);
      final chunks = _chunkList(uncachedPaths, numberOfIsolates);

      final results = await Future.wait(
        chunks.map((chunk) => Isolate.run(() => _countAssetsForFiles(chunk))),
      );

      final allCounts = results.expand((list) => list).toList();

      // Fill in the placeholders and update cache
      final newCacheEntries = <String, int>{};
      for (int j = 0; j < uncachedMetas.length; j++) {
        final meta = uncachedMetas[j];
        final count = allCounts[j];
        final idx = uncachedIndices[j];

        backups[idx] = ExistingBackup(
          filename: meta.filename,
          filepath: meta.filepath,
          fileSize: meta.fileSize,
          lastModifiedTimestamp: meta.lastModified,
          totalAssetCount: count,
        );

        final key = BackupCache.cacheKey(
            meta.filepath, meta.lastModified, meta.fileSize);
        newCacheEntries[key] = count;
      }

      // Persist new entries and prune stale ones
      await cache.putAll(newCacheEntries);
      final validKeys = fileMetas
          .map((m) =>
              BackupCache.cacheKey(m.filepath, m.lastModified, m.fileSize))
          .toSet();
      await cache.pruneStaleEntries(validKeys);
    }

    state = ExistingBackupsState(backups: backups);

    debugPrint('loadExistingBackups - finished at ${DateTime.now()}');
  }

  List<List<T>> _chunkList<T>(List<T> list, int chunkSize) {
    final chunks = <List<T>>[];
    final itemsPerChunk = (list.length / chunkSize).ceil();

    for (int i = 0; i < list.length; i += itemsPerChunk) {
      final end = min(i + itemsPerChunk, list.length);
      chunks.add(list.sublist(i, end));
    }

    return chunks;
  }

  void addBackup(ExistingBackup newBackup) {
    final existingIndex = state.backups
        .indexWhere((backup) => backup.filename == newBackup.filename);

    if (existingIndex >= 0) {
      // Replace existing backup
      final updatedBackups = [...state.backups];
      updatedBackups[existingIndex] = newBackup;
      state = ExistingBackupsState(backups: updatedBackups);
    } else {
      // Add new backup
      state = ExistingBackupsState(backups: [...state.backups, newBackup]);
    }
  }

  ExistingBackup? _getMostRecentBackupByFilename(String filename) {
    final matchingBackups =
        state.backups.where((backup) => backup.filename == filename).toList();

    if (matchingBackups.isEmpty) {
      return null;
    }

    // Sort by lastModifiedTimestamp in descending order and take the first (most recent)
    matchingBackups.sort(
        (a, b) => b.lastModifiedTimestamp.compareTo(a.lastModifiedTimestamp));

    return matchingBackups.first;
  }

  ExistingBackup? getBackupByMod(Mod mod) {
    try {
      final forceBackupJsonFilename =
          ref.read(settingsProvider).forceBackupJsonFilename;

      ExistingBackup? foundBackup;

      if (forceBackupJsonFilename && mod.modType == ModTypeEnum.mod) {
        // Try to find backup name which includes JSON filename
        final backupFileNameWithJson = getBackupFilenameByMod(mod, true);
        foundBackup = _getMostRecentBackupByFilename(backupFileNameWithJson);

        if (foundBackup == null) {
          // Try to find backup name which doesn't force inclusion of JSON filename
          final standardBackupFileName = getBackupFilenameByMod(mod, false);
          foundBackup = _getMostRecentBackupByFilename(standardBackupFileName);
        }
      } else {
        final backupFileName = getBackupFilenameByMod(mod, false);
        foundBackup = _getMostRecentBackupByFilename(backupFileName);
      }

      // If backup found, update its state with the matching mod's filepath
      if (foundBackup != null && foundBackup.matchingModFilepath == null) {
        return _updateBackupWithModFilepath(foundBackup, mod.jsonFilePath);
      }

      return foundBackup;
    } catch (e) {
      return null;
    }
  }

  ExistingBackup _updateBackupWithModFilepath(
      ExistingBackup backup, String? modFilepath) {
    final backupIndex = state.backups.indexWhere(
      (b) => b.filename == backup.filename && b.filepath == backup.filepath,
    );

    if (backupIndex >= 0) {
      final updatedBackups = [...state.backups];
      final updatedBackup = backup.copyWith(matchingModFilepath: modFilepath);
      updatedBackups[backupIndex] = updatedBackup;

      state = ExistingBackupsState(backups: updatedBackups);
      return updatedBackup;
    }

    return backup;
  }

  Future<void> deleteBackup(ExistingBackup backup) async {
    try {
      state = state.copyWith(deletingBackup: true);

      final file = File(backup.filepath);

      if (file.existsSync()) {
        await file.delete();

        // Remove backup from state after successful deletion
        final updatedBackups =
            state.backups.where((b) => b.filepath != backup.filepath).toList();
        state = ExistingBackupsState(backups: updatedBackups);

        // Find and refresh any mods that matched this backup
        final modsAsyncValue = ref.read(modsProvider);
        if (modsAsyncValue.hasValue) {
          final modsState = modsAsyncValue.value!;
          final backupFilenameWithoutExt =
              backup.filename.replaceAll('.ttsmod', '');

          final allMods = [
            ...modsState.mods,
            ...modsState.saves,
            ...modsState.savedObjects,
          ];

          for (final mod in allMods) {
            final backupName1 =
                getBackupFilenameByMod(mod, false).replaceAll('.ttsmod', '');
            final backupName2 =
                getBackupFilenameByMod(mod, true).replaceAll('.ttsmod', '');

            if (backupFilenameWithoutExt == backupName1 ||
                backupFilenameWithoutExt == backupName2) {
              // Refresh this mod's backup status
              await ref.read(modsProvider.notifier).updateModBackup(mod);
              break;
            }
          }
        }
      }
    } catch (e) {
      rethrow;
    } finally {
      state = state.copyWith(deletingBackup: false);
    }
  }
}

/// Top-level function for Isolate.run — counts assets for a batch of zip files
/// using the custom central directory reader (no process spawning, no full read).
Future<List<int>> _countAssetsForFiles(List<String> filePaths) async {
  final counts = <int>[];
  for (final filePath in filePaths) {
    try {
      final count = await ZipAssetCounter.countAssets(filePath);
      counts.add(count);
    } catch (_) {
      counts.add(0);
    }
  }
  return counts;
}

class _FileMeta {
  final String filepath;
  final String filename;
  final int lastModified;
  final int fileSize;

  _FileMeta({
    required this.filepath,
    required this.filename,
    required this.lastModified,
    required this.fileSize,
  });
}
