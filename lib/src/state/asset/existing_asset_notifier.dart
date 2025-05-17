import 'dart:io';

import 'package:collection/collection.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart' show StateNotifier;
import 'package:tts_mod_vault/src/state/asset/asset_type_lists.dart'
    show AssetTypeLists;
import 'package:tts_mod_vault/src/state/directories/directories_state.dart'
    show DirectoriesState;
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart'
    show AssetType;
import 'package:tts_mod_vault/src/utils.dart' show getDirectoryByType;
import 'package:path/path.dart' as p;

class ExistingAssetsNotifier extends StateNotifier<AssetTypeLists> {
  final DirectoriesState directories;

  ExistingAssetsNotifier(this.directories) : super(AssetTypeLists.empty());

  Future<void> loadAssetTypeLists() async {
    final assetBundles = <String>[];
    final audio = <String>[];
    final images = <String>[];
    final models = <String>[];
    final pdfs = <String>[];

    for (final type in AssetType.values) {
      final directory = getDirectoryByType(directories, type);

      final filenames = await _getDirectoryFilenames(directory);

      // Assign filenames to the correct list based on type
      switch (type) {
        case AssetType.assetBundle:
          assetBundles.addAll(filenames);
          break;
        case AssetType.audio:
          audio.addAll(filenames);
          break;
        case AssetType.image:
          images.addAll(filenames);
          break;
        case AssetType.model:
          models.addAll(filenames);
          break;
        case AssetType.pdf:
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
    final List<String> filenames = await directory
        .list()
        .where((entity) =>
            entity is File) // Filter to only include files, not directories
        .map((entity) => p.basenameWithoutExtension(entity.path))
        .toList();
    return filenames;
  }

  Future<void> updateAssetTypeList(AssetType type) async {
    final directory = getDirectoryByType(directories, type);
    final filenames = await _getDirectoryFilenames(directory);

    switch (type) {
      case AssetType.assetBundle:
        state = state.copyWith(assetBundles: filenames);
        break;
      case AssetType.audio:
        state = state.copyWith(audio: filenames);
        break;
      case AssetType.image:
        state = state.copyWith(images: filenames);
        break;
      case AssetType.model:
        state = state.copyWith(models: filenames);
        break;
      case AssetType.pdf:
        state = state.copyWith(pdfs: filenames);
        break;
    }
  }

  String? getAssetNameStartingWith(String prefix, AssetType type) {
    switch (type) {
      case AssetType.assetBundle:
        return state.assetBundles
            .firstWhereOrNull((element) => element.startsWith(prefix));

      case AssetType.audio:
        return state.audio
            .firstWhereOrNull((element) => element.startsWith(prefix));

      case AssetType.image:
        return state.images
            .firstWhereOrNull((element) => element.startsWith(prefix));

      case AssetType.model:
        return state.models
            .firstWhereOrNull((element) => element.startsWith(prefix));

      case AssetType.pdf:
        return state.pdfs
            .firstWhereOrNull((element) => element.startsWith(prefix));
    }
  }
}
