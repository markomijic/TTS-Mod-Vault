import 'dart:convert' show JsonEncoder, json;
import 'dart:io' show File;

import 'package:bson/bson.dart' show BsonBinary, BsonCodec;
import 'package:dio/dio.dart'
    show CancelToken, Dio, DioException, DioExceptionType, Options;
import 'package:fixnum/fixnum.dart' show Int64;
import 'package:flutter/material.dart' show debugPrint;
import 'package:hooks_riverpod/hooks_riverpod.dart' show Ref, StateNotifier;
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:tts_mod_vault/src/state/download/download_state.dart'
    show DownloadState;
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart'
    show AssetTypeEnum;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart'
    show Mod, ModTypeEnum;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        directoriesProvider,
        downloadProvider,
        existingAssetListsProvider,
        modsProvider,
        selectedModProvider,
        settingsProvider;
import 'package:tts_mod_vault/src/utils.dart'
    show
        getExtensionByType,
        getFileNameFromURL,
        newSteamUserContentUrl,
        getPublishedFileDetailsUrl;

import 'package:path/path.dart' as path;

class DownloadNotifier extends StateNotifier<DownloadState> {
  final Ref ref;
  final Dio dio;

  // Map to store active CancelTokens
  final Map<String, CancelToken> _cancelTokens = {};

  DownloadNotifier(this.ref)
      : dio = Dio(),
        super(const DownloadState());

  Future<void> handleCancelDownloadsButton() async {
    await ref.read(downloadProvider.notifier).cancelAllDownloads();
    if (ref.read(selectedModProvider) != null) {
      await ref
          .read(modsProvider.notifier)
          .updateSelectedMod(ref.read(selectedModProvider)!);
    }
  }

  Future<void> cancelAllDownloads() async {
    state = state.copyWith(
      downloadingAssets: false,
      cancelledDownloads: true,
      progress: null,
      downloadingType: null,
    );

    for (final token in _cancelTokens.values) {
      token.cancel('All downloads cancelled by user');
    }
    _cancelTokens.clear();
  }

  Future<void> downloadAllFiles(Mod mod) async {
    if (mod.assetLists == null) {
      return;
    }

    await downloadFiles(
      modAssetListUrls: mod.assetLists!.assetBundles
          .where((e) => !e.fileExists)
          .map((e) => e.url)
          .toList(),
      type: AssetTypeEnum.assetBundle,
    );

    await downloadFiles(
      modAssetListUrls: mod.assetLists!.audio
          .where((e) => !e.fileExists)
          .map((e) => e.url)
          .toList(),
      type: AssetTypeEnum.audio,
    );

    await downloadFiles(
      modAssetListUrls: mod.assetLists!.images
          .where((e) => !e.fileExists)
          .map((e) => e.url)
          .toList(),
      type: AssetTypeEnum.image,
    );

    await downloadFiles(
      modAssetListUrls: mod.assetLists!.models
          .where((e) => !e.fileExists)
          .map((e) => e.url)
          .toList(),
      type: AssetTypeEnum.model,
    );

    await downloadFiles(
      modAssetListUrls: mod.assetLists!.pdf
          .where((e) => !e.fileExists)
          .map((e) => e.url)
          .toList(),
      type: AssetTypeEnum.pdf,
    );

    resetState();
  }

  void resetState() {
    state = DownloadState(
      downloadingAssets: false,
      cancelledDownloads: false,
      progress: 0.0,
      downloadingType: null,
    );
  }

  Future<void> _downloadUrl(
    String url,
    String tempPath,
    CancelToken cancelToken,
    int batchLength,
  ) async {
    await dio.download(
      url,
      tempPath,
      cancelToken: cancelToken,
      onReceiveProgress: (received, total) {
        if (total <= 0 || batchLength > 1) return;
        state = state.copyWith(progress: received / total);
      },
    );
  }

