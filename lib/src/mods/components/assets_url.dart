import 'dart:io' show Directory, FileSystemEntity;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_hooks/flutter_hooks.dart' show useState;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:path/path.dart' as p show basenameWithoutExtension, normalize;
import 'package:tts_mod_vault/src/mods/enums/context_menu_action_enum.dart'
    show ContextMenuActionEnum;
import 'package:tts_mod_vault/src/state/asset/models/asset_model.dart'
    show Asset;
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart'
    show AssetTypeEnum;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        actionInProgressProvider,
        directoriesProvider,
        downloadProvider,
        modsProvider,
        selectedModProvider;
import 'package:tts_mod_vault/src/utils.dart'
    show
        getFileNameFromURL,
        newUrl,
        oldUrl,
        openFileInExplorer,
        openUrl,
        showSnackBar;

class AssetsUrl extends HookConsumerWidget {
  final Asset asset;
  final AssetTypeEnum type;

  const AssetsUrl({
    super.key,
    required this.asset,
    required this.type,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSelected = useState(false);

    void showContextMenu(BuildContext context, Offset position) {
      showMenu(
        context: context,
        color: Theme.of(context).scaffoldBackgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: Colors.white, width: 2),
        ),
        position: RelativeRect.fromLTRB(
          position.dx,
          position.dy,
          position.dx,
          position.dy,
        ),
        items: [
          if (asset.fileExists)
            PopupMenuItem(
              value: ContextMenuActionEnum.openInExplorer,
              child: Row(
                spacing: 8,
                children: [
                  Icon(Icons.folder_open),
                  Text('Open in File Explorer'),
                ],
              ),
            ),
          PopupMenuItem(
            value: ContextMenuActionEnum.openInBrowser,
            child: Row(
              spacing: 8,
              children: [
                Icon(Icons.open_in_browser),
                Text('Open in Browser'),
              ],
            ),
          ),
          PopupMenuItem(
            value: ContextMenuActionEnum.copyUrl,
            child: Row(
              spacing: 8,
              children: [
                Icon(Icons.link),
                Text('Copy URL'),
              ],
            ),
          ),
          PopupMenuItem(
            value: ContextMenuActionEnum.copyFilename,
            child: Row(
              spacing: 8,
              children: [
                Icon(Icons.content_copy),
                Text('Copy Filename'),
              ],
            ),
          ),
          if (!asset.fileExists)
            PopupMenuItem(
              value: ContextMenuActionEnum.download,
              child: Row(
                spacing: 8,
                children: [
                  Icon(Icons.download),
                  Text('Download'),
                ],
              ),
            ),
        ],
      ).then((value) async {
        isSelected.value = false;

        if (value != null) {
          switch (value) {
            case ContextMenuActionEnum.openInExplorer:
              if (asset.fileExists &&
                  asset.filePath != null &&
                  asset.filePath!.isNotEmpty) {
                final directory = Directory(ref
                    .read(directoriesProvider.notifier)
                    .getDirectoryByType(type));
                if (!await directory.exists()) return;

                final List<FileSystemEntity> files = directory.listSync();

                final fileToOpen = files.firstWhereOrNull((file) {
                  final name = p.basenameWithoutExtension(file.path);

                  final newUrlBase =
                      p.basenameWithoutExtension(asset.filePath!);
                  // Check if file exists under old url naming scheme
                  final oldUrlbase = newUrlBase.replaceFirst(
                      getFileNameFromURL(newUrl), getFileNameFromURL(oldUrl));

                  return name.startsWith(newUrlBase) ||
                      name.startsWith(oldUrlbase);
                });

                if (fileToOpen != null) {
                  openFileInExplorer(p.normalize(fileToOpen.path));
                }
              }
              break;

            case ContextMenuActionEnum.openInBrowser:
              final result = await openUrl(asset.url);
              if (!result && context.mounted) {
                showSnackBar(context, "Failed to open: ${asset.url}");
              }
              break;

            case ContextMenuActionEnum.copyUrl:
              await Clipboard.setData(ClipboardData(text: asset.url));
              if (context.mounted) {
                showSnackBar(
                  context,
                  '${asset.url} copied to clipboard',
                  Duration(seconds: 3),
                );
              }
              break;

            case ContextMenuActionEnum.copyFilename:
              final textToCopy = getFileNameFromURL(asset.url);
              await Clipboard.setData(ClipboardData(text: textToCopy));
              if (context.mounted) {
                showSnackBar(
                  context,
                  '$textToCopy copied to clipboard',
                  Duration(seconds: 3),
                );
              }
              break;

            case ContextMenuActionEnum.download:
              final selectedMod = ref.read(selectedModProvider);
              if (selectedMod == null) break;

              await ref.read(downloadProvider.notifier).downloadFiles(
                    modName: selectedMod.name,
                    modAssetListUrls: [asset.url],
                    type: type,
                    downloadingAllFiles: false,
                  );
              await ref.read(modsProvider.notifier).updateMod(selectedMod.name);
              break;
          }
        }
      });
    }

    return Container(
      padding: EdgeInsets.symmetric(vertical: 2),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onSecondaryTapDown: (details) {
            if (ref.read(actionInProgressProvider)) return;

            isSelected.value = true;
            showContextMenu(context, details.globalPosition);
          },
          child: Text(
            asset.url,
            style: TextStyle(
              fontSize: 12,
              color: isSelected.value
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
