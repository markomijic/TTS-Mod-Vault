import 'dart:io' show Directory, File;
import 'dart:isolate' show Isolate;

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
    show getFileNameFromURL, newSteamUserContentUrl, oldCloudUrl;

class ExistingAssetsNotifier extends StateNotifier<ExistingAssetsListsState> {
  final Ref ref;

  ExistingAssetsNotifier(this.ref) : super(ExistingAssetsListsState.empty());

  Future<void> loadExistingAssetsLists() async {
    debugPrint('loadExistingAssetsLists - started at ${DateTime.now()}');

    final directoryPaths = {
      for (final type in AssetTypeEnum.values)
        type: ref.read(directoriesProvider.notifier).getDirectoryByType(type)
    };

    final futures = AssetTypeEnum.values.map((type) async {
      final directoryPath = directoryPaths[type] ?? '';

      final (filenames, filepaths) = await Isolate.run(
        () => _getDirectoryFileNamesAndPaths(directoryPath),
      );

      return (type, filenames, filepaths);
    });

    final results = await Future.wait(futures);

    final Map<AssetTypeEnum, (List<String>, List<String>)> resultMap = {
      for (final (type, filenames, filepaths) in results)
        type: (filenames, filepaths)
    };

    state = ExistingAssetsListsState(
      assetBundles: resultMap[AssetTypeEnum.assetBundle]?.$1 ?? [],
      assetBundlesFilepaths: resultMap[AssetTypeEnum.assetBundle]?.$2 ?? [],
      audio: resultMap[AssetTypeEnum.audio]?.$1 ?? [],
      audioFilepaths: resultMap[AssetTypeEnum.audio]?.$2 ?? [],
      images: resultMap[AssetTypeEnum.image]?.$1 ?? [],
      imagesFilepaths: resultMap[AssetTypeEnum.image]?.$2 ?? [],
      models: resultMap[AssetTypeEnum.model]?.$1 ?? [],
      modelsFilepaths: resultMap[AssetTypeEnum.model]?.$2 ?? [],
      pdf: resultMap[AssetTypeEnum.pdf]?.$1 ?? [],
      pdfFilepaths: resultMap[AssetTypeEnum.pdf]?.$2 ?? [],
    );

    debugPrint('loadExistingAssetsLists - finished at ${DateTime.now()}');
  }

  Future<void> setExistingAssetsListByType(AssetTypeEnum type) async {
    final directoryPath =
        ref.read(directoriesProvider.notifier).getDirectoryByType(type);

    final (filenames, filepaths) = await Isolate.run(
      () => _getDirectoryFileNamesAndPaths(directoryPath),
    );

    _updateStateByType(type, filenames, filepaths);
  }

  void addExistingAsset(AssetTypeEnum type, String filename, String filepath) {
    switch (type) {
      case AssetTypeEnum.assetBundle:
        final newFilenames = [filename, ...state.assetBundles];
        final newFilepaths = [filepath, ...state.assetBundlesFilepaths];
        state = state.copyWith(
          assetBundles: newFilenames,
          assetBundlesFilepaths: newFilepaths,
        );
        break;
      case AssetTypeEnum.audio:
        final newFilenames = [filename, ...state.audio];
        final newFilepaths = [filepath, ...state.audioFilepaths];
        state = state.copyWith(
          audio: newFilenames,
          audioFilepaths: newFilepaths,
        );
        break;
      case AssetTypeEnum.image:
        final newFilenames = [filename, ...state.images];
        final newFilepaths = [filepath, ...state.imagesFilepaths];
        state = state.copyWith(
          images: newFilenames,
          imagesFilepaths: newFilepaths,
        );
        break;
      case AssetTypeEnum.model:
        final newFilenames = [filename, ...state.models];
        final newFilepaths = [filepath, ...state.modelsFilepaths];
        state = state.copyWith(
          models: newFilenames,
          modelsFilepaths: newFilepaths,
        );
        break;
      case AssetTypeEnum.pdf:
        final newFilenames = [filename, ...state.pdf];
        final newFilepaths = [filepath, ...state.pdfFilepaths];
        state = state.copyWith(
          pdf: newFilenames,
          pdfFilepaths: newFilepaths,
        );
        break;
    }
  }

  void _updateStateByType(
      AssetTypeEnum type, List<String> filenames, List<String> filepaths) {
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

  bool doesAssetFileExist(String assetFileName, AssetTypeEnum type) {
    switch (type) {
      case AssetTypeEnum.assetBundle:
        return state.assetBundles
                .firstWhereOrNull((element) => element == assetFileName) !=
            null;
      case AssetTypeEnum.audio:
        return state.audio
                .firstWhereOrNull((element) => element == assetFileName) !=
            null;
      case AssetTypeEnum.image:
        return state.images
                .firstWhereOrNull((element) => element == assetFileName) !=
            null;
      case AssetTypeEnum.model:
        return state.models
                .firstWhereOrNull((element) => element == assetFileName) !=
            null;
      case AssetTypeEnum.pdf:
        return state.pdf
                .firstWhereOrNull((element) => element == assetFileName) !=
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

///
/// Top-level function required by Isolate.run
///
Future<(List<String>, List<String>)> _getDirectoryFileNamesAndPaths(
    String dirPath) async {
  final directory = Directory(dirPath);

  if (!directory.existsSync()) {
    return (<String>[], <String>[]);
  }

  final files = await directory
      .list()
      .where((entity) => entity is File)
      .cast<File>()
      .toList();

  final filenames = <String>[];
  final filepaths = <String>[];

  for (final file in files) {
    final filename = p.basenameWithoutExtension(file.path);
    final mappedFilename = filename.startsWith(getFileNameFromURL(oldCloudUrl))
        ? filename.replaceFirst(getFileNameFromURL(oldCloudUrl),
            getFileNameFromURL(newSteamUserContentUrl))
        : filename;

    filenames.add(mappedFilename);
    filepaths.add(file.path);
  }

  return (filenames, filepaths);
}
