import 'dart:convert' show LineSplitter, utf8;
import 'dart:io' show Directory, File;

import 'package:flutter/material.dart' show debugPrint;
import 'package:intl/intl.dart' show DateFormat;
import 'package:path/path.dart' as path;
import 'package:tts_mod_vault/src/state/asset/models/asset_lists_model.dart'
    show AssetLists;
import 'package:tts_mod_vault/src/state/asset/models/asset_model.dart'
    show Asset;
import 'package:tts_mod_vault/src/state/backup/backup_status_enum.dart'
    show ExistingBackupStatusEnum;
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart'
    show AssetTypeEnum;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart'
    show AudioAssetVisibility, Mod, ModTypeEnum, InitialMod;
import 'package:tts_mod_vault/src/utils.dart'
    show getFileNameFromURL, newSteamUserContentUrl, oldCloudUrl;

final urlRegex = RegExp(
  r'(?:[a-zA-Z]+:\/\/)?[a-zA-Z0-9.-]+\.[a-z]{2,}(?:\/[^{}"]*)?',
  caseSensitive: false,
);
final nicknameRegex = RegExp(r'"Nickname"\s*:\s*"([^"]*)"');
final saveNameRegex = RegExp(r'"SaveName"\s*:\s*"([^"]*)"');

class IsolateWorkData {
  final List<List<InitialMod>> batches;
  final Map<String, String?> cachedDateTimeStamps;
  final Map<String, Map<String, String>?> cachedAssetLists;
  final bool ignoreAudioAssets;
  final Map<String, AudioAssetVisibility> modAudioPreferences;
  // Asset existence maps for O(1) lookups
  final Map<String, String> existingAssetBundles;
  final Map<String, String> existingAudio;
  final Map<String, String> existingImages;
  final Map<String, String> existingModels;
  final Map<String, String> existingPdf;

  IsolateWorkData({
    required this.batches,
    required this.cachedDateTimeStamps,
    required this.cachedAssetLists,
    required this.ignoreAudioAssets,
    required this.modAudioPreferences,
    required this.existingAssetBundles,
    required this.existingAudio,
    required this.existingImages,
    required this.existingModels,
    required this.existingPdf,
  });
}

class IsolateWorkResult {
  final List<Mod> processedMods;
  final List<ModStorageUpdate> storageUpdates;

  IsolateWorkResult({
    required this.processedMods,
    required this.storageUpdates,
  });
}

class ModStorageUpdate {
  final String jsonFileName;
  final String dateTimeStamp;
  final Map<String, String> jsonURLs;

  ModStorageUpdate({
    required this.jsonFileName,
    required this.dateTimeStamp,
    required this.jsonURLs,
  });
}

class UpdateUrlPrefixesParams {
  final String modJsonFilePath;
  final List<String> oldPrefixes;
  final String newPrefix;
  final bool renameFile;
  final Map<String, String?> assets;

  UpdateUrlPrefixesParams(
    this.modJsonFilePath,
    this.oldPrefixes,
    this.newPrefix,
    this.renameFile,
    this.assets,
  );
}

class UpdateUrlPrefixesResult {
  final bool updated;
  final String jsonString;

  UpdateUrlPrefixesResult({
    required this.updated,
    required this.jsonString,
  });
}

