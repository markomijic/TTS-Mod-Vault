import 'dart:io';

import 'package:riverpod/riverpod.dart';
import 'package:tts_mod_vault/src/state/cleanup/cleanup_state.dart';
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart';
import 'package:tts_mod_vault/src/state/provider.dart';

class CleanupNotifier extends StateNotifier<CleanupState> {
  final Ref ref;

  CleanupNotifier(this.ref) : super(const CleanupState());

  Future<void> startCleanup(
    Function(int fileCount) onAwaitingConfirmation,
  ) async {
    try {
      state = CleanupState(
        status: CleanupStatus.scanning,
        errorMessage: null,
        filesToDelete: [],
      );

      final Set<String> referencedFiles = {};
      final mods = ref.read(modsProvider).mods;

      for (final mod in mods) {
        mod.getAllAssets().forEach(
          (e) {
            if (e.fileExists && e.filePath != null) {
              referencedFiles.add(e.filePath!);
            }
          },
        );
      }

      for (final asset in AssetType.values) {
        await _processDirectory(asset, referencedFiles);
      }

      state = state.copyWith(status: CleanupStatus.awaitingConfirmation);

      onAwaitingConfirmation(state.filesToDelete.length);
    } catch (e) {
      state = state.copyWith(
        status: CleanupStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> _processDirectory(
    AssetType type,
    Set<String> referencedFiles,
  ) async {
    final directory = Directory(_getDirectoryByType(type));
    if (!directory.existsSync()) return;

    final List<FileSystemEntity> files = directory.listSync(recursive: true);

    for (final file in files) {
      if (file is File) {
        final path = file.path;
        if (!referencedFiles.contains(path)) {
          state = state.copyWith(
            filesToDelete: [...state.filesToDelete, path],
          );
        }
      }
    }
  }

  Future<void> executeDelete() async {
    if (state.status != CleanupStatus.awaitingConfirmation) return;

    try {
      state = state.copyWith(status: CleanupStatus.deleting);

      for (final filePath in state.filesToDelete) {
        final file = File(filePath);
        if (file.existsSync()) {
          await file.delete();
        }
      }

      state = state.copyWith(
        status: CleanupStatus.completed,
        filesToDelete: [],
      );
    } catch (e) {
      state = state.copyWith(
        status: CleanupStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  void cancelCleanup() {
    state = const CleanupState();
  }

  String _getDirectoryByType(AssetType type) {
    switch (type) {
      case AssetType.assetBundle:
        return ref.read(directoriesProvider).assetBundlesDir;
      case AssetType.audio:
        return ref.read(directoriesProvider).audioDir;
      case AssetType.image:
        return ref.read(directoriesProvider).imagesDir;
      case AssetType.model:
        return ref.read(directoriesProvider).modelsDir;
      case AssetType.pdf:
        return ref.read(directoriesProvider).pdfDir;
    }
  }
}
