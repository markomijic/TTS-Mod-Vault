import 'package:collection/collection.dart';
import 'package:riverpod/riverpod.dart';
import 'package:tts_mod_vault/src/state/directories/directories_state.dart';
import 'dart:io';

import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart';
import 'package:tts_mod_vault/src/utils.dart';

class AssetTypeLists {
  final List<String> assetBundles;
  final List<String> audio;
  final List<String> images;
  final List<String> models;
  final List<String> pdfs;

  AssetTypeLists({
    required this.assetBundles,
    required this.audio,
    required this.images,
    required this.models,
    required this.pdfs,
  });

  AssetTypeLists.empty()
      : assetBundles = [],
        audio = [],
        images = [],
        models = [],
        pdfs = [];

  AssetTypeLists copyWith({
    List<String>? assetBundles,
    List<String>? audio,
    List<String>? images,
    List<String>? models,
    List<String>? pdfs,
  }) {
    return AssetTypeLists(
      assetBundles: assetBundles ?? this.assetBundles,
      audio: audio ?? this.audio,
      images: images ?? this.images,
      models: models ?? this.models,
      pdfs: pdfs ?? this.pdfs,
    );
  }
}

class StringListNotifier extends StateNotifier<AssetTypeLists> {
  final DirectoriesState directories;

  StringListNotifier(this.directories) : super(AssetTypeLists.empty());

  Future<void> loadStrings() async {
    final assetBundles = <String>[];
    final audio = <String>[];
    final images = <String>[];
    final models = <String>[];
    final pdfs = <String>[];

    for (final type in AssetType.values) {
      final directory = getDirectoryByType(directories, type);

      final filenames = await getDirectoryFilenames(directory);

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

  Future<List<String>> getDirectoryFilenames(String path) async {
    final directory = Directory(path);
    final List<String> filenames = await directory
        .list()
        .map((entity) => entity.path.split(Platform.pathSeparator).last)
        .toList();
    return filenames;
  }

  Future<void> updateTypeList(AssetType type) async {
    final directory = getDirectoryByType(directories, type);
    final filenames = await getDirectoryFilenames(directory);

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

  String? hasStringStartingWith(String prefix, AssetType type) {
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