Future<IsolateWorkResult> processMultipleBatchesInIsolate(
  IsolateWorkData workData,
) async {
  final List<Mod> allProcessedMods = [];
  final List<ModStorageUpdate> allStorageUpdates = [];

  for (int batchIndex = 0; batchIndex < workData.batches.length; batchIndex++) {
    final batch = workData.batches[batchIndex];

    for (final mod in batch) {
      try {
        final cachedUpdateTime =
            workData.cachedDateTimeStamps[mod.jsonFileName];
        final updateTimeChanged = cachedUpdateTime != null &&
            cachedUpdateTime.isNotEmpty &&
            cachedUpdateTime != mod.dateTimeStamp;

        final needsRefresh = cachedUpdateTime == null ||
            workData.cachedAssetLists[mod.jsonFileName] == null ||
            updateTimeChanged;

        Map<String, String>? jsonURLs;

        if (needsRefresh) {
          jsonURLs = await extractUrlsFromJson(mod.jsonFilePath);

          allStorageUpdates.add(ModStorageUpdate(
            jsonFileName: mod.jsonFileName,
            dateTimeStamp: mod.dateTimeStamp ?? '',
            jsonURLs: jsonURLs,
          ));
        } else {
          // Use cached URLs
          jsonURLs = workData.cachedAssetLists[mod.jsonFileName];
        }

        // Build asset lists eagerly in isolate with O(1) lookups
        if (jsonURLs != null) {
          final assetLists = buildAssetListsFromUrls(
            jsonURLs,
            workData.existingAssetBundles,
            workData.existingAudio,
            workData.existingImages,
            workData.existingModels,
            workData.existingPdf,
            workData.ignoreAudioAssets,
            mod.jsonFileName,
            workData.modAudioPreferences,
          );

          final completeMod = Mod.fromInitial(
            mod,
            assetLists: assetLists.$1,
            assetCount: assetLists.$2,
            existingAssetCount: assetLists.$3,
            missingAssetCount: assetLists.$2 - assetLists.$3,
            hasAudioAssets: assetLists.$4,
            audioVisibility: workData.modAudioPreferences[mod.jsonFileName] ??
                AudioAssetVisibility.useGlobalSetting,
          );

          allProcessedMods.add(completeMod);
        }
      } catch (e) {
        debugPrint(
            'Isolate error processing mod ${mod.jsonFileName}: ${e.toString()}');
      }
    }
  }

  return IsolateWorkResult(
    processedMods: allProcessedMods,
    storageUpdates: allStorageUpdates,
  );
}

Future<Map<String, String>> extractUrlsFromJson(String filePath) async {
  final file = File(filePath);
  final jsonString = await file.readAsString();

  return extractUrlsFromJsonString(jsonString);
}

Map<String, String> extractUrlsFromJsonString(String jsonString) {
  Map<String, String> urls = {};

  try {
    // Use regex extraction instead of full JSON parsing
    urls = _extractUrlsWithRegex(jsonString);
  } catch (e) {
    debugPrint('extractUrlsFromJson error: $e');
  }

  Map<String, String> finalUrls = {};

  for (final url in urls.entries) {
    if (url.key.startsWith("file:/")) {
      continue;
    }

    final processedUrls = _processUrl(url.key, url.value);
    finalUrls.addAll(processedUrls);
  }

  return finalUrls.map((key, value) => MapEntry(
        key.replaceAll(oldCloudUrl, newSteamUserContentUrl),
        value,
      ));
}

// Separates one url into multiple entries and/or removes {prefix} such as {en}
// Example input urlKey: {en}https://www.en-example.com{fr}https://www.fr-example.com
Map<String, String> _processUrl(String urlKey, String value) {
  final matches = urlRegex.allMatches(urlKey);

  final urls = matches.map((m) => m.group(0)).nonNulls.toList();

  Map<String, String> finalUrls = {};
  for (final url in urls) {
    final trimmedUrl =
        url.replaceAll(RegExp(r'\\[rn]'), ''); // Remove literal \r and \n
    finalUrls[trimmedUrl] = value;
  }

  return finalUrls;
}

// Fast regex-based URL extraction using exact AssetTypeEnum subtypes
Map<String, String> _extractUrlsWithRegex(String jsonString) {
  Map<String, String> urls = {};

  List<String> assetKeys = [];
  for (final value in AssetTypeEnum.values) {
    assetKeys.addAll(value.subtypes);
  }

  // Create regex pattern for each exact asset key
  for (final key in assetKeys) {
    // Pattern: "key": "url_value"
    // Handles various whitespace scenarios and captures the URL
    final pattern = RegExp(
      '"$key"\\s*:\\s*"([^"]*)"',
      caseSensitive: true,
    );

    final matches = pattern.allMatches(jsonString);
    for (final match in matches) {
      final url = match.group(1);
      if (url != null && url.isNotEmpty) {
        urls[url] = key;
      }
    }
  }

  return urls;
}

