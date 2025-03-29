import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart' show VoidCallback, debugPrint;
import 'package:path/path.dart' as path;
import 'package:riverpod/riverpod.dart' show AsyncNotifier, AsyncValue;
import 'package:tts_mod_vault/src/state/asset/asset_lists_model.dart'
    show AssetLists;
import 'package:tts_mod_vault/src/state/asset/asset_model.dart' show Asset;
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart'
    show AssetType;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show Mod;
import 'package:tts_mod_vault/src/state/mods/mods_state.dart' show ModsState;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        directoriesProvider,
        existingAssetListsProvider,
        selectedModProvider,
        storageProvider;
import 'package:tts_mod_vault/src/utils.dart'
    show getDirectoryByType, getExtensionByType, getFileNameFromURL;

class ModsStateNotifier extends AsyncNotifier<ModsState> {
  @override
  Future<ModsState> build() async {
    return ModsState(mods: [], selectedMod: null);
  }

  void setLoading() {
    state = const AsyncValue.loading();
  }

  Future<void> loadModsData(VoidCallback? onDataLoaded) async {
    debugPrint('loadModsData START: ${DateTime.now()}');

    setLoading();

    try {
      final workShopFileInfosPath = path.join(
        ref.read(directoriesProvider).workshopDir,
        'WorkshopFileInfos.json',
      );

      final workshopDirJsonFilePaths = await getJsonFilesInDirectory(
          ref.read(directoriesProvider).workshopDir);

      final String jsonString =
          await File(workShopFileInfosPath).readAsString();
      final List<dynamic> jsonList = json.decode(jsonString);

      final jsonListMods = jsonList.map((json) => Mod.fromJson(json)).toList();

      for (final workshopDirJsonFilePath in workshopDirJsonFilePaths) {
        final workshopDirJsonFileName =
            path.basenameWithoutExtension(workshopDirJsonFilePath);

        if (workshopDirJsonFileName == "WorkshopFileInfos") continue;

        final modIsInJsonList = jsonListMods.firstWhereOrNull((jsonItem) =>
            path.basenameWithoutExtension(jsonItem.directory) ==
            workshopDirJsonFileName);

        if (modIsInJsonList == null) {
          final saveName = await getSaveNameFromJson(workshopDirJsonFilePath);

          if (saveName != null && saveName.isNotEmpty) {
            jsonListMods.add(Mod(
              directory: workshopDirJsonFilePath,
              name: saveName,
              updateTime: 0,
            ));
          }
        }
      }

      // Sort alphabetically
      jsonListMods.sort((a, b) => a.name.compareTo(b.name));

      // Process items concurrently
      final mods = await Future.wait(
        jsonListMods.map((item) async {
          try {
            if (await doesJsonExist(path.basename(item.directory))) {
              final fileName = path.basenameWithoutExtension(item.directory);
              Map<String, String>? jsonURLs;

              jsonURLs = ref.read(storageProvider).getItemMap(fileName) ??
                  await extractUrlsFromJson(item.directory);

              final mod = getModData(item, fileName, jsonURLs);

              if (ref.read(storageProvider).getItem(fileName) == null ||
                  ref.read(storageProvider).getItemUpdateTime(fileName) !=
                      item.updateTime) {
                if (ref.read(storageProvider).getItemUpdateTime(fileName) !=
                    item.updateTime) {
                  await ref.read(storageProvider).deleteItem(fileName);
                }
                await ref.read(storageProvider).saveAllItemData(
                      fileName,
                      fileName,
                      item.updateTime,
                      jsonURLs,
                    );
              }
              // Uncomment to delete all cached mod data
              /*   else {
                await ref.read(storageProvider).deleteItem(fileName);
              } */

              return mod;
            } else {
              debugPrint('loadModsData - missing JSON: ${item.directory}');
              return null;
            }
          } catch (e) {
            debugPrint('loadModsData - error processing item: ${e.toString()}');
            return null;
          }
        }),
      );

      state = AsyncValue.data(
        ModsState(
          mods: mods.whereType<Mod>().toList(), // Filter out null mods
          selectedMod: null,
        ),
      );

      debugPrint('loadModsData END: ${DateTime.now()}');
      if (onDataLoaded != null) {
        onDataLoaded();
      }
    } catch (e) {
      debugPrint('loadModsData error: $e');
      state = AsyncValue.error(e, StackTrace.current);
    }
  }

