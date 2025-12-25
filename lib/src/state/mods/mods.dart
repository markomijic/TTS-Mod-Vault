import 'dart:io' show File, Platform;
import 'dart:isolate' show Isolate;
import 'dart:math' show max;

import 'package:collection/collection.dart' show IterableExtension;
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart' show VoidCallback, debugPrint;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show AsyncNotifier, AsyncValue, AsyncValueX;
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/src/state/asset/models/asset_lists_model.dart'
    show AssetLists;
import 'package:tts_mod_vault/src/state/asset/models/asset_model.dart'
    show Asset;
import 'package:tts_mod_vault/src/state/backup/backup_status_enum.dart'
    show ExistingBackupStatusEnum;
import 'package:tts_mod_vault/src/state/backup/models/existing_backup_model.dart'
    show ExistingBackup;
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
        UpdateUrlPrefixesParams,
        extractUrlsFromJson,
        extractUrlsFromJsonString,
        getJsonFilesInDirectory,
        processInitialModsInIsolate,
        processMultipleBatchesInIsolate,
        renameAssetFile,
        updateUrlPrefixesFilesIsolate;
import 'package:tts_mod_vault/src/state/mods/mods_state.dart' show ModsState;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        directoriesProvider,
        existingAssetListsProvider,
        existingBackupsProvider,
        loadingMessageProvider,
        selectedModProvider,
        settingsProvider,
        sortAndFilterProvider,
        storageProvider,
        multiSelectModsProvider;
import 'package:tts_mod_vault/src/state/storage/storage.dart' show Storage;
import 'package:tts_mod_vault/src/utils.dart'
    show getFileNameFromURL, newSteamUserContentUrl, oldCloudUrl;

class ModsStateNotifier extends AsyncNotifier<ModsState> {
  @override
  Future<ModsState> build() async {
    return ModsState(mods: [], saves: [], savedObjects: []);
  }

  List<Mod> getAllMods() {
    return state.maybeWhen(
      data: (state) => [...state.mods, ...state.saves, ...state.savedObjects],
      orElse: () => [],
    );
  }

