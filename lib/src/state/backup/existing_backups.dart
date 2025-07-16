import 'dart:io' show Directory, File;
import 'dart:isolate' show Isolate;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart' show debugPrint;
import 'package:hooks_riverpod/hooks_riverpod.dart' show Ref, StateNotifier;
import 'package:path/path.dart' as path;
import 'package:tts_mod_vault/src/state/backup/existing_backups_state.dart'
    show ExistingBackupsState;
import 'package:tts_mod_vault/src/state/backup/models/existing_backup_model.dart'
    show ExistingBackup;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show Mod;
import 'package:tts_mod_vault/src/state/provider.dart'
    show loadingMessageProvider;
import 'package:tts_mod_vault/src/utils.dart' show sanitizeFileName;

class ExistingBackupsStateNotifier extends StateNotifier<ExistingBackupsState> {
  final Ref ref;
  static const String _backupsDirectoryPath =
      r'D:\Downloads\Backups'; // TODO replace with path from settings

  ExistingBackupsStateNotifier(this.ref) : super(ExistingBackupsState.empty());

  Future<void> loadExistingBackups() async {
    debugPrint('loadExistingBackups');

    ref.read(loadingMessageProvider.notifier).state =
        'Loading existing backups';

    final backups = await Isolate.run(
      () => _getBackupsFromDirectory(_backupsDirectoryPath),
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
      final backupFileName =
          sanitizeFileName("${mod.saveName}(${mod.jsonFileName}).ttsmod");

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

  if (!directory.existsSync()) {
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

    backups.add(ExistingBackup(
      filename: filename,
      filepath: path.normalize(entity.path),
      lastModifiedTimestamp: stat.modified.millisecondsSinceEpoch ~/ 1000,
    ));
  }

  return backups;
}
