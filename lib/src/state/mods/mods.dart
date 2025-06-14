import 'dart:convert' show jsonDecode;
import 'dart:io' show Directory, File, FileSystemEntity;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart' show VoidCallback, debugPrint;
import 'package:path/path.dart' as path;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show AsyncNotifier, AsyncValue;
import 'package:tts_mod_vault/src/state/asset/models/asset_lists_model.dart'
    show AssetLists;
import 'package:tts_mod_vault/src/state/asset/models/asset_model.dart'
    show Asset;
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
    show dateTimeToUnixTimestamp, getFileNameFromURL, newUrl, oldUrl;

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
      final workshopJsonsPaths = await _getJsonFilesInDirectory(
          ref.read(directoriesProvider).workshopDir);

      List<Mod> jsonListMods = [];

      for (final jsonPath in workshopJsonsPaths) {
        final jsonFileName = path.basenameWithoutExtension(jsonPath);

        if (jsonFileName == "WorkshopFileInfos") continue;

        try {
          final file = File(jsonPath);
          final jsonString = await file.readAsString();
          final jsonData = jsonDecode(jsonString);

          final saveName = await _getSaveNameFromJson(jsonData);
          final dateTimeStamp = await _getDateTimeStampFromJson(jsonData);

          if (saveName != null && saveName.isNotEmpty) {
            jsonListMods.add(Mod(
              jsonFilePath: jsonPath,
              saveName: saveName,
              dateTimeStamp: dateTimeStamp,
              jsonFileName: jsonFileName,
            ));
          }
        } catch (e) {
          debugPrint('loadModsData - failed to read json $jsonPath, error: $e');
        }
      }

      // Sort Mods alphabetically
      jsonListMods.sort((a, b) => a.saveName.compareTo(b.saveName));

      // Process mods in groups of batch size at most
      const int batchSize = 5;
      final List<Mod> allMods = [];

      for (int i = 0; i < jsonListMods.length; i += batchSize) {
        final batch = jsonListMods.skip(i).take(batchSize).toList();
        debugPrint('loadModsData - processing batch of size: ${batch.length}');

        final batchResults = await Future.wait(
          batch.map((mod) async {
            try {
              if (await File(mod.jsonFilePath).exists()) {
                final storage = ref.read(storageProvider);

                // Get cached data
                final cachedMod = storage.getModName(mod.jsonFileName);
                final cachedUpdateTime =
                    storage.getModDateTimeStamp(mod.jsonFileName);
                final cachedAssetLists =
                    storage.getModAssetLists(mod.jsonFileName);

                // Check if update is needed
                final updateTimeChanged = cachedUpdateTime != mod.dateTimeStamp;
                final needsRefresh = cachedMod == null || updateTimeChanged;

                Map<String, String>? jsonURLs;

                if (needsRefresh) {
                  jsonURLs = await _extractUrlsFromJson(mod.jsonFilePath);

                  if (updateTimeChanged) {
                    await storage.deleteMod(mod.jsonFileName);
                  }

                  await storage.saveModData(
                      mod.jsonFileName, mod.dateTimeStamp ?? '', jsonURLs);
                } else {
                  jsonURLs = cachedAssetLists;
                }

                // Uncomment this to delete all stored mod data
                // await storage.deleteMod(jsonFileName);

                return _getModData(mod, jsonURLs ?? <String, String>{});
              } else {
                debugPrint('loadModsData - missing JSON: ${mod.jsonFilePath}');
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

      final selectedMod = ref.read(selectedModProvider);
      if (selectedMod != null) {
        setSelectedMod(allMods.firstWhereOrNull(
            (m) => m.jsonFilePath == selectedMod.jsonFilePath));
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

  Future<void> updateModByJsonFilename(String jsonFilename) async {
    try {
      Mod? updatedMod;

      final updatedMods = await Future.wait(
        state.value!.mods.map((mod) async {
          if (mod.jsonFileName == jsonFilename) {
            updatedMod = await _getModData(
              mod,
              ref.read(storageProvider).getModAssetLists(mod.jsonFileName) ??
                  await _extractUrlsFromJson(mod.jsonFilePath),
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
    Mod mod,
    Map<String, String> jsonURLs,
  ) async {
    final assetLists = _getAssetListsFromUrls(jsonURLs);
    final imageFilePath =
        await _getImageFilePath(mod.jsonFilePath, mod.jsonFileName);

    return mod.copyWith(
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
    final assetUrls = <String>[];

    for (final url in urls) {
      assetUrls.add(_replaceInUrl(url, oldUrl, newUrl));
    }

    final existenceChecks = assetUrls
        .map((assetUrl) => ref
            .read(existingAssetListsProvider.notifier)
            .doesAssetFileExist(getFileNameFromURL(assetUrl), type))
        .toList();

    return List.generate(
      assetUrls.length,
      (i) => Asset(
        url: assetUrls[i],
        fileExists: existenceChecks[i],
        filePath: existenceChecks[i]
            ? ref
                .read(existingAssetListsProvider.notifier)
                .getAssetFilePath(getFileNameFromURL(assetUrls[i]), type)
            : null,
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
        .map((type) => _getAssetsByType(urlsByType[type] ?? [], type))
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
          mods.firstWhereOrNull((mod) => mod.jsonFileName == jsonFileName);

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

  // Load and parse the JSON from a file
  Future<Map<String, String>> _extractUrlsFromJson(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return {};
      }

      final jsonString = await file.readAsString();
      final decodedJson = jsonDecode(jsonString);

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
      final directory = Directory(directoryPath);

      if (!await directory.exists()) {
        return jsonFilePaths;
      }

      // List all files in the directory
      await for (final FileSystemEntity entity
          in directory.list(recursive: true)) {
        if (entity is File) {
          // Check if the file has a .json extension
          if (path.extension(entity.path).toLowerCase() == '.json') {
            jsonFilePaths.add(path.normalize(entity.path));
          }
        }
      }

      return jsonFilePaths;
    } catch (e) {
      debugPrint('_getJsonFilesInDirectory error: $e');
      return jsonFilePaths;
    }
  }

  Future<String?> _getSaveNameFromJson(dynamic jsonData) async {
    try {
      if (jsonData is Map<String, dynamic> &&
          jsonData.containsKey('SaveName')) {
        return jsonData['SaveName'].toString();
      }

      if (jsonData is List) {
        for (final item in jsonData) {
          if (item is Map<String, dynamic> && item.containsKey('SaveName')) {
            return item['SaveName'].toString();
          }
        }
      }

      return null;
    } catch (e) {
      debugPrint("_getSaveNameFromJson error: $e");
      return null;
    }
  }

  Future<String?> _getDateTimeStampFromJson(dynamic jsonData) async {
    try {
      if (jsonData is Map<String, dynamic> && jsonData.containsKey('Date')) {
        final dateValue = jsonData['Date'].toString();
        return dateTimeToUnixTimestamp(dateValue);
      }

      if (jsonData is List) {
        for (final item in jsonData) {
          if (item is Map<String, dynamic> && item.containsKey('Date')) {
            final dateValue = item['Date'].toString();
            return dateTimeToUnixTimestamp(dateValue);
          }
        }
      }

      return null;
    } catch (e) {
      debugPrint("_getDateTimeStampFromJson error: $e");
      return null;
    }
  }
}