  Future<void> loadModsData({
    VoidCallback? onDataLoaded,
    bool clearCache = false,
  }) async {
    final startTime = DateTime.now();
    debugPrint('loadModsData START: $startTime');

    ref.read(loadingMessageProvider.notifier).state = 'Loading';
    state = const AsyncValue.loading();

    try {
      if (clearCache) {
        await ref.read(storageProvider).clearAllModData();
      }
    } catch (e) {
      debugPrint("loadModsData - error on clearing cache: $e");
    }

    try {
      // Contains setting loading message provider
      await ref.read(existingBackupsProvider.notifier).loadExistingBackups();
    } catch (e) {
      debugPrint("loadModsData - error on loading existing backups: $e");
    }

    try {
      ref.read(loadingMessageProvider.notifier).state =
          'Loading existing asset files';

      await ref
          .read(existingAssetListsProvider.notifier)
          .loadExistingAssetsLists();

      ref.read(loadingMessageProvider.notifier).state =
          'Creating lists of items to load';

      final workshopDir = ref.read(directoriesProvider).workshopDir.toString();
      final savesDir = ref.read(directoriesProvider).savesDir.toString();
      final savedObjectsDir =
          ref.read(directoriesProvider).savedObjectsDir.toString();

      final jsonPathsFutures = [
        Isolate.run(() => getJsonFilesInDirectory(directoryPath: workshopDir)),
        Isolate.run(() => getJsonFilesInDirectory(
              directoryPath: savesDir,
              excludeDirectory: savedObjectsDir,
            )),
      ];

      final showSavedObjects = ref.read(settingsProvider).showSavedObjects;
      if (showSavedObjects) {
        jsonPathsFutures.add(Isolate.run(
            () => getJsonFilesInDirectory(directoryPath: savedObjectsDir)));
      }

      final jsonPaths = await Future.wait(jsonPathsFutures);

      debugPrint('loadModsData - getting initial mods ${DateTime.now()}');

      List<(ModTypeEnum type, List<String>)> allPaths = [
        (ModTypeEnum.mod, jsonPaths[0]),
        (ModTypeEnum.save, jsonPaths[1]),
      ];

      if (showSavedObjects) {
        allPaths.add((ModTypeEnum.savedObject, jsonPaths[2]));
      }

      final initialMods = await getInitialMods(allPaths);

      // Prepare cached data for all mods using bulk reads
      debugPrint('Loading cached data from storage');
      final allCachedDateTimeStamps =
          ref.read(storageProvider).getAllModDateTimeStamps();
      final allCachedUrls = ref.read(storageProvider).getAllModUrls();

      // Filter to only the mods we need
      final Map<String, String?> cachedDateTimeStamps = {};
      final Map<String, Map<String, String>?> cachedUrls = {};

      for (final mod in initialMods) {
        cachedDateTimeStamps[mod.jsonFileName] =
            allCachedDateTimeStamps[mod.jsonFileName];
        cachedUrls[mod.jsonFileName] = allCachedUrls[mod.jsonFileName];
      }

      // Create adaptive batches based on file sizes
      debugPrint('loadModsData - creating adaptive batches, ${DateTime.now()}');
      final List<List<Mod>> adaptiveBatches =
          await _createAdaptiveBatches(initialMods);
      debugPrint(
          'loadModsData - created ${adaptiveBatches.length} adaptive batches');

      // Distribute batches across isolates
      final numberOfIsolates = max(Platform.numberOfProcessors - 2, 2);
      debugPrint(
          'Using $numberOfIsolates isolates for ${adaptiveBatches.length} batches');

      final batchesPerIsolate =
          _distributeBatchesAcrossIsolates(adaptiveBatches, numberOfIsolates);
      debugPrint('Batch distribution:');
      for (int i = 0; i < batchesPerIsolate.length; i++) {
        final totalMods = batchesPerIsolate[i].expand((batch) => batch).length;
        debugPrint(
            '  Isolate $i: ${batchesPerIsolate[i].length} batches, $totalMods mods');
      }

      // Create work data for each isolate
      final ignoreAudio = ref.read(settingsProvider).ignoreAudioAssets;
      final existingAssets = ref.read(existingAssetListsProvider);

      final List<IsolateWorkData> isolateWorkData =
          batchesPerIsolate.map((batches) {
        // Get all mods for this isolate to prepare relevant cached data
        final allModsForIsolate = batches.expand((batch) => batch).toList();

        return IsolateWorkData(
          batches: batches,
          cachedDateTimeStamps:
              Map.fromEntries(allModsForIsolate.map((mod) => MapEntry(
                    mod.jsonFileName,
                    cachedDateTimeStamps[mod.jsonFileName],
                  ))),
          cachedAssetLists:
              Map.fromEntries(allModsForIsolate.map((mod) => MapEntry(
                    mod.jsonFileName,
                    cachedUrls[mod.jsonFileName],
                  ))),
          ignoreAudioAssets: ignoreAudio,
          // Pass asset maps for O(1) existence checks in isolate
          existingAssetBundles: existingAssets.assetBundles,
          existingAudio: existingAssets.audio,
          existingImages: existingAssets.images,
          existingModels: existingAssets.models,
          existingPdf: existingAssets.pdf,
        );
      }).toList();

      debugPrint('Starting ${isolateWorkData.length} isolates in parallel');

      ref.read(loadingMessageProvider.notifier).state = showSavedObjects
          ? 'Loading ${jsonPaths[0].length} mods, ${jsonPaths[1].length} saves and ${jsonPaths[2].length} saved objects'
          : 'Loading ${jsonPaths[0].length} mods and ${jsonPaths[1].length} saves';

      final List<IsolateWorkResult> allResults = await Future.wait(
        isolateWorkData
            .map((workData) =>
                Isolate.run(() => processMultipleBatchesInIsolate(workData)))
            .toList(),
      );

      debugPrint(
          'All isolates completed at ${DateTime.now()}. Processing results...');

      final List<Mod> allProcessedMods = [];
      final List<ModStorageUpdate> allStorageUpdates = [];

      for (final result in allResults) {
        allProcessedMods.addAll(result.processedMods);
        allStorageUpdates.addAll(result.storageUpdates);
      }

      // Bulk save storage updates
      Map<String, Map<String, String>> allModUrlsData = {};
      Map<String, String> allModMetadata = {};

      for (final update in allStorageUpdates) {
        allModUrlsData[update.jsonFileName] = update.jsonURLs;
        allModMetadata[update.jsonFileName] = update.jsonFileName;
        allModMetadata['${update.jsonFileName}${Storage.dateTimeStampSuffix}'] =
            update.dateTimeStamp;
      }

      if (allStorageUpdates.isNotEmpty) {
        debugPrint('Applying ${allStorageUpdates.length} storage updates...');
        ref.read(loadingMessageProvider.notifier).state =
            'Updating cached data';

        await Future.wait([
          ref.read(storageProvider).saveAllModUrlsData(allModUrlsData),
          ref.read(storageProvider).saveAllModMetadata(allModMetadata),
        ]);

        debugPrint('Bulk storage operations completed ${DateTime.now()}');
      }

      final mods = <Mod>[];
      final saves = <Mod>[];
      final savedObjects = <Mod>[];

      for (final mod in allProcessedMods) {
        switch (mod.modType) {
          case ModTypeEnum.mod:
            mods.add(_getInitialModWithBackup(mod));
            break;
          case ModTypeEnum.save:
            saves.add(_getInitialModWithBackup(mod));
            break;
          case ModTypeEnum.savedObject:
            if (showSavedObjects) {
              savedObjects.add(_getInitialModWithBackup(mod));
            }
            break;
        }
      }

      // Set filters state
      ref.read(sortAndFilterProvider.notifier).resetState();
      ref.read(sortAndFilterProvider.notifier).setFolders(allProcessedMods);

      // Artificial delay to ensure at least 500ms of visual refresh indicator
      final stateEndTime = DateTime.now();
      final elapsed = stateEndTime.difference(startTime);
      if (elapsed < Duration(milliseconds: 500)) {
        final remainingTime = Duration(milliseconds: 500) - elapsed;
        await Future.delayed(remainingTime);
      }

      state = AsyncValue.data(ModsState(
        mods: mods,
        saves: saves,
        savedObjects: savedObjects,
      ));

      final selectedMod = ref.read(selectedModProvider);

      // If there was previously a mod selected - update selected mod
      if (selectedMod != null) {
        final mod = allProcessedMods.firstWhereOrNull(
            (m) => m.jsonFilePath == selectedMod.jsonFilePath);

        if (mod != null) {
          updateSelectedMod(mod);
        } else {
          resetSelectedMod();
        }
      }

      final endTime = DateTime.now();
      debugPrint('loadModsData END: $endTime');
      debugPrint('loadModsData total time: ${endTime.difference(startTime)}');

      // Used in Loader
      if (onDataLoaded != null) {
        onDataLoaded();
      }
    } catch (e) {
      debugPrint('loadModsData error: $e');
      state = AsyncValue.error(e, StackTrace.current);
    }
  }

