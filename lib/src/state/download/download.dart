import 'dart:convert' show JsonEncoder, json;
import 'dart:io' show Directory, File;
import 'dart:isolate' show Isolate, ReceivePort;

import 'package:archive/archive_io.dart' show ZipFileEncoder;
import 'package:bson/bson.dart' show BsonBinary, BsonCodec;
import 'package:dio/dio.dart'
    show CancelToken, Dio, DioException, DioExceptionType, Options;
import 'package:file_picker/file_picker.dart' show FilePicker;
import 'package:fixnum/fixnum.dart' show Int64;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show debugPrint;
import 'package:hooks_riverpod/hooks_riverpod.dart' show Ref, StateNotifier;
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:collection/collection.dart' show IterableExtension;
import 'package:tts_mod_vault/src/state/backup/backup_state.dart'
    show
        BackupCompleteMessage,
        BackupIsolateData,
        BackupProgressMessage,
        FilepathsIsolateData;
import 'package:tts_mod_vault/src/state/backup/models/existing_backup_model.dart'
    show ExistingBackup;
import 'package:tts_mod_vault/src/state/bulk_actions/mod_update_result.dart'
    show DownloadModUpdatesResult, ModUpdateResult, ModUpdateStatus;
import 'package:tts_mod_vault/src/state/download/download_by_id_result.dart'
    show DownloadByIdResult, DownloadByIdSummary;
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
        existingBackupsProvider,
        logProvider,
        modsProvider,
        selectedModProvider,
        settingsProvider;
import 'package:tts_mod_vault/src/utils.dart'
    show
        getBackupFilenameByMod,
        getExtensionByType,
        getFileNameFromURL,
        newSteamUserContentUrl,
        getPublishedFileDetailsUrl;

