import 'dart:io';

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart'
    show FilePicker, FilePickerResult, FileType;
import 'package:flutter/material.dart' show debugPrint;
import 'package:archive/archive.dart'
    show Archive, ArchiveFile, ZipDecoder, ZipEncoder;
import 'package:path/path.dart' as p
    show basenameWithoutExtension, extension, join, normalize, relative, split;
import 'package:hooks_riverpod/hooks_riverpod.dart' show Ref, StateNotifier;
import 'package:tts_mod_vault/src/state/backup/backup_state.dart'
    show BackupState;
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

  Future<bool> importBackup() async {
    try {
      state = state.copyWith(
        importInProgress: true,
        lastImportedJsonFileName: "",
        currentCount: 0,
        totalCount: 0,
      );

      FilePickerResult? result;
      try {
        result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['ttsmod'],
          allowMultiple: false,
        );
      } catch (e) {
        debugPrint("importBackup - file picker error: $e");
        return false;
      }

      if (result == null || result.files.isEmpty) {
        state = state.copyWith(importInProgress: false);
        return false;
      }

      final filePath = result.files.single.path!;
      if (filePath.isEmpty) {
        state = state.copyWith(importInProgress: false);
        return false;
      }

      state = state.copyWith(
          importFileName: p.basenameWithoutExtension(result.files.single.name));

      final bytes = await File(filePath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final modsDir = Directory(ref.read(directoriesProvider).modsDir);
      final savesDir = Directory(ref.read(directoriesProvider).savesDir);

      for (final file in archive) {
        if (file.isFile) {
          final filename = file.name;
          String targetDir = modsDir.parent.path;

          if (filename.startsWith('Mods')) {
            targetDir = modsDir.parent.path;
          } else if (filename.startsWith('Saves')) {
            targetDir = savesDir.parent.path;
          }

          final data = file.content as List<int>;
          final outputFile = File('$targetDir/$filename');

          if (isJsonFile(filename)) {
            state = state.copyWith(
                lastImportedJsonFileName: p.basenameWithoutExtension(filename));
          }

          try {
            state = state.copyWith(
                currentCount: archive.files.indexOf(file) + 1,
                totalCount: archive.files.length);
            await outputFile.create(recursive: true);
            await outputFile.writeAsBytes(data);
          } catch (e) {
            debugPrint(
                'importBackup failed for $filename because of error: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('importBackup error: $e');
      state = state.copyWith(importInProgress: false, importFileName: "");
      return false;
    }

    state = state.copyWith(importInProgress: false, importFileName: "");
    return true;
  }

  void resetLastImportedJsonFileName() {
    state = state.copyWith(lastImportedJsonFileName: "");
  }

  bool isJsonFile(String inputPath) {
    final filePath = p.normalize(inputPath);

    final isJsonFile = p.extension(filePath).toLowerCase() == '.json';
    final containsWorkshop = p.split(filePath).contains('Workshop');

    return isJsonFile && containsWorkshop;
  }

  Future<String> createBackup(Mod mod) async {
    state = state.copyWith(
      backupInProgress: true,
      currentCount: 0,
      totalCount: 0,
    );

    final saveDirectoryPath = await FilePicker.platform.getDirectoryPath(
      lockParentWindow: true,
    );

    if (saveDirectoryPath == null) {
      state = state.copyWith(backupInProgress: false);
      return "";
    }

    String returnValue =
        "Backup of ${mod.saveName} has been created in $saveDirectoryPath";

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
      final file = File(p.join(saveDirectoryPath, backupFileName));
      final zipData = ZipEncoder().encode(archive);

      await file.writeAsBytes(zipData);

      // Add new backup to state, update mod
      final newBackup = ExistingBackup(
        filename: backupFileName,
        filepath: p.join(saveDirectoryPath, backupFileName),
        lastModifiedTimestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );
      ref.read(existingBackupsProvider.notifier).addBackup(newBackup);
      ref.read(modsProvider.notifier).updateSelectedMod(mod);
    } catch (e) {
      debugPrint('createBackup - error: ${e.toString()}');
      returnValue = e.toString();
    } finally {
      state = state.copyWith(backupInProgress: false);
    }

    return returnValue;
  }
}
