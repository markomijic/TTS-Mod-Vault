import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';

import 'package:riverpod/riverpod.dart';
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart';
import 'package:tts_mod_vault/src/state/mods/mod_model.dart';
import 'package:tts_mod_vault/src/state/provider.dart';
import 'package:tts_mod_vault/src/utils.dart'
    show getDirectoryByType, getExtensionByType, getFileNameFromURL;
import 'download_state.dart';
import 'package:path/path.dart' as path;

class DownloadNotifier extends StateNotifier<DownloadState> {
  final Ref ref;
  final Dio dio;

  DownloadNotifier(this.ref)
      : dio = Dio(),
        super(const DownloadState());

/*   Future<void> downloadAllMods(
    List<Mod> mods,
    Future<void> Function(Mod mod) callback,
  ) async {
    for (final mod in mods) {
      await downloadAllFiles(mod); 
      await callback(mod);
    }
  } */

  Future<void> downloadAllFiles(Mod mod) async {
    if (mod.assetLists == null) {
      return;
    }

    await downloadFiles(
      modName: mod.name,
      urls: mod.assetLists!.assetBundles
          .where((e) => !e.fileExists)
          .map((e) => e.url)
          .toList(),
      type: AssetType.assetBundle,
    );

    await downloadFiles(
      modName: mod.name,
      urls: mod.assetLists!.audio
          .where((e) => !e.fileExists)
          .map((e) => e.url)
          .toList(),
      type: AssetType.audio,
    );

    await downloadFiles(
      modName: mod.name,
      urls: mod.assetLists!.images
          .where((e) => !e.fileExists)
          .map((e) => e.url)
          .toList(),
      type: AssetType.image,
    );

    await downloadFiles(
      modName: mod.name,
      urls: mod.assetLists!.models
          .where((e) => !e.fileExists)
          .map((e) => e.url)
          .toList(),
      type: AssetType.model,
    );

    await downloadFiles(
      modName: mod.name,
      urls: mod.assetLists!.pdf
          .where((e) => !e.fileExists)
          .map((e) => e.url)
          .toList(),
      type: AssetType.pdf,
    );

    await ref.read(stringListProvider.notifier).loadStrings();

    state = state.copyWith(
      isDownloading: false,
      progress: null,
      downloadingType: null,
    );
  }

  Future<void> downloadFiles({
    required String modName,
    required List<String> urls,
    required AssetType type,
    bool downloadingAllFiles = true,
  }) async {
    if (urls.isEmpty) {
      return;
    }

    try {
      state = state.copyWith(
        isDownloading: true,
        progress: 0.0,
        errorMessage: null,
        downloadingType: type,
      );

      final int batchSize = 5; // TODO set from settings

      for (int i = 0; i < urls.length; i += batchSize) {
        final batch = urls.sublist(
          i,
          i + batchSize > urls.length ? urls.length : i + batchSize,
        );

        await Future.wait(batch.map((url) async {
          try {
            final fileName = getFileNameFromURL(url);
            final directory =
                getDirectoryByType(ref.read(directoriesProvider), type);

            if (type == AssetType.image || type == AssetType.audio) {
              final tempPath = path.join(directory, '${fileName}_temp');
              await dio.download(
                url,
                tempPath,
                onReceiveProgress: (received, total) {
                  if (total <= 0 || batch.length > 1) return;
                  // Progress per file
                  state = state.copyWith(progress: received / total);
                },
              );

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
                onReceiveProgress: (received, total) {
                  if (total <= 0 || batch.length > 1) return;
                  // Progress per file
                  state = state.copyWith(progress: received / total);
                },
              );
            }
          } catch (e) {
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
        await ref.read(stringListProvider.notifier).updateTypeList(type);
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
