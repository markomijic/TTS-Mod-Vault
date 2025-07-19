import 'dart:io' show Directory, File;
import 'dart:isolate' show Isolate;

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
    debugPrint('loadExistingBackups');

    final backupsDir = ref.read(directoriesProvider).backupsDir;

    final backups = await Isolate.run(
      () => _getBackupsFromDirectory(backupsDir),
    );

    state = ExistingBackupsState(backups: backups);
  }

  bool doesBackupExist(String filename) {
    return state.backups.any((backup) => backup.filename == filename);
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

  ExistingBackup? getBackupByMod(Mod mod) {
    try {
      final backupFileName = getBackupFilenameByMod(mod);

      return state.backups
          .firstWhereOrNull((backup) => backup.filename == backupFileName);
    } catch (e) {
      return null;
    }
  }
}

///
/// Top-level function required by Isolate.run
///
Future<List<ExistingBackup>> _getBackupsFromDirectory(String dirPath) async {
  final directory = Directory(dirPath);

  if (dirPath.isEmpty || !directory.existsSync()) {
    return <ExistingBackup>[];
  }

  final entities = await directory
      .list(recursive: true)
      .where((entity) => entity is File)
      .cast<File>()
      .where((file) => path.extension(file.path).toLowerCase() == '.ttsmod')
      .toList();

  final backups = <ExistingBackup>[];

  for (final entity in entities) {
    final stat = await entity.stat();
    final filename = path.basename(entity.path);
    final totalAssetCount = await getTotalFileCount(entity.path);

    backups.add(ExistingBackup(
      filename: filename,
      filepath: path.normalize(entity.path),
      lastModifiedTimestamp: stat.modified.millisecondsSinceEpoch ~/ 1000,
      totalAssetCount: totalAssetCount,
    ));
  }

  return backups;
}

Future<int> getTotalFileCount(String ttsmodPath) async {
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
