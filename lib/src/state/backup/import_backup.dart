import 'dart:io';

import 'package:archive/archive.dart' show ZipDecoder;
import 'package:file_picker/file_picker.dart'
    show FilePicker, FilePickerResult, FileType;
import 'package:flutter/material.dart' show debugPrint;
import 'package:hooks_riverpod/hooks_riverpod.dart' show Ref, StateNotifier;
import 'package:path/path.dart' as p
    show basenameWithoutExtension, extension, normalize, split;
import 'package:tts_mod_vault/src/state/backup/import_backup_state.dart'
    show ImportBackupState, ImportBackupStatusEnum;
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart'
    show AssetTypeEnum;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show ModTypeEnum;
import 'package:tts_mod_vault/src/state/provider.dart'
    show directoriesProvider, existingAssetListsProvider, modsProvider;

class ImportBackupNotifier extends StateNotifier<ImportBackupState> {
  final Ref ref;

  ImportBackupNotifier(this.ref) : super(const ImportBackupState());

  Future<void> importBackup() async {
    ModTypeEnum? modType;
    try {
      state = state.copyWith(
        status: ImportBackupStatusEnum.awaitingBackupFile,
        currentCount: 0,
        totalCount: 0,
      );

      final backupsDir = ref.read(directoriesProvider).backupsDir;

      FilePickerResult? result;
      try {
        result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          lockParentWindow: true,
          initialDirectory: backupsDir.isEmpty ? null : backupsDir,
          allowedExtensions: ['ttsmod'],
          allowMultiple: false,
        );
      } catch (e) {
        debugPrint("importBackup - file picker error: $e");
        return;
      }

      if (result == null || result.files.isEmpty) {
        state = state.copyWith(
          status: ImportBackupStatusEnum.idle,
        );
        return;
      }

      final filePath = result.files.single.path ?? '';
      if (filePath.isEmpty) {
        state = state.copyWith(
          status: ImportBackupStatusEnum.idle,
        );
        return;
      }

      state = state.copyWith(
        status: ImportBackupStatusEnum.importingBackup,
        importFileName: p.basenameWithoutExtension(result.files.single.name),
      );

      final bytes = await File(filePath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final modsDir = Directory(ref.read(directoriesProvider).modsDir);
      final savesDir = Directory(ref.read(directoriesProvider).savesDir);
      final savedObjectsDir =
          Directory(ref.read(directoriesProvider).savedObjectsDir);

      final Map<AssetTypeEnum, Map<String, String>> extractedAssets = {
        for (final type in AssetTypeEnum.values) type: {},
      };
      String? importedJsonFilePath;

      for (final file in archive) {
        if (file.isFile) {
          final filename = file.name;
          String targetDir = modsDir.parent.path;

          if (filename.startsWith('Saves')) {
            targetDir = savesDir.parent.path;
          }

          final data = file.content as List<int>;
          final outputFile = File('$targetDir/$filename');
          if (_isJsonFile(filename)) {
            importedJsonFilePath = outputFile.path;

            // Determine mod type based on the path
            if (outputFile.path.contains(savedObjectsDir.path)) {
              modType = ModTypeEnum.savedObject;
            } else if (outputFile.path.contains(savesDir.path)) {
              modType = ModTypeEnum.save;
            } else if (outputFile.path.contains(modsDir.path)) {
              modType = ModTypeEnum.mod;
            } else {
              // Default to mod if we can't determine
              modType = ModTypeEnum.mod;
            }
          } else {
            // Track asset files by their type based on directory
            final assetType = _getAssetTypeFromPath(file.name);
            if (assetType != null) {
              final assetFilename = p.basenameWithoutExtension(outputFile.path);
              extractedAssets[assetType]![assetFilename] = outputFile.path;
            }
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

      if (importedJsonFilePath != null && modType != null) {
        // Add only the newly extracted assets instead of rescanning all directories
        for (final entry in extractedAssets.entries) {
          final assetType = entry.key;
          final assets = entry.value;

          for (final asset in assets.entries) {
            ref.read(existingAssetListsProvider.notifier).addExistingAsset(
                  assetType,
                  asset.key,
                  asset.value,
                );
          }
        }

        await ref.read(modsProvider.notifier).addSingleMod(
              importedJsonFilePath,
              modType,
            );
      }
    } catch (e) {
      debugPrint('importBackup error: $e');
    }

    state = state.copyWith(
      status: ImportBackupStatusEnum.idle,
      importFileName: "",
    );
  }

  bool _isJsonFile(String inputPath) {
    final filePath = p.normalize(inputPath);

    final isJsonFile = p.extension(filePath).toLowerCase() == '.json';
    final containsWorkshop = p.split(filePath).contains('Workshop');

    return isJsonFile && containsWorkshop;
  }

  AssetTypeEnum? _getAssetTypeFromPath(String filePath) {
    final normalizedPath = p.normalize(filePath);
    final pathParts =
        p.split(normalizedPath).map((part) => part.toLowerCase()).toList();

    // Check if path contains any of the asset type directory names (case-insensitive)
    for (final assetType in AssetTypeEnum.values) {
      if (pathParts.contains(assetType.label.toLowerCase())) {
        return assetType;
      }
    }

    return null;
  }
}
