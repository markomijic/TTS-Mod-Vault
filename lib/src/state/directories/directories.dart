import 'dart:io' show Directory, Platform;
import 'package:flutter/material.dart' show debugPrint;
import 'package:hooks_riverpod/hooks_riverpod.dart' show Ref, StateNotifier;
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart'
    show AssetTypeEnum;
import 'package:tts_mod_vault/src/state/provider.dart' show storageProvider;

import 'directories_state.dart' show DirectoriesState;
import 'package:path/path.dart' as path;

class DirectoriesNotifier extends StateNotifier<DirectoriesState> {
  final Ref ref;

  DirectoriesNotifier(this.ref) : super(DirectoriesState.empty());

  void initializeDirectories() {
    debugPrint("initializeDirectories");

    final ttsDir =
        ref.read(storageProvider).getTtsDir() ?? _getDefaultTtsDirectory();
    state = DirectoriesState.fromTtsDir(ttsDir);
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

  Future<void> _saveNewTtsDirectory(String ttsDir) async {
    state = DirectoriesState.fromTtsDir(ttsDir);
    await ref.read(storageProvider).saveTtsDir(ttsDir);
  }

  Future<bool> isTtsDirectoryValid(String ttsDir) async {
    final mainDirectoryResult = await Directory(ttsDir).exists();

    if (!mainDirectoryResult) return false;

    final mainTtsDirectoriesResult = await Future.wait([
      'Mods',
      'Saves',
      'DLC',
      'Screenshots'
    ].map((folder) => Directory(path.join(ttsDir, folder)).exists()))
        .then((exists) => exists.every((e) => e));

    if (!mainTtsDirectoriesResult) return false;

    await _saveNewTtsDirectory(ttsDir);
    return true;
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
