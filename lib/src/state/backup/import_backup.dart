import 'dart:convert' show utf8;
import 'dart:io';

import 'package:archive/archive.dart' show ZipDecoder;
import 'package:collection/collection.dart' show IterableExtension;
import 'package:flutter/material.dart' show debugPrint;
import 'package:hooks_riverpod/hooks_riverpod.dart' show Ref, StateNotifier;
import 'package:path/path.dart' as p
    show
        basename,
        basenameWithoutExtension,
        dirname,
        equals,
        extension,
        join,
        normalize,
        split;
import 'package:tts_mod_vault/src/state/backup/import_backup_state.dart'
    show ImportBackupState;
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart'
    show AssetTypeEnum;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show ModTypeEnum;
import 'package:tts_mod_vault/src/state/mods/mods_isolates.dart'
    show extractDateTimeStampFromString;
import 'package:tts_mod_vault/src/state/provider.dart'
    show directoriesProvider, existingAssetListsProvider, modsProvider;

/// The user's choice when an imported backup's JSON is older than the local
/// (already imported) JSON file.
enum JsonConflictChoice { keepCurrent, useBackup, cancel }

/// Info shown to the user when deciding which JSON file to keep on import.
class JsonImportConflict {
  final String jsonFileName;
  final String? localDateTimeStamp;
  final String? backupDateTimeStamp;
  final int existingAssetCount;
  final int backupAssetCount;
  final String targetPath;

  const JsonImportConflict({
    required this.jsonFileName,
    required this.localDateTimeStamp,
    required this.backupDateTimeStamp,
    required this.existingAssetCount,
    required this.backupAssetCount,
    required this.targetPath,
  });
}

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

  Future<Set<String>> importBackupFromPath(
    String filePath, {
    Future<JsonConflictChoice> Function(JsonImportConflict conflict)?
        onJsonConflict,
    String? targetJsonDir,
  }) async {
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

      String targetDirFor(String filename) => filename.startsWith('Saves')
          ? savesDir.parent.path
          : modsDir.parent.path;

      // Pre-pass: locate the JSON entry, capture its zip-relative location, and
      // extract the backup JSON's internal save date so we can detect a
      // conflict before writing anything.
      String? jsonEntryName; // zip-relative path of the JSON entry
      String? jsonEntryDir; // zip-relative dir of the JSON (and its image)
      String? backupDateTimeStamp;
      int backupAssetCount = 0;
      for (final file in archive) {
        if (!file.isFile) continue;
        if (_isJsonFile(file.name)) {
          jsonEntryName = file.name;
          jsonEntryDir = p.dirname(file.name);

          try {
            backupDateTimeStamp = extractDateTimeStampFromString(
                utf8.decode(file.content as List<int>, allowMalformed: true));
          } catch (e) {
            debugPrint('importBackup failed to read backup JSON date: $e');
          }
        } else if (_getAssetTypeFromPath(file.name) != null) {
          backupAssetCount++;
        }
      }

      // Determine where the JSON should be restored. An explicit [targetJsonDir]
      // (right-click import) wins. Otherwise (sidebar bulk import) try to match
      // the backup's JSON filename to a single existing mod and restore into its
      // CURRENT folder, so a mod moved into a subfolder isn't duplicated into the
      // stale path stored in the backup. Falls back to the backup's stored path
      // when there is no match or the match is ambiguous.
      String? effectiveTargetDir = targetJsonDir;
      if (effectiveTargetDir == null && jsonEntryName != null) {
        final jsonBase = p.basename(jsonEntryName).toLowerCase();
        final matches = ref
            .read(modsProvider.notifier)
            .getAllMods()
            .where((m) => p.basename(m.jsonFilePath).toLowerCase() == jsonBase)
            .toList();
        if (matches.length == 1) {
          effectiveTargetDir = p.dirname(matches.first.jsonFilePath);
        }
      }

      String? jsonTargetPath;
      if (jsonEntryName != null) {
        jsonTargetPath = effectiveTargetDir != null
            ? p.join(effectiveTargetDir, p.basename(jsonEntryName))
            : File('${targetDirFor(jsonEntryName)}/$jsonEntryName').path;

        // Determine mod type based on the final destination path
        if (jsonTargetPath.contains(savedObjectsDir.path)) {
          modType = ModTypeEnum.savedObject;
        } else if (jsonTargetPath.contains(savesDir.path)) {
          modType = ModTypeEnum.save;
        } else {
          // Default to mod if we can't determine
          modType = ModTypeEnum.mod;
        }
      }

      // Detect conflict: local JSON already exists and is strictly newer than
      // the backup's JSON. Ask the caller which file to keep.
      bool skipJsonWrite = false;
      if (jsonTargetPath != null &&
          backupDateTimeStamp != null &&
          onJsonConflict != null &&
          File(jsonTargetPath).existsSync()) {
        String? localDateTimeStamp;
        try {
          localDateTimeStamp = extractDateTimeStampFromString(
              await File(jsonTargetPath).readAsString());
        } catch (e) {
          debugPrint('importBackup failed to read local JSON date: $e');
        }

        if (localDateTimeStamp != null &&
            int.tryParse(localDateTimeStamp) != null &&
            int.tryParse(backupDateTimeStamp) != null &&
            int.parse(localDateTimeStamp) > int.parse(backupDateTimeStamp)) {
          final normalizedTarget = p.normalize(jsonTargetPath);
          final existingMod = ref
              .read(modsProvider.notifier)
              .getAllMods()
              .where((m) => p.normalize(m.jsonFilePath) == normalizedTarget)
              .firstOrNull;

          final choice = await onJsonConflict(JsonImportConflict(
            jsonFileName: p.basename(jsonTargetPath),
            localDateTimeStamp: localDateTimeStamp,
            backupDateTimeStamp: backupDateTimeStamp,
            existingAssetCount: existingMod?.existingAssetCount ?? 0,
            backupAssetCount: backupAssetCount,
            targetPath: jsonTargetPath,
          ));

          switch (choice) {
            case JsonConflictChoice.cancel:
              return {};
            case JsonConflictChoice.keepCurrent:
              skipJsonWrite = true;
              break;
            case JsonConflictChoice.useBackup:
              break;
          }
        }
      }

      for (final file in archive) {
        if (file.isFile) {
          final filename = file.name;

          final data = file.content as List<int>;

          // Redirect the JSON and its sibling image (entries sharing the JSON's
          // zip directory) into the target mod's current folder when known.
          final redirectToTargetDir = effectiveTargetDir != null &&
              jsonEntryDir != null &&
              p.equals(p.dirname(filename), jsonEntryDir);
          final outputFile = redirectToTargetDir
              ? File(p.join(effectiveTargetDir, p.basename(filename)))
              : File('${targetDirFor(filename)}/$filename');
          final isJson = _isJsonFile(filename);
          if (isJson) {
            importedJsonFilePath = outputFile.path;
          } else {
            // Track asset files by their type based on directory
            final assetType = _getAssetTypeFromPath(file.name);
            if (assetType != null) {
              final assetFilename = p.basenameWithoutExtension(outputFile.path);
              extractedAssets[assetType]![assetFilename] = outputFile.path;
            }
          }

          // Keep the user's newer local JSON: skip only the JSON write but
          // still restore the backup's asset files.
          if (isJson && skipJsonWrite) {
            state = state.copyWith(
                currentCount: archive.files.indexOf(file) + 1,
                totalCount: archive.files.length);
            continue;
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
        return extractedAssets.values.expand((assets) => assets.keys).toSet();
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