/// Builds AssetLists from URLs with O(1) existence checks
/// This function runs in isolate and doesn't have access to Riverpod
/// Returns: (AssetLists, totalCount, existingCount, hasAudio)
(AssetLists, int, int, bool) buildAssetListsFromUrls(
  Map<String, String> urlsData,
  Map<String, String> assetBundles,
  Map<String, String> audio,
  Map<String, String> images,
  Map<String, String> models,
  Map<String, String> pdf,
  bool ignoreAudioGlobal,
  String modJsonFileName,
  Map<String, AudioAssetVisibility> modAudioPreferences,
) {
  // Group URLs by type
  Map<AssetTypeEnum, List<String>> urlsByType = {
    for (final type in AssetTypeEnum.values) type: [],
  };

  // Track if mod has audio assets (regardless of filtering)
  bool hasAudioInJson = false;

  for (final entry in urlsData.entries) {
    for (final assetType in AssetTypeEnum.values) {
      if (assetType.subtypes.contains(entry.value)) {
        // Check if this is an audio asset
        if (assetType == AssetTypeEnum.audio) {
          hasAudioInJson = true;

          // Use switch expression for type-safe handling
          final modVisibility = modAudioPreferences[modJsonFileName] ??
              AudioAssetVisibility.useGlobalSetting;

          final ignoreAudio = switch (modVisibility) {
            AudioAssetVisibility.alwaysShow => false,
            AudioAssetVisibility.alwaysHide => true,
            AudioAssetVisibility.useGlobalSetting => ignoreAudioGlobal,
          };

          if (ignoreAudio) {
            break; // Skip adding to urlsByType
          }
        }

        urlsByType[assetType]!.add(entry.key);
        break;
      }
    }
  }

  // Build Asset objects with O(1) lookups
  final allAssets = <List<Asset>>[];

  for (final type in AssetTypeEnum.values) {
    final assetMap = switch (type) {
      AssetTypeEnum.assetBundle => assetBundles,
      AssetTypeEnum.audio => audio,
      AssetTypeEnum.image => images,
      AssetTypeEnum.model => models,
      AssetTypeEnum.pdf => pdf,
    };

    final assets = urlsByType[type]!.map((url) {
      final filename = getFileNameFromURL(url);
      final filepath = assetMap[filename]; // O(1) lookup!

      return Asset(
        url: url,
        fileExists: filepath != null,
        type: type,
        filePath: filepath,
      );
    }).toList();

    allAssets.add(assets);
  }

  final totalCount = allAssets.expand((list) => list).length;
  final existingFilesCount = allAssets
      .expand((list) => list)
      .where((asset) => asset.fileExists)
      .length;

  return (
    AssetLists(
      assetBundles: allAssets[0],
      audio: allAssets[1],
      images: allAssets[2],
      models: allAssets[3],
      pdf: allAssets[4],
    ),
    totalCount,
    existingFilesCount,
    hasAudioInJson,
  );
}

// Original URL extraction method
/* Map<String, String> _extractUrlsWithReversedKeysIsolate(dynamic data,
    [String? parentKey]) {
  Map<String, String> urls = {};

  if (data is Map) {
    data.forEach((key, value) {
      if (value is String && Uri.tryParse(value)?.hasAbsolutePath == true) {
        urls[value] = key;
      } else if (value is Map || value is List) {
        urls.addAll(_extractUrlsWithReversedKeysIsolate(value, key));
      }
    });
  } else if (data is List) {
    for (final item in data) {
      urls.addAll(_extractUrlsWithReversedKeysIsolate(item, parentKey ?? ''));
    }
  }

  return urls;
} */

Future<UpdateUrlPrefixesResult> updateUrlPrefixesFilesIsolate(
  UpdateUrlPrefixesParams params,
) async {
  bool updatedFiles = false;
  String jsonString = await File(params.modJsonFilePath).readAsString();

  for (final asset in params.assets.entries) {
    final url = asset.key;
    final filePath = asset.value;

    for (final oldPrefix in params.oldPrefixes) {
      if (oldPrefix.contains('http://cloud-3.steamusercontent.com') &&
          params.newPrefix
              .contains('https://steamusercontent-a.akamaihd.net')) {
        jsonString = jsonString.replaceAll(oldPrefix, params.newPrefix);
        updatedFiles = true;
        continue;
      }

      if (url.startsWith(oldPrefix)) {
        final newUrl = url.replaceFirst(oldPrefix, params.newPrefix);
        jsonString = jsonString.replaceAll(url, newUrl);
        updatedFiles = true;

        if (params.renameFile && filePath != null) {
          await renameAssetFile(filePath, newUrl);
        }
      }
    }
  }

  if (updatedFiles) {
    await File(params.modJsonFilePath).writeAsString(jsonString);
  }

  return UpdateUrlPrefixesResult(
    updated: updatedFiles,
    jsonString: jsonString,
  );
}