  Future<void> downloadFiles({
    required List<String> modAssetListUrls,
    required AssetTypeEnum type,
    bool downloadingAllFiles = true,
  }) async {
    if (modAssetListUrls.isEmpty) {
      return;
    }

    if (state.cancelledDownloads) {
      return;
    }

    final urls = modAssetListUrls.where((url) {
      final fileName = getFileNameFromURL(url);
      return !ref
          .read(existingAssetListsProvider.notifier)
          .doesAssetFileExist(fileName, type);
    }).toList();

    // Track successful downloads
    final List<(String, String)> successfulDownloads = [];

    try {
      state = state.copyWith(
        downloadingAssets: true,
        progress: 0.0,
        downloadingType: type,
      );

      final int batchSize = ref.read(settingsProvider).concurrentDownloads;

      for (int i = 0; i < urls.length; i += batchSize) {
        if (state.cancelledDownloads) {
          continue;
        }

        final batch = urls.sublist(
          i,
          i + batchSize > urls.length ? urls.length : i + batchSize,
        );

        await Future.wait(batch.map((originalUrl) async {
          // Set filename and path
          final fileName = getFileNameFromURL(originalUrl);
          final directory =
              ref.read(directoriesProvider.notifier).getDirectoryByType(type);
          final tempPath = path.join(directory, '${fileName}_temp');

          // Set url and cancel token
          final url = await resolveUrlWithScheme(originalUrl);
          final cancelToken = CancelToken();
          _cancelTokens[url] = cancelToken;

          try {
            if (state.cancelledDownloads) {
              _cancelTokens.remove(url);
              return;
            }

            try {
              await _downloadUrl(
                url,
                tempPath,
                cancelToken,
                batch.length,
              );
            } on DioException catch (e) {
              // Check is Steam CDN url missing a trailing '/'
              if (e.response?.statusCode == 404 &&
                  url.startsWith(newSteamUserContentUrl) &&
                  !url.endsWith('/')) {
                await _downloadUrl(
                  '$url/',
                  tempPath,
                  cancelToken,
                  batch.length,
                );
              } else {
                rethrow;
              }
            }

            final tempFile = File(tempPath);
            final bytes = await tempFile.readAsBytes();
            final firstContent = String.fromCharCodes(bytes.take(100).toList());
            bool isErrorPage = false;

            // Check for HTML error pages
            if (firstContent.contains('<html>') ||
                firstContent.contains('<!DOCTYPE')) {
              debugPrint("File is a HTML error page");
              isErrorPage = true;
            }

            if (cancelToken.isCancelled || isErrorPage) {
              if (await tempFile.exists()) {
                await tempFile.delete();
              }
            } else {
              final finalPath = path.join(directory,
                  fileName + getExtensionByType(type, tempPath, bytes));
              await tempFile.rename(finalPath);

              // Track successful download
              successfulDownloads.add((fileName, finalPath));
            }

            // Remove the token after download
            _cancelTokens.remove(url);
          } catch (e) {
            // Remove the token in case of error
            _cancelTokens.remove(url);

            try {
              if (await File(tempPath).exists()) {
                await File(tempPath).delete();
              }
            } catch (e) {
              debugPrint('Error deleting file after download error $e');
            }

            // Handle cancellation specifically
            if (e is DioException && e.type == DioExceptionType.cancel) {
              debugPrint('Download cancelled for $url');
              return; // Don't treat cancellation as an error
            }

            debugPrint('Error occurred while downloading files: $e');
          }
        }));

        // Progress per batch
        if (batch.length > 1) {
          double progress = (i + batchSize) / urls.length;
          state = state.copyWith(progress: progress.clamp(0.0, 1.0));
        }
      }
    } catch (e) {
      debugPrint('downloadAllFiles error: $e');
    } finally {
      // Add successful downloads to existing assets list
      if (successfulDownloads.isNotEmpty) {
        final existingAssetsNotifier =
            ref.read(existingAssetListsProvider.notifier);
        for (final (filename, filepath) in successfulDownloads) {
          existingAssetsNotifier.addExistingAsset(type, filename, filepath);
        }
      }

      if (!downloadingAllFiles) {
        resetState();
      }
    }
  }

  Future<String> resolveUrlWithScheme(String url) async {
    // If URL already starts with http/https, return it directly
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }

    final httpsUrl = 'https://$url';
    final httpUrl = 'http://$url';

    Future<bool> isReachable(String fullUrl) async {
      try {
        final response = await dio.request(
          fullUrl,
          options: Options(
            method: 'HEAD',
            validateStatus: (status) => status != null && status < 500,
          ),
        );
        return response.statusCode != null && response.statusCode! < 400;
      } catch (_) {
        return false;
      }
    }

