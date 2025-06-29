import 'dart:convert' show jsonDecode;
import 'dart:io' show Directory, File;

import 'package:flutter/material.dart' show debugPrint;
import 'package:intl/intl.dart' show DateFormat;
import 'package:path/path.dart' as path;
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart'
    show AssetTypeEnum;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart'
    show Mod, ModTypeEnum;
import 'package:tts_mod_vault/src/utils.dart'
    show newSteamUserContentUrl, oldCloudUrl;

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
  try {
    final file = File(filePath);
    final jsonString = await file.readAsString();

    // Use regex extraction instead of full JSON parsing
    Map<String, String> urls = _extractUrlsWithRegex(jsonString);
    return urls;
  } catch (e) {
    // Fallback to original method if regex fails
    try {
      final file = File(filePath);
      final jsonString = await file.readAsString();
      final decodedJson = jsonDecode(jsonString);
      return _extractUrlsWithReversedKeysIsolate(decodedJson);
    } catch (fallbackError) {
      return {};
    }
  }
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

Map<String, String> _extractUrlsWithReversedKeysIsolate(dynamic data,
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
  final String fileNameToIgnore;
  final ModTypeEnum modType;

  InitialModsIsolateData({
    required this.jsonsPaths,
    required this.fileNameToIgnore,
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
        .map((jsonPath) => _processSingleFileOptimized(
            jsonPath, data.fileNameToIgnore, data.modType))
        .toList();

    final results = await Future.wait(futures);
    jsonListMods.addAll(results.whereType<Mod>());
  }

  return jsonListMods;
}

Future<Mod?> _processSingleFileOptimized(
    String jsonPath, String fileNameToIgnore, ModTypeEnum modType) async {
  final jsonFileName = path.basenameWithoutExtension(jsonPath);

  if (jsonFileName == fileNameToIgnore) return null;

  try {
    final file = File(jsonPath);
    final jsonString = await file.readAsString();

    final saveName =
        _extractSaveNameFromString(jsonString, modType) ?? jsonFileName;
    final dateTimeStamp = _extractDateTimeStampFromString(jsonString);
    final imageFilePath =
        await _getImageFilePathIsolate(jsonPath, jsonFileName);

    return Mod(
      modType: modType,
      jsonFilePath: jsonPath,
      saveName: saveName.isNotEmpty ? saveName : jsonFileName,
      dateTimeStamp: dateTimeStamp,
      jsonFileName: jsonFileName,
      imageFilePath: imageFilePath,
    );
  } catch (e) {
    return null;
  }
}

String? _extractSaveNameFromString(String jsonString, ModTypeEnum modType) {
  try {
    if (modType == ModTypeEnum.savedObject) {
      // Look for "Nickname":"value" pattern in ObjectStates
      // First check if ObjectStates exists
      if (jsonString.contains('"ObjectStates"')) {
        final nicknameRegex = RegExp(r'"Nickname"\s*:\s*"([^"]*)"');
        final match = nicknameRegex.firstMatch(jsonString);
        return match?.group(1);
      }
      return null;
    } else {
      // Look for "SaveName":"value" pattern
      final saveNameRegex = RegExp(r'"SaveName"\s*:\s*"([^"]*)"');
      final match = saveNameRegex.firstMatch(jsonString);
      return match?.group(1);
    }
  } catch (e) {
    // Fallback to JSON parsing if regex fails
    return _fallbackToJsonParsing(jsonString, modType);
  }
}

String? _extractDateTimeStampFromString(String jsonString) {
  try {
    // Look for "Date":"value" pattern
    final dateRegex = RegExp(r'"Date"\s*:\s*"([^"]*)"');
    final match = dateRegex.firstMatch(jsonString);
    if (match != null) {
      final dateValue = match.group(1);
      if (dateValue != null && dateValue.isNotEmpty) {
        return dateTimeToUnixTimestampSync(dateValue);
      }
    }
    return null;
  } catch (e) {
    // Fallback to JSON parsing if regex fails
    return _fallbackToJsonDateParsing(jsonString);
  }
}

// Fallback methods in case regex fails
String? _fallbackToJsonParsing(String jsonString, ModTypeEnum modType) {
  try {
    final jsonData = jsonDecode(jsonString);
    return _getSaveNameFromJsonSync(jsonData, modType);
  } catch (e) {
    return null;
  }
}

String? _fallbackToJsonDateParsing(String jsonString) {
  try {
    final jsonData = jsonDecode(jsonString);
    return _getDateTimeStampFromJsonSync(jsonData);
  } catch (e) {
    return null;
  }
}

// Synchronous versions for isolate use
String? _getSaveNameFromJsonSync(dynamic jsonData, ModTypeEnum modType) {
  try {
    if (modType == ModTypeEnum.savedObject) {
      // For saved objects, look for nickname in ObjectStates
      if (jsonData is Map<String, dynamic> &&
          jsonData.containsKey('ObjectStates')) {
        final objectStates = jsonData['ObjectStates'] as List<dynamic>?;
        if (objectStates != null && objectStates.isNotEmpty) {
          final firstObject = objectStates[0] as Map<String, dynamic>?;
          if (firstObject != null && firstObject.containsKey('Nickname')) {
            return firstObject['Nickname'].toString();
          }
        }
      }
      return null;
    }

    if (jsonData is Map<String, dynamic> && jsonData.containsKey('SaveName')) {
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
    return null;
  }
}

String? _getDateTimeStampFromJsonSync(dynamic jsonData) {
  try {
    if (jsonData is Map<String, dynamic> && jsonData.containsKey('Date')) {
      final dateValue = jsonData['Date'].toString();
      return dateTimeToUnixTimestampSync(dateValue);
    }

    if (jsonData is List) {
      for (final item in jsonData) {
        if (item is Map<String, dynamic> && item.containsKey('Date')) {
          final dateValue = item['Date'].toString();

          if (dateValue.isEmpty) return null;

          return dateTimeToUnixTimestampSync(dateValue);
        }
      }
    }

    return null;
  } catch (e) {
    return null;
  }
}

String? dateTimeToUnixTimestampSync(String dateTimeVrijednost) {
  try {
    DateFormat format = DateFormat('M/d/yyyy h:mm:ss a');
    DateTime dateTime = format.parse(dateTimeVrijednost);
    return (dateTime.millisecondsSinceEpoch / 1000).floor().toString();
  } catch (e) {
    return null;
  }
}

Future<List<String>> getJsonFilesInDirectory({
  required String directoryPath,
  String? excludeDirectory,
}) async {
  final List<String> jsonFilePaths = [];

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
        jsonFilePaths.add(path.normalize(entity.path));
      }
    }
  } catch (e) {
    debugPrint('getJsonFilesInDirectory error: $e');
  }

  return jsonFilePaths;
}
