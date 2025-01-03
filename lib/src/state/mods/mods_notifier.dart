import 'dart:convert';
import 'dart:io';
import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as path;
import 'package:riverpod/riverpod.dart';
import 'package:tts_mod_vault/src/state/asset/asset_lists_model.dart';
import 'package:tts_mod_vault/src/state/asset/asset_model.dart';
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart';
import 'package:tts_mod_vault/src/state/mods/mod_model.dart';
import 'package:tts_mod_vault/src/state/mods/mods_state.dart';
import 'package:tts_mod_vault/src/state/provider.dart';
import 'package:tts_mod_vault/src/utils.dart';

class ModsStateNotifier extends StateNotifier<ModsState> {
  final Ref ref;

  ModsStateNotifier(this.ref) : super(ModsState());

  Future<void> loadModsData() async {
    state = ModsState(mods: [], selectedMod: null);

    try {
      final workShopFileInfosPath = path.join(
          ref.read(directoriesProvider).workshopDir, 'WorkshopFileInfos.json');

      final String jsonString =
          await File(workShopFileInfosPath).readAsString();
      final List<dynamic> jsonList = json.decode(jsonString);
      final items = jsonList.map((json) => Mod.fromJson(json)).toList();

      List<Mod> mods = [];

      for (final item in items) {
        try {
          if (await doesJsonExist(path.basename(item.directory))) {
            mods.add(await getModData(item));
          } else {
            debugPrint('missing json: ${item.directory}');
          }
        } catch (e) {
          continue;
        }
      }

      state = state.copyWith(mods: mods);
    } catch (e) {
      debugPrint('Error loading items: $e');
    }
  }

  Future<Mod> getModData(Mod mod) async {
    final fileName = path.basenameWithoutExtension(mod.directory);
    final imageFilePath =
        path.join(ref.read(directoriesProvider).workshopDir, '$fileName.png');
    final jsonURLs = await extractUrlsFromJson(mod.directory);
    final assetLists = await getAssetListsFromUrls(jsonURLs);

    return Mod(
      directory: mod.directory,
      name: mod.name,
      updateTime: mod.updateTime,
      fileName: fileName,
      imageFilePath: imageFilePath,
      assetLists: assetLists.$1,
      totalCount: assetLists.$2,
      totalExistsCount: assetLists.$3,
    );
  }

  Future<void> updateMod(String modName) async {
    Mod? updatedMod;
    final updatedMods = await Future.wait(state.mods.map((mod) async {
      if (mod.name == modName) {
        updatedMod = await getModData(mod);
        return updatedMod ?? mod;
      }

      return mod;
    }).toList());

    state = state.copyWith(mods: updatedMods, selectedMod: updatedMod);
  }

  Future<(AssetLists, int, int)> getAssetListsFromUrls(
      Map<String, String> data) async {
    final List<String> assetBundleURLs = [];
    final List<String> audioURLs = [];
    final List<String> imageURLs = [];
    final List<String> modelURLs = [];
    final List<String> pdfURLs = [];

    int totalCount = 0;
    int existingFilesCount = 0;

    for (final element in data.entries) {
      for (final assetType in AssetType.values) {
        if (assetType.subtypes.contains(element.value)) {
          totalCount++;
          switch (assetType) {
            case AssetType.assetBundle:
              assetBundleURLs.add(element.key);
            case AssetType.audio:
              audioURLs.add(element.key);
            case AssetType.image:
              imageURLs.add(element.key);
            case AssetType.model:
              modelURLs.add(element.key);
            case AssetType.pdf:
              pdfURLs.add(element.key);
          }
          break;
        }
      }
    }

    Future<List<Asset>> getAssetsByType(
      List<String> urls,
      AssetType type,
    ) async {
      return await Future.wait(
        urls.map(
          (url) async {
            final updatedUrl = replaceInUrl(
                url,
                'http://cloud-3.steamusercontent.com/',
                'https://steamusercontent-a.akamaihd.net/');

            final fileExists = await doesAssetExist(updatedUrl, type);
            if (fileExists) {
              existingFilesCount++;
            }
            return Asset(url: updatedUrl, fileExists: fileExists);
          },
        ),
      );
    }

    final assetBundleAssets =
        await getAssetsByType(assetBundleURLs, AssetType.assetBundle);
    final audioAssets = await getAssetsByType(audioURLs, AssetType.audio);
    final imageAssets = await getAssetsByType(imageURLs, AssetType.image);
    final modelAssets = await getAssetsByType(modelURLs, AssetType.model);
    final pdfAssets = await getAssetsByType(pdfURLs, AssetType.pdf);

    return (
      AssetLists(
        assetBundles: assetBundleAssets,
        audio: audioAssets,
        images: imageAssets,
        models: modelAssets,
        pdf: pdfAssets,
      ),
      totalCount,
      existingFilesCount,
    );
  }

  Future<bool> doesJsonExist(String fileName) async {
    final jsonPath =
        path.joinAll([ref.read(directoriesProvider).workshopDir, fileName]);
    return await File(jsonPath).exists();
  }

  Future<bool> doesAssetExist(String url, AssetType type) async {
    String filePath = '';
    if (type == AssetType.image) {
      final file = Directory(ref.read(directoriesProvider).imagesDir)
          .listSync()
          .firstWhereOrNull(
            (entity) =>
                entity is File &&
                path.basenameWithoutExtension(entity.path) ==
                    getFileNameFromURL(url),
          );

      if (file != null && file is File) {
        filePath = file.path;
      }
    }

    final assetPath = path.joinAll([
      getDirectoryByType(ref.read(directoriesProvider), type),
      getFileNameFromURL(url) + getExtensionByType(type, filePath),
    ]);

    return await File(assetPath).exists();
  }

  Future<void> selectItem(Mod item) async {
    state = state.copyWith(selectedMod: item);
  }

  String replaceInUrl(String url, String oldPart, String newPart) {
    if (url.contains(oldPart)) {
      return url.replaceAll(oldPart, newPart);
    }
    return url;
  }

  // Function to recursively extract URLs and their associated keys from the JSON structure
  Map<String, String> extractUrlsWithReversedKeys(dynamic data,
      [String? parentKey]) {
    Map<String, String> urls = {};

    // If the data is a Map, look for URL-like values or recurse into it
    if (data is Map) {
      data.forEach((key, value) {
        // Check if the value is a URL
        if (value is String && Uri.tryParse(value)?.hasAbsolutePath == true) {
          // Add the URL as the key and the key-path (or just the last-level key) as the value
          urls[value] = key;
        }
        // If the value is a Map or List, recurse into it
        else if (value is Map || value is List) {
          urls.addAll(extractUrlsWithReversedKeys(value, key));
        }
      });
    }
    // If the data is a List, iterate through it and recurse into each element
    else if (data is List) {
      for (final item in data) {
        urls.addAll(extractUrlsWithReversedKeys(item, parentKey ?? ''));
      }
    }

    return urls;
  }

  // Function to load and parse the JSON from a file
  Future<Map<String, String>> extractUrlsFromJson(String filePath) async {
    try {
      // Read the JSON file
      final file = File(filePath);
      final jsonString = await file.readAsString();

      // Parse the JSON string into a Dart object (Map or List depending on your structure)
      final decodedJson = jsonDecode(jsonString);

      // Extract URLs with reversed key-value relationships
      Map<String, String> urls = extractUrlsWithReversedKeys(decodedJson);

      return urls;
    } catch (e) {
      debugPrint('Error reading or parsing the file: $e');
    }

    return {};
  }
}
