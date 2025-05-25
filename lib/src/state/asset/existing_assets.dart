import 'dart:io';

import 'package:collection/collection.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart' show Ref, StateNotifier;
import 'package:tts_mod_vault/src/state/asset/asset_type_lists.dart'
    show AssetTypeLists;
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart'
    show AssetTypeEnum;
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/src/state/provider.dart' show directoriesProvider;

class ExistingAssetsNotifier extends StateNotifier<AssetTypeLists> {
  final Ref ref;

  ExistingAssetsNotifier(this.ref) : super(AssetTypeLists.empty());

  Future<void> loadAssetTypeLists() async {
    final assetBundles = <String>[];
    final audio = <String>[];
    final images = <String>[];
    final models = <String>[];
    final pdfs = <String>[];

    for (final type in AssetTypeEnum.values) {
      final directory =
          ref.read(directoriesProvider.notifier).getDirectoryByType(type);

      final filenames = await _getDirectoryFilenames(directory);

      switch (type) {
        case AssetTypeEnum.assetBundle:
          assetBundles.addAll(filenames);
          break;
        case AssetTypeEnum.audio:
          audio.addAll(filenames);
          break;
        case AssetTypeEnum.image:
          images.addAll(filenames);
          break;
        case AssetTypeEnum.model:
          models.addAll(filenames);
          break;
        case AssetTypeEnum.pdf:
          pdfs.addAll(filenames);
          break;
      }
    }

    state = AssetTypeLists(
      assetBundles: assetBundles,
      audio: audio,
      images: images,
      models: models,
      pdfs: pdfs,
    );
  }

  Future<List<String>> _getDirectoryFilenames(String path) async {
    final directory = Directory(path);

    if (!directory.existsSync()) {
      return [];
    }

    final List<String> filenames = await directory
        .list()
        .where((entity) =>
            entity is File) // Filter to only include files, not directories
        .map((entity) => p.basenameWithoutExtension(entity.path))
        .toList();
    return filenames;
  }

  Future<void> updateAssetTypeList(AssetTypeEnum type) async {
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
