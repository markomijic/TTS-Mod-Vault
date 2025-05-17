import 'dart:io';

import 'package:file_picker/file_picker.dart' show FilePicker, FileType;
import 'package:flutter/material.dart' show debugPrint;
import 'package:archive/archive.dart'
    show Archive, ArchiveFile, ZipDecoder, ZipEncoder;
import 'package:path/path.dart' as p show join, relative;
import 'package:riverpod/riverpod.dart' show Ref, StateNotifier;
import 'package:tts_mod_vault/src/state/backup/backup_state.dart'
    show BackupState;
import 'package:tts_mod_vault/src/state/provider.dart'
    show directoriesProvider, selectedModProvider;
import 'package:tts_mod_vault/src/utils.dart' show sanitizeFileName;

class BackupNotifier extends StateNotifier<BackupState> {
  final Ref ref;

  BackupNotifier(this.ref) : super(const BackupState());

  Future<bool> importBackup() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['ttsmod'],
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) {
        return false;
      }

      final filePath = result.files.single.path!;
      if (filePath.isEmpty) {
        return false;
      }

      state = state.copyWith(importInProgress: true);

      final bytes = await File(filePath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final targetDir = ref.read(directoriesProvider).ttsDir;

      for (final file in archive) {
        if (file.isFile) {
          final filename = file.name;
          final data = file.content as List<int>;
          final outputFile = File('$targetDir/$filename');

          try {
            await outputFile.writeAsBytes(data);
          } catch (e) {
            debugPrint(
                'importBackup failed for $filename because of error: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('importBackup error: $e');
      state = state.copyWith(importInProgress: false);
      return false;
    }

    state = state.copyWith(importInProgress: false);
    return true;
  }

  Future<String> createBackup() async {
    final mod = ref.read(selectedModProvider);
    if (mod == null) {
      return 'Select a mod to create a backup';
    }

    final saveDirectoryPath = await FilePicker.platform.getDirectoryPath();
    if (saveDirectoryPath == null) {
      return "";
    }

    final allModAssets = mod.getAllAssets();
    String returnValue =
        "Backup of ${mod.name} has been created in $saveDirectoryPath";

    try {
      state = state.copyWith(backupInprogress: true);

      final filePaths = <String>[];

      // Add filepaths of assets
      for (final asset in allModAssets) {
        if (asset.fileExists &&
            asset.filePath != null &&
            asset.filePath!.isNotEmpty) {
          filePaths.add(asset.filePath!);
        }
      }

      // Add JSON and image filepaths
      filePaths.add(mod.directory);
      if (mod.imageFilePath != null && mod.imageFilePath!.isNotEmpty) {
        filePaths.add(mod.imageFilePath!);
      }

      final archive = Archive();

      for (final filePath in filePaths) {
        final file = File(filePath);

        if (!await file.exists()) {
          debugPrint('createBackup - file does not exist: $filePath');
          continue;
        }

        try {
          final fileData = await file.readAsBytes();
          final relativePath =
              p.relative(filePath, from: ref.read(directoriesProvider).ttsDir);
          final archiveFile =
              ArchiveFile(relativePath, fileData.length, fileData);

          archive.addFile(archiveFile);
        } catch (e) {
          debugPrint('createBackup - error reading file $filePath: $e');
        }
      }

      if (archive.files.isEmpty) {
        throw Exception('No valid files to create a backup');
      }

      final backupFileName =
          sanitizeFileName("${mod.name}(${mod.fileName}).ttsmod");
      final file = File(p.join(saveDirectoryPath, backupFileName));
      final zipData = ZipEncoder().encode(archive);

      await file.writeAsBytes(zipData);
    } catch (e) {
      debugPrint('createBackup - error: ${e.toString()}');
      returnValue = e.toString();
    } finally {
      state = state.copyWith(backupInprogress: false);
    }

    return returnValue;
  }
}
