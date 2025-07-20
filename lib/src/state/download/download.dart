import 'dart:io' show File;

import 'package:dio/dio.dart'
    show CancelToken, Dio, DioException, DioExceptionType, Options;
import 'package:flutter/material.dart' show debugPrint;
import 'package:hooks_riverpod/hooks_riverpod.dart' show Ref, StateNotifier;
import 'package:tts_mod_vault/src/state/download/download_state.dart'
    show DownloadState;
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart'
    show AssetTypeEnum;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show Mod;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        directoriesProvider,
        downloadProvider,
        existingAssetListsProvider,
        modsProvider,
        selectedModProvider,
        settingsProvider;
import 'package:tts_mod_vault/src/utils.dart'
    show getExtensionByType, getFileNameFromURL;

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
      downloading: false,
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
      downloading: false,
      cancelledDownloads: false,
      progress: 0.0,
      downloadingType: null,
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
        downloading: true,
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

            await dio.download(
              url,
              tempPath,
              cancelToken: cancelToken,
              onReceiveProgress: (received, total) {
                if (total <= 0 || batch.length > 1) return;
                // Progress per file
                state = state.copyWith(progress: received / total);
              },
            );

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
    } catch (e) {
      state = state.copyWith(downloading: false);
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
}
