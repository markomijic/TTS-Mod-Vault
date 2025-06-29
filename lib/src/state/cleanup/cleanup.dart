import 'dart:io' show Directory, File, FileSystemEntity;
import 'dart:isolate' show Isolate;

import 'package:flutter/material.dart' show debugPrint;
import 'package:hooks_riverpod/hooks_riverpod.dart' show Ref, StateNotifier;
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/src/state/cleanup/cleanup_state.dart'
    show CleanUpState, CleanUpStatusEnum;
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart'
    show AssetTypeEnum;
import 'package:tts_mod_vault/src/state/provider.dart'
    show directoriesProvider, modsProvider, storageProvider;
import 'package:tts_mod_vault/src/utils.dart'
    show getFileNameFromURL, newSteamUserContentUrl, oldCloudUrl;

class CleanupNotifier extends StateNotifier<CleanUpState> {
  final Ref ref;

  CleanupNotifier(this.ref) : super(const CleanUpState());

  Future<void> startCleanup(
    Function(int fileCount) onAwaitingConfirmation,
  ) async {
    try {
      state = CleanUpState(
        status: CleanUpStatusEnum.scanning,
        errorMessage: null,
        filesToDelete: [],
      );

      final allMods = ref.read(modsProvider.notifier).getAllMods();

      if (allMods.isEmpty) {
        throw "no mods available, cancelling cleanup";
      }

      final allJsonFileNames = await Isolate.run(
          () => allMods.map((mod) => mod.jsonFileName).toList());

      final bulkUrls =
          ref.read(storageProvider).getModUrlsBulk(allJsonFileNames);

      final referencedFiles = await Isolate.run(
        () {
          final Set<String> files = {};

          for (final mod in allMods) {
            final urls = bulkUrls[mod.jsonFileName];
            if (urls == null) continue;

            for (final url in urls.entries) {
              files.add(getFileNameFromURL(url.key));
            }
          }

          return files;
        },
      );

      // Process each asset type in parallel
      final List<Future<List<String>>> futures = [];

      for (final assetType in AssetTypeEnum.values) {
        // Get directory paths before isolate calls
        final mainDirPath = ref
            .read(directoriesProvider.notifier)
            .getDirectoryByType(assetType);

        final rawDirPath = (assetType == AssetTypeEnum.image ||
                assetType == AssetTypeEnum.model)
            ? ref
                .read(directoriesProvider.notifier)
                .getRawDirectoryByType(assetType)
            : null;

        final List<DirectoryProcessData> directoriesToProcess = [];

        if (await Directory(mainDirPath).exists()) {
          directoriesToProcess.add(DirectoryProcessData(
            directoryPath: mainDirPath,
            referencedFileNames: referencedFiles,
            assetType: assetType,
          ));
        }

        if (rawDirPath != null && await Directory(rawDirPath).exists()) {
          directoriesToProcess.add(DirectoryProcessData(
            directoryPath: rawDirPath,
            referencedFileNames: referencedFiles,
            assetType: assetType,
          ));
        }

        for (final processData in directoriesToProcess) {
          futures
              .add(Isolate.run(() => processDirectoryInIsolate(processData)));
        }
      }

      final List<List<String>> allResults = await Future.wait(futures);

      final List<String> allFilesToDelete = [];
      for (final result in allResults) {
        allFilesToDelete.addAll(result);
      }

      state = state.copyWith(
        filesToDelete: allFilesToDelete,
        status: allFilesToDelete.isNotEmpty
            ? CleanUpStatusEnum.awaitingConfirmation
            : CleanUpStatusEnum.idle,
      );

      onAwaitingConfirmation(state.filesToDelete.length);
    } catch (e) {
      state = state.copyWith(
        status: CleanUpStatusEnum.error,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> executeDelete() async {
    if (state.status != CleanUpStatusEnum.awaitingConfirmation) return;

    try {
      state = state.copyWith(status: CleanUpStatusEnum.deleting);

      final List<String> filePaths = List<String>.from(state.filesToDelete);
      await Isolate.run(() => _deleteFiles(filePaths));

      state = state.copyWith(status: CleanUpStatusEnum.completed);
    } catch (e) {
      state = state.copyWith(
        status: CleanUpStatusEnum.error,
        errorMessage: e.toString(),
      );
    } finally {
      state = state.copyWith(filesToDelete: []);
    }
  }

  static Future<void> _deleteFiles(List<String> filePaths) async {
    for (final filePath in filePaths) {
      try {
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        continue;
      }
    }
  }

  void resetState() {
    state = const CleanUpState();
  }
}

class DirectoryProcessData {
  final String directoryPath;
  final Set<String> referencedFileNames;
  final AssetTypeEnum assetType;

  DirectoryProcessData({
    required this.directoryPath,
    required this.referencedFileNames,
    required this.assetType,
  });
}

// Top-level function for isolate processing
Future<List<String>> processDirectoryInIsolate(
    DirectoryProcessData data) async {
  final List<String> filesToDelete = [];

  try {
    final directory = Directory(data.directoryPath);
    final List<FileSystemEntity> files = directory.listSync();

    for (final file in files) {
      if (file is File) {
        String fileName = p.basenameWithoutExtension(file.path);

        // Ignore rawt/rawm files that are not from URL download
        if (fileName.startsWith("file")) continue;

        // In case of old url naming scheme rename to new url to match existing assets lists
        if (fileName.startsWith(getFileNameFromURL(oldCloudUrl))) {
          final originalFileName = fileName;

          fileName = fileName.replaceFirst(getFileNameFromURL(oldCloudUrl),
              getFileNameFromURL(newSteamUserContentUrl));

          // Check if old url file has a duplicate with new url file
          final newUrlFilepath =
              file.path.replaceFirst(originalFileName, fileName);
          if (await File(newUrlFilepath).exists()) {
            filesToDelete.add(file.path);
            continue;
          }
        }

        if (!data.referencedFileNames.contains(fileName)) {
          filesToDelete.add(file.path);
        }
      }
    }
  } catch (e) {
    // Log error but continue processing other directories
    debugPrint('Error processing directory ${data.directoryPath}: $e');
  }

  return filesToDelete;
}
