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
    show AudioAssetVisibility, InitialMod, Mod, ModTypeEnum;
import 'package:tts_mod_vault/src/state/mods/mods_isolates.dart'
    show
        InitialModsIsolateData,
        IsolateWorkData,
        IsolateWorkResult,
        ModStorageUpdate,
        UpdateUrlPrefixesParams,
        createAdaptiveBatchesInIsolate,
        extractUrlsFromJson,
        extractUrlsFromJsonString,
        getJsonFilesInDirectory,
        processInitialModsInIsolate,
        processMultipleBatchesInIsolate,
        renameAssetFile,
        buildAssetListsFromUrls,
        updateUrlPrefixesFilesIsolate;
import 'package:tts_mod_vault/src/state/mods/mods_state.dart' show ModsState;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        backupCacheProvider,
        directoriesProvider,
        existingAssetListsProvider,
        existingBackupsProvider,
        loadingMessageProvider,
        settingsProvider,
        sortAndFilterProvider,
        refreshingSharedAssetsProvider,
        storageProvider,
        multiModsProvider;
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
        await ref.read(backupCacheProvider).clear();
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
      final ignoredSubfolders = ref.read(settingsProvider).ignoredSubfolders;

      final jsonPathsFutures = [
        Isolate.run(() => getJsonFilesInDirectory(
              directoryPath: workshopDir,
              ignoredSubfolders: ignoredSubfolders,
            )),
        Isolate.run(() => getJsonFilesInDirectory(
              directoryPath: savesDir,
              ignoredSubfolders: ["Saved Objects", ...ignoredSubfolders],
            )),
      ];

      final showSavedObjects = ref.read(settingsProvider).showSavedObjects;
      if (showSavedObjects) {
        jsonPathsFutures.add(Isolate.run(() => getJsonFilesInDirectory(
              directoryPath: savedObjectsDir,
              ignoredSubfolders: ignoredSubfolders,
            )));
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

      // Prune storage entries for mods no longer on disk
      final validJsonFileNames = initialMods.map((m) => m.jsonFileName).toSet();
      await ref.read(storageProvider).pruneOrphanedModData(validJsonFileNames);

      // Prepare cached data for all mods using bulk reads
      debugPrint('Loading cached data from storage');
      final allCachedDateTimeStamps =
          ref.read(storageProvider).getAllModDateTimeStamps();
      final allCachedUrls = ref.read(storageProvider).getAllModUrls();
      final allAudioPreferences =
          ref.read(storageProvider).getAllModAudioPreferences();

      // Filter to only the mods we need
      final Map<String, String?> cachedDateTimeStamps = {};
      final Map<String, Map<String, String>?> cachedUrls = {};
      final Map<String, AudioAssetVisibility> audioPreferences = {};

      for (final mod in initialMods) {
        cachedDateTimeStamps[mod.jsonFileName] =
            allCachedDateTimeStamps[mod.jsonFileName];
        cachedUrls[mod.jsonFileName] = allCachedUrls[mod.jsonFileName];
        audioPreferences[mod.jsonFileName] =
            allAudioPreferences[mod.jsonFileName] ??
                AudioAssetVisibility.useGlobalSetting;
      }

      // Create adaptive batches based on file sizes
      debugPrint('loadModsData - creating adaptive batches, ${DateTime.now()}');
      final List<List<InitialMod>> adaptiveBatches =
          await Isolate.run(() => createAdaptiveBatchesInIsolate(initialMods));
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
          modAudioPreferences:
              Map.fromEntries(allModsForIsolate.map((mod) => MapEntry(
                    mod.jsonFileName,
                    audioPreferences[mod.jsonFileName] ??
                        AudioAssetVisibility.useGlobalSetting,
                  ))),
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
        // Apply audio preference to mod
        final modWithPreference = Mod(
          modType: mod.modType,
          jsonFilePath: mod.jsonFilePath,
          jsonFileName: mod.jsonFileName,
          parentFolderName: mod.parentFolderName,
          saveName: mod.saveName,
          createdAtTimestamp: mod.createdAtTimestamp,
          lastModifiedTimestamp: mod.lastModifiedTimestamp,
          dateTimeStamp: mod.dateTimeStamp,
          imageFilePath: mod.imageFilePath,
          backupStatus: mod.backupStatus,
          backup: mod.backup,
          assetLists: mod.assetLists,
          assetCount: mod.assetCount,
          existingAssetCount: mod.existingAssetCount,
          hasAudioAssets: mod.hasAudioAssets,
          audioVisibility:
              audioPreferences[mod.jsonFileName] ?? mod.audioVisibility,
        );

        switch (modWithPreference.modType) {
          case ModTypeEnum.mod:
            mods.add(_getModWithBackup(modWithPreference));
            break;
          case ModTypeEnum.save:
            saves.add(_getModWithBackup(modWithPreference));
            break;
          case ModTypeEnum.savedObject:
            if (showSavedObjects) {
              savedObjects.add(_getModWithBackup(modWithPreference));
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

      final multiMods = ref.read(multiModsProvider);

      // If there was previously one mod selected - check if it still exists
      if (multiMods.length == 1) {
        final mod = allProcessedMods
            .firstWhereOrNull((m) => m.jsonFilePath == multiMods.first);

        if (mod == null) {
          resetSelectedMod();
        }
      } else {
        resetSelectedMod(); // TODO rename this + setSelectedMod
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

  Future<List<InitialMod>> getInitialMods(
    List<(ModTypeEnum type, List<String>)> allPaths,
  ) async {
    List<InitialMod> allMods = [];
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
    List<Future<List<InitialMod>>> futures = [];

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
  List<List<List<InitialMod>>> _distributeBatchesAcrossIsolates(
      List<List<InitialMod>> batches, int numberOfIsolates) {
    final List<List<List<InitialMod>>> batchesPerIsolate = [];

    // Initialize empty lists for each isolate
    for (int i = 0; i < numberOfIsolates; i++) {
      batchesPerIsolate.add(<List<InitialMod>>[]);
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

  Future<Map<String, String>> getUrlsByMod(Mod mod,
      [bool forceExtraction = false]) async {
    if (forceExtraction) {
      return await extractUrlsFromJson(mod.jsonFilePath);
    }

    return ref.read(storageProvider).getModUrls(mod.jsonFileName) ??
        await extractUrlsFromJson(mod.jsonFilePath);
  }

  // TODO remove & replace with getCompleteMod + updateMod?
  Future<Mod> updateSelectedMod(Mod selectedMod) async {
    try {
      if (!state.hasValue) return selectedMod;

      final modList = switch (selectedMod.modType) {
        ModTypeEnum.mod => state.value!.mods,
        ModTypeEnum.save => state.value!.saves,
        ModTypeEnum.savedObject => state.value!.savedObjects,
      };

      final modIndex = modList.indexWhere(
        (m) => m.jsonFilePath == selectedMod.jsonFilePath,
      );

      if (modIndex == -1) return selectedMod;

      final urls =
          ref.read(storageProvider).getModUrls(selectedMod.jsonFileName) ??
              await extractUrlsFromJson(selectedMod.jsonFilePath);

      final updatedMod = await getCompleteMod(selectedMod, urls);

      final updatedList = [...modList];
      updatedList[modIndex] = updatedMod;

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

      return updatedMod;
    } catch (e, stack) {
      debugPrint('updateSelectedMod error: $e');
      state = AsyncValue.error(e, stack);
    }

    return selectedMod;
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
      final tempMod = Mod.fromInitial(
        newMod,
        assetLists: AssetLists(
            assetBundles: [], audio: [], images: [], models: [], pdf: []),
        assetCount: 0,
        existingAssetCount: 0,
        missingAssetCount: 0,
        audioVisibility: AudioAssetVisibility.useGlobalSetting,
        hasAudioAssets: false,
      );
      final completeMod = await getCompleteMod(tempMod, urls);

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

  Mod _getModWithBackup(Mod mod) {
    try {
      final backup =
          ref.read(existingBackupsProvider.notifier).getBackupByMod(mod);

      return Mod(
        modType: mod.modType,
        jsonFilePath: mod.jsonFilePath,
        jsonFileName: mod.jsonFileName,
        parentFolderName: mod.parentFolderName,
        saveName: mod.saveName,
        createdAtTimestamp: mod.createdAtTimestamp,
        lastModifiedTimestamp: mod.lastModifiedTimestamp,
        dateTimeStamp: mod.dateTimeStamp,
        imageFilePath: mod.imageFilePath,
        assetLists: mod.assetLists,
        assetCount: mod.assetCount,
        existingAssetCount: mod.existingAssetCount,
        audioVisibility: mod.audioVisibility,
        hasAudioAssets: mod.hasAudioAssets,
        backupStatus: getModBackupStatus(
          backup,
          mod.dateTimeStamp,
          mod.existingAssetCount,
        ),
        backup: backup,
      );
    } catch (e) {
      return mod;
    }
  }

  Future<Mod> getCompleteMod(
    Mod mod,
    Map<String, String> jsonURLs, {
    bool refreshLastModified = false,
  }) async {
    ExistingBackup? backup =
        ref.read(existingBackupsProvider.notifier).getBackupByMod(mod);

    final assetLists = _getAssetListsFromUrls(jsonURLs, mod);

    int lastModifiedTimestamp = mod.lastModifiedTimestamp;
    if (refreshLastModified) {
      final fileStat = await File(mod.jsonFilePath).stat();
      lastModifiedTimestamp = fileStat.modified.microsecondsSinceEpoch ~/ 1000;
    }

    // Creating new Mod object because copyWith returns previous backup value if new one is null
    return Mod(
      modType: mod.modType,
      jsonFilePath: mod.jsonFilePath,
      jsonFileName: mod.jsonFileName,
      parentFolderName: mod.parentFolderName,
      saveName: mod.saveName,
      createdAtTimestamp: mod.createdAtTimestamp,
      lastModifiedTimestamp: lastModifiedTimestamp,
      dateTimeStamp: mod.dateTimeStamp,
      imageFilePath: mod.imageFilePath,
      backup: backup,
      backupStatus: getModBackupStatus(
        backup,
        mod.dateTimeStamp,
        assetLists.$3,
      ),
      assetLists: assetLists.$1,
      assetCount: assetLists.$2,
      existingAssetCount: assetLists.$3,
      hasAudioAssets: assetLists.$4,
      audioVisibility: mod.audioVisibility,
    );
  }

  ExistingBackupStatusEnum getModBackupStatus(
    ExistingBackup? backup,
    String? dateTimeStamp,
    int existingAssetCount,
  ) {
    ExistingBackupStatusEnum backupStatus = ExistingBackupStatusEnum.noBackup;

    if (backup != null) {
      if (dateTimeStamp == null ||
          backup.lastModifiedTimestamp > int.parse(dateTimeStamp)) {
        if (backup.totalAssetCount != existingAssetCount) {
          backupStatus = ExistingBackupStatusEnum.assetCountMismatch;
        } else {
          backupStatus = ExistingBackupStatusEnum.upToDate;
        }
      } else {
        backupStatus = ExistingBackupStatusEnum.outOfDate;
      }
    }
    return backupStatus;
  }

  /// Finds all mods that reference any of the [affectedFilenames] and
  /// re-processes their asset lists against the current existingAssetListsProvider.
  /// Skips [excludeJsonFileName] (typically the already-updated selected mod).
  /// Heavy computation runs in isolates to avoid UI lag.
  Future<void> refreshModsWithSharedAssets(
    Set<String> affectedFilenames, {
    String? excludeJsonFileName,
  }) async {
    if (!state.hasValue || affectedFilenames.isEmpty) return;

    ref.read(refreshingSharedAssetsProvider.notifier).state = true;
    try {
      // 1. Read all data on UI thread (fast provider reads)
      final allModUrls = ref.read(storageProvider).getAllModUrls();
      final existingAssets = ref.read(existingAssetListsProvider);
      final ignoreAudioGlobal = ref.read(settingsProvider).ignoreAudioAssets;
      final allMods = getAllMods();
      final modAudioPreferences = <String, AudioAssetVisibility>{};
      for (final mod in allMods) {
        modAudioPreferences[mod.jsonFileName] = mod.audioVisibility;
      }

      // 2. Find affected mods in isolate
      final affectedModJsonFileNames = await Isolate.run(
        () => _findAffectedModsStatic(
            allModUrls, affectedFilenames, excludeJsonFileName),
      );

      if (affectedModJsonFileNames.isEmpty) return;

      // 3. Recompute asset lists in isolate
      final recomputedResults = await Isolate.run(
        () => _recomputeAffectedModAssetsStatic(
          affectedModJsonFileNames: affectedModJsonFileNames,
          allModUrls: allModUrls,
          assetBundles: existingAssets.assetBundles,
          audio: existingAssets.audio,
          images: existingAssets.images,
          models: existingAssets.models,
          pdf: existingAssets.pdf,
          ignoreAudioGlobal: ignoreAudioGlobal,
          modAudioPreferences: modAudioPreferences,
        ),
      );

      // 4. Apply updates in a single batch on UI thread
      final recomputedMap = <String, (AssetLists, int, int, bool)>{};
      for (final result in recomputedResults) {
        recomputedMap[result.$1] = (result.$2, result.$3, result.$4, result.$5);
      }

      final updatedMods = <Mod>[];
      for (final mod in allMods) {
        final recomputed = recomputedMap[mod.jsonFileName];
        if (recomputed == null) continue;

        updatedMods.add(Mod(
          modType: mod.modType,
          jsonFilePath: mod.jsonFilePath,
          jsonFileName: mod.jsonFileName,
          parentFolderName: mod.parentFolderName,
          saveName: mod.saveName,
          createdAtTimestamp: mod.createdAtTimestamp,
          lastModifiedTimestamp: mod.lastModifiedTimestamp,
          dateTimeStamp: mod.dateTimeStamp,
          imageFilePath: mod.imageFilePath,
          backup: mod.backup,
          backupStatus: getModBackupStatus(
            mod.backup,
            mod.dateTimeStamp,
            recomputed.$3,
          ),
          audioVisibility: mod.audioVisibility,
          assetLists: recomputed.$1,
          assetCount: recomputed.$2,
          existingAssetCount: recomputed.$3,
          hasAudioAssets: recomputed.$4,
        ));
      }

      updateModsBatch(updatedMods);
    } finally {
      ref.read(refreshingSharedAssetsProvider.notifier).state = false;
    }
  }

  /// Finds which mod jsonFileNames reference any of the affected filenames.
  /// Runs in an isolate.
  static Set<String> _findAffectedModsStatic(
    Map<String, Map<String, String>?> allModUrls,
    Set<String> affectedFilenames,
    String? excludeJsonFileName,
  ) {
    final affectedModJsonFileNames = <String>{};

    for (final entry in allModUrls.entries) {
      final modJsonFileName = entry.key;
      if (modJsonFileName == excludeJsonFileName) continue;

      final urls = entry.value;
      if (urls == null) continue;

      for (final url in urls.keys) {
        if (affectedFilenames.contains(getFileNameFromURL(url))) {
          affectedModJsonFileNames.add(modJsonFileName);
          break;
        }
      }
    }

    return affectedModJsonFileNames;
  }

  /// Recomputes asset lists for affected mods. Runs in an isolate.
  static List<(String, AssetLists, int, int, bool)>
      _recomputeAffectedModAssetsStatic({
    required Set<String> affectedModJsonFileNames,
    required Map<String, Map<String, String>?> allModUrls,
    required Map<String, String> assetBundles,
    required Map<String, String> audio,
    required Map<String, String> images,
    required Map<String, String> models,
    required Map<String, String> pdf,
    required bool ignoreAudioGlobal,
    required Map<String, AudioAssetVisibility> modAudioPreferences,
  }) {
    final results = <(String, AssetLists, int, int, bool)>[];

    for (final jsonFileName in affectedModJsonFileNames) {
      final urls = allModUrls[jsonFileName];
      if (urls == null) continue;

      final assetData = buildAssetListsFromUrls(
        urls,
        assetBundles,
        audio,
        images,
        models,
        pdf,
        ignoreAudioGlobal,
        jsonFileName,
        modAudioPreferences,
      );

      results.add((
        jsonFileName,
        assetData.$1,
        assetData.$2,
        assetData.$3,
        assetData.$4
      ));
    }

    return results;
  }

  /// Updates multiple mods in a single state mutation, triggering only one rebuild.
  void updateModsBatch(List<Mod> updatedMods) {
    if (!state.hasValue || updatedMods.isEmpty) return;

    try {
      final updatedByPath = <String, Mod>{};
      for (final mod in updatedMods) {
        updatedByPath[p.normalize(mod.jsonFilePath)] = mod;
      }

      List<Mod>? newMods;
      List<Mod>? newSaves;
      List<Mod>? newSavedObjects;

      for (final mod in updatedMods) {
        switch (mod.modType) {
          case ModTypeEnum.mod:
            newMods ??= [...state.value!.mods];
            break;
          case ModTypeEnum.save:
            newSaves ??= [...state.value!.saves];
            break;
          case ModTypeEnum.savedObject:
            newSavedObjects ??= [...state.value!.savedObjects];
            break;
        }
      }

      void applyToList(List<Mod> list) {
        for (int i = 0; i < list.length; i++) {
          final updated = updatedByPath[p.normalize(list[i].jsonFilePath)];
          if (updated != null) {
            list[i] = updated;
          }
        }
      }

      if (newMods != null) applyToList(newMods);
      if (newSaves != null) applyToList(newSaves);
      if (newSavedObjects != null) applyToList(newSavedObjects);

      state = AsyncValue.data(state.value!.copyWith(
        mods: newMods,
        saves: newSaves,
        savedObjects: newSavedObjects,
      ));
    } catch (e, stack) {
      debugPrint('updateModsBatch error: $e');
      state = AsyncValue.error(e, stack);
    }
  }

  Future<Mod> updateModBackup(Mod mod) async {
    ExistingBackup? backup =
        ref.read(existingBackupsProvider.notifier).getBackupByMod(mod);

    // Creating new Mod object because copyWith returns previous backup value if new one is null
    final updatedMod = Mod(
      modType: mod.modType,
      jsonFilePath: mod.jsonFilePath,
      jsonFileName: mod.jsonFileName,
      parentFolderName: mod.parentFolderName,
      saveName: mod.saveName,
      backupStatus: getModBackupStatus(
        backup,
        mod.dateTimeStamp,
        mod.existingAssetCount,
      ),
      createdAtTimestamp: mod.createdAtTimestamp,
      lastModifiedTimestamp: mod.lastModifiedTimestamp,
      backup: backup,
      dateTimeStamp: mod.dateTimeStamp,
      imageFilePath: mod.imageFilePath,
      assetLists: mod.assetLists,
      assetCount: mod.assetCount,
      existingAssetCount: mod.existingAssetCount,
      hasAudioAssets: mod.hasAudioAssets,
      audioVisibility: mod.audioVisibility,
    );

    updateMod(updatedMod);

    return updatedMod;
  }

  /// Re-processes a single mod's assets with updated audio preference
  Future<void> reprocessModAssets(Mod mod) async {
    try {
      if (!state.hasValue) return;

      // Get URLs from storage or extract fresh
      final urls = ref.read(storageProvider).getModUrls(mod.jsonFileName) ??
          await extractUrlsFromJson(mod.jsonFilePath);

      // Rebuild asset lists with current preference
      final assetLists = _getAssetListsFromUrls(urls, mod);

      final updatedMod = Mod(
        modType: mod.modType,
        jsonFilePath: mod.jsonFilePath,
        jsonFileName: mod.jsonFileName,
        parentFolderName: mod.parentFolderName,
        saveName: mod.saveName,
        createdAtTimestamp: mod.createdAtTimestamp,
        lastModifiedTimestamp: mod.lastModifiedTimestamp,
        dateTimeStamp: mod.dateTimeStamp,
        imageFilePath: mod.imageFilePath,
        backup: mod.backup,
        backupStatus: getModBackupStatus(
          mod.backup,
          mod.dateTimeStamp,
          assetLists.$3,
        ),
        audioVisibility: mod.audioVisibility,
        // -----------------------------------------
        assetLists: assetLists.$1,
        assetCount: assetLists.$2,
        existingAssetCount: assetLists.$3,
        hasAudioAssets: assetLists.$4,
      );

      // Update the mod in state
      updateMod(updatedMod);
    } catch (e, stack) {
      debugPrint('reprocessModAssets error: $e');
      state = AsyncValue.error(e, stack);
    }
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
        type: type,
        filePath: filepath,
      );
    }).toList();
  }

  // TODO remove/replace with isolate method?
  (AssetLists, int, int, bool) _getAssetListsFromUrls(
    Map<String, String> data,
    Mod mod,
  ) {
    final ignoreAudioGlobal = ref.read(settingsProvider).ignoreAudioAssets;
    final ignoreAudio = switch (mod.audioVisibility) {
      AudioAssetVisibility.alwaysShow => false,
      AudioAssetVisibility.alwaysHide => true,
      AudioAssetVisibility.useGlobalSetting => ignoreAudioGlobal,
    };

    Map<AssetTypeEnum, List<String>> urlsByType = {
      for (final type in AssetTypeEnum.values) type: [],
    };

    bool hasAudioInJson = false;

    for (final element in data.entries) {
      for (final assetType in AssetTypeEnum.values) {
        if (assetType.subtypes.contains(element.value)) {
          // Determine if audio should be ignored for this specific mod
          if (assetType == AssetTypeEnum.audio) {
            hasAudioInJson = true;

            if (ignoreAudio) {
              break; // Skip adding to urlsByType
            }
          }

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
      hasAudioInJson,
    );
  }

  void setSelectedMod(Mod mod) {
    ref.read(multiModsProvider.notifier).state = {mod.jsonFilePath};
  }

  void resetSelectedMod() {
    ref.read(multiModsProvider.notifier).state = {};
  }

  Future<void> deleteMod(Mod mod) async {
    try {
      if (!state.hasValue) return;

      // Delete JSON file
      final jsonFile = File(mod.jsonFilePath);
      if (await jsonFile.exists()) {
        await jsonFile.delete();
      }

      // Delete image file if it exists
      if (mod.imageFilePath != null) {
        final imageFile = File(mod.imageFilePath!);
        if (await imageFile.exists()) {
          await imageFile.delete();
        }
      }

      // Clean up cached storage data
      await ref.read(storageProvider).deleteMod(mod.jsonFileName);

      // Remove from state
      final currentState = state.value!;
      final normalizedPath = p.normalize(mod.jsonFilePath);

      switch (mod.modType) {
        case ModTypeEnum.mod:
          final updatedList = currentState.mods
              .where((m) => p.normalize(m.jsonFilePath) != normalizedPath)
              .toList();
          state = AsyncValue.data(currentState.copyWith(mods: updatedList));
          break;
        case ModTypeEnum.save:
          final updatedList = currentState.saves
              .where((m) => p.normalize(m.jsonFilePath) != normalizedPath)
              .toList();
          state = AsyncValue.data(currentState.copyWith(saves: updatedList));
          break;
        case ModTypeEnum.savedObject:
          final updatedList = currentState.savedObjects
              .where((m) => p.normalize(m.jsonFilePath) != normalizedPath)
              .toList();
          state =
              AsyncValue.data(currentState.copyWith(savedObjects: updatedList));
          break;
      }

      resetSelectedMod();
    } catch (e) {
      debugPrint('deleteMod error: $e');
      rethrow;
    }
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
      final completeMod = await getCompleteMod(selectedMod, jsonURLs,
          refreshLastModified: true);

      await ref
          .read(storageProvider)
          .updateModUrls(selectedMod.jsonFileName, jsonURLs);

      updateMod(completeMod);
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
      final completeMod =
          await getCompleteMod(mod, jsonURLs, refreshLastModified: true);

      await ref.read(storageProvider).updateModUrls(mod.jsonFileName, jsonURLs);

      updateMod(completeMod);
    }
  }
}