  Future<void> updateMod(String modName) async {
    try {
      Mod? updatedMod;

      final updatedMods = await Future.wait(
        state.value!.mods.map((mod) async {
          if (mod.name == modName) {
            updatedMod = getModData(
              mod,
              mod.fileName!,
              ref.read(storageProvider).getItemMap(mod.fileName!) ??
                  await extractUrlsFromJson(mod.directory),
            );
            return updatedMod ?? mod;
          }
          return mod;
        }).toList(),
      );

      if (updatedMod != null) {
        selectItem(updatedMod!);
      }

      state = AsyncValue.data(
        state.value!.copyWith(
          mods: updatedMods,
          isLoading: false,
        ),
      );
    } catch (e) {
      debugPrint('updateMod error: $e');
      state = AsyncValue.error(e, StackTrace.current);
    }
  }

  Mod getModData(Mod mod, String fileName, Map<String, String> jsonURLs) {
    final imageFilePath =
        path.join(ref.read(directoriesProvider).workshopDir, '$fileName.png');

    final assetLists = getAssetListsFromUrls(jsonURLs);

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

  List<Asset> getAssetsByType(List<String> urls, AssetType type) {
    final filePaths = urls.map((url) {
      final updatedUrl = replaceInUrl(
          url,
          'http://cloud-3.steamusercontent.com/',
          'https://steamusercontent-a.akamaihd.net/');
      return (updatedUrl, getFilePath(updatedUrl, type));
    }).toList();

    final existenceChecks = filePaths
        .map((filePath) =>
            ref
                .read(existingAssetListsProvider.notifier)
                .getAssetNameStartingWith(
                    getFileNameFromURL(filePath.$1), type) !=
            null)
        .toList();

    return List.generate(
      urls.length,
      (i) => Asset(
        url: filePaths[i].$1,
        fileExists: existenceChecks[i],
        filePath: existenceChecks[i] ? path.normalize(filePaths[i].$2) : null,
      ),
    );
  }

  (AssetLists, int, int) getAssetListsFromUrls(Map<String, String> data) {
    Map<AssetType, List<String>> urlsByType = {
      for (var type in AssetType.values) type: [],
    };

    for (final element in data.entries) {
      for (final assetType in AssetType.values) {
        if (assetType.subtypes.contains(element.value)) {
          urlsByType[assetType]!.add(element.key);
          break;
        }
      }
    }

    final results = AssetType.values
        .map((type) => getAssetsByType(urlsByType[type]!, type))
        .toList();

    final totalCount = data.length;
    final existingFilesCount = results
        .expand((list) => list)
        .where((asset) => asset.fileExists)
        .length;

    return (
      AssetLists(
        assetBundles: results[0],
        audio: results[1],
        images: results[2],
        models: results[3],
        pdf: results[4],
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

  String getFilePath(String url, AssetType type) {
    String filePath = '';
    final fileNameFromURL = getFileNameFromURL(url);
    if (type == AssetType.image || type == AssetType.audio) {
      final fileExists = ref
          .read(existingAssetListsProvider.notifier)
          .getAssetNameStartingWith(fileNameFromURL, type);

      if (fileExists != null) {
        filePath = path.joinAll([
          type == AssetType.image
              ? ref.read(directoriesProvider).imagesDir
              : ref.read(directoriesProvider).audioDir,
          fileExists
        ]);
      }
    }

    return path.joinAll([
      getDirectoryByType(ref.read(directoriesProvider), type),
      fileNameFromURL + getExtensionByType(type, filePath),
    ]);
  }

  Future<void> selectItem(Mod item) async {
    ref.read(selectedModProvider.notifier).state = item;
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
    // Filter urls where the value (key name) matches any subtype from any AssetType
    return Map.fromEntries(urls.entries.where((entry) =>
        AssetType.values.any((type) => type.subtypes.contains(entry.value))));
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

  Future<List<String>> getJsonFilesInDirectory(String directoryPath) async {
    final List<String> jsonFilePaths = [];

    try {
      final Directory directory = Directory(directoryPath);

      if (!await directory.exists()) {
        return jsonFilePaths;
      }

      // List all files in the directory
      await for (final FileSystemEntity entity
          in directory.list(recursive: false)) {
        if (entity is File) {
          // Check if the file has a .json extension
          if (path.extension(entity.path).toLowerCase() == '.json') {
            jsonFilePaths.add(entity.path);
          }
        }
      }

      return jsonFilePaths;
    } catch (e) {
      debugPrint('getJsonFilesInDirectory error: $e');
      return jsonFilePaths;
    }
  }

  Future<String?> getSaveNameFromJson(String filePath) async {
    try {
      final File file = File(filePath);
      final String jsonString = await file.readAsString();
      final Map<String, dynamic> jsonData = jsonDecode(jsonString);

      if (jsonData.containsKey('SaveName')) {
        return jsonData['SaveName'] as String;
      }

      return null;
    } catch (e) {
      debugPrint("getSaveNameFromJson error: $e");
      return null;
    }
  }
}
