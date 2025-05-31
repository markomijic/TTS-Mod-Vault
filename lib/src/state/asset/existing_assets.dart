import 'dart:io' show Directory, File;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart' show debugPrint;
import 'package:hooks_riverpod/hooks_riverpod.dart' show Ref, StateNotifier;
import 'package:path/path.dart' as path;
import 'package:tts_mod_vault/src/state/asset/existing_assets_state.dart'
    show ExistingAssetsListsState;
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart'
    show AssetTypeEnum;
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/src/state/provider.dart' show directoriesProvider;
import 'package:tts_mod_vault/src/utils.dart'
    show getFileNameFromURL, newUrl, oldUrl;

class ExistingAssetsNotifier extends StateNotifier<ExistingAssetsListsState> {
  final Ref ref;

  ExistingAssetsNotifier(this.ref) : super(ExistingAssetsListsState.empty());

  Future<void> loadExistingAssetsLists() async {
    debugPrint('loadExistingAssetsLists');

    for (final type in AssetTypeEnum.values) {
      await setExistingAssetsListByType(type);
    }
  }

  Future<void> setExistingAssetsListByType(AssetTypeEnum type) async {
    final directory =
        ref.read(directoriesProvider.notifier).getDirectoryByType(type);
    final (filenames, filepaths) =
        await _getDirectoryFileNamesAndPaths(directory);

    switch (type) {
      case AssetTypeEnum.assetBundle:
        state = state.copyWith(
            assetBundles: filenames, assetBundlesFilepaths: filepaths);
        break;
      case AssetTypeEnum.audio:
        state = state.copyWith(audio: filenames, audioFilepaths: filepaths);
        break;
      case AssetTypeEnum.image:
        state = state.copyWith(images: filenames, imagesFilepaths: filepaths);
        break;
      case AssetTypeEnum.model:
        state = state.copyWith(models: filenames, modelsFilepaths: filepaths);
        break;
      case AssetTypeEnum.pdf:
        state = state.copyWith(pdf: filenames, pdfFilepaths: filepaths);
        break;
    }
  }

  Future<(List<String>, List<String>)> _getDirectoryFileNamesAndPaths(
      String path) async {
    final directory = Directory(path);

    if (!directory.existsSync()) {
      return (<String>[], <String>[]);
    }

    final files = await directory
        .list()
        // Filter to only include files, not directories
        .where((entity) => entity is File)
        .toList();

    final List<String> filenames = [];
    final List<String> filepaths = [];

    for (final file in files) {
      final filename = p.basenameWithoutExtension(file.path);
      final filepath = file.path;

      // In case of old files named using old url, remap them to the new url for the existing assets list
      final mappedFilename = filename.startsWith(getFileNameFromURL(oldUrl))
          ? filename.replaceFirst(
              getFileNameFromURL(oldUrl), getFileNameFromURL(newUrl))
          : filename;

      filenames.add(mappedFilename);
      filepaths.add(filepath);
    }

    return (filenames, filepaths);
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
        return state.pdf.firstWhereOrNull(
                (element) => element.startsWith(assetFileName)) !=
            null;
    }
  }

  String? getAssetFilePath(String assetFilename, AssetTypeEnum type) {
    switch (type) {
      case AssetTypeEnum.assetBundle:
        final index = state.assetBundles.indexOf(assetFilename);
        return index < 0
            ? null
            : path.normalize(state.assetBundlesFilepaths[index]);

      case AssetTypeEnum.audio:
        final index = state.audio.indexOf(assetFilename);
        return index < 0 ? null : path.normalize(state.audioFilepaths[index]);

      case AssetTypeEnum.image:
        final index = state.images.indexOf(assetFilename);
        return index < 0 ? null : path.normalize(state.imagesFilepaths[index]);

      case AssetTypeEnum.model:
        final index = state.models.indexOf(assetFilename);
        return index < 0 ? null : path.normalize(state.modelsFilepaths[index]);

      case AssetTypeEnum.pdf:
        final index = state.pdf.indexOf(assetFilename);
        return index < 0 ? null : path.normalize(state.pdfFilepaths[index]);
    }
  }
}