import 'package:path/path.dart' as p;

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
      isDownloading: false,
      cancelledDownloads: true,
      progress: 0.0,
      statusMessage: null,
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

    ref
        .read(logProvider.notifier)
        .addInfo('Starting download for: ${mod.saveName}');

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

    ref
        .read(logProvider.notifier)
        .addSuccess('Download completed: ${mod.saveName}');

    resetState();
  }

  void resetState() {
    state = const DownloadState();
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
        isDownloading: true,
        progress: 0.01,
        statusMessage: 'Downloading ${type.label}',
      );

      final int batchSize = ref.read(settingsProvider).concurrentDownloads;

      for (int i = 0; i < urls.length; i += batchSize) {
        if (state.cancelledDownloads) {
          break;
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
          final tempPath = p.join(directory, '${fileName}_temp');

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
              final finalPath = p.join(directory,
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
          final completed = (i + batch.length).clamp(0, urls.length);
          state = state.copyWith(
            statusMessage:
                'Downloading ${type.label} $completed/${urls.length}',
            progress: (completed / urls.length).clamp(0.0, 1.0),
          );
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

    if (await _checkUrl(httpsUrl)) {
      return httpsUrl;
    } else if (await _checkUrl(httpUrl)) {
      return httpUrl;
    } else {
      return url; // Could not resolve; return original
    }
  }

  /// Core URL checking logic (no scheme resolution to avoid circular dependency)
  /// Returns true if the URL returns a valid response (200-399 status code)
  /// First tries HEAD request, then falls back to GET if HEAD fails (some servers don't support HEAD)
  Future<bool> _checkUrl(String url) async {
    try {
      // Try HEAD request first (faster, doesn't download content)
      try {
        final headResponse = await dio.request(
          url,
          options: Options(
            method: 'HEAD',
            validateStatus: (status) => status != null && status < 500,
            followRedirects: true,
            maxRedirects: 5,
          ),
        );

        // Consider 2xx and 3xx as live
        if (headResponse.statusCode != null && headResponse.statusCode! < 400) {
          return true;
        }
      } catch (headError) {
        debugPrint('HEAD request failed for $url, trying GET: $headError');
      }

      // Fallback to GET request with range header (only download first byte to check if URL works)
      final getResponse = await dio.request(
        url,
        options: Options(
          method: 'GET',
          headers: {
            'Range': 'bytes=0-0', // Only request first byte
          },
          validateStatus: (status) => status != null && status < 500,
          followRedirects: true,
          maxRedirects: 5,
        ),
      );

      // Consider 2xx (200-299) and partial content (206) as live
      // Also accept 3xx redirects
      return getResponse.statusCode != null &&
          (getResponse.statusCode! < 400 || getResponse.statusCode == 206);
    } catch (e) {
      return false;
    }
  }

  /// Checks if a URL is live (not invalid/404)
  /// Returns true if the URL returns a valid response (200-399 status code)
  /// First tries HEAD request, then falls back to GET if HEAD fails (some servers don't support HEAD)
  Future<bool> isUrlLive(String url) async {
    try {
      // Resolve URL with scheme if needed
      final resolvedUrl = await resolveUrlWithScheme(url);
      return await _checkUrl(resolvedUrl);
    } catch (e) {
      debugPrint('Error checking URL $url: $e');
      return false;
    }
  }

  /// Checks all URLs in a mod to see if they're still live
  /// Returns a list of URLs that are invalid
  /// The onComplete callback is called after the state is reset, allowing dialogs to be shown
  Future<void> checkModUrlsLive(
    Mod mod, {
    void Function(List<String> invalidUrls)? onComplete,
  }) async {
    final invalidUrls = <String>[];

    if (mod.assetLists == null) {
      onComplete?.call([]);
      return;
    }

    final allAssets = mod.getAllAssets();
    final int batchSize = ref.read(settingsProvider).concurrentDownloads;

    try {
      state = state.copyWith(
        isDownloading: true,
        progress: 0.0,
        statusMessage: 'Checked 0/${allAssets.length} URLs',
      );

      for (int i = 0; i < allAssets.length; i += batchSize) {
        if (state.cancelledDownloads) {
          break;
        }

        final batch = allAssets.sublist(
          i,
          i + batchSize > allAssets.length ? allAssets.length : i + batchSize,
        );

        await Future.wait(batch.map((asset) async {
          final isLive = await isUrlLive(asset.url);
          if (!isLive) invalidUrls.add(asset.url);
        }));

        // Update progress after each batch
        final checked = (i + batch.length).clamp(0, allAssets.length);
        state = state.copyWith(
          statusMessage: 'Checked $checked/${allAssets.length} URLs',
          progress: (checked / allAssets.length).clamp(0.0, 1.0),
        );
      }
    } finally {
      state = state.copyWith(
        isDownloading: false,
        progress: 0.0,
        statusMessage: null,
        cancelledDownloads: false,
      );

      // Call the callback after state is reset, so the UI has returned to normal
      // and the dialog context will be valid
      onComplete?.call(invalidUrls);
    }
  }

  Future<DownloadModUpdatesResult> downloadModUpdates({
    required List<Mod> mods,
    bool forceUpdate = false,
  }) async {
    if (mods.isEmpty) {
      return const DownloadModUpdatesResult(
        results: [],
        successCount: 0,
        failCount: 0,
        skippedCount: 0,
        summaryMessage: 'No mods selected',
      );
    }

    try {
      state = state.copyWith(
        isDownloading: true,
        progress: 0.01,
        statusMessage: 'Updating mods',
      );

      // Check which mods need updating
      final modsToUpdate = <({
        String modId,
        String directory,
        int currentEpoch,
        Map<String, dynamic>? fileDetails
      })>[];

      for (final mod in mods) {
        // Extract mod ID from filename (remove .json extension)
        final modId = mod.jsonFileName.replaceAll('.json', '');
        final directory = p.dirname(mod.jsonFilePath);

        // Get current epoch from mod's dateTimeStamp (which contains EpochTime)
        final currentEpoch = mod.dateTimeStamp != null
            ? int.tryParse(mod.dateTimeStamp!) ?? 0
            : 0;

        if (forceUpdate) {
          // Force update - add all mods to the update list (without fileDetails)
          modsToUpdate.add((
            modId: modId,
            directory: directory,
            currentEpoch: currentEpoch,
            fileDetails: null,
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
              fileDetails: fileDetails,
            ));
          }
        }
      }

      if (modsToUpdate.isEmpty) {
        state = state.copyWith(
          isDownloading: false,
          progress: 0.0,
          statusMessage: null,
        );

        // All mods are already up to date
        final upToDateResults = mods
            .map((mod) => ModUpdateResult(
                  modId: mod.jsonFileName.replaceAll('.json', ''),
                  modName: mod.saveName,
                  status: ModUpdateStatus.upToDate,
                ))
            .toList();

        final summaryMsg = mods.length == 1
            ? 'Mod is already up to date'
            : 'All mods are already up to date';

        return DownloadModUpdatesResult(
          results: upToDateResults,
          successCount: 0,
          failCount: 0,
          skippedCount: mods.length,
          summaryMessage: summaryMsg,
        );
      }

      // Download the mods that need updating
      final results = <ModUpdateResult>[];
      final errorMessages = <String>[];
      int successCount = 0;
      int failCount = 0;

      for (int i = 0; i < modsToUpdate.length; i++) {
        final modInfo = modsToUpdate[i];
        final mod = mods.firstWhere(
            (m) => m.jsonFileName.replaceAll('.json', '') == modInfo.modId);

        try {
          final result = await _downloadSingleMod(
            modId: modInfo.modId,
            targetDirectory: modInfo.directory,
            currentIndex: i,
            totalCount: modsToUpdate.length,
            fileDetails: modInfo.fileDetails,
          );

          if (result.startsWith('Mod saved to:')) {
            successCount++;
            results.add(ModUpdateResult(
              modId: modInfo.modId,
              modName: mod.saveName,
              status: ModUpdateStatus.updated,
            ));
          } else {
            failCount++;
            results.add(ModUpdateResult(
              modId: modInfo.modId,
              modName: mod.saveName,
              status: ModUpdateStatus.failed,
              errorMessage: result,
            ));
            errorMessages.add('[${modInfo.modId}] $result');
          }
        } catch (e) {
          failCount++;

          results.add(ModUpdateResult(
            modId: modInfo.modId,
            modName: mod.saveName,
            status: ModUpdateStatus.failed,
            errorMessage: e.toString(),
          ));
          errorMessages.add('[${modInfo.modId}] Error: $e');
        }

        state = state.copyWith(
          statusMessage: modsToUpdate.length == 1
              ? 'Updating ${mods[0].saveName}'
              : 'Updating mods ${i + 1}/${modsToUpdate.length}',
          progress: ((i + 1) / modsToUpdate.length).clamp(0.0, 1.0),
        );
      }

      state = state.copyWith(
        isDownloading: false,
        progress: 0.0,
        statusMessage: null,
      );

      final skippedCount = mods.length - modsToUpdate.length;

      // Add skipped mods (already up to date) to results
      for (final mod in mods) {
        final modId = mod.jsonFileName.replaceAll('.json', '');
        if (!results.any((r) => r.modId == modId)) {
          results.add(ModUpdateResult(
            modId: modId,
            modName: mod.saveName,
            status: ModUpdateStatus.upToDate,
          ));
        }
      }

      String summary =
          'Updated $successCount of ${modsToUpdate.length} mods${skippedCount > 0 ? ' ($skippedCount already up to date)' : ''}';

      if (successCount == 1 && modsToUpdate.length == 1 && mods.length == 1) {
        summary = 'Updated ${mods[0].saveName}';
        ref.read(logProvider.notifier).addSuccess(summary);
      } else if (failCount > 0) {
        ref
            .read(logProvider.notifier)
            .addWarning('$summary ($failCount failed)');
      } else {
        ref.read(logProvider.notifier).addSuccess(summary);
      }

      final summaryMessage = failCount > 0
          ? '$summary\n\nFailed:\n${errorMessages.join('\n')}'
          : summary;

      return DownloadModUpdatesResult(
        results: results,
        successCount: successCount,
        failCount: failCount,
        skippedCount: skippedCount,
        summaryMessage: summaryMessage,
      );
    } catch (e) {
      state = state.copyWith(
        isDownloading: false,
        progress: 0.0,
        statusMessage: null,
      );
      ref.read(logProvider.notifier).addError('Download mod updates error: $e');

      // Return error results for all mods
      final eString = e.toString();
      String errorMessage = eString;
      if (eString.contains("NoSuchMethod")) {
        errorMessage = "Mod is not available on the Workshop";
      }
      if (eString.contains(
          "type 'Null' is not a subtype of type 'int' in type cast")) {
        errorMessage = "Mod is unlisted on the Workshop - cannot update";
      }

      final errorResults = mods
          .map((mod) => ModUpdateResult(
                modId: mod.jsonFileName.replaceAll('.json', ''),
                modName: mod.saveName,
                status: ModUpdateStatus.failed,
                errorMessage: errorMessage,
              ))
          .toList();

      return DownloadModUpdatesResult(
        results: errorResults,
        successCount: 0,
        failCount: mods.length,
        skippedCount: 0,
        summaryMessage: 'Error: $e',
      );
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
      state = state.copyWith(
        // isDownloading: true, // Commented out to not show download progress bar in selected mod view
        progress: 0.01,
        statusMessage: 'Downloading mods',
      );

      final downloadResults = <DownloadByIdResult>[];

      for (int i = 0; i < modIds.length; i++) {
        final modId = modIds[i].trim();
        if (modId.isEmpty) continue;

        // Show partial progress for current mod (starts at 25% of the segment)
        final baseProgress = i / modIds.length;
        final segmentSize = 1.0 / modIds.length;
        state = state.copyWith(progress: baseProgress + (segmentSize * 0.25));

        String? modName;
        bool success = false;
        String? errorMessage;

        try {
          final result = await _downloadSingleMod(
            modId: modId,
            targetDirectory: targetDirectory,
            currentIndex: i,
            totalCount: modIds.length,
          );

          if (result.startsWith('Mod saved to:')) {
            success = true;
            // Try to get the mod name from the newly added mod
            final jsonFilePath = '$targetDirectory/$modId.json';
            final mods = ref.read(modsProvider.notifier).getAllMods();
            final addedMod =
                mods.firstWhereOrNull((m) => m.jsonFilePath == jsonFilePath);
            modName = addedMod?.saveName;
          } else {
            errorMessage = result;
          }
        } catch (e) {
          final eString = e.toString();
          if (eString.contains("NoSuchMethod")) {
            errorMessage = "Mod is not available on the Workshop";
          } else if (eString.contains(
              "type 'Null' is not a subtype of type 'int' in type cast")) {
            errorMessage = "Mod is unlisted - cannot download";
          } else {
            errorMessage = 'Error: $e';
          }
        }

        downloadResults.add(DownloadByIdResult(
          modId: modId,
          modName: modName,
          success: success,
          errorMessage: errorMessage,
        ));

        // Update progress after completing current mod
        state = state.copyWith(
          statusMessage: 'Downloading mods ${i + 1}/${modIds.length}',
          progress: ((i + 1) / modIds.length).clamp(0.0, 1.0),
        );
      }

      state = state.copyWith(
        isDownloading: false,
        progress: 0.0,
        statusMessage: null,
      );

      final summary = DownloadByIdSummary(downloadResults);
      final message = summary.toDisplayString();

      if (modIds.length == 1) {
        if (summary.successCount > 0) {
          ref.read(logProvider.notifier).addSuccess(message);
        } else {
          ref.read(logProvider.notifier).addError(message);
        }
      } else {
        if (summary.failCount > 0) {
          ref.read(logProvider.notifier).addWarning(
              'Downloaded ${summary.successCount} of ${summary.totalCount} mods successfully (${summary.failCount} failed)');
        } else {
          ref.read(logProvider.notifier).addSuccess(
              'Downloaded ${summary.successCount} of ${summary.totalCount} mods successfully');
        }
      }

      return message;
    } catch (e) {
      state = state.copyWith(
        isDownloading: false,
        progress: 0.0,
        statusMessage: null,
      );
      ref.read(logProvider.notifier).addError('Download mods by ID error: $e');
      return 'Error: $e';
    }
  }

  /// Downloads assets to temp folder, creates backups, then deletes temp folder
  /// This is useful for creating backups without permanently storing assets
  Future<String> downloadBackupAndDeleteAssets({
    required List<Mod> mods,
    String? backupDirectory,
  }) async {
    if (mods.isEmpty) {
      return 'No mods provided';
    }

    String? backupDirPath = backupDirectory;
    Directory? tempDownloadDir;

    try {
      // 1. Initialization Phase
      state = state.copyWith(
        isDownloading: true,
        progress: 0.01,
        statusMessage: 'Downloading assets for backup',
      );

      // Track results
      final results = <({String modName, bool success, String? error})>[];

      // Prompt for backup directory if not provided
      if (backupDirPath == null || backupDirPath.isEmpty) {
        final backupsDir = ref.read(directoriesProvider).backupsDir;
        backupDirPath = await FilePicker.platform.getDirectoryPath(
          lockParentWindow: true,
          initialDirectory: backupsDir.isEmpty ? null : backupsDir,
        );

        if (backupDirPath == null) {
          state = state.copyWith(
            isDownloading: false,
            progress: 0.0,
            statusMessage: null,
          );
          return 'Backup directory selection cancelled';
        }
      }

      // Create temporary download folder structure
      final tempDownloadPath = p.join(backupDirPath, '_tempDownload');
      tempDownloadDir = Directory(tempDownloadPath);
      await tempDownloadDir.create(recursive: true);

      // Create subdirectories for each asset type
      final tempDirs = <AssetTypeEnum, String>{};
      for (final type in AssetTypeEnum.values) {
        final typeDir = p.join(tempDownloadPath, type.name);
        await Directory(typeDir).create(recursive: true);
        tempDirs[type] = typeDir;
      }

      // 2. Main Processing Loop
      for (int i = 0; i < mods.length; i++) {
        final mod = mods[i];
        final baseProgress = i / mods.length;
        final segmentSize = 1.0 / mods.length;

        // Check for cancellation
        if (state.cancelledDownloads) {
          break;
        }

        debugPrint('Processing mod ${i + 1}/${mods.length}: ${mod.saveName}');

        try {
          // A. Download Phase (to temp folder)
          if (mod.assetLists != null) {
            await _downloadFilesToCustomDirectory(
              modAssetListUrls:
                  mod.assetLists!.assetBundles.map((e) => e.url).toList(),
              type: AssetTypeEnum.assetBundle,
              targetDirectory: tempDirs[AssetTypeEnum.assetBundle]!,
            );

            await _downloadFilesToCustomDirectory(
              modAssetListUrls:
                  mod.assetLists!.audio.map((e) => e.url).toList(),
              type: AssetTypeEnum.audio,
              targetDirectory: tempDirs[AssetTypeEnum.audio]!,
            );

            await _downloadFilesToCustomDirectory(
              modAssetListUrls:
                  mod.assetLists!.images.map((e) => e.url).toList(),
              type: AssetTypeEnum.image,
              targetDirectory: tempDirs[AssetTypeEnum.image]!,
            );

            await _downloadFilesToCustomDirectory(
              modAssetListUrls:
                  mod.assetLists!.models.map((e) => e.url).toList(),
              type: AssetTypeEnum.model,
              targetDirectory: tempDirs[AssetTypeEnum.model]!,
            );

            await _downloadFilesToCustomDirectory(
              modAssetListUrls: mod.assetLists!.pdf.map((e) => e.url).toList(),
              type: AssetTypeEnum.pdf,
              targetDirectory: tempDirs[AssetTypeEnum.pdf]!,
            );
          }

          state = state.copyWith(progress: baseProgress + (segmentSize * 0.4));

          // Check for cancellation
          if (state.cancelledDownloads) {
            break;
          }

          // B. Create Backup from Temp Files
          final backupSuccess = await _createBackupFromCustomDirectories(
            mod: mod,
            backupDirectory: backupDirPath,
            assetDirectories: tempDirs,
          );

          state = state.copyWith(progress: baseProgress + (segmentSize * 0.8));

          // C. Track Results
          if (backupSuccess) {
            results.add((
              modName: mod.saveName,
              success: true,
              error: null,
            ));
            debugPrint('✓ Successfully processed: ${mod.saveName}');
          } else {
            results.add((
              modName: mod.saveName,
              success: false,
              error: 'Backup creation failed',
            ));
            debugPrint('✗ Failed to process: ${mod.saveName}');
          }

          state = state.copyWith(progress: baseProgress + segmentSize);

          // Yield to UI
          await Future.delayed(Duration.zero);
        } catch (e) {
          results.add((
            modName: mod.saveName,
            success: false,
            error: e.toString(),
          ));
          debugPrint('✗ Error processing ${mod.saveName}: $e');
        }
      }

      // 3. Build Result Summary
      final successCount = results.where((r) => r.success).length;
      final failedResults = results.where((r) => !r.success).toList();

      if (state.cancelledDownloads) {
        return 'Operation cancelled by user. Processed $successCount of ${mods.length} mods successfully.';
      }

      if (mods.length == 1) {
        final message = results.first.success
            ? 'Backup created successfully for ${mods[0].saveName}'
            : 'Failed to create backup: ${results.first.error ?? "Unknown error"}';
        if (results.first.success) {
          ref.read(logProvider.notifier).addSuccess(message);
        } else {
          ref.read(logProvider.notifier).addError(message);
        }
        return message;
      }

      final summary =
          'Processed $successCount of ${mods.length} mods successfully';

      if (failedResults.isEmpty) {
        ref.read(logProvider.notifier).addSuccess(summary);
        return summary;
      } else {
        final failureDetails = failedResults
            .map((r) => '[${r.modName}] ${r.error ?? "Unknown error"}')
            .join('\n');
        ref
            .read(logProvider.notifier)
            .addWarning('$summary (${failedResults.length} failed)');
        return '$summary\n\nFailed:\n$failureDetails';
      }
    } catch (e) {
      debugPrint('downloadBackupAndDeleteAssets error: $e');
      ref.read(logProvider.notifier).addError('Download backup error: $e');
      return 'Error: $e';
    } finally {
      // 4. Cleanup Phase - Always attempt to delete temp folder
      if (tempDownloadDir != null) {
        try {
          if (await tempDownloadDir.exists()) {
            await tempDownloadDir.delete(recursive: true);
            debugPrint('Cleaned up temporary download folder');
          }
        } catch (e) {
          debugPrint('Failed to delete temp download folder: $e');
          // Don't fail the operation if cleanup fails
        }
      }

      // Reset state
      resetState();
    }
  }

  Future<String> _downloadSingleMod({
    required String modId,
    required String targetDirectory,
    required int currentIndex,
    required int totalCount,
    Map<String, dynamic>? fileDetails,
  }) async {
    final baseProgress = currentIndex / totalCount;
    final segmentSize = 1.0 / totalCount;

    // Update progress: 25% - fetching mod info
    state = state.copyWith(progress: baseProgress + (segmentSize * 0.25));

    // If fileDetails not provided, fetch from API
    late final Map<String, dynamic> details;
    if (fileDetails == null) {
      final url = Uri.parse(getPublishedFileDetailsUrl);

      final response = await http.post(
        url,
        body: {
          'itemcount': '1',
          'publishedfileids[0]': modId,
        },
      );

      final responseData = json.decode(response.body);
      details = responseData['response']['publishedfiledetails'][0];
    } else {
      details = fileDetails;
    }

    final consumerAppId = details['consumer_app_id'];
    if (consumerAppId != 286160) {
      return 'Consumer app ID does not match. Expected: 286160, Got: $consumerAppId';
    }

    final fileUrl = details['file_url'];
    final previewUrl = details['preview_url'];
    final timeUpdated = details['time_updated'] as int;
    final title = details['title'] as String?;

    // Update progress: 50% - downloading BSON
    state = state.copyWith(progress: baseProgress + (segmentSize * 0.5));

    final bsonResult = await _downloadAndConvertBson(
      fileUrl: fileUrl,
      modId: modId,
      targetDirectory: targetDirectory,
      timeUpdated: timeUpdated,
      title: title,
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
    String? title,
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

      // Overwrite SaveName with title from Steam API if provided
      if (title != null && title.isNotEmpty) {
        decodedData['SaveName'] = title;
      }

      // Add EpochTime if missing, and ensure it's the 2nd value in JSON
      if (!decodedData.containsKey('EpochTime')) {
        final reorderedData = <String, dynamic>{};
        final entries = decodedData.entries.toList();

        // Add first entry (usually SaveName)
        if (entries.isNotEmpty) {
          reorderedData[entries.first.key] = entries.first.value;
        }

        // Add EpochTime as 2nd entry
        reorderedData['EpochTime'] = timeUpdated;

        // Add remaining entries
        for (int i = 1; i < entries.length; i++) {
          reorderedData[entries[i].key] = entries[i].value;
        }

        decodedData.clear();
        decodedData.addAll(reorderedData);
      }

      // Log any problematic values before encoding
      if (kDebugMode) _findProblematicValues(decodedData, '');

      final jsonEncoder = JsonEncoder.withIndent('  ', (object) {
        if (object is Int64) return object.toString();
        if (object is double && object.isInfinite) {
          return "Infinity";
        }
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

  /// Recursively finds and logs problematic values (Infinity, NaN) in decoded BSON data
  void _findProblematicValues(dynamic data, String path) {
    if (data is Map) {
      for (final entry in data.entries) {
        final newPath =
            path.isEmpty ? entry.key.toString() : '$path.${entry.key}';
        _findProblematicValues(entry.value, newPath);
      }
    } else if (data is List) {
      for (int i = 0; i < data.length; i++) {
        _findProblematicValues(data[i], '$path[$i]');
      }
    } else if (data is double) {
      if (data.isInfinite) {
        debugPrint(
            '_findProblematicValues - Found Infinity at path: $path (value: $data)');
      } else if (data.isNaN) {
        debugPrint('_findProblematicValues - Found NaN at path: $path');
      }
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

  /// Creates a backup using custom asset directories (temp folders) instead of main directories
  /// Returns true on success, false on failure
  Future<bool> _createBackupFromCustomDirectories({
    required Mod mod,
    required String backupDirectory,
    required Map<AssetTypeEnum, String> assetDirectories,
  }) async {
    try {
      // 1. Create FilepathsIsolateData with temp directories
      final filepathsData = FilepathsIsolateData(mod, assetDirectories);

      // 2. Get file paths from temp directories
      final filePaths = await Isolate.run(
          () => _getFilePathsIsolateForDownload(filepathsData));
      final totalAssetCount = filePaths.$2;

      // 3. Prepare backup isolate data
      final receivePort = ReceivePort();
      final forceBackupJsonFilename =
          ref.read(settingsProvider).forceBackupJsonFilename;
      final backupFileName =
          getBackupFilenameByMod(mod, forceBackupJsonFilename);
      final targetBackupFilePath = p.join(backupDirectory, backupFileName);

      final modsDir = Directory(ref.read(directoriesProvider).modsDir);
      final savesDir = Directory(ref.read(directoriesProvider).savesDir);

      final isolateData = BackupIsolateData(
        filePaths: filePaths.$1,
        targetBackupFilePath: targetBackupFilePath,
        modsParentPath: modsDir.parent.path,
        savesParentPath: savesDir.parent.path,
        savesPath: savesDir.path,
        sendPort: receivePort.sendPort,
      );

      // 4. Start the backup isolate
      await Isolate.spawn(_backupIsolateForDownload, isolateData);

      // 5. Listen for messages from isolate
      await for (final message in receivePort) {
        if (message is BackupProgressMessage) {
          // Progress tracking (could update state if needed)
          debugPrint('Backup progress: ${message.current}/${message.total}');
        } else if (message is BackupCompleteMessage) {
          receivePort.close();

          if (message.success) {
            // Add new backup to state
            final newBackup = ExistingBackup(
              filename: backupFileName,
              filepath: targetBackupFilePath,
              lastModifiedTimestamp:
                  DateTime.now().millisecondsSinceEpoch ~/ 1000,
              totalAssetCount: totalAssetCount,
            );
            ref.read(existingBackupsProvider.notifier).addBackup(newBackup);
            return true;
          } else {
            debugPrint('Backup failed: ${message.message}');
            return false;
          }
        }
      }

      return false;
    } catch (e) {
      debugPrint('_createBackupFromCustomDirectories error: $e');
      return false;
    }
  }

  /// Downloads files to a custom directory (for temporary downloads)
  /// Similar to downloadFiles() but:
  /// - Uses targetDirectory parameter instead of directoriesProvider
  /// - Does NOT update existingAssetListsProvider (these are temp files)
  /// - Downloads ALL assets (no skip logic for existing files)
  Future<void> _downloadFilesToCustomDirectory({
    required List<String> modAssetListUrls,
    required AssetTypeEnum type,
    required String targetDirectory,
  }) async {
    if (modAssetListUrls.isEmpty) {
      return;
    }

    if (state.cancelledDownloads) {
      return;
    }

    try {
      state = state.copyWith(
        isDownloading: true,
        progress: 0.01,
        statusMessage: 'Downloading ${type.label}',
      );

      final int batchSize = ref.read(settingsProvider).concurrentDownloads;

      for (int i = 0; i < modAssetListUrls.length; i += batchSize) {
        if (state.cancelledDownloads) {
          break;
        }

        final batch = modAssetListUrls.sublist(
          i,
          i + batchSize > modAssetListUrls.length
              ? modAssetListUrls.length
              : i + batchSize,
        );

        await Future.wait(batch.map((originalUrl) async {
          // Set filename and path
          final fileName = getFileNameFromURL(originalUrl);
          final tempPath = p.join(targetDirectory, '${fileName}_temp');

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
              final finalPath = p.join(targetDirectory,
                  fileName + getExtensionByType(type, tempPath, bytes));
              await tempFile.rename(finalPath);
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
          final completed =
              (i + batch.length).clamp(0, modAssetListUrls.length);
          state = state.copyWith(
            statusMessage:
                'Downloading ${type.label} $completed/${modAssetListUrls.length}',
            progress: (completed / modAssetListUrls.length).clamp(0.0, 1.0),
          );
        }
      }
    } catch (e) {
      debugPrint('_downloadFilesToCustomDirectory error: $e');
    }
  }
}

// Helper functions for backup creation from custom directories
(List<String>, int) _getFilePathsIsolateForDownload(FilepathsIsolateData data) {
  final filePaths = <String>[];

  for (final type in AssetTypeEnum.values) {
    final dirPath = data.directories[type];
    if (dirPath == null) continue;

    final directory = Directory(dirPath);
    if (!directory.existsSync()) continue;

    final files = directory.listSync();
    data.mod.getAssetsByType(type).forEach((asset) {
      if (asset.filePath == null) return;

      final newUrlBase = p.basenameWithoutExtension(asset.filePath!);
      final oldUrlBase = newUrlBase.replaceFirst(
        getFileNameFromURL(newSteamUserContentUrl),
        getFileNameFromURL('https://cloud-3.steamusercontent.com/'),
      );

      final match = files.firstWhereOrNull((file) {
        final base = p.basenameWithoutExtension(file.path);
        return base.startsWith(newUrlBase) || base.startsWith(oldUrlBase);
      });

      if (match != null && match.path.isNotEmpty) {
        filePaths.add(p.normalize(match.path));
      }
    });
  }

  final assetFilesCount = filePaths.length;

  // Add JSON and image filepaths
  filePaths.add(data.mod.jsonFilePath);
  if (data.mod.imageFilePath != null && data.mod.imageFilePath!.isNotEmpty) {
    filePaths.add(data.mod.imageFilePath!);
  }

  return (filePaths, assetFilesCount);
}

void _backupIsolateForDownload(BackupIsolateData data) async {
  try {
    final encoder = ZipFileEncoder();
    encoder.create(data.targetBackupFilePath);

    for (int i = 0; i < data.filePaths.length; i++) {
      final filePath = data.filePaths[i];
      final file = File(filePath);

      if (!await file.exists()) {
        continue;
      }

      String? relativePath;

      if (filePath.startsWith(data.savesPath)) {
        relativePath = p.relative(filePath, from: data.savesParentPath);
      } else {
        relativePath = p.relative(filePath, from: data.modsParentPath);
      }

      encoder.addFile(file, relativePath);

      // Send progress message
      data.sendPort.send(BackupProgressMessage(i + 1, data.filePaths.length));
    }

    encoder.close();

    // Send completion message
    data.sendPort
        .send(BackupCompleteMessage(true, 'Backup created successfully'));
  } catch (e) {
    // Send error message
    data.sendPort.send(BackupCompleteMessage(false, 'Backup failed: $e'));
  }
}