Future<void> renameAssetFile(
  String currentFilePath,
  String newAssetUrl,
) async {
  try {
    final file = File(currentFilePath);

    if (!file.existsSync()) return;

    final newFileName = getFileNameFromURL(newAssetUrl);
    final fileExtension = path.extension(currentFilePath);
    final newPath = path.join(file.parent.path, '$newFileName$fileExtension');

    await file.rename(newPath);
  } catch (e) {
    debugPrint('_renameAssetFileError: $e');
  }
}

Future<String?> _getImageFilePathIsolate(
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

class InitialModsIsolateData {
  final List<String> jsonsPaths;
  final ModTypeEnum modType;

  InitialModsIsolateData({
    required this.jsonsPaths,
    required this.modType,
  });
}

Future<List<InitialMod>> processInitialModsInIsolate(
  InitialModsIsolateData data,
) async {
  // Process files in parallel chunks within the isolate
  final chunkSize = 10;
  List<InitialMod> jsonListMods = [];

  for (int i = 0; i < data.jsonsPaths.length; i += chunkSize) {
    final chunk = data.jsonsPaths.skip(i).take(chunkSize).toList();

    // Process chunk in parallel
    final futures = chunk
        .map((jsonPath) => _processSingleFileOptimized(jsonPath, data.modType))
        .toList();

    final results = await Future.wait(futures);
    jsonListMods.addAll(results.whereType<InitialMod>());
  }

  return jsonListMods;
}

Future<InitialMod?> _processSingleFileOptimized(
  String jsonPath,
  ModTypeEnum modType,
) async {
  final jsonFileName = path.basenameWithoutExtension(jsonPath);

  try {
    final initialModMetaData = await _extractInitialModMetadataFromFile(
        jsonPath, jsonFileName, modType);

    final saveName = initialModMetaData['saveName'] ??
        ''; // Non-null (fallback to jsonFileName)
    final dateTimeStamp = initialModMetaData['dateTimeStamp']; // Can be null

    final parentFolder = path.basename(path.dirname(jsonPath));
    final imageFilePath =
        await _getImageFilePathIsolate(jsonPath, jsonFileName);
    final jsonFileStat = await File(jsonPath).stat();

    return InitialMod(
      modType: modType,
      jsonFilePath: jsonPath,
      parentFolderName: parentFolder,
      saveName: saveName.isNotEmpty ? saveName.trim() : jsonFileName,
      backupStatus: ExistingBackupStatusEnum.noBackup,
      createdAtTimestamp: jsonFileStat.changed.millisecondsSinceEpoch ~/ 1000,
      lastModifiedTimestamp:
          jsonFileStat.modified.microsecondsSinceEpoch ~/ 1000,
      dateTimeStamp: dateTimeStamp,
      jsonFileName: jsonFileName,
      imageFilePath: imageFilePath,
    );
  } catch (e) {
    return null;
  }
}

Future<Map<String, String?>> _extractInitialModMetadataFromFile(
  String jsonPath,
  String jsonFileName,
  ModTypeEnum modType,
) async {
  final file = File(jsonPath);

  String? saveName;
  String? dateTimeStamp;
  const chunkSize = 10;

  await for (final chunk in _readFileInChunks(file, chunkSize)) {
    if (modType == ModTypeEnum.savedObject) {
      saveName = jsonFileName;
    } else {
      // Try to extract data from current chunk
      saveName ??= _extractSaveNameFromString(chunk, modType);
    }
    dateTimeStamp ??= _extractDateTimeStampFromString(chunk);

    // If we found both, we can stop
    if (saveName != null && dateTimeStamp != null) {
      break;
    }
  }

  return {
    'saveName': saveName ?? jsonFileName,
    'dateTimeStamp': dateTimeStamp,
  };
}

Stream<String> _readFileInChunks(File file, int linesPerChunk) async* {
  final lines = <String>[];
  int lineCount = 0;

  await for (final line in file
      .openRead()
      .transform(utf8.decoder)
      .transform(const LineSplitter())) {
    lines.add(line);
    lineCount++;

    // When we reach chunk size, yield the chunk and reset
    if (lineCount % linesPerChunk == 0) {
      yield lines.join('\n');
      lines.clear();
    }
  }

  // Yield any remaining lines
  if (lines.isNotEmpty) {
    yield lines.join('\n');
  }
}

String? _extractSaveNameFromString(String jsonString, ModTypeEnum modType) {
  try {
    if (modType == ModTypeEnum.savedObject) {
      // Look for "Nickname":"value" pattern in ObjectStates
      final match = nicknameRegex.firstMatch(jsonString);
      return match?.group(1);
    } else {
      // Look for "SaveName":"value" pattern
      final match = saveNameRegex.firstMatch(jsonString);
      return match?.group(1);
    }
  } catch (e) {
    debugPrint('_extractSaveNameFromString error: $e');
  }

  return null;
}

String? _extractDateTimeStampFromString(String jsonString) {
  try {
    // First, check for "EpochTime": value pattern (numeric, already in Unix timestamp format)
    final epochRegex = RegExp(r'"EpochTime"\s*:\s*(\d+)');
    final epochMatch = epochRegex.firstMatch(jsonString);
    if (epochMatch != null) {
      final epochValue = epochMatch.group(1);
      if (epochValue != null && epochValue.isNotEmpty) {
        return epochValue; // Already a Unix timestamp, return as-is
      }
    }

    // Fallback: Look for "Date":"value" pattern and convert to Unix timestamp
    final dateRegex = RegExp(r'"Date"\s*:\s*"([^"]*)"');
    final dateMatch = dateRegex.firstMatch(jsonString);
    if (dateMatch != null) {
      final dateValue = dateMatch.group(1);
      if (dateValue != null && dateValue.isNotEmpty) {
        return _dateTimeToUnixTimestampSync(dateValue);
      }
    }
  } catch (e) {
    debugPrint('_extractDateTimeStampFromString error: $e');
  }

  return null;
}

String? _dateTimeToUnixTimestampSync(String dateValue) {
  try {
    DateFormat format;

    if (dateValue.toUpperCase().contains('AM') ||
        dateValue.toUpperCase().contains('PM')) {
      format = DateFormat('M/d/yyyy h:mm:ss a');
    } else {
      format = DateFormat('MM/dd/yyyy HH:mm:ss');
    }

    final dateTime = format.tryParse(dateValue);

    if (dateTime == null) {
      return null;
    }

    return (dateTime.millisecondsSinceEpoch ~/ 1000).toString();
  } catch (e) {
    return null;
  }
}

Future<List<String>> getJsonFilesInDirectory({
  required String directoryPath,
  String? excludeDirectory,
}) async {
  final List<String> jsonFilePaths = [];
  final List<String> excludeFiles = [
    'WorkshopFileInfos.json',
    'SaveFileInfos.json'
  ];

  try {
    final directory = Directory(directoryPath);

    if (!await directory.exists()) {
      return jsonFilePaths;
    }

    await for (final entity in directory.list(recursive: true)) {
      if (entity is File &&
          path.extension(entity.path).toLowerCase() == '.json') {
        if (excludeDirectory != null &&
            path.isWithin(excludeDirectory, entity.path)) {
          continue;
        }

        final fileName = path.basename(entity.path);
        if (excludeFiles.contains(fileName)) {
          continue;
        }

        jsonFilePaths.add(path.normalize(entity.path));
      }
    }
  } catch (e) {
    debugPrint('getJsonFilesInDirectory error: $e');
  }

  return jsonFilePaths;
}

/// Creates adaptive batches based on file sizes and complexity
Future<List<List<InitialMod>>> createAdaptiveBatchesInIsolate(
    List<InitialMod> mods) async {
  const int targetBatchSizeBytes = 50 * 1024 * 1024; // 50MB per batch
  const int maxModsPerBatch = 100;
  const int minModsPerBatch = 5;
  const int parallelStatChunkSize = 100; // Process 100 file stats at a time

  // Get all file sizes in parallel chunks
  final List<(InitialMod, int)> modsWithSizes = [];

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
              'createAdaptiveBatchesInIsolate - error getting file size for ${mod.jsonFilePath}: $e');
          return (mod, 0);
        }
      }),
    );

    modsWithSizes.addAll(chunkResults);
  }

  // Now create batches using the sizes we collected
  List<List<InitialMod>> batches = [];
  List<InitialMod> currentBatch = [];
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