  Future<List<Mod>> getInitialMods(
    List<(ModTypeEnum type, List<String>)> allPaths,
  ) async {
    List<Mod> allMods = [];
    int allPathsLength = 0;

    for (final paths in allPaths) {
      allPathsLength += paths.$2.length;
    }

    if (allPathsLength == 0) {
      return [];
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
    const int targetBatchSizeBytes = 50 * 1024 * 1024; // 50MB per batch
    const int maxModsPerBatch = 100;
    const int minModsPerBatch = 5;
    const int parallelStatChunkSize = 100; // Process 100 file stats at a time

    // Get all file sizes in parallel chunks
    final List<(Mod, int)> modsWithSizes = [];

    for (int i = 0; i < mods.length; i += parallelStatChunkSize) {
      final chunk = mods.skip(i).take(parallelStatChunkSize).toList();

      // Process this chunk in parallel
      final chunkResults = await Future.wait(
        chunk.map((mod) async {
          try {
            final file = File(mod.jsonFilePath);
            return (mod, await file.length());
          } catch (e) {
            debugPrint(
                '_createAdaptiveBatches - error getting file size for ${mod.jsonFilePath}: $e');
            return (mod, 0);
          }
        }),
      );

      modsWithSizes.addAll(chunkResults);
    }

    // Now create batches using the sizes we collected
    List<List<Mod>> batches = [];
    List<Mod> currentBatch = [];
    int currentBatchSize = 0;

    for (final (mod, fileSizeInBytes) in modsWithSizes) {
      if (fileSizeInBytes == 0) continue; // Skip files we couldn't read

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

    // If there are no batches, create one with all mods
    if (batches.isEmpty && mods.isNotEmpty) {
      batches.add(mods);
    }

    return batches;
  }

  Future<Map<String, String>> getUrlsByMod(Mod mod,
      [bool forceExtraction = false]) async {
    if (forceExtraction) {
      return await extractUrlsFromJson(mod.jsonFilePath);
    }

    return ref.read(storageProvider).getModUrls(mod.jsonFileName) ??
        await extractUrlsFromJson(mod.jsonFilePath);
  }

  Future<void> updateSelectedMod(Mod selectedMod) async {
    try {
      if (!state.hasValue) return;

      final modList = switch (selectedMod.modType) {
        ModTypeEnum.mod => state.value!.mods,
        ModTypeEnum.save => state.value!.saves,
        ModTypeEnum.savedObject => state.value!.savedObjects,
      };

      final modIndex = modList.indexWhere(
        (m) => m.jsonFilePath == selectedMod.jsonFilePath,
      );

      if (modIndex == -1) return;

      final urls =
          ref.read(storageProvider).getModUrls(selectedMod.jsonFileName) ??
              await extractUrlsFromJson(selectedMod.jsonFilePath);

      final updatedMod = await getCompleteMod(selectedMod, urls);

      final updatedList = [...modList];
      updatedList[modIndex] = updatedMod;

      setSelectedMod(updatedMod);

      switch (selectedMod.modType) {
        case ModTypeEnum.mod:
          state = AsyncValue.data(state.value!.copyWith(mods: updatedList));
          break;
        case ModTypeEnum.save:
          state = AsyncValue.data(state.value!.copyWith(saves: updatedList));
          break;
        case ModTypeEnum.savedObject:
          state =
              AsyncValue.data(state.value!.copyWith(savedObjects: updatedList));
          break;
      }
    } catch (e, stack) {
      debugPrint('updateSelectedMod error: $e');
      state = AsyncValue.error(e, stack);
    }
  }

  void updateMod(Mod mod) {
    try {
      if (!state.hasValue) return;

      final modList = switch (mod.modType) {
        ModTypeEnum.mod => state.value!.mods,
        ModTypeEnum.save => state.value!.saves,
        ModTypeEnum.savedObject => state.value!.savedObjects,
      };

      final normalizedPath = p.normalize(mod.jsonFilePath);
      final modIndex = modList.indexWhere(
        (m) => p.normalize(m.jsonFilePath) == normalizedPath,
      );

      if (modIndex == -1) return;

      final updatedList = [...modList];
      updatedList[modIndex] = mod;

      switch (mod.modType) {
        case ModTypeEnum.mod:
          state = AsyncValue.data(state.value!.copyWith(mods: updatedList));
          break;
        case ModTypeEnum.save:
          state = AsyncValue.data(state.value!.copyWith(saves: updatedList));
          break;
        case ModTypeEnum.savedObject:
          state =
              AsyncValue.data(state.value!.copyWith(savedObjects: updatedList));
          break;
      }
    } catch (e, stack) {
      debugPrint('updateMod error: $e');
      state = AsyncValue.error(e, stack);
    }
  }

  Future<void> addSingleMod(String jsonFilePath, ModTypeEnum modType) async {
    debugPrint('addSingleMod - path: $jsonFilePath, type: ${modType.label}');

    try {
      if (!state.hasValue) return;

      final initialMod = await Isolate.run(
          () => processInitialModsInIsolate(InitialModsIsolateData(
                jsonsPaths: [p.normalize(jsonFilePath)],
                modType: modType,
              )));

      if (initialMod.isEmpty) {
        debugPrint('addSingleMod - failed to create initial mod');
        return;
      }

      final newMod = initialMod.first;

      // Get URLs and complete mod data
      final urls = await extractUrlsFromJson(newMod.jsonFilePath);
      final completeMod = await getCompleteMod(newMod, urls);

      // Save to storage
      final Map<String, String> metadata = {
        newMod.jsonFileName: newMod.jsonFileName,
      };
      if (newMod.dateTimeStamp != null) {
        metadata['${newMod.jsonFileName}${Storage.dateTimeStampSuffix}'] =
            newMod.dateTimeStamp!;
      }

      await Future.wait([
        ref.read(storageProvider).updateModUrls(newMod.jsonFileName, urls),
        ref.read(storageProvider).saveAllModMetadata(metadata),
      ]);

      // Add to appropriate list or replace if already exists
      final currentState = state.value!;
      final normalizedPath = p.normalize(completeMod.jsonFilePath);

      switch (modType) {
        case ModTypeEnum.mod:
          final existingIndex = currentState.mods.indexWhere(
              (mod) => p.normalize(mod.jsonFilePath) == normalizedPath);
          final updatedList = existingIndex >= 0
              ? [
                  ...currentState.mods.sublist(0, existingIndex),
                  completeMod,
                  ...currentState.mods.sublist(existingIndex + 1),
                ]
              : [...currentState.mods, completeMod];
          state = AsyncValue.data(currentState.copyWith(mods: updatedList));
          ref
              .read(sortAndFilterProvider.notifier)
              .addModFolder(completeMod.parentFolderName);
          break;
        case ModTypeEnum.save:
          final existingIndex = currentState.saves.indexWhere(
              (mod) => p.normalize(mod.jsonFilePath) == normalizedPath);
          final updatedList = existingIndex >= 0
              ? [
                  ...currentState.saves.sublist(0, existingIndex),
                  completeMod,
                  ...currentState.saves.sublist(existingIndex + 1),
                ]
              : [...currentState.saves, completeMod];
          state = AsyncValue.data(currentState.copyWith(saves: updatedList));
          ref
              .read(sortAndFilterProvider.notifier)
              .addSaveFolder(completeMod.parentFolderName);
          break;
        case ModTypeEnum.savedObject:
          final existingIndex = currentState.savedObjects.indexWhere(
              (mod) => p.normalize(mod.jsonFilePath) == normalizedPath);
          final updatedList = existingIndex >= 0
              ? [
                  ...currentState.savedObjects.sublist(0, existingIndex),
                  completeMod,
                  ...currentState.savedObjects.sublist(existingIndex + 1),
                ]
              : [...currentState.savedObjects, completeMod];
          state =
              AsyncValue.data(currentState.copyWith(savedObjects: updatedList));
          ref
              .read(sortAndFilterProvider.notifier)
              .addSavedObjectFolder(completeMod.parentFolderName);
          break;
      }

      // Set as selected mod
      setSelectedMod(completeMod);
    } catch (e, stack) {
      debugPrint('addSingleMod error: $e');
      state = AsyncValue.error(e, stack);
    }
  }

  Mod _getInitialModWithBackup(Mod mod) {
    try {
      final backup =
          ref.read(existingBackupsProvider.notifier).getBackupByMod(mod);

      final backupStatus = backup == null
          ? ExistingBackupStatusEnum.noBackup
          : (mod.dateTimeStamp == null ||
                  backup.lastModifiedTimestamp > int.parse(mod.dateTimeStamp!))
              ? ExistingBackupStatusEnum.upToDate
              : ExistingBackupStatusEnum.outOfDate;

      return mod.copyWith(backup: backup, backupStatus: backupStatus);
    } catch (e) {
      return mod;
    }
  }

  Future<Mod> getCompleteMod(Mod mod, Map<String, String> jsonURLs) async {
    ExistingBackup? backup =
        ref.read(existingBackupsProvider.notifier).getBackupByMod(mod);

    if (backup != null && backup.totalAssetCount == null) {
      final backupTotalAssetCount = await ref
          .read(existingBackupsProvider.notifier)
          .listZipContents(backup.filepath);

      backup = backup.copyWith(totalAssetCount: backupTotalAssetCount);
      ref.read(existingBackupsProvider.notifier).addBackup(backup);
    }

    final backupStatus = backup == null
        ? ExistingBackupStatusEnum.noBackup
        : (mod.dateTimeStamp == null ||
                backup.lastModifiedTimestamp > int.parse(mod.dateTimeStamp!))
            ? ExistingBackupStatusEnum.upToDate
            : ExistingBackupStatusEnum.outOfDate;

    final assetLists = _getAssetListsFromUrls(jsonURLs);

    return mod.copyWith(
      backup: backup,
      backupStatus: backupStatus,
      assetLists: assetLists.$1,
      assetCount: assetLists.$2,
      existingAssetCount: assetLists.$3,
      missingAssetCount: assetLists.$2 - assetLists.$3,
    );
  }

  Map<String, String> _getAssetMapByType(AssetTypeEnum type) {
    final existingAssets = ref.read(existingAssetListsProvider);
    return switch (type) {
      AssetTypeEnum.assetBundle => existingAssets.assetBundles,
      AssetTypeEnum.audio => existingAssets.audio,
      AssetTypeEnum.image => existingAssets.images,
      AssetTypeEnum.model => existingAssets.models,
      AssetTypeEnum.pdf => existingAssets.pdf,
    };
  }

  List<Asset> _getAssetsByType(List<String> urls, AssetTypeEnum type) {
    final assetMap = _getAssetMapByType(type);

    return urls.map((url) {
      final normalizedUrl = url.replaceAll(oldCloudUrl, newSteamUserContentUrl);
      final filename = getFileNameFromURL(normalizedUrl);
      final filepath = assetMap[filename]; // O(1) lookup!

      return Asset(
        url: normalizedUrl,
        fileExists: filepath != null,
        filePath: filepath,
      );
    }).toList();
  }

  // TODO remove/replace with isolate method?
  (AssetLists, int, int) _getAssetListsFromUrls(Map<String, String> data) {
    final ignoreAudio = ref.read(settingsProvider).ignoreAudioAssets;

    Map<AssetTypeEnum, List<String>> urlsByType = {
      for (final type in AssetTypeEnum.values) type: [],
    };

    for (final element in data.entries) {
      for (final assetType in AssetTypeEnum.values) {
        if (ignoreAudio && assetType == AssetTypeEnum.audio) {
          continue;
        }

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

  void setSelectedMod(Mod mod) {
    ref.read(multiSelectModsProvider.notifier).state = {mod.jsonFilePath};
    ref.read(selectedModProvider.notifier).state = mod;
  }

  void resetSelectedMod() {
    ref.read(selectedModProvider.notifier).state = null;
  }

  Future<void> updateModAsset({
    required Mod selectedMod,
    required Asset oldAsset,
    required AssetTypeEnum assetType,
    required String newAssetUrl,
    required bool renameFile,
  }) async {
    try {
      if (!state.hasValue) {
        return;
      }

      await _replaceUrlInJsonFile(
          selectedMod.jsonFilePath, oldAsset.url, newAssetUrl);

      if (renameFile && oldAsset.filePath != null) {
        await renameAssetFile(oldAsset.filePath!, newAssetUrl);
        await ref
            .read(existingAssetListsProvider.notifier)
            .setExistingAssetsListByType(assetType);
      }

      final jsonURLs = await getUrlsByMod(selectedMod, true);
      final completeMod = await getCompleteMod(selectedMod, jsonURLs);

      await ref
          .read(storageProvider)
          .updateModUrls(selectedMod.jsonFileName, jsonURLs);

      updateMod(completeMod);
      setSelectedMod(completeMod);
    } catch (e) {
      debugPrint('updateModAsset error: $e');
      state = AsyncValue.error(e, StackTrace.current);
    }
  }

  Future<void> _replaceUrlInJsonFile(
    String filePath,
    String oldUrl,
    String newUrl,
  ) async {
    String jsonString = await File(filePath).readAsString();

    final oldUrlAsCloudUrl = oldUrl.startsWith(newSteamUserContentUrl)
        ? oldUrl.replaceFirst(newSteamUserContentUrl, oldCloudUrl)
        : '';

    final targetUrl =
        oldUrlAsCloudUrl.isNotEmpty && jsonString.contains(oldUrlAsCloudUrl)
            ? oldUrlAsCloudUrl
            : oldUrl;

    await File(filePath)
        .writeAsString(jsonString.replaceAll(targetUrl, newUrl));
  }

  Future<void> updateUrlPrefixes(
    Mod mod,
    List<String> oldPrefixes,
    String newPrefix,
    bool renameFile,
  ) async {
    final assets = Map.fromEntries(
        mod.getAllAssets().map((a) => MapEntry(a.url, a.filePath)));
    final modJsonFilePath = mod.jsonFilePath;

    final result = await compute(
      updateUrlPrefixesFilesIsolate,
      UpdateUrlPrefixesParams(
        modJsonFilePath,
        oldPrefixes,
        newPrefix,
        renameFile,
        assets,
      ),
    );

    if (result.updated) {
      await ref
          .read(existingAssetListsProvider.notifier)
          .loadExistingAssetsLists();

      final jsonURLs = extractUrlsFromJsonString(result.jsonString);
      final completeMod = await getCompleteMod(mod, jsonURLs);

      await ref.read(storageProvider).updateModUrls(mod.jsonFileName, jsonURLs);

      updateMod(completeMod);
      setSelectedMod(completeMod);
    }
  }
}
