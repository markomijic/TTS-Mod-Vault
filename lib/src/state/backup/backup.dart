import 'dart:io' show Directory, FileSystemEntity, File;
import 'dart:isolate' show ReceivePort, Isolate;

import 'package:archive/archive.dart' show Archive, ArchiveFile, ZipEncoder;
import 'package:collection/collection.dart' show IterableExtension;
import 'package:file_picker/file_picker.dart' show FilePicker;
import 'package:flutter/material.dart' show debugPrint;
import 'package:hooks_riverpod/hooks_riverpod.dart' show Ref, StateNotifier;
import 'package:path/path.dart' as p
    show basenameWithoutExtension, join, normalize, relative;
import 'package:tts_mod_vault/src/state/backup/backup_state.dart'
    show
        BackupState,
        BackupStatusEnum,
        BackupIsolateData,
        BackupProgressMessage,
        BackupCompleteMessage;
import 'package:tts_mod_vault/src/state/backup/models/existing_backup_model.dart'
    show ExistingBackup;
import 'package:tts_mod_vault/src/state/bulk_actions/bulk_actions_state.dart'
    show BulkActionsStatusEnum;
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart'
    show AssetTypeEnum;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show Mod;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        directoriesProvider,
        existingBackupsProvider,
        modsProvider,
        bulkActionsProvider;
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
      status: BackupStatusEnum.awaitingBackupFolder,
      currentCount: 0,
      totalCount: 0,
      message: "",
    );

    final backupsDir = ref.read(directoriesProvider).backupsDir;

    final backupDirPath = backupDirectory ??
        await FilePicker.platform.getDirectoryPath(
          lockParentWindow: true,
          initialDirectory: backupsDir.isEmpty ? null : backupsDir,
        );

    if (backupDirPath == null) {
      state = state.copyWith(status: BackupStatusEnum.idle);
      return;
    }

    state = state.copyWith(status: BackupStatusEnum.backingUp);

    try {
      // Prepare file paths
      final filePaths = <String>[];

      for (final type in AssetTypeEnum.values) {
        final directory = Directory(
            ref.read(directoriesProvider.notifier).getDirectoryByType(type));
        if (!await directory.exists()) continue;

        final List<FileSystemEntity> files = directory.listSync();

        mod.getAssetsByType(type).forEach((asset) {
          final assetFile = files.firstWhereOrNull((file) {
            if (asset.filePath == null) return false;

            final name = p.basenameWithoutExtension(file.path);
            final newUrlBase = p.basenameWithoutExtension(asset.filePath!);

            final oldUrlBase = newUrlBase.replaceFirst(
              getFileNameFromURL(newSteamUserContentUrl),
              getFileNameFromURL(oldCloudUrl),
            );

            return name.startsWith(newUrlBase) || name.startsWith(oldUrlBase);
          });

          if (assetFile != null && assetFile.path.isNotEmpty) {
            filePaths.add(p.normalize(assetFile.path));
          }
        });
      }

      // Add JSON and image filepaths
      filePaths.add(mod.jsonFilePath);
      if (mod.imageFilePath != null && mod.imageFilePath!.isNotEmpty) {
        filePaths.add(mod.imageFilePath!);
      }

      // Set up isolate communication
      final receivePort = ReceivePort();
      final backupFileName = getBackupFilenameByMod(mod);
      final targetBackupFilePath = p.join(backupDirPath, backupFileName);

      final modsDir = Directory(ref.read(directoriesProvider).modsDir);
      final savesDir = Directory(ref.read(directoriesProvider).savesDir);

      final isolateData = BackupIsolateData(
        filePaths: filePaths,
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
            // Add new backup to state, update mod
            final newBackup = ExistingBackup(
              filename: backupFileName,
              filepath: targetBackupFilePath,
              lastModifiedTimestamp:
                  DateTime.now().millisecondsSinceEpoch ~/ 1000,
            );
            ref.read(existingBackupsProvider.notifier).addBackup(newBackup);
            ref.read(modsProvider.notifier).updateSelectedMod(mod);
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

void _backupIsolate(BackupIsolateData data) async {
  try {
    final archive = Archive();

    for (int i = 0; i < data.filePaths.length; i++) {
      final filePath = data.filePaths[i];
      final file = File(filePath);

      if (!await file.exists()) {
        // Skip missing files but continue
        continue;
      }

      try {
        final fileData = await file.readAsBytes();

        final isInSavesPath = filePath.startsWith(p.normalize(data.savesPath));

        final relativePath = p.relative(
          filePath,
          from: isInSavesPath ? data.savesParentPath : data.modsParentPath,
        );

        final archiveFile =
            ArchiveFile(relativePath, fileData.length, fileData);
        archive.addFile(archiveFile);

        // Send progress update
        data.sendPort.send(BackupProgressMessage(i + 1, data.filePaths.length));
      } catch (e) {
        // Log error but continue with other files
        debugPrint('Error reading file $filePath: $e');
      }
    }

    if (archive.files.isEmpty) {
      data.sendPort.send(
          BackupCompleteMessage(false, 'No valid files to create a backup'));
      return;
    }

    // Encode and write the archive
    final zipData = ZipEncoder().encode(archive);
    final backupFile = File(data.targetBackupFilePath);
    await backupFile.writeAsBytes(zipData);

    data.sendPort.send(BackupCompleteMessage(
        true, 'Backup has been created at ${data.targetBackupFilePath}'));
  } catch (e) {
    data.sendPort.send(BackupCompleteMessage(false, e.toString()));
  }
}
