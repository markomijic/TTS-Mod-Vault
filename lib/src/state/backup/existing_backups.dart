import 'dart:io' show Directory, File;
import 'dart:isolate' show Isolate;
import 'dart:math' show max, min;
import 'dart:io' show Platform;

import 'package:archive/archive.dart' show ZipDecoder;
import 'package:collection/collection.dart';
import 'package:flutter/material.dart' show debugPrint;
import 'package:hooks_riverpod/hooks_riverpod.dart' show Ref, StateNotifier;
import 'package:path/path.dart' as path;
import 'package:tts_mod_vault/src/state/backup/existing_backups_state.dart'
    show ExistingBackupsState;
import 'package:tts_mod_vault/src/state/backup/models/existing_backup_model.dart'
    show ExistingBackup;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show Mod;
import 'package:tts_mod_vault/src/state/provider.dart' show directoriesProvider;
import 'package:tts_mod_vault/src/utils.dart' show getBackupFilenameByMod;

class ExistingBackupsStateNotifier extends StateNotifier<ExistingBackupsState> {
  final Ref ref;

  ExistingBackupsStateNotifier(this.ref) : super(ExistingBackupsState.empty());

  Future<void> loadExistingBackups() async {
    debugPrint('loadExistingBackups - started at ${DateTime.now()}');

    final backupsDir = ref.read(directoriesProvider).backupsDir;
    final directory = Directory(backupsDir);

    if (backupsDir.isEmpty || !directory.existsSync()) {
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
      state = ExistingBackupsState(backups: []);
      return;
    }

    final numberOfIsolates = max(Platform.numberOfProcessors - 2, 2);
    final chunkedFiles = _chunkList(files, numberOfIsolates);
    final futures = chunkedFiles
        .map((chunk) => Isolate.run(() => _processBackupFiles(chunk)))
        .toList();

    final results = await Future.wait(futures);
    final backups = results.expand((list) => list).toList();

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

  ExistingBackup? getInitialBackupByMod(Mod mod) {
    try {
      final backupFileName = getBackupFilenameByMod(mod);

      return state.backups
          .firstWhereOrNull((backup) => backup.filename == backupFileName);
    } catch (e) {
      return null;
    }
  }

  Future<ExistingBackup?> getCompleteBackup(Mod mod) async {
    try {
      final backupFileName = getBackupFilenameByMod(mod);

      final backup = state.backups
          .firstWhereOrNull((backup) => backup.filename == backupFileName);

      if (backup == null) {
        return backup;
      }

      if (backup.totalAssetCount == -1) {
        final full = await _getBackupWithTotalAssetCount(backup);
        addBackup(full);
        return full;
      }

      return backup;
    } catch (e) {
      return null;
    }
  }

  Future<ExistingBackup> _getBackupWithTotalAssetCount(
    ExistingBackup backup,
  ) async {
    final totalAssetCount = await _getTotalAssetCount(backup.filepath);

    return backup.copyWith(totalAssetCount: totalAssetCount);
  }

  Future<int> _getTotalAssetCount(String ttsmodPath) async {
    const targetFolders = ['Assetbundles', 'Audio', 'Images', 'PDF', 'Models'];

    try {
      final file = File(ttsmodPath);
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      int totalCount = 0;

      for (final entry in archive) {
        if (entry.isFile) {
          final parentFolderName = path.basename(path.dirname(entry.name));

          for (final folder in targetFolders) {
            if (parentFolderName == folder) {
              totalCount++;
              break;
            }
          }
        }
      }

      return totalCount;
    } catch (e) {
      debugPrint('getTotalFileCount - error reading $ttsmodPath: $e');
      return 0;
    }
  }
}

///
/// Top-level function required by Isolate.run
///
Future<List<ExistingBackup>> _processBackupFiles(List<File> files) async {
  final backups = <ExistingBackup>[];

  for (final file in files) {
    final stat = await file.stat();
    final filename = path.basename(file.path);

    backups.add(ExistingBackup(
      filename: filename,
      filepath: path.normalize(file.path),
      lastModifiedTimestamp: stat.modified.millisecondsSinceEpoch ~/ 1000,
      totalAssetCount: -1,
    ));
  }

  return backups;
}
