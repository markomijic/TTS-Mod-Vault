import 'dart:io';

import 'package:archive/archive.dart' show ZipDecoder;
import 'package:flutter/material.dart' show debugPrint;
import 'package:hooks_riverpod/hooks_riverpod.dart' show Ref, StateNotifier;
import 'package:path/path.dart' as p
    show basename, basenameWithoutExtension, extension, join, normalize, split;
import 'package:tts_mod_vault/src/state/backup/import_backup_state.dart'
    show ImportBackupState;
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart'
    show AssetTypeEnum;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show ModTypeEnum;
import 'package:tts_mod_vault/src/state/provider.dart'
    show directoriesProvider, existingAssetListsProvider, modsProvider;

class ImportBackupNotifier extends StateNotifier<ImportBackupState> {
  final Ref ref;

  ImportBackupNotifier(this.ref) : super(const ImportBackupState());

  Future<void> importJson(
    String sourcePath,
    String destinationFolder,
    ModTypeEnum modType,
    String? pngSourcePath,
  ) async {
    try {
      state = state.copyWith(
        currentCount: 0,
        totalCount: 0,
      );

      // Get the filename from the source path
      final fileName = p.basename(sourcePath);

      // Copy the JSON file to the selected directory
      final targetPath = p.join(destinationFolder, fileName);
      await File(sourcePath).copy(targetPath);

      // Copy PNG if provided
      if (pngSourcePath != null && pngSourcePath.isNotEmpty) {
        try {
          final jsonBaseName = p.basenameWithoutExtension(targetPath);
          final pngTargetPath = p.join(destinationFolder, '$jsonBaseName.png');
          await File(pngSourcePath).copy(pngTargetPath);
        } catch (e) {
          debugPrint('PNG copy failed: $e');
          // PNG failure doesn't prevent JSON import from succeeding
        }
      }

      // Add the mod to the app state
      await ref.read(modsProvider.notifier).addSingleMod(targetPath, modType);
    } catch (e) {
      debugPrint('importJson error: $e');
    }
  }

  Future<Set<String>> importBackupFromPath(String filePath) async {
    ModTypeEnum? modType;
    try {
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

        // Return all extracted asset filenames for shared asset refresh
        return extractedAssets.values
            .expand((assets) => assets.keys)
            .toSet();
      }
    } catch (e) {
      debugPrint('importBackup error: $e');
    }

    return {};
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
