import 'dart:convert' show LineSplitter, utf8;
import 'dart:io' show Directory, File;

import 'package:flutter/material.dart' show debugPrint;
import 'package:intl/intl.dart' show DateFormat;
import 'package:path/path.dart' as path;
import 'package:tts_mod_vault/src/state/backup/backup_status_enum.dart'
    show ExistingBackupStatusEnum;
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart'
    show AssetTypeEnum;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart'
    show Mod, ModTypeEnum;
import 'package:tts_mod_vault/src/utils.dart'
    show newSteamUserContentUrl, oldCloudUrl;

final urlRegex = RegExp(
  r'(?:[a-zA-Z]+:\/\/)?[a-zA-Z0-9.-]+\.[a-z]{2,}(?:\/[^{}"]*)?',
  caseSensitive: false,
);

class IsolateWorkData {
  final List<List<Mod>> batches;
  final Map<String, String?> cachedDateTimeStamps;
  final Map<String, Map<String, String>?> cachedAssetLists;

  IsolateWorkData({
    required this.batches,
    required this.cachedDateTimeStamps,
    required this.cachedAssetLists,
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

Future<IsolateWorkResult> processMultipleBatchesInIsolate(
    IsolateWorkData workData) async {
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
            jsonURLs: jsonURLs.map((key, value) => MapEntry(
                  key.replaceAll(oldCloudUrl, newSteamUserContentUrl),
                  value,
                )),
          ));
        }

        allProcessedMods.add(mod);
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
  Map<String, String> urls = {};

  try {
    final file = File(filePath);
    final jsonString = await file.readAsString();

    // Use regex extraction instead of full JSON parsing
    urls = _extractUrlsWithRegex(jsonString);
  } catch (e) {
    debugPrint('extractUrlsFromJson error: $e');
  }

  Map<String, String> finalUrls = {};

  for (final url in urls.entries) {
    final processedUrls = _processUrl(url.key, url.value);
    finalUrls.addAll(processedUrls);
  }

  return finalUrls;
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

Future<List<Mod>> processInitialModsInIsolate(
  InitialModsIsolateData data,
) async {
  // Process files in parallel chunks within the isolate
  final chunkSize = 10;
  List<Mod> jsonListMods = [];

  for (int i = 0; i < data.jsonsPaths.length; i += chunkSize) {
    final chunk = data.jsonsPaths.skip(i).take(chunkSize).toList();

    // Process chunk in parallel
    final futures = chunk
        .map((jsonPath) => _processSingleFileOptimized(jsonPath, data.modType))
        .toList();

    final results = await Future.wait(futures);
    jsonListMods.addAll(results.whereType<Mod>());
  }

  return jsonListMods;
}

Future<Mod?> _processSingleFileOptimized(
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

    return Mod(
      modType: modType,
      jsonFilePath: jsonPath,
      parentFolderName: parentFolder,
      saveName: saveName.isNotEmpty ? saveName.trim() : jsonFileName,
      backupStatus: ExistingBackupStatusEnum.noBackup,
      createdAtTimestamp: jsonFileStat.changed.millisecondsSinceEpoch ~/ 1000,
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
  const chunkSize = 50;

  await for (final chunk in _readFileInChunks(file, chunkSize)) {
    // Try to extract data from current chunk
    saveName ??= _extractSaveNameFromString(chunk, modType);
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
      final nicknameRegex = RegExp(r'"Nickname"\s*:\s*"([^"]*)"');
      final match = nicknameRegex.firstMatch(jsonString);
      return match?.group(1);
    } else {
      // Look for "SaveName":"value" pattern
      final saveNameRegex = RegExp(r'"SaveName"\s*:\s*"([^"]*)"');
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
    // Look for "Date":"value" pattern
    final dateRegex = RegExp(r'"Date"\s*:\s*"([^"]*)"');
    final match = dateRegex.firstMatch(jsonString);
    if (match != null) {
      final dateValue = match.group(1);
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
