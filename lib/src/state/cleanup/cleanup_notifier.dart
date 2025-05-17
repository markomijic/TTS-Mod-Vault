import 'dart:io' show Directory, File, FileSystemEntity;

import 'package:hooks_riverpod/hooks_riverpod.dart' show Ref, StateNotifier;
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/src/state/cleanup/cleanup_state.dart'
    show CleanUpState, CleanUpStatusEnum;
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart'
    show AssetType;
import 'package:tts_mod_vault/src/state/provider.dart'
    show directoriesProvider, modsProvider;

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

      final Set<String> referencedFiles = {};
      final mods = ref.read(modsProvider).value!.mods;

      for (final mod in mods) {
        mod.getAllAssets().forEach(
          (e) {
            if (e.fileExists && e.filePath != null && e.filePath!.isNotEmpty) {
              referencedFiles.add(p.basenameWithoutExtension(e.filePath!));
            }
          },
        );
      }

      for (final asset in AssetType.values) {
        await _processDirectory(asset, referencedFiles);
      }

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
    AssetType type,
    Set<String> referencedFilesUris,
  ) async {
    final directory = Directory(_getDirectoryByType(type));
    if (!directory.existsSync()) return;

    final List<FileSystemEntity> files = directory.listSync(recursive: true);

    for (final file in files) {
      if (file is File) {
        final filePath = p.basenameWithoutExtension(file.path);

        if (!referencedFilesUris.contains(filePath)) {
          state = state.copyWith(
            filesToDelete: [...state.filesToDelete, file.path],
          );
        }
      }
    }
  }

  Future<void> executeDelete() async {
    if (state.status != CleanUpStatusEnum.awaitingConfirmation) return;

    try {
      state = state.copyWith(status: CleanUpStatusEnum.deleting);

      for (final filePath in state.filesToDelete) {
        final file = File(filePath);
        if (file.existsSync()) {
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