    if (await isReachable(httpsUrl)) {
      return httpsUrl;
    } else if (await isReachable(httpUrl)) {
      return httpUrl;
    } else {
      return url; // Could not resolve; return original
    }
  }

  Future<String> downloadModUpdates({
    required List<Mod> mods,
    bool forceUpdate = false,
  }) async {
    if (mods.isEmpty) {
      return 'No mods selected';
    }

    try {
      state = state.copyWith(downloadingMods: true, progress: 0.01);

      // Check which mods need updating
      final modsToUpdate =
          <({String modId, String directory, int currentEpoch})>[];

      for (final mod in mods) {
        // Extract mod ID from filename (remove .json extension)
        final modId = mod.jsonFileName.replaceAll('.json', '');
        final directory = path.dirname(mod.jsonFilePath);

        // Get current epoch from mod's dateTimeStamp (which contains EpochTime)
        final currentEpoch = mod.dateTimeStamp != null
            ? int.tryParse(mod.dateTimeStamp!) ?? 0
            : 0;

        if (forceUpdate) {
          // Force update - add all mods to the update list
          modsToUpdate.add((
            modId: modId,
            directory: directory,
            currentEpoch: currentEpoch,
          ));
        } else {
          // Fetch latest info from Steam
          final url = Uri.parse(getPublishedFileDetailsUrl);

          final response = await http.post(
            url,
            body: {
              'itemcount': '1',
              'publishedfileids[0]': modId,
            },
          );

          final responseData = json.decode(response.body);
          final fileDetails =
              responseData['response']['publishedfiledetails'][0];
          final steamEpoch = fileDetails['time_updated'] as int;

          // Only add to update list if Steam version is newer by more than 60 seconds
          // 60s covers instances of EpochTime and Date being <= 60s apart (it's mostly <= 10s so far)
          final timeDifference = (steamEpoch - currentEpoch).abs();
          if (steamEpoch > currentEpoch && timeDifference > 60) {
            modsToUpdate.add((
              modId: modId,
              directory: directory,
              currentEpoch: currentEpoch,
            ));
          }
        }
      }

      if (modsToUpdate.isEmpty) {
        state = state.copyWith(downloadingMods: false, progress: 0.0);
        return mods.length == 1
            ? 'Mod is up to date'
            : 'All mods are up to date';
      }

      // Download the mods that need updating
      final results = <String>[];
      int successCount = 0;
      int failCount = 0;

      for (int i = 0; i < modsToUpdate.length; i++) {
        final modInfo = modsToUpdate[i];

        try {
          final result = await _downloadSingleMod(
            modId: modInfo.modId,
            targetDirectory: modInfo.directory,
            currentIndex: i,
            totalCount: modsToUpdate.length,
          );

          if (result.startsWith('Mod saved to:')) {
            successCount++;
          } else {
            failCount++;
            results.add('[${modInfo.modId}] $result');
          }
        } catch (e) {
          failCount++;
          results.add('[${modInfo.modId}] Error: $e');
        }

        state = state.copyWith(progress: (i + 1) / modsToUpdate.length);
      }

      state = state.copyWith(downloadingMods: false, progress: 0.0);

      final skippedCount = mods.length - modsToUpdate.length;

      if (successCount == 1 && modsToUpdate.length == 1 && mods.length == 1) {
        return "Updated ${mods[0].saveName}";
      }

      final summary =
          'Updated $successCount of ${modsToUpdate.length} mods${skippedCount > 0 ? ' ($skippedCount already up to date)' : ''}';

      return failCount > 0
          ? '$summary\n\nFailed:\n${results.join('\n')}'
          : summary;
    } catch (e) {
      state = state.copyWith(downloadingMods: false, progress: 0.0);
      return 'Error: $e';
    }
  }

  Future<String> downloadModsByIds({
    required List<String> modIds,
    required String targetDirectory,
  }) async {
    if (modIds.isEmpty) {
      return 'No mod IDs provided';
    }

    try {
      state = state.copyWith(downloadingMods: true, progress: 0.01);

      final results = <String>[];
      int successCount = 0;
      int failCount = 0;

      for (int i = 0; i < modIds.length; i++) {
        final modId = modIds[i].trim();
        if (modId.isEmpty) continue;

        // Show partial progress for current mod (starts at 25% of the segment)
        final baseProgress = i / modIds.length;
        final segmentSize = 1.0 / modIds.length;
        state = state.copyWith(progress: baseProgress + (segmentSize * 0.25));

        try {
          final result = await _downloadSingleMod(
            modId: modId,
            targetDirectory: targetDirectory,
            currentIndex: i,
            totalCount: modIds.length,
          );

          if (result.startsWith('Mod saved to:')) {
            successCount++;
          } else {
            failCount++;
            results.add('[$modId] $result');
          }
        } catch (e) {
          failCount++;
          results.add('[$modId] Error: $e');
        }

        // Update progress after completing current mod
        state = state.copyWith(progress: (i + 1) / modIds.length);
      }

      state = state.copyWith(downloadingMods: false, progress: 0.0);

      if (modIds.length == 1) {
        return results.isEmpty ? 'Mod downloaded successfully' : results.first;
      } else {
        final summary =
            'Downloaded $successCount of ${modIds.length} mods successfully';
        return failCount > 0
            ? '$summary\n\nFailed:\n${results.join('\n')}'
            : summary;
      }
    } catch (e) {
      state = state.copyWith(downloadingMods: false, progress: 0.0);
      return 'Error: $e';
    }
  }

  Future<String> _downloadSingleMod({
    required String modId,
    required String targetDirectory,
    required int currentIndex,
    required int totalCount,
  }) async {
    final baseProgress = currentIndex / totalCount;
    final segmentSize = 1.0 / totalCount;

    // Update progress: 25% - fetching mod info
    state = state.copyWith(progress: baseProgress + (segmentSize * 0.25));

    final url = Uri.parse(getPublishedFileDetailsUrl);

    final response = await http.post(
      url,
      body: {
        'itemcount': '1',
        'publishedfileids[0]': modId,
      },
    );

    final responseData = json.decode(response.body);
    final fileDetails = responseData['response']['publishedfiledetails'][0];

    final consumerAppId = fileDetails['consumer_app_id'];
    if (consumerAppId != 286160) {
      return 'Consumer app ID does not match. Expected: 286160, Got: $consumerAppId';
    }

    final fileUrl = fileDetails['file_url'];
    final previewUrl = fileDetails['preview_url'];
    final timeUpdated = fileDetails['time_updated'] as int;

    // Update progress: 50% - downloading BSON
    state = state.copyWith(progress: baseProgress + (segmentSize * 0.5));

    final bsonResult = await _downloadAndConvertBson(
      fileUrl: fileUrl,
      modId: modId,
      targetDirectory: targetDirectory,
      timeUpdated: timeUpdated,
    );

    if (!bsonResult.startsWith('Mod saved to:')) {
      return bsonResult;
    }

    // Update progress: 75% - downloading image
    state = state.copyWith(progress: baseProgress + (segmentSize * 0.75));

    await _downloadAndResizeImage(
      imageUrl: previewUrl,
      modId: modId,
      targetDirectory: targetDirectory,
    );

    // Add the newly downloaded mod to state
    final jsonFilePath = '$targetDirectory/$modId.json';
    await ref.read(modsProvider.notifier).addSingleMod(
          jsonFilePath,
          ModTypeEnum.mod,
        );

    return bsonResult;
  }

  Future<String> _downloadAndConvertBson({
    required dynamic fileUrl,
    required String modId,
    required String targetDirectory,
    required int timeUpdated,
  }) async {
    try {
      if (fileUrl is! String) {
        return "Invalid url: $fileUrl";
      }

      final response = await http.get(Uri.parse(fileUrl));
      if (response.statusCode != 200) {
        return "Failed to download BSON file from $fileUrl";
      }

      final bsonBinary = BsonBinary.from(response.bodyBytes);
      final decodedData = BsonCodec.deserialize(bsonBinary);
      decodedData.removeWhere((key, value) => value is BsonBinary);

      final jsonEncoder = JsonEncoder.withIndent('  ', (object) {
        if (object is Int64) return object.toString();
        return object;
      });

      final jsonString = jsonEncoder.convert(decodedData);

      final filePath = '$targetDirectory/$modId.json';
      final file = File(filePath);

      await file.writeAsString(jsonString);
      return 'Mod saved to: $filePath';
    } catch (e) {
      return 'Error for mod json file: $e';
    }
  }

  Future<void> _downloadAndResizeImage({
    required dynamic imageUrl,
    required String modId,
    required String targetDirectory,
  }) async {
    if (imageUrl is! String) {
      return;
    }

    try {
      // Download the image
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode != 200) {
        debugPrint('Failed to download image');
        return;
      }

      // Decode the image
      final originalImage = img.decodeImage(response.bodyBytes);
      if (originalImage == null) {
        debugPrint('Failed to decode image');
        return;
      }

      // First save the original at maximum quality
      final tempPath = '$targetDirectory/${modId}_temp.png';
      final tempFile = File(tempPath);
      await tempFile.writeAsBytes(img.encodePng(
        originalImage,
        level: 0,
      ));

      // Read back the uncompressed image
      final uncompressedBytes = await tempFile.readAsBytes();
      final uncompressedImage = img.decodeImage(uncompressedBytes);
      if (uncompressedImage == null) {
        debugPrint('Failed to decode uncompressed image');
        return;
      }

      // Now resize from the uncompressed version
      final resizedImage = img.copyResizeCropSquare(
        uncompressedImage,
        size: 256,
        interpolation: img.Interpolation.cubic,
      );

      // Save the final resized image with minimal compression
      final finalPath = '$targetDirectory/$modId.png';
      final finalFile = File(finalPath);

      await finalFile.writeAsBytes(img.encodePng(
        resizedImage,
        level: 0, // Keep using no compression for best quality
      ));

      // Clean up temp file
      await tempFile.delete();

      debugPrint('Image saved to: $finalPath');
    } catch (e) {
      debugPrint('Error processing image: $e');
    }
  }
}
