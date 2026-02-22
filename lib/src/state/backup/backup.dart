import 'dart:io' show Directory, File;
import 'dart:isolate' show ReceivePort, Isolate;

import 'package:archive/archive_io.dart' show ZipFileEncoder;
import 'package:collection/collection.dart' show IterableExtension;
import 'package:file_picker/file_picker.dart' show FilePicker;
import 'package:flutter/material.dart' show debugPrint;
import 'package:hooks_riverpod/hooks_riverpod.dart' show Ref, StateNotifier;
import 'package:path/path.dart' as p
    show basename, basenameWithoutExtension, dirname, join, normalize, relative;
import 'package:tts_mod_vault/src/state/backup/backup_state.dart'
    show
        BackupCompleteMessage,
        BackupIsolateData,
        BackupProgressMessage,
        BackupState,
        BackupStatusEnum,
        FilepathsIsolateData;
import 'package:tts_mod_vault/src/state/backup/models/existing_backup_model.dart'
    show ExistingBackup;
import 'package:tts_mod_vault/src/state/bulk_actions/bulk_actions_state.dart'
    show BulkActionsStatusEnum;
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart'
    show AssetTypeEnum;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show Mod;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        bulkActionsProvider,
        directoriesProvider,
        existingBackupsProvider,
        settingsProvider;
import 'package:tts_mod_vault/src/utils.dart'
    show
        getBackupFilenameByMod,
        getFileNameFromURL,
        newSteamUserContentUrl,
        oldCloudUrl;

class BackupNotifier extends StateNotifier<BackupState> {
  final Ref ref;

  BackupNotifier(this.ref) : super(const BackupState());

  void resetMessage() {
    state = state.copyWith(message: "");
  }

  Future<void> createBackup(Mod mod, [String? backupDirectory]) async {
    state = state.copyWith(
      status: backupDirectory != null && backupDirectory.isNotEmpty
          ? BackupStatusEnum.backingUp
          : BackupStatusEnum.awaitingBackupFolder,
      currentCount: 0,
      totalCount: 0,
      message: "",
    );

    final backupsDir = ref.read(directoriesProvider).backupsDir;

    final backupDirPath = backupDirectory != null && backupDirectory.isNotEmpty
        ? backupDirectory
        : await FilePicker.platform.getDirectoryPath(
            lockParentWindow: true,
            initialDirectory: backupsDir.isEmpty ? null : backupsDir,
          );

    if (backupDirPath == null) {
      state = state.copyWith(status: BackupStatusEnum.idle);
      return;
    }

    state = state.copyWith(status: BackupStatusEnum.backingUp);

    try {
      final filepathsData = FilepathsIsolateData(
        mod,
        {
          for (final type in AssetTypeEnum.values)
            type:
                ref.read(directoriesProvider.notifier).getDirectoryByType(type)
        },
      );

      final filePaths =
          await Isolate.run(() => _getFilePathsIsolate(filepathsData));
      final totalAssetCount = filePaths.$2;

      final receivePort = ReceivePort();
      final forceBackupJsonFilename =
          ref.read(settingsProvider).forceBackupJsonFilename;
      final backupFileName =
          getBackupFilenameByMod(mod, forceBackupJsonFilename);
      final targetBackupFilePath = p.join(backupDirPath, backupFileName);

      final modsDir = Directory(ref.read(directoriesProvider).modsDir);
      final savesDir = Directory(ref.read(directoriesProvider).savesDir);

      final isolateData = BackupIsolateData(
        filePaths: filePaths.$1,
        targetBackupFilePath: targetBackupFilePath,
        modsParentPath: modsDir.parent.path,
        savesParentPath: savesDir.parent.path,
        savesPath: savesDir.path,
        sendPort: receivePort.sendPort,
      );

      // Start the isolate
      await Isolate.spawn(_backupIsolate, isolateData);

      // Listen for messages from isolate
      await for (final message in receivePort) {
        if (message is BackupProgressMessage) {
          state = state.copyWith(
            currentCount: message.current,
            totalCount: message.total,
          );
        } else if (message is BackupCompleteMessage) {
          receivePort.close();

          if (message.success) {
            // Add new backup to state
            final backupFile = File(targetBackupFilePath);
            final backupFileSize =
                backupFile.existsSync() ? backupFile.lengthSync() : 0;
            final newBackup = ExistingBackup(
              filename: backupFileName,
              filepath: targetBackupFilePath,
              parentFolderName: p.basename(p.dirname(targetBackupFilePath)),
              lastModifiedTimestamp:
                  DateTime.now().millisecondsSinceEpoch ~/ 1000,
              totalAssetCount: totalAssetCount,
              fileSize: backupFileSize,
            );
            ref.read(existingBackupsProvider.notifier).addBackup(newBackup);
          }

          if (ref.read(bulkActionsProvider).status ==
              BulkActionsStatusEnum.idle) {
            state = state.copyWith(message: message.message);
          }
          break;
        }
      }
    } catch (e) {
      debugPrint('createBackup - error: ${e.toString()}');
      state = state.copyWith(message: e.toString());
    } finally {
      state = state.copyWith(status: BackupStatusEnum.idle);
    }
  }
}

(List<String>, int) _getFilePathsIsolate(FilepathsIsolateData data) {
  final filePaths = <String>[];

  for (final type in AssetTypeEnum.values) {
    final dirPath = data.directories[type];
    if (dirPath == null) continue;

    final directory = Directory(dirPath);
    if (!directory.existsSync()) continue;

    final files = directory.listSync();
    data.mod.getAssetsByType(type).forEach((asset) {
      if (asset.filePath == null) return;

      final newUrlBase = p.basenameWithoutExtension(asset.filePath!);
      final oldUrlBase = newUrlBase.replaceFirst(
        getFileNameFromURL(newSteamUserContentUrl),
        getFileNameFromURL(oldCloudUrl),
      );

      final match = files.firstWhereOrNull((file) {
        final base = p.basenameWithoutExtension(file.path);
        return base.startsWith(newUrlBase) || base.startsWith(oldUrlBase);
      });

      if (match != null && match.path.isNotEmpty) {
        filePaths.add(p.normalize(match.path));
      }
    });
  }

  final assetFilesCount = filePaths.length;

  // Add JSON and image filepaths
  filePaths.add(data.mod.jsonFilePath);
  if (data.mod.imageFilePath != null && data.mod.imageFilePath!.isNotEmpty) {
    filePaths.add(data.mod.imageFilePath!);
  }

  return (filePaths, assetFilesCount);
}

void _backupIsolate(BackupIsolateData data) async {
  try {
    final encoder = ZipFileEncoder();
    encoder.create(data.targetBackupFilePath);

    for (int i = 0; i < data.filePaths.length; i++) {
      final filePath = data.filePaths[i];
      final file = File(filePath);

      if (!await file.exists()) {
        continue;
      }

      try {
        final isInSavesPath = filePath.startsWith(p.normalize(data.savesPath));

        final relativePath = p.relative(
          filePath,
          from: isInSavesPath ? data.savesParentPath : data.modsParentPath,
        );

        await encoder.addFile(file, relativePath);

        data.sendPort.send(
          BackupProgressMessage(i + 1, data.filePaths.length),
        );
      } catch (e) {
        debugPrint('Error adding file $filePath: $e');
      }
    }

    await encoder.close();

    data.sendPort.send(BackupCompleteMessage(
      true,
      'Backup has been created at ${data.targetBackupFilePath}',
    ));
  } catch (e) {
    data.sendPort.send(BackupCompleteMessage(false, e.toString()));
  }
}
