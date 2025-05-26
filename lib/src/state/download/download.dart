import 'dart:io' show File;

import 'package:dio/dio.dart'
    show CancelToken, Dio, DioException, DioExceptionType;
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
        selectedAssetProvider,
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
    await ref.read(downloadProvider.notifier)._cancelAllDownloads();
    if (ref.read(selectedModProvider) != null) {
      await ref
          .read(modsProvider.notifier)
          .updateMod(ref.read(selectedModProvider)!.name);
    }
    ref.read(selectedAssetProvider.notifier).resetState();
  }

  Future<void> _cancelAllDownloads() async {
    for (final token in _cancelTokens.values) {
      token.cancel('All downloads cancelled by user');
    }
    _cancelTokens.clear();

    await ref
        .read(existingAssetListsProvider.notifier)
        .loadExistingAssetsLists();

    state = state.copyWith(
      isDownloading: false,
      progress: null,
      downloadingType: null,
      errorMessage: 'Downloads cancelled',
    );
  }

  Future<void> downloadAllFiles(Mod mod) async {
    if (mod.assetLists == null) {
      return;
    }

    await downloadFiles(
      modName: mod.name,
      modAssetListUrls: mod.assetLists!.assetBundles
          .where((e) => !e.fileExists)
          .map((e) => e.url)
          .toList(),
      type: AssetTypeEnum.assetBundle,
    );

    await downloadFiles(
      modName: mod.name,
      modAssetListUrls: mod.assetLists!.audio
          .where((e) => !e.fileExists)
          .map((e) => e.url)
          .toList(),
      type: AssetTypeEnum.audio,
    );

    await downloadFiles(
      modName: mod.name,
      modAssetListUrls: mod.assetLists!.images
          .where((e) => !e.fileExists)
          .map((e) => e.url)
          .toList(),
      type: AssetTypeEnum.image,
    );

    await downloadFiles(
      modName: mod.name,
      modAssetListUrls: mod.assetLists!.models
          .where((e) => !e.fileExists)
          .map((e) => e.url)
          .toList(),
      type: AssetTypeEnum.model,
    );

    await downloadFiles(
      modName: mod.name,
      modAssetListUrls: mod.assetLists!.pdf
          .where((e) => !e.fileExists)
          .map((e) => e.url)
          .toList(),
      type: AssetTypeEnum.pdf,
    );

    await ref
        .read(existingAssetListsProvider.notifier)
        .loadExistingAssetsLists();

    state = state.copyWith(
      isDownloading: false,
      progress: null,
      downloadingType: null,
    );
  }

  Future<void> downloadFiles({
    required String modName,
    required List<String> modAssetListUrls,
    required AssetTypeEnum type,
    bool downloadingAllFiles = true,
  }) async {
    if (modAssetListUrls.isEmpty) {
      return;
    }

    final urls = modAssetListUrls.where((url) {
      final fileName = getFileNameFromURL(url);
      return !ref
          .read(existingAssetListsProvider.notifier)
          .doesAssetFileExist(fileName, type);
    }).toList();

    try {
      state = state.copyWith(
        isDownloading: true,
        progress: 0.0,
        errorMessage: null,
        downloadingType: type,
      );

      final int batchSize = ref.read(settingsProvider).concurrentDownloads;

      for (int i = 0; i < urls.length; i += batchSize) {
        final batch = urls.sublist(
          i,
          i + batchSize > urls.length ? urls.length : i + batchSize,
        );

        await Future.wait(batch.map((url) async {
          // Create a new CancelToken for this download
          final cancelToken = CancelToken();
          _cancelTokens[url] = cancelToken;

          try {
            final fileName = getFileNameFromURL(url);
            final directory =
                ref.read(directoriesProvider.notifier).getDirectoryByType(type);

            if (type == AssetTypeEnum.image || type == AssetTypeEnum.audio) {
              final tempPath = path.join(directory, '${fileName}_temp');
              await dio.download(
                url,
                tempPath,
                cancelToken: cancelToken, // Use the cancel token
                onReceiveProgress: (received, total) {
                  if (total <= 0 || batch.length > 1) return;
                  // Progress per file
                  state = state.copyWith(progress: received / total);
                },
              );

              // Check if download was cancelled before proceeding
              if (cancelToken.isCancelled) {
                // Clean up the temp file if it exists
                final tempFile = File(tempPath);
                if (await tempFile.exists()) {
                  await tempFile.delete();
                }
                return;
              }

              final bytes = await File(tempPath).readAsBytes();
              final extension = getExtensionByType(type, tempPath, bytes);

              final finalPath = path.join(directory, fileName + extension);
              await File(tempPath).rename(finalPath);
            } else {
              final assetPath = path.join(
                directory,
                fileName + getExtensionByType(type),
              );

              await dio.download(
                url,
                assetPath,
                cancelToken: cancelToken, // Use the cancel token
                onReceiveProgress: (received, total) {
                  if (total <= 0 || batch.length > 1) return;
                  // Progress per file
                  state = state.copyWith(progress: received / total);
                },
              );

              // Check if download was cancelled before proceeding
              if (cancelToken.isCancelled) {
                // Clean up the downloaded file if it exists
                final file = File(assetPath);
                if (await file.exists()) {
                  await file.delete();
                }
                return;
              }
            }

            // Remove the token after successful download
            _cancelTokens.remove(url);
          } catch (e) {
            // Remove the token in case of error
            _cancelTokens.remove(url);

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

      if (!downloadingAllFiles) {
        await ref
            .read(existingAssetListsProvider.notifier)
            .setExistingAssetsListByType(type);
        state = state.copyWith(
          isDownloading: false,
          progress: null,
          downloadingType: null,
        );
      }
    } catch (e) {
      state = state.copyWith(
        isDownloading: false,
        errorMessage: e.toString(),
      );
    }
  }
}
