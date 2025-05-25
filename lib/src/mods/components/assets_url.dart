import 'dart:io' show Directory, FileSystemEntity;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show ConsumerWidget, WidgetRef;
import 'package:path/path.dart' as p show basenameWithoutExtension, normalize;
import 'package:tts_mod_vault/src/state/asset/asset_model.dart' show Asset;
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart'
    show AssetTypeEnum;
import 'package:tts_mod_vault/src/state/provider.dart'
    show directoriesProvider, selectedAssetProvider;
import 'package:tts_mod_vault/src/utils.dart'
    show openFileInExplorer, showSnackBar;

class AssetsUrl extends ConsumerWidget {
  final Asset asset;
  final AssetTypeEnum type;

  const AssetsUrl({
    super.key,
    required this.asset,
    required this.type,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedAsset = ref.watch(selectedAssetProvider);

    return Container(
      padding: EdgeInsets.symmetric(vertical: 2),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () =>
              ref.read(selectedAssetProvider.notifier).setAsset(asset, type),
          onDoubleTap: () async {
            if (asset.fileExists &&
                asset.filePath != null &&
                asset.filePath!.isNotEmpty) {
              final directory = Directory(ref
                  .read(directoriesProvider.notifier)
                  .getDirectoryByType(type));
              if (!await directory.exists()) return;

              final List<FileSystemEntity> files = directory.listSync();
              final fileToOpen = files.firstWhereOrNull((ele) => p
                  .basenameWithoutExtension(ele.path)
                  .startsWith(p.basenameWithoutExtension(asset.filePath!)));

              if (fileToOpen != null) {
                openFileInExplorer(p.normalize(fileToOpen.path));
              }
            }
          },
          onLongPress: () async {
            await Clipboard.setData(ClipboardData(text: asset.url));
            if (context.mounted) {
              showSnackBar(
                context,
                '${asset.url} copied to clipboard',
                Duration(seconds: 3),
              );
            }
          },
          child: Text(
            asset.url,
            style: TextStyle(
              fontSize: 12,
              color: selectedAsset != null && asset == selectedAsset.asset
                  ? Colors.lightBlue
                  : asset.fileExists
                      ? Colors.green
                      : Colors.red,
            ),
          ),
        ),
      ),
    );
  }
}
