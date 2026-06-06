import 'dart:convert' show JsonEncoder, json;
import 'dart:io' show File, FileMode, HttpClient, RandomAccessFile;

import 'package:bson/bson.dart' show BsonBinary, BsonCodec;
import 'package:dio/dio.dart'
    show BaseOptions, CancelToken, Dio, DioException, DioExceptionType, Options;
import 'package:dio/io.dart' show IOHttpClientAdapter;
import 'package:fixnum/fixnum.dart' show Int64;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart' show debugPrint;
import 'package:hooks_riverpod/hooks_riverpod.dart' show Ref, StateNotifier;
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:collection/collection.dart' show IterableExtension;
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
        logProvider,
        modsProvider,
        selectedModProvider,
        settingsProvider;
import 'package:tts_mod_vault/src/utils.dart'
    show
        getExtensionByType,
        getFileNameFromURL,
        newSteamUserContentUrl,
        getPublishedFileDetailsUrl;

import 'package:path/path.dart' as p;

class DownloadNotifier extends StateNotifier<DownloadState> {
  final Ref ref;
  final Dio dio;

  // Active cancel tokens for in-flight downloads / URL checks
  final Set<CancelToken> _cancelTokens = {};

  DownloadNotifier(this.ref)
      : dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 15))),
        super(const DownloadState()) {
    _configureProxy();
  }

  void _configureProxy() {
    final proxyUrl = ref.read(settingsProvider).proxyUrl;
    (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient();
      if (proxyUrl.isNotEmpty) {
        client.findProxy = (uri) => 'PROXY $proxyUrl';
      } else {
        client.findProxy = null;
      }
      return client;
    };
  }

  void updateProxySettings() {
    _configureProxy();
  }

  // MARK: Cancel DL button
  Future<void> handleCancelDownloadsButton() async {
    await ref.read(downloadProvider.notifier).cancelAllDownloads();
    if (ref.read(selectedModProvider) != null) {
      await ref
          .read(modsProvider.notifier)
          .updateSelectedMod(ref.read(selectedModProvider)!);
    }
  }

  // MARK: Cancel all DLs
  Future<void> cancelAllDownloads() async {
    state = state.copyWith(
      isDownloading: false,
      cancelledDownloads: true,
      progress: 0.0,
      statusMessage: null,
    );

    for (final token in _cancelTokens) {
      token.cancel('All downloads cancelled by user');
    }
    _cancelTokens.clear();
  }

  // MARK: DL all files
  Future<Set<String>> downloadAllFiles(Mod mod) async {
    ref
        .read(logProvider.notifier)
        .addInfo('Starting download for: ${mod.saveName}');

    // Clear any sticky cancel flag from a previous run
    if (state.cancelledDownloads) {
      state = state.copyWith(cancelledDownloads: false);
    }

    final Set<String> allDownloaded = {};

    allDownloaded.addAll(await downloadFiles(
      modAssetListUrls: mod.assetLists.assetBundles
          .where((e) => !e.fileExists)
          .map((e) => e.url)
          .toList(),
      type: AssetTypeEnum.assetBundle,
    ));

    allDownloaded.addAll(await downloadFiles(
      modAssetListUrls: mod.assetLists.audio
          .where((e) => !e.fileExists)
          .map((e) => e.url)
          .toList(),
      type: AssetTypeEnum.audio,
    ));

    allDownloaded.addAll(await downloadFiles(
      modAssetListUrls: mod.assetLists.images
          .where((e) => !e.fileExists)
          .map((e) => e.url)
          .toList(),
      type: AssetTypeEnum.image,
    ));

    allDownloaded.addAll(await downloadFiles(
      modAssetListUrls: mod.assetLists.models
          .where((e) => !e.fileExists)
          .map((e) => e.url)
          .toList(),
      type: AssetTypeEnum.model,
    ));

    allDownloaded.addAll(await downloadFiles(
      modAssetListUrls: mod.assetLists.pdf
          .where((e) => !e.fileExists)
          .map((e) => e.url)
          .toList(),
      type: AssetTypeEnum.pdf,
    ));

    ref
        .read(logProvider.notifier)
        .addSuccess('Download completed: ${mod.saveName}');

    resetState();
    return allDownloaded;
  }

  // MARK: Reset state
  void resetState() {
    state = const DownloadState();
  }

  // MARK: DL URL
  Future<void> _downloadUrl(
    String url,
    String tempPath,
    CancelToken cancelToken, {
    void Function(double fraction)? onProgress,
  }) async {
    await dio.download(
      url,
      tempPath,
      cancelToken: cancelToken,
      options: Options(
        receiveTimeout: const Duration(seconds: 60),
      ),
      onReceiveProgress: (received, total) {
        if (total <= 0) return;
        onProgress?.call(received / total);
      },
    );
  }

  // MARK: DL URL w/ retry
  /// Wraps [_downloadUrl] with exponential backoff for transient failures.
  /// Retries on connection/receive timeouts, connection errors, and 5xx.
  /// Does not retry on cancel or 4xx.
  Future<void> _downloadUrlWithRetry(
    String url,
    String tempPath,
    CancelToken cancelToken, {
    void Function(double fraction)? onProgress,
    int maxAttempts = 3,
  }) async {
    int attempt = 0;
    while (true) {
      attempt++;
      try {
        await _downloadUrl(url, tempPath, cancelToken, onProgress: onProgress);
        return;
      } on DioException catch (e) {
        if (attempt >= maxAttempts ||
            cancelToken.isCancelled ||
            !_isRetryableDioError(e)) {
          rethrow;
        }
        final delayMs = 500 * (1 << (attempt - 1)); // 500, 1000, 2000
        debugPrint(
            'Retrying download (attempt ${attempt + 1}/$maxAttempts) '
            'after ${delayMs}ms for $url: ${e.type}');
        await Future.delayed(Duration(milliseconds: delayMs));
      }
    }
  }

  bool _isRetryableDioError(DioException e) {
    if (e.type == DioExceptionType.cancel) return false;
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return true;
    }
    final code = e.response?.statusCode;
    return code != null && code >= 500 && code < 600;
  }

  // MARK: DL FILES
  Future<List<String>> downloadFiles({
    required List<String> modAssetListUrls,
    required AssetTypeEnum type,
    bool downloadingAllFiles = true,
  }) async {
    if (modAssetListUrls.isEmpty) {
      return [];
    }

    if (state.cancelledDownloads) {
      // Within a bulk run, the flag short-circuits remaining types.
      // For a standalone single-asset call, clear it and start fresh.
      if (downloadingAllFiles) {
        return [];
      }
      state = state.copyWith(cancelledDownloads: false);
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

      final ignoredDomains = ref.read(settingsProvider).ignoredDomains;
      final int workerCount = ref.read(settingsProvider).concurrentDownloads;

      // Worker-pool state: file-count progress + per-active-job byte fraction
      int completed = 0;
      final progressByJob = <int, double>{};

      void publishProgress() {
        final fractional = progressByJob.values
            .fold<double>(0, (acc, v) => acc + v);
        final p = ((completed + fractional) / urls.length).clamp(0.0, 1.0);
        state = state.copyWith(
          statusMessage: 'Downloading ${type.label} $completed/${urls.length}',
          progress: p,
        );
      }

      Future<void> processOne(int jobId, String originalUrl) async {
        CancelToken? cancelToken;
        String? tempPath;
        String urlForLog = originalUrl;

        try {
          // Skip if URL domain is in ignored list
          if (ignoredDomains.isNotEmpty) {
            final uri = Uri.tryParse(originalUrl);
            if (uri != null &&
                ignoredDomains.any((d) => uri.host.contains(d))) {
              return;
            }
          }

          // Set filename and path
          final fileName = getFileNameFromURL(originalUrl);
          final directory =
              ref.read(directoriesProvider.notifier).getDirectoryByType(type);
          tempPath = p.join(directory, '${fileName}_temp');

          // Set url and cancel token
          final url = await resolveUrlWithScheme(originalUrl);
          urlForLog = url;
          cancelToken = CancelToken();
          _cancelTokens.add(cancelToken);

          if (state.cancelledDownloads) return;

          void onProgress(double fraction) {
            progressByJob[jobId] = fraction;
            publishProgress();
          }

          try {
            await _downloadUrlWithRetry(url, tempPath, cancelToken,
                onProgress: onProgress);
          } on DioException catch (e) {
            // Check is Steam CDN url missing a trailing '/'
            if (e.response?.statusCode == 404 &&
                url.startsWith(newSteamUserContentUrl) &&
                !url.endsWith('/')) {
              await _downloadUrlWithRetry('$url/', tempPath, cancelToken,
                  onProgress: onProgress);
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
        } catch (e) {
          if (tempPath != null) {
            try {
              if (await File(tempPath).exists()) {
                await File(tempPath).delete();
              }
            } catch (e) {
              debugPrint('Error deleting file after download error $e');
            }
          }

          // Handle cancellation specifically
          if (e is DioException && e.type == DioExceptionType.cancel) {
            debugPrint('Download cancelled for $urlForLog');
          } else {
            debugPrint('Error occurred while downloading files: $e');
          }
        } finally {
          if (cancelToken != null) _cancelTokens.remove(cancelToken);
          progressByJob.remove(jobId);
          completed++;
          publishProgress();
        }
      }

      // Hand-rolled worker pool: each worker pulls the next URL by atomic
      // index increment (safe because Dart is single-threaded). A finished
      // worker immediately picks the next URL — no head-of-line blocking
      // from a slow file like the previous fixed-batch Future.wait did.
      int nextIndex = 0;
      final workers = List.generate(workerCount, (_) async {
        while (true) {
          if (state.cancelledDownloads) return;
          if (nextIndex >= urls.length) return;
          final myIndex = nextIndex++;
          await processOne(myIndex, urls[myIndex]);
        }
      });

      await Future.wait(workers);
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

    return successfulDownloads.map((e) => e.$1).toList();
  }

  // MARK: Resolve URL
  Future<String> resolveUrlWithScheme(String url,
      {CancelToken? cancelToken}) async {
    // If URL already starts with http/https, return it directly
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }

    final httpsUrl = 'https://$url';
    final httpUrl = 'http://$url';

    if (await _checkUrl(httpsUrl, cancelToken: cancelToken)) {
      return httpsUrl;
    } else if (await _checkUrl(httpUrl, cancelToken: cancelToken)) {
      return httpUrl;
    } else {
      return url; // Could not resolve; return original
    }
  }

  // MARK: Check URL
  /// Core URL checking logic (no scheme resolution to avoid circular dependency)
  /// Returns true if the URL returns a valid response (200-399 status code)
  /// First tries HEAD request, then falls back to GET if HEAD fails (some servers don't support HEAD)
  Future<bool> _checkUrl(String url, {CancelToken? cancelToken}) async {
    try {
      // Try HEAD request first (faster, doesn't download content)
      try {
        final headResponse = await dio.request(
          url,
          cancelToken: cancelToken,
          options: Options(
            method: 'HEAD',
            validateStatus: (status) => status != null && status < 500,
            followRedirects: true,
            maxRedirects: 5,
            sendTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 15),
          ),
        );

        // Consider 2xx and 3xx as live
        if (headResponse.statusCode != null && headResponse.statusCode! < 400) {
          return true;
        }
      } catch (headError) {
        if (headError is DioException &&
            headError.type == DioExceptionType.cancel) {
          rethrow;
        }
        debugPrint('HEAD request failed for $url, trying GET: $headError');
      }

      // Fallback to GET request with range header (only download first byte to check if URL works)
      final getResponse = await dio.request(
        url,
        cancelToken: cancelToken,
        options: Options(
          method: 'GET',
          headers: {
            'Range': 'bytes=0-0', // Only request first byte
          },
          validateStatus: (status) => status != null && status < 500,
          followRedirects: true,
          maxRedirects: 5,
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
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

  // MARK: Is URL Live
  /// Checks if a URL is live (not invalid/404)
  /// Returns true if the URL returns a valid response (200-399 status code)
  /// First tries HEAD request, then falls back to GET if HEAD fails (some servers don't support HEAD)
  Future<bool> isUrlLive(String url, {CancelToken? cancelToken}) async {
    try {
      // Resolve URL with scheme if needed
      final resolvedUrl =
          await resolveUrlWithScheme(url, cancelToken: cancelToken);
      return await _checkUrl(resolvedUrl, cancelToken: cancelToken);
    } catch (e) {
      debugPrint('Error checking URL $url: $e');
      return false;
    }
  }

  // MARK: Check all URLs
  Future<void> checkModUrlsLive(Mod mod) async {
    final invalidUrls = <String>[];

    final allAssets = mod.getAllAssets();
    final int batchSize = ref.read(settingsProvider).concurrentDownloads;
    final checkToken = CancelToken();
    _cancelTokens.add(checkToken);

    try {
      state = state.copyWith(
        //isDownloading: true, // Not setting this to true so that progress bar appears only in url check results dialog
        progress: 0.0,
        statusMessage: 'Checked 0/${allAssets.length} URLs',
      );

      for (int i = 0; i < allAssets.length; i += batchSize) {
        if (checkToken.isCancelled) break;

        final batch = allAssets.sublist(
          i,
          i + batchSize > allAssets.length ? allAssets.length : i + batchSize,
        );

        await Future.wait(batch.map((asset) async {
          if (checkToken.isCancelled) return;
          final isLive = await isUrlLive(asset.url, cancelToken: checkToken);
          if (!isLive) invalidUrls.add(asset.url);
        }));

        if (checkToken.isCancelled) break;

        // Update progress after each batch
        final checked = (i + batch.length).clamp(0, allAssets.length);
        state = state.copyWith(
          statusMessage: 'Checked $checked/${allAssets.length} URLs',
          progress: (checked / allAssets.length).clamp(0.0, 1.0),
        );
      }
    } finally {
      _cancelTokens.remove(checkToken);
      state = state.copyWith(
        isDownloading: false,
        progress: 0.0,
        statusMessage: null,
        cancelledDownloads: false,
      );
    }
    if (!checkToken.isCancelled) {
      ref.read(modsProvider.notifier).updateModInvalidUrls(mod, invalidUrls);
    }
  }

  // MARK: DL MOD Updates
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
        statusMessage:
            mods.length == 1 ? 'Updating ${mods[0].saveName}' : 'Updating mods',
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

  // MARK: DL MODS by IDs
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

  // MARK: DL MOD
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

  // MARK: DL BSON
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

      // Add or update EpochTime, ensuring it's the 2nd value in JSON if adding
      if (decodedData.containsKey('EpochTime')) {
        // Just update the value
        decodedData['EpochTime'] = timeUpdated;
      } else {
        // Add as 2nd entry by reordering
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

      await _writeStringPreservingCreationTime(file, jsonString);
      return 'Mod saved to: $filePath';
    } catch (e) {
      return 'Error for mod json file: $e';
    }
  }

  /// Writes [content] to [file] without resetting the filesystem creation time.
  /// Uses FileMode.append (OPEN_ALWAYS on Windows) to avoid CREATE_ALWAYS
  /// which can reset the creation timestamp.
  Future<void> _writeStringPreservingCreationTime(
    File file,
    String content,
  ) async {
    final RandomAccessFile raf = await file.open(mode: FileMode.append);
    try {
      await raf.truncate(0);
      await raf.setPosition(0);
      await raf.writeString(content);
    } finally {
      await raf.close();
    }
  }

  // MARK: JSON issues
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

  // MARK: DL Image
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
