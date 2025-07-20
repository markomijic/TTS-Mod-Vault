import 'dart:io' show Directory, FileSystemEntity, File;
import 'dart:isolate' show SendPort, ReceivePort, Isolate;

import 'package:archive/archive.dart' show Archive, ArchiveFile, ZipEncoder;
import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart' show FilePicker;
import 'package:flutter/material.dart' show debugPrint;
import 'package:hooks_riverpod/hooks_riverpod.dart' show Ref, StateNotifier;
import 'package:path/path.dart' as p
    show basenameWithoutExtension, join, normalize, relative;
import 'package:tts_mod_vault/src/state/backup/backup_state.dart'
    show BackupState, BackupStatusEnum;
import 'package:tts_mod_vault/src/state/backup/models/existing_backup_model.dart'
    show ExistingBackup;
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart'
    show AssetTypeEnum;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show Mod;
import 'package:tts_mod_vault/src/state/provider.dart'
    show directoriesProvider, existingBackupsProvider, modsProvider;
import 'package:tts_mod_vault/src/utils.dart'
    show
        getBackupFilenameByMod,
        getFileNameFromURL,
        newSteamUserContentUrl,
        oldCloudUrl;

class BackupNotifier extends StateNotifier<BackupState> {
  final Ref ref;

  BackupNotifier(this.ref) : super(const BackupState());

  // TODO review isolate function and remove old function
  Future<String> createBackup2(Mod mod, [String? backupAllDir]) async {
    state = state.copyWith(
      status: BackupStatusEnum.awaitingBackupFolder,
      currentCount: 0,
      totalCount: 0,
    );

    final backupsDir = ref.read(directoriesProvider).backupsDir;

    final backupDirPath = backupAllDir ??
        await FilePicker.platform.getDirectoryPath(
          lockParentWindow: true,
          initialDirectory: backupsDir.isEmpty ? null : backupsDir,
        );

    if (backupDirPath == null) {
      state = state.copyWith(status: BackupStatusEnum.idle);
      return "";
    }

    String returnValue =
        "Backup of ${mod.saveName} has been created in $backupDirPath";

    state = state.copyWith(status: BackupStatusEnum.backingUp);

    try {
      // Add filepaths of assets
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

            // Check if file exists under old url naming scheme
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

      final totalAssetCount = filePaths.length;

      // Add JSON and image filepaths
      filePaths.add(mod.jsonFilePath);
      if (mod.imageFilePath != null && mod.imageFilePath!.isNotEmpty) {
        filePaths.add(mod.imageFilePath!);
      }

      final archive = Archive();

      final modsDir = Directory(ref.read(directoriesProvider).modsDir);
      final savesDir = Directory(ref.read(directoriesProvider).savesDir);

      for (final filePath in filePaths) {
        final file = File(filePath);

        if (!await file.exists()) {
          debugPrint(
              'createBackup - ${mod.saveName} does not exist: $filePath');
          continue;
        }

        try {
          final fileData = await file.readAsBytes();

          final isInSavesPath = filePath.startsWith(p.normalize(savesDir.path));

          final relativePath = p.relative(
            filePath,
            from: isInSavesPath ? savesDir.parent.path : modsDir.parent.path,
          );
          final archiveFile =
              ArchiveFile(relativePath, fileData.length, fileData);

          state = state.copyWith(
            currentCount: filePaths.indexOf(filePath) + 1,
            totalCount: filePaths.length,
          );
          archive.addFile(archiveFile);
        } catch (e) {
          debugPrint('createBackup - error reading file $filePath: $e');
        }
      }

      if (archive.files.isEmpty) {
        throw Exception('No valid files to create a backup');
      }

      final backupFileName = getBackupFilenameByMod(mod);
      final file = File(p.join(backupDirPath, backupFileName));
      final zipData = ZipEncoder().encode(archive);

      await file.writeAsBytes(zipData);

      // Add new backup to state, update mod
      final newBackup = ExistingBackup(
        filename: backupFileName,
        filepath: p.join(backupDirPath, backupFileName),
        lastModifiedTimestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        totalAssetCount: totalAssetCount,
      );
      ref.read(existingBackupsProvider.notifier).addBackup(newBackup);
      ref.read(modsProvider.notifier).updateSelectedMod(mod);
    } catch (e) {
      debugPrint('createBackup - error: ${e.toString()}');
      returnValue = e.toString();
    } finally {
      state = state.copyWith(status: BackupStatusEnum.idle);
    }

    return returnValue;
  }

  // Modified createBackup method for the BackupNotifier class

  Future<String> createBackup(Mod mod, [String? backupAllDir]) async {
    state = state.copyWith(
      status: BackupStatusEnum.awaitingBackupFolder,
      currentCount: 0,
      totalCount: 0,
    );

    final backupsDir = ref.read(directoriesProvider).backupsDir;

    final backupDirPath = backupAllDir ??
        await FilePicker.platform.getDirectoryPath(
          lockParentWindow: true,
          initialDirectory: backupsDir.isEmpty ? null : backupsDir,
        );

    if (backupDirPath == null) {
      state = state.copyWith(status: BackupStatusEnum.idle);
      return "";
    }

    String returnValue =
        "Backup of ${mod.saveName} has been created in $backupDirPath";

    state = state.copyWith(status: BackupStatusEnum.backingUp);

    try {
      // Prepare file paths (same logic as original)
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

      final totalAssetCount = filePaths.length;

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
      await Isolate.spawn(_backupIsolateEntryPoint, isolateData);

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
              totalAssetCount: totalAssetCount,
            );
            ref.read(existingBackupsProvider.notifier).addBackup(newBackup);
            ref.read(modsProvider.notifier).updateSelectedMod(mod);
          } else {
            returnValue = message.message;
          }
          break;
        }
      }
    } catch (e) {
      debugPrint('createBackup - error: ${e.toString()}');
      returnValue = e.toString();
    } finally {
      state = state.copyWith(status: BackupStatusEnum.idle);
    }

    return returnValue;
  }
}

// Message types for isolate communication
abstract class BackupMessage {}

class BackupProgressMessage extends BackupMessage {
  final int current;
  final int total;

  BackupProgressMessage(this.current, this.total);
}

class BackupCompleteMessage extends BackupMessage {
  final bool success;
  final String message;

  BackupCompleteMessage(this.success, this.message);
}

// Data to send to isolate
class BackupIsolateData {
  final List<String> filePaths;
  final String targetBackupFilePath;
  final String modsParentPath;
  final String savesParentPath;
  final String savesPath;
  final SendPort sendPort;

  BackupIsolateData({
    required this.filePaths,
    required this.targetBackupFilePath,
    required this.modsParentPath,
    required this.savesParentPath,
    required this.savesPath,
    required this.sendPort,
  });
}

// The isolate entry point
void _backupIsolateEntryPoint(BackupIsolateData data) async {
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

    data.sendPort
        .send(BackupCompleteMessage(true, 'Backup created successfully'));
  } catch (e) {
    data.sendPort.send(BackupCompleteMessage(false, e.toString()));
  }
}
