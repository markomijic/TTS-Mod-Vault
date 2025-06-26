import 'dart:convert' show jsonDecode;
import 'dart:io' show Directory, File, Platform;
import 'dart:isolate' show Isolate;
import 'dart:math' show max;

import 'package:collection/collection.dart' show IterableExtension;
import 'package:flutter/material.dart' show VoidCallback, debugPrint;
import 'package:path/path.dart' as path;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show AsyncNotifier, AsyncValue, AsyncValueX;
import 'package:tts_mod_vault/src/state/asset/models/asset_lists_model.dart'
    show AssetLists;
import 'package:tts_mod_vault/src/state/asset/models/asset_model.dart'
    show Asset;
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart'
    show AssetTypeEnum;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart'
    show Mod, ModTypeEnum;
import 'package:tts_mod_vault/src/state/mods/mods_isolates.dart'
    show
        InitialModsIsolateData,
        IsolateWorkData,
        IsolateWorkResult,
        ModStorageUpdate,
        processInitialModsInIsolate,
        processMultipleBatchesInIsolate;
import 'package:tts_mod_vault/src/state/mods/mods_state.dart' show ModsState;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        backupProvider,
        directoriesProvider,
        existingAssetListsProvider,
        selectedModProvider,
        storageProvider;
import 'package:tts_mod_vault/src/state/storage/storage.dart' show Storage;
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

  List<Mod> getAllMods() {
    return state.maybeWhen(
      data: (state) => [...state.mods, ...state.saves, ...state.savedObjects],
      orElse: () => [],
    );
  }

  Future<List<Mod>> getInitialMods(
    List<(ModTypeEnum type, List<String>)> allPaths,
  ) async {
    List<Mod> allMods = [];
    int allPathsLength = 0;

    for (final paths in allPaths) {
      allPathsLength += paths.$2.length;
    }

    final numberOfIsolates = max(Platform.numberOfProcessors - 2, 2);
    final chunkSize = (allPathsLength / numberOfIsolates).ceil();
    final totalChunks = (allPathsLength / chunkSize).ceil();

    debugPrint(
        'getInitialMods - Processing $allPathsLength files in $totalChunks chunks using $numberOfIsolates isolates');

    // Process files in chunks across multiple isolates
    List<Future<List<Mod>>> futures = [];

    for (final paths in allPaths) {
      for (int i = 0; i < paths.$2.length; i += chunkSize) {
        final chunk = paths.$2.skip(i).take(chunkSize).toList();

        final isolateData = InitialModsIsolateData(
          jsonsPaths: chunk,
          modType: paths.$1,
          fileNameToIgnore: paths.$1 == ModTypeEnum.mod
              ? "WorkshopFileInfos"
              : paths.$1 == ModTypeEnum.save
                  ? "SaveFileInfos"
                  : "",
        );

        futures
            .add(Isolate.run(() => processInitialModsInIsolate(isolateData)));

        // Limit concurrent isolates to prevent overwhelming the system
        if (futures.length >= numberOfIsolates) {
          final results = await Future.wait(futures);
          for (final result in results) {
            allMods.addAll(result);
          }
          futures.clear();
        }
      }
    }

    // Process any remaining futures
    if (futures.isNotEmpty) {
      final results = await Future.wait(futures);
      for (final result in results) {
        allMods.addAll(result);
      }
    }

    debugPrint('getInitialMods - Completed processing ${allMods.length} files');
    return allMods;
  }

  Future<void> loadModsData({
    VoidCallback? onDataLoaded,
    String modJsonFileName = "",
  }) async {
    final startTime = DateTime.now();
    debugPrint('loadModsData START: $startTime');

    setLoading();

    try {
      final workshopJsonsPaths = await _getJsonFilesInDirectory(
          ref.read(directoriesProvider).workshopDir);

      final savesJsonsPaths = await _getJsonFilesInDirectory(
        ref.read(directoriesProvider).savesDir,
        excludeDirectory: ref.read(directoriesProvider).savedObjectsDir,
      );

      final savedObjectsJsonsPaths = await _getJsonFilesInDirectory(
          ref.read(directoriesProvider).savedObjectsDir);

      debugPrint('loadModsData - getting initial mods ${DateTime.now()}');

      List<(ModTypeEnum type, List<String>)> allPaths = [
        (ModTypeEnum.mod, workshopJsonsPaths),
        (ModTypeEnum.save, savesJsonsPaths),
        (ModTypeEnum.savedObject, savedObjectsJsonsPaths),
      ];

      final jsonListMods = await getInitialMods(allPaths);

      // Create adaptive batches based on file sizes
      debugPrint('loadModsData - creating adaptive batches, ${DateTime.now()}');
      final List<List<Mod>> adaptiveBatches =
          await _createAdaptiveBatches(jsonListMods);
      debugPrint(
          'loadModsData - created ${adaptiveBatches.length} adaptive batches');

      final numberOfIsolates = max(Platform.numberOfProcessors - 2, 2);
      debugPrint(
          'Using $numberOfIsolates isolates for ${adaptiveBatches.length} batches');

      // Uncomment this to delete all stored mod data
      //await ref.read(storageProvider).clearAllModData();

      // Prepare cached data for all mods
      final Map<String, String?> cachedDateTimeStamps = {};
      final Map<String, Map<String, String>?> cachedAssetLists = {};

      for (final mod in jsonListMods) {
        cachedDateTimeStamps[mod.jsonFileName] =
            ref.read(storageProvider).getModDateTimeStamp(mod.jsonFileName);
        cachedAssetLists[mod.jsonFileName] =
            ref.read(storageProvider).getModAssetLists(mod.jsonFileName);
      }

      // Distribute batches across isolates
      final batchesPerIsolate =
          _distributeBatchesAcrossIsolates(adaptiveBatches, numberOfIsolates);

      debugPrint('Batch distribution:');
      for (int i = 0; i < batchesPerIsolate.length; i++) {
        final totalMods = batchesPerIsolate[i].expand((batch) => batch).length;
        debugPrint(
            '  Isolate $i: ${batchesPerIsolate[i].length} batches, $totalMods mods');
      }

      // Create work data for each isolate
      final List<IsolateWorkData> isolateWorkData =
          batchesPerIsolate.map((batches) {
        // Get all mods for this isolate to prepare relevant cached data
        final allModsForIsolate = batches.expand((batch) => batch).toList();

        return IsolateWorkData(
          batches: batches,
          cachedDateTimeStamps: Map.fromEntries(allModsForIsolate.map((mod) =>
              MapEntry(
                  mod.jsonFileName, cachedDateTimeStamps[mod.jsonFileName]))),
          cachedAssetLists: Map.fromEntries(allModsForIsolate.map((mod) =>
              MapEntry(mod.jsonFileName, cachedAssetLists[mod.jsonFileName]))),
        );
      }).toList();

      debugPrint('Starting ${isolateWorkData.length} isolates in parallel...');

      // Process all isolates in parallel
      final List<IsolateWorkResult> allResults = await Future.wait(
        isolateWorkData
            .map((workData) =>
                Isolate.run(() => processMultipleBatchesInIsolate(workData)))
            .toList(),
      );

      debugPrint(
          'All isolates completed at ${DateTime.now()}. Processing results...');

      // Collect all results
      final List<Mod> allProcessedMods = [];
      final List<ModStorageUpdate> allStorageUpdates = [];

      for (final result in allResults) {
        allProcessedMods.addAll(result.processedMods);
        allStorageUpdates.addAll(result.storageUpdates);
      }

      if (allStorageUpdates.isNotEmpty) {
        debugPrint('Applying ${allStorageUpdates.length} storage updates...');
      }

      // Group updates by type for bulk operations
      Map<String, Map<String, String>> allModUrlsData = {};
      Map<String, String> allModMetadata = {};

      // Prepare for bulk save
      for (final update in allStorageUpdates) {
        allModUrlsData[update.jsonFileName] = update.jsonURLs;
        allModMetadata[update.jsonFileName] = update.jsonFileName;
        allModMetadata['${update.jsonFileName}${Storage.dateTimeStampSuffix}'] =
            update.dateTimeStamp;
      }

      if (allModUrlsData.isNotEmpty) {
        // Single bulk operation for all new/updated data
        await Future.wait([
          ref.read(storageProvider).saveAllModUrlsData(allModUrlsData),
          ref.read(storageProvider).saveAllModMetadata(allModMetadata),
        ]);
      }

      debugPrint('Bulk storage operations completed ${DateTime.now()}');

      debugPrint(
          'Processing asset lists for ${allProcessedMods.length} mods...');

      // Process asset lists in main isolate (requires access to providers)
      //final allMods = await processAssetListsChunked(allProcessedMods);
      List<Mod> allMods = [];
      for (final mod in allProcessedMods) {
        final jsonURLs =
            ref.read(storageProvider).getModAssetLists(mod.jsonFileName) ??
                <String, String>{};
        final finalMod = await _getModData(mod, jsonURLs);
        allMods.add(finalMod);
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

      // Sort all mods alphabetically
      allMods.sort((a, b) => a.saveName.compareTo(b.saveName));

      state = AsyncValue.data(ModsState(
        mods: allMods
            .where((element) => element.modType == ModTypeEnum.mod)
            .toList(),
        saves: allMods
            .where((element) => element.modType == ModTypeEnum.save)
            .toList(),
        savedObjects: allMods
            .where((element) => element.modType == ModTypeEnum.savedObject)
            .toList(),
      ));

      final endTime = DateTime.now();
      debugPrint('loadModsData END: $endTime');
      debugPrint('loadModsData total time: ${endTime.difference(startTime)}');

      if (onDataLoaded != null) {
        onDataLoaded();
      }
    } catch (e) {
      debugPrint('loadModsData error: $e');
      state = AsyncValue.error(e, StackTrace.current);
    }
  }

  /// Distributes batches evenly across the specified number of isolates
  List<List<List<Mod>>> _distributeBatchesAcrossIsolates(
      List<List<Mod>> batches, int numberOfIsolates) {
    final List<List<List<Mod>>> batchesPerIsolate = [];

    // Initialize empty lists for each isolate
    for (int i = 0; i < numberOfIsolates; i++) {
      batchesPerIsolate.add(<List<Mod>>[]);
    }

    final baseBatchesPerIsolate = batches.length ~/ numberOfIsolates;
    final remainder = batches.length % numberOfIsolates;

    int batchIndex = 0;
    for (int isolateIndex = 0;
        isolateIndex < numberOfIsolates;
        isolateIndex++) {
      final batchesForThisIsolate =
          baseBatchesPerIsolate + (isolateIndex < remainder ? 1 : 0);

      for (int j = 0; j < batchesForThisIsolate; j++) {
        if (batchIndex < batches.length) {
          batchesPerIsolate[isolateIndex].add(batches[batchIndex++]);
        }
      }
    }

    // Remove empty isolate work (shouldn't happen, but just in case)
    return batchesPerIsolate.where((batches) => batches.isNotEmpty).toList();
  }

  /// Creates adaptive batches based on file sizes and complexity
  Future<List<List<Mod>>> _createAdaptiveBatches(List<Mod> mods) async {
    const int targetBatchSizeBytes = 100 * 1024 * 1024; // 100MB per batch
    const int maxModsPerBatch = 100;
    const int minModsPerBatch = 5;

    List<List<Mod>> batches = [];
    List<Mod> currentBatch = [];
    int currentBatchSize = 0;

    for (final mod in mods) {
      int fileSizeInBytes = 0;
      try {
        final file = File(mod.jsonFilePath);
        fileSizeInBytes = await file.length();
      } catch (e) {
        debugPrint(
            '_createAdaptiveBatches - error getting file size for ${mod.jsonFilePath}: $e');
        // Skip files we can't read
        continue;
      }

      // Check if we should create a new batch
      final shouldCreateNewBatch = currentBatch.isNotEmpty &&
          (currentBatch.length >= maxModsPerBatch ||
              (currentBatchSize + fileSizeInBytes > targetBatchSizeBytes &&
                  currentBatch.length >= minModsPerBatch));

      if (shouldCreateNewBatch) {
        batches.add(List.from(currentBatch));
        currentBatch = [mod];
        currentBatchSize = fileSizeInBytes;
      } else {
        currentBatch.add(mod);
        currentBatchSize += fileSizeInBytes;
      }
    }

    // Add the last batch if it's not empty
    if (currentBatch.isNotEmpty) {
      batches.add(currentBatch);
    }

    // If we ended up with no batches somehow, create one with all mods
    if (batches.isEmpty && mods.isNotEmpty) {
      batches.add(mods);
    }

    return batches;
  }

  Future<void> updateMod(Mod selectedMod) async {
    try {
      if (!state.hasValue) {
        return;
      }

      Mod? updatedMod;

      final mods = switch (selectedMod.modType) {
            ModTypeEnum.mod => state.value?.mods,
            ModTypeEnum.save => state.value?.saves,
            ModTypeEnum.savedObject => state.value?.savedObjects,
          } ??
          [];

      final updatedMods = await Future.wait(mods.map((mod) async {
        if (mod.jsonFileName == selectedMod.jsonFileName) {
          updatedMod = await _getModData(
            mod,
            ref.read(storageProvider).getModAssetLists(mod.jsonFileName) ??
                await _extractUrlsFromJson(mod.jsonFilePath),
          );
          if (updatedMod != null) return updatedMod!;
        }
        return mod;
      }).toList());

      if (updatedMod != null) {
        setSelectedMod(updatedMod!);
      }

      switch (selectedMod.modType) {
        case ModTypeEnum.mod:
          state = AsyncValue.data(state.value!.copyWith(mods: updatedMods));
          break;

        case ModTypeEnum.save:
          state = AsyncValue.data(state.value!.copyWith(saves: updatedMods));
          break;

        case ModTypeEnum.savedObject:
          state =
              AsyncValue.data(state.value!.copyWith(savedObjects: updatedMods));
          break;
      }
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
    /*   final imageFilePath = mod.imageFilePath ??
        await _getImageFilePath(mod.jsonFilePath, mod.jsonFileName); */

    return mod.copyWith(
      //imageFilePath: imageFilePath,
      assetLists: assetLists.$1,
      totalCount: assetLists.$2,
      totalExistsCount: assetLists.$3,
    );
  }

  /* Future<String?> _getImageFilePath(
    String modDirectory,
    String fileName,
  ) async {
    String? imageFilePath;

    final imageWorkshopDir =
        path.join(path.dirname(modDirectory), '$fileName.png');

    if (await File(imageWorkshopDir).exists()) {
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
  } */

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

  Future<List<String>> _getJsonFilesInDirectory(
    String directoryPath, {
    String? excludeDirectory,
  }) async {
    final List<String> jsonFilePaths = [];

    try {
      final directory = Directory(directoryPath);

      if (!await directory.exists()) {
        return jsonFilePaths;
      }

      // List all files in the directory
      await for (final entity in directory.list(recursive: false)) {
        // TO DO NO COMMITO
        if (entity is File) {
          // Check if the file has a .json extension
          if (path.extension(entity.path).toLowerCase() == '.json') {
            // Skip files in excluded directory if specified
            if (excludeDirectory != null &&
                path.isWithin(excludeDirectory, entity.path)) {
              continue;
            }
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

  Future<void> updateModAsset({
    required Mod selectedMod,
    required Asset oldAsset,
    required AssetTypeEnum assetType,
    required String newAssetUrl,
  }) async {
    try {
      if (!state.hasValue) {
        return;
      }

      final mods = switch (selectedMod.modType) {
            ModTypeEnum.mod => state.value?.mods,
            ModTypeEnum.save => state.value?.saves,
            ModTypeEnum.savedObject => state.value?.savedObjects,
          } ??
          [];

      final updatedAssetLists = await _updateAssetInLists(
        selectedMod.assetLists,
        oldAsset,
        assetType,
        newAssetUrl,
      );

      final updatedMods = mods.map((mod) {
        if (mod.jsonFileName == selectedMod.jsonFileName) {
          return mod.copyWith(assetLists: updatedAssetLists);
        }
        return mod;
      }).toList();

      final updatedSelectedMod = updatedMods.firstWhereOrNull(
        (mod) => mod.jsonFileName == selectedMod.jsonFileName,
      );
      setSelectedMod(updatedSelectedMod);

      switch (selectedMod.modType) {
        case ModTypeEnum.mod:
          state = AsyncValue.data(state.value!.copyWith(mods: updatedMods));
          break;
        case ModTypeEnum.save:
          state = AsyncValue.data(state.value!.copyWith(saves: updatedMods));
          break;
        case ModTypeEnum.savedObject:
          state =
              AsyncValue.data(state.value!.copyWith(savedObjects: updatedMods));
          break;
      }
    } catch (e) {
      debugPrint('updateModAsset error: $e');
      state = AsyncValue.error(e, StackTrace.current);
    }
  }

  Future<AssetLists?> _updateAssetInLists(
    AssetLists? assetLists,
    Asset oldAsset,
    AssetTypeEnum assetType,
    String newAssetUrl,
  ) async {
    if (assetLists == null) return null;

    Future<List<Asset>> updateAssetList(List<Asset> assets) async {
      final newFilepath = oldAsset.filePath == null
          ? null
          : path.join(path.dirname(oldAsset.filePath!),
              '${getFileNameFromURL(newAssetUrl)}${path.extension(oldAsset.filePath!)}');
      final newFileExists =
          newFilepath != null ? await File(newFilepath).exists() : false;
      final newAsset = Asset(
        url: newAssetUrl,
        filePath: newFilepath,
        fileExists: newFileExists,
      );

      debugPrint('newAsset filepath: $newFilepath');
      debugPrint('newAsset url: $newAssetUrl');
      debugPrint('newAsset exists: $newFileExists');

      return assets.map((asset) {
        return asset.url == oldAsset.url ? newAsset : asset;
      }).toList();
    }

    switch (assetType) {
      case AssetTypeEnum.assetBundle:
        return assetLists.copyWith(
          assetBundles: await updateAssetList(assetLists.assetBundles),
        );

      case AssetTypeEnum.audio:
        return assetLists.copyWith(
          audio: await updateAssetList(assetLists.audio),
        );

      case AssetTypeEnum.image:
        return assetLists.copyWith(
          images: await updateAssetList(assetLists.images),
        );

      case AssetTypeEnum.model:
        return assetLists.copyWith(
          models: await updateAssetList(assetLists.models),
        );

      case AssetTypeEnum.pdf:
        return assetLists.copyWith(
          pdf: await updateAssetList(assetLists.pdf),
        );
    }
  }
}
