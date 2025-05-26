import 'dart:io' show Directory, File;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart' show debugPrint;
import 'package:hooks_riverpod/hooks_riverpod.dart' show Ref, StateNotifier;
import 'package:tts_mod_vault/src/state/asset/asset_type_lists.dart'
    show ExistingAssetsLists;
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart'
    show AssetTypeEnum;
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/src/state/provider.dart' show directoriesProvider;
import 'package:tts_mod_vault/src/utils.dart'
    show getFileNameFromURL, newUrl, oldUrl;

class ExistingAssetsNotifier extends StateNotifier<ExistingAssetsLists> {
  final Ref ref;

  ExistingAssetsNotifier(this.ref) : super(ExistingAssetsLists.empty());

  Future<void> loadExistingAssetsLists() async {
    debugPrint('loadExistingAssetsLists');

    for (final type in AssetTypeEnum.values) {
      await setExistingAssetsListByType(type);
    }
  }

  Future<void> setExistingAssetsListByType(AssetTypeEnum type) async {
    final directory =
        ref.read(directoriesProvider.notifier).getDirectoryByType(type);
    final filenames = await _getDirectoryFilenames(directory);

    switch (type) {
      case AssetTypeEnum.assetBundle:
        state = state.copyWith(assetBundles: filenames);
        break;
      case AssetTypeEnum.audio:
        state = state.copyWith(audio: filenames);
        break;
      case AssetTypeEnum.image:
        state = state.copyWith(images: filenames);
        break;
      case AssetTypeEnum.model:
        state = state.copyWith(models: filenames);
        break;
      case AssetTypeEnum.pdf:
        state = state.copyWith(pdfs: filenames);
        break;
    }
  }

  Future<List<String>> _getDirectoryFilenames(String path) async {
    final directory = Directory(path);

    if (!directory.existsSync()) {
      return [];
    }

    final List<String> filenames = await directory
        .list()
        // Filter to only include files, not directories
        .where((entity) => entity is File)
        .map((entity) => p.basenameWithoutExtension(entity.path))
        .toList();

    // In case of old files named using old url, remap them to the new url for the existing assets list
    return filenames.map((filename) {
      if (filename.startsWith(getFileNameFromURL(oldUrl))) {
        return filename.replaceFirst(
            getFileNameFromURL(oldUrl), getFileNameFromURL(newUrl));
      }

      return filename;
    }).toList();
  }

  bool doesAssetFileExist(String assetFileName, AssetTypeEnum type) {
    switch (type) {
      case AssetTypeEnum.assetBundle:
        return state.assetBundles.firstWhereOrNull(
                (element) => element.startsWith(assetFileName)) !=
            null;

      case AssetTypeEnum.audio:
        return state.audio.firstWhereOrNull(
                (element) => element.startsWith(assetFileName)) !=
            null;

      case AssetTypeEnum.image:
        return state.images.firstWhereOrNull(
                (element) => element.startsWith(assetFileName)) !=
            null;

      case AssetTypeEnum.model:
        return state.models.firstWhereOrNull(
                (element) => element.startsWith(assetFileName)) !=
            null;

      case AssetTypeEnum.pdf:
        return state.pdfs.firstWhereOrNull(
                (element) => element.startsWith(assetFileName)) !=
            null;
    }
  }
}
