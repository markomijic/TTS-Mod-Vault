import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart' show VoidCallback, debugPrint;
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as path;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show AsyncNotifier, AsyncValue;
import 'package:tts_mod_vault/src/state/asset/asset_lists_model.dart'
    show AssetLists;
import 'package:tts_mod_vault/src/state/asset/asset_model.dart' show Asset;
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart'
    show AssetTypeEnum;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show Mod;
import 'package:tts_mod_vault/src/state/mods/mods_state.dart' show ModsState;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        backupProvider,
        directoriesProvider,
        existingAssetListsProvider,
        selectedModProvider,
        storageProvider;
import 'package:tts_mod_vault/src/utils.dart'
    show getFileNameFromURL, newUrl, oldUrl;

class ModsStateNotifier extends AsyncNotifier<ModsState> {
  @override
  Future<ModsState> build() async {
    return ModsState(mods: []);
  }

  void setLoading() {
    state = const AsyncValue.loading();
  }

  Future<void> loadModsData({
    VoidCallback? onDataLoaded,
    String modJsonFileName = "",
  }) async {
    debugPrint('loadModsData START: ${DateTime.now()}');

    setLoading();

    try {
      final workShopFileInfosPath = path.join(
        ref.read(directoriesProvider).workshopDir,
        'WorkshopFileInfos.json',
      );

      final workshopDirJsonFilePaths = await _getJsonFilesInDirectory(
          ref.read(directoriesProvider).workshopDir);

      List<Mod> jsonListMods = [];

      if (await File(workShopFileInfosPath).exists()) {
        final String jsonString =
            await File(workShopFileInfosPath).readAsString();
        final List<dynamic> jsonList = json.decode(jsonString);

        jsonListMods = jsonList.map((json) => Mod.fromJson(json)).toList();
      }

      for (final workshopDirJsonFilePath in workshopDirJsonFilePaths) {
        final workshopDirJsonFileName =
            path.basenameWithoutExtension(workshopDirJsonFilePath);

        if (workshopDirJsonFileName == "WorkshopFileInfos") continue;

        final modIsInJsonList = jsonListMods.firstWhereOrNull((jsonItem) =>
            path.basenameWithoutExtension(jsonItem.directory) ==
            workshopDirJsonFileName);

        if (modIsInJsonList == null) {
          final saveName = await _getSaveNameFromJson(workshopDirJsonFilePath);

          if (saveName != null && saveName.isNotEmpty) {
            jsonListMods.add(Mod(
              directory: workshopDirJsonFilePath,
              name: saveName,
              updateTime: 0,
            ));
          }
        }
      }

      // Sort Mods alphabetically
      jsonListMods.sort((a, b) => a.name.compareTo(b.name));

      // Process mods in groups of batch size at most
      const int batchSize = 5;
      final List<Mod> allMods = [];

      for (int i = 0; i < jsonListMods.length; i += batchSize) {
        final batch = jsonListMods.skip(i).take(batchSize).toList();
        debugPrint('loadModsData - processing batch of size: ${batch.length}');

        final batchResults = await Future.wait(
          batch.map((item) async {
            try {
              if (await File(path.normalize(item.directory)).exists()) {
                final jsonFileName =
                    path.basenameWithoutExtension(item.directory);
                final storage = ref.read(storageProvider);

                // Get cached data
                final cachedMod = storage.getModName(jsonFileName);
                final cachedUpdateTime = storage.getModUpdateTime(jsonFileName);
                final cachedAssetLists = storage.getModAssetLists(jsonFileName);

                // Check if update is needed
                final updateTimeChanged = cachedUpdateTime != item.updateTime;
                final needsRefresh = cachedMod == null || updateTimeChanged;

                Map<String, String>? jsonURLs;

                if (needsRefresh) {
                  jsonURLs = cachedAssetLists ??
                      await _extractUrlsFromJson(item.directory);

                  if (updateTimeChanged) {
                    await storage.deleteMod(jsonFileName);
                  }

                  await storage.saveModData(
                      jsonFileName, item.updateTime, jsonURLs);
                } else {
                  jsonURLs = cachedAssetLists;
                }

                // Uncomment this to delete all stored mod data
                // await storage.deleteMod(jsonFileName);

                return _getModData(
                    item, jsonFileName, jsonURLs ?? <String, String>{});
              } else {
                debugPrint('loadModsData - missing JSON: ${item.directory}');
                return null;
              }
            } catch (e) {
              debugPrint(
                  'loadModsData - error processing item: ${e.toString()}');
              return null;
            }
          }),
        );

        // Add non-null results from this batch
        allMods.addAll(batchResults.whereType<Mod>());
      }

      if (ref.read(selectedModProvider) != null) {
        setSelectedMod(null);
      }

      if (modJsonFileName.isNotEmpty) {
        ref.read(backupProvider.notifier).resetLastImportedJsonFileName();
        _setSelectedModByJsonFileName(allMods, modJsonFileName);
      }

      state = AsyncValue.data(ModsState(mods: allMods));

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
          if (mod.name == modName && mod.fileName != null) {
            updatedMod = await _getModData(
              mod,
              mod.fileName!,
              ref.read(storageProvider).getModAssetLists(mod.fileName!) ??
                  await _extractUrlsFromJson(mod.directory),
            );

            if (updatedMod != null) return updatedMod!;
          }
          return mod;
        }).toList(),
      );

      if (updatedMod != null) {
        setSelectedMod(updatedMod!);
      }

      state = AsyncValue.data(state.value!.copyWith(mods: updatedMods));
    } catch (e) {
      debugPrint('updateMod error: $e');
      state = AsyncValue.error(e, StackTrace.current);
    }
  }

  Future<Mod> _getModData(
      Mod mod, String fileName, Map<String, String> jsonURLs) async {
    final assetLists = _getAssetListsFromUrls(jsonURLs);
    final imageFilePath = await _getImageFilePath(mod.directory, fileName);

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

  Future<String?> _getImageFilePath(
    String modDirectory,
    String fileName,
  ) async {
    String? imageFilePath;

    final imageWorkshopDir =
        path.join(path.dirname(modDirectory), '$fileName.png');
    final workshopDirFile = File(imageWorkshopDir);

    if (await workshopDirFile.exists()) {
      imageFilePath = imageWorkshopDir;
    } else {
      final imageThumbnailsDir =
          path.join(path.dirname(modDirectory), 'Thumbnails', '$fileName.png');
      final thumbnailsDirFile = File(imageThumbnailsDir);

      if (await thumbnailsDirFile.exists()) {
        imageFilePath = imageThumbnailsDir;
      }
    }

    return imageFilePath;
  }

  List<Asset> _getAssetsByType(List<String> urls, AssetTypeEnum type) {
    final filePaths = <(String, String)>[];

    for (final url in urls) {
      if (url.startsWith("file:///")) continue;

      final updatedUrl = _replaceInUrl(url, oldUrl, newUrl);

      final filePath = path.joinAll([
        ref.read(directoriesProvider.notifier).getDirectoryByType(type),
        getFileNameFromURL(updatedUrl),
      ]);

      filePaths.add((updatedUrl, filePath));
    }

    final existenceChecks = filePaths
        .map((filePath) => ref
            .read(existingAssetListsProvider.notifier)
            .doesAssetFileExist(getFileNameFromURL(filePath.$1), type))
        .toList();

    return List.generate(
      filePaths.length,
      (i) => Asset(
        url: filePaths[i].$1,
        fileExists: existenceChecks[i],
        filePath: existenceChecks[i] ? path.normalize(filePaths[i].$2) : null,
      ),
    );
  }

  (AssetLists, int, int) _getAssetListsFromUrls(Map<String, String> data) {
    Map<AssetTypeEnum, List<String>> urlsByType = {
      for (final type in AssetTypeEnum.values) type: [],
    };

    for (final element in data.entries) {
      for (final assetType in AssetTypeEnum.values) {
        if (assetType.subtypes.contains(element.value)) {
          urlsByType[assetType]!.add(element.key);
          break;
        }
      }
    }

    final results = AssetTypeEnum.values
        .map((type) => _getAssetsByType(urlsByType[type]!, type))
        .toList();

    final totalCount = results.expand((list) => list).length;
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

  Future<void> _setSelectedModByJsonFileName(
      List<Mod> mods, String jsonFileName) async {
    if (mods.isNotEmpty) {
      final foundMod =
          mods.firstWhereOrNull((mod) => mod.fileName == jsonFileName);

      if (foundMod != null) setSelectedMod(foundMod);
    }
  }

  void setSelectedMod(Mod? item) {
    ref.read(selectedModProvider.notifier).state = item;
  }

  String _replaceInUrl(String url, String oldPart, String newPart) {
    if (url.contains(oldPart)) {
      return url.replaceAll(oldPart, newPart);
    }
    return url;
  }

  // Function to recursively extract URLs and their associated keys from the JSON structure
  Map<String, String> _extractUrlsWithReversedKeys(dynamic data,
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
          urls.addAll(_extractUrlsWithReversedKeys(value, key));
        }
      });
    }
    // If the data is a List, iterate through it and recurse into each element
    else if (data is List) {
      for (final item in data) {
        urls.addAll(_extractUrlsWithReversedKeys(item, parentKey ?? ''));
      }
    }
    // Filter urls where the value (key name) matches any subtype from any AssetType
    return Map.fromEntries(urls.entries.where((entry) => AssetTypeEnum.values
        .any((type) => type.subtypes.contains(entry.value))));
  }

  // Function to load and parse the JSON from a file
  Future<Map<String, String>> _extractUrlsFromJson(String filePath) async {
    try {
      // Read the JSON file
      final file = File(filePath);
      final jsonString = await file.readAsString();

      // Parse the JSON string into a Dart object (Map or List depending on your structure)
      final decodedJson = jsonDecode(jsonString);

      // Extract URLs with reversed key-value relationships
      Map<String, String> urls = _extractUrlsWithReversedKeys(decodedJson);

      return urls;
    } catch (e) {
      debugPrint('_extractUrlsFromJson error: $e');
    }

    return {};
  }

  Future<List<String>> _getJsonFilesInDirectory(String directoryPath) async {
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
      debugPrint('_getJsonFilesInDirectory error: $e');
      return jsonFilePaths;
    }
  }

  Future<String?> _getSaveNameFromJson(String filePath) async {
    try {
      final File file = File(filePath);
      final String jsonString = await file.readAsString();
      final Map<String, dynamic> jsonData = jsonDecode(jsonString);

      if (jsonData.containsKey('SaveName')) {
        return jsonData['SaveName'] as String;
      }

      return null;
    } catch (e) {
      debugPrint("_getSaveNameFromJson error: $e");
      return null;
    }
  }
}
