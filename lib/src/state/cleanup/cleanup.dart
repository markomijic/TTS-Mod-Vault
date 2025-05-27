import 'dart:io' show Directory, File, FileSystemEntity;

import 'package:flutter/material.dart' show debugPrint;
import 'package:hooks_riverpod/hooks_riverpod.dart' show Ref, StateNotifier;
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/src/state/cleanup/cleanup_state.dart'
    show CleanUpState, CleanUpStatusEnum;
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart'
    show AssetTypeEnum;
import 'package:tts_mod_vault/src/state/provider.dart'
    show directoriesProvider, modsProvider;
import 'package:tts_mod_vault/src/utils.dart';

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

      final mods = ref.read(modsProvider).value?.mods;

      if (mods == null || mods.isEmpty) {
        throw "No mods available, cancelling cleanup";
      }

      final Set<String> referencedFiles = {};
      for (final assetType in AssetTypeEnum.values) {
        referencedFiles.clear();
        for (final mod in mods) {
          mod.getAssetsByType(assetType).forEach(
            (e) {
              if (e.fileExists &&
                  e.filePath != null &&
                  e.filePath!.isNotEmpty) {
                referencedFiles.add(p.basenameWithoutExtension(e.filePath!));
              }
            },
          );
        }

        final directory = Directory(ref
            .read(directoriesProvider.notifier)
            .getDirectoryByType(assetType));
        if (await directory.exists()) {
          await _processDirectory(directory, referencedFiles);
        }

        if (assetType == AssetTypeEnum.image ||
            assetType == AssetTypeEnum.model) {
          final rawDirPath = ref
              .read(directoriesProvider.notifier)
              .getRawDirectoryByType(assetType);
          if (rawDirPath == null) continue;

          final directory = Directory(rawDirPath);
          if (!await directory.exists()) continue;

          await _processDirectory(directory, referencedFiles);
        }
      }
      referencedFiles.clear();
      state = state.copyWith(
          status: state.filesToDelete.isNotEmpty
              ? CleanUpStatusEnum.awaitingConfirmation
              : CleanUpStatusEnum.idle);

      onAwaitingConfirmation(state.filesToDelete.length);
    } catch (e) {
      state = state.copyWith(
        status: CleanUpStatusEnum.error,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> _processDirectory(
    Directory directory,
    Set<String> referencedFileNames,
  ) async {
    final List<FileSystemEntity> files = directory.listSync();

    for (final file in files) {
      if (file is File) {
        String fileName = p.basenameWithoutExtension(file.path);

        // Ignore rawt/rawm files that are not from URL download
        if (fileName.startsWith("file")) continue;

        // In case of old url naming scheme rename to new url to match existing assets lists
        if (fileName.startsWith(getFileNameFromURL(oldUrl))) {
          final originalFileName = fileName;

          fileName = fileName.replaceFirst(
              getFileNameFromURL(oldUrl), getFileNameFromURL(newUrl));

          // Check if old url file has a duplicate with new url file
          final newUrlFilepath =
              file.path.replaceFirst(originalFileName, fileName);
          if (await File(newUrlFilepath).exists()) {
            state = state.copyWith(
              filesToDelete: [...state.filesToDelete, file.path],
            );
            continue;
          }
        }

        if (!referencedFileNames.contains(fileName)) {
          state = state.copyWith(
            filesToDelete: [...state.filesToDelete, file.path],
          );
        }
      }
    }

    debugPrint(
        'Processed ${directory.path}, total files to delete is now: ${state.filesToDelete.length}');
  }

  Future<void> executeDelete() async {
    if (state.status != CleanUpStatusEnum.awaitingConfirmation) return;

    try {
      state = state.copyWith(status: CleanUpStatusEnum.deleting);

      for (final filePath in state.filesToDelete) {
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
        }
      }

      state = state.copyWith(
        status: CleanUpStatusEnum.completed,
        filesToDelete: [],
      );
    } catch (e) {
      state = state.copyWith(
        status: CleanUpStatusEnum.error,
        errorMessage: e.toString(),
      );
    }
  }

  void resetState() {
    state = const CleanUpState();
  }
}
