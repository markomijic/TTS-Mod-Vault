import 'dart:io';
import 'package:riverpod/riverpod.dart';
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart'
    show AssetTypeEnum;

import 'directories_state.dart';
import 'package:path/path.dart' as path;

class DirectoriesNotifier extends StateNotifier<DirectoriesState> {
  DirectoriesNotifier() : super(_initializeState());

  static DirectoriesState _initializeState() {
    final ttsDir = _getDefaultTtsDirectory();
    return DirectoriesState.fromTtsDir(ttsDir);
  }

  static String _getDefaultTtsDirectory() {
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

  static String _getUserHome() {
    if (Platform.isWindows) {
      return Platform.environment['USERPROFILE'] ?? '';
    }
    return Platform.environment['HOME'] ?? '';
  }

  void updateTtsDirectory(String newTtsDir) {
    state = DirectoriesState.fromTtsDir(newTtsDir);
  }

  Future<bool> checkIfTtsDirectoryExists() async {
    try {
      return Directory(state.ttsDir).exists();
    } catch (e) {
      return false;
    }
  }

  Future<bool> checkIfTtsDirectoryFoldersExist(String ttsDir) {
    final requiredFolders = ['Mods', 'Saves', 'DLC', 'Screenshots'];

    return Future.wait(requiredFolders
            .map((folder) => Directory(path.join(ttsDir, folder)).exists()))
        .then((exists) => exists.every((e) => e));
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
}
