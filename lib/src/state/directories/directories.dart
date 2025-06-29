import 'dart:io' show Directory, Platform;
import 'package:flutter/material.dart' show debugPrint;
import 'package:hooks_riverpod/hooks_riverpod.dart' show Ref, StateNotifier;
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart'
    show AssetTypeEnum;
import 'package:tts_mod_vault/src/state/provider.dart' show storageProvider;

import 'directories_state.dart'
    show DirectoriesState, DirectoriesStateExtensions;
import 'package:path/path.dart' as path;

class DirectoriesNotifier extends StateNotifier<DirectoriesState> {
  final Ref ref;

  DirectoriesNotifier(this.ref) : super(DirectoriesState.empty());

  void initializeDirectories() {
    debugPrint("initializeDirectories");

    final modsDir = ref.read(storageProvider).getModsDir() ??
        path.joinAll([_getDefaultTtsDirectory(), 'Mods']);
    final savesDir = ref.read(storageProvider).getSavesDir() ??
        path.joinAll([_getDefaultTtsDirectory(), 'Saves']);
    state = DirectoriesState.fromDirs(modsDir, savesDir);
  }

  String _getDefaultTtsDirectory() {
    debugPrint("_getDefaultTtsDirectory");

    final String userHome = _getUserHome();

    if (Platform.isWindows) {
      return path
          .joinAll([userHome, 'Documents', 'My Games', 'Tabletop Simulator']);
    }

    if (Platform.isMacOS) {
      return path.joinAll([userHome, 'Library', 'Tabletop Simulator']);
    }

    final String snapDir = path.joinAll([
      userHome,
      'snap',
      'steam',
      'common',
      '.local',
      'share',
      'Tabletop Simulator',
    ]);

    if (Directory(snapDir).existsSync()) {
      return snapDir;
    }

    return path.joinAll([userHome, '.local', 'share', 'Tabletop Simulator']);
  }

  String _getUserHome() {
    if (Platform.isWindows) {
      return Platform.environment['USERPROFILE'] ?? '';
    }
    return Platform.environment['HOME'] ?? '';
  }

  Future<void> saveDirectories() async {
    debugPrint('saveDirectories');
    await ref.read(storageProvider).saveModsDir(state.modsDir);
    await ref.read(storageProvider).saveSavesDir(state.savesDir);
  }

  Future<bool> isModsDirectoryValid(
    String initialDir, [
    updateState = true,
  ]) async {
    final directory = Directory(initialDir);

    final doesDirectoryExist = await directory.exists();

    if (!doesDirectoryExist) return false;

    bool result = false;

    if (directory.path.endsWith('Mods')) {
      result = true;
      if (updateState) {
        state = state.updateMods(initialDir);
      }
    } else {
      result = await Directory(path.join(initialDir, 'Mods')).exists();
      if (result && updateState) {
        state = state.updateMods(path.joinAll([initialDir, 'Mods']));
      }
    }

    return result;
  }

  Future<bool> isSavesDirectoryValid(
    String initialDir, [
    updateState = true,
  ]) async {
    final directory = Directory(initialDir);

    final doesDirectoryExist = await directory.exists();

    if (!doesDirectoryExist) return false;

    bool result = false;

    if (directory.path.endsWith('Saves')) {
      result = true;
      if (updateState) {
        state = state.updateSaves(initialDir);
      }
    } else {
      result = await Directory(path.join(initialDir, 'Saves')).exists();
      if (result && updateState) {
        state = state.updateSaves(path.joinAll([initialDir, 'Saves']));
      }
    }

    return result;
  }

  String getDirectoryByType(AssetTypeEnum type) {
    switch (type) {
      case AssetTypeEnum.assetBundle:
        return state.assetBundlesDir;
      case AssetTypeEnum.audio:
        return state.audioDir;
      case AssetTypeEnum.image:
        return state.imagesDir;
      case AssetTypeEnum.model:
        return state.modelsDir;
      case AssetTypeEnum.pdf:
        return state.pdfDir;
    }
  }

  String? getRawDirectoryByType(AssetTypeEnum type) {
    switch (type) {
      case AssetTypeEnum.image:
        return state.imagesRawDir;
      case AssetTypeEnum.model:
        return state.modelsRawDir;
      default:
        return null;
    }
  }
}
