import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useState;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/mods/components/replace_url_dialog.dart'
    show showReplaceUrlDialog;
import 'package:tts_mod_vault/src/mods/enums/context_menu_action_enum.dart'
    show ContextMenuActionEnum;
import 'package:tts_mod_vault/src/state/asset/models/asset_model.dart'
    show Asset;
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart'
    show AssetTypeEnum;
import 'package:tts_mod_vault/src/state/provider.dart'
    show selectedModProvider, downloadProvider;
import 'package:tts_mod_vault/src/utils.dart'
    show
        copyToClipboard,
        getFileNameFromPath,
        openFile,
        openInFileExplorer,
        openUrl,
        showSnackBar;

class ImagesViewerGridCard extends HookConsumerWidget {
  final Asset asset;

  const ImagesViewerGridCard({super.key, required this.asset});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void showImagesViewerGridCardContextMenu(
      BuildContext context,
      WidgetRef ref,
      Offset position,
      Asset asset,
    ) {
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
          PopupMenuItem(
            value: ContextMenuActionEnum.openFile,
            child: Row(
              spacing: 8,
              children: [
                Icon(Icons.file_open),
                Text('Open File'),
              ],
            ),
          ),
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
                Text('Open URL in Browser'),
              ],
            ),
          ),
          PopupMenuItem(
            value: ContextMenuActionEnum.checkUrl,
            child: Row(
              spacing: 8,
              children: [
                Icon(Icons.link),
                Text('Check if URL is invalid'),
              ],
            ),
          ),
          PopupMenuItem(
            value: ContextMenuActionEnum.copyUrl,
            child: Row(
              spacing: 8,
              children: [
                Icon(Icons.copy),
                Text('Copy URL'),
              ],
            ),
          ),
          PopupMenuItem(
            value: ContextMenuActionEnum.copyFilename,
            child: Row(
              spacing: 8,
              children: [
                Icon(Icons.file_copy),
                Text('Copy Filename'),
              ],
            ),
          ),
          PopupMenuItem(
            value: ContextMenuActionEnum.replaceUrl,
            child: Row(
              spacing: 8,
              children: [
                Icon(Icons.find_replace),
                Text('Update URL'),
              ],
            ),
          ),
        ],
      ).then((value) async {
        if (value != null) {
          switch (value) {
            case ContextMenuActionEnum.openInBrowser:
              openUrl(asset.url);
              break;

            case ContextMenuActionEnum.openInExplorer:
              if (asset.filePath != null && asset.filePath!.isNotEmpty) {
                openInFileExplorer(asset.filePath!);
              }
              break;

            case ContextMenuActionEnum.openFile:
              if (asset.filePath != null && asset.filePath!.isNotEmpty) {
                openFile(asset.filePath!);
              }
              break;

            case ContextMenuActionEnum.copyUrl:
              if (context.mounted) {
                copyToClipboard(context, asset.url);
              }
              break;

            case ContextMenuActionEnum.copyFilename:
              if (context.mounted) {
                copyToClipboard(
                  context,
                  getFileNameFromPath(asset.filePath ?? ''),
                );
              }
              break;

            case ContextMenuActionEnum.replaceUrl:
              final mod = ref.read(selectedModProvider);
              if (context.mounted && mod != null) {
                showReplaceUrlDialog(
                    context, ref, asset, AssetTypeEnum.image, mod);
              }
              break;

            case ContextMenuActionEnum.checkUrl:
              if (!context.mounted) break;

              final isLive = await ref
                  .read(downloadProvider.notifier)
                  .isUrlLive(asset.url);

              if (!context.mounted) break;
              showSnackBar(
                  context, isLive ? 'URL is valid' : 'URL is not valid');
              break;

            default:
              break;
          }
        }
      });
    }

    final isHovered = useState(false);
    return Stack(
      children: [
        Image.file(
          File(asset.filePath!),
          height: 256,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: Colors.black,
              child: Center(
                  child: Text(
                'Failed to load image',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                ),
              )),
            );
          },
        ),
        GestureDetector(
          onDoubleTap: () {
            if (asset.filePath != null && asset.filePath!.isNotEmpty) {
              openFile(asset.filePath!);
            }
          },
          onSecondaryTapDown: (details) => showImagesViewerGridCardContextMenu(
              context, ref, details.globalPosition, asset),
          child: MouseRegion(
            onEnter: (event) => isHovered.value = true,
            onExit: (event) => isHovered.value = false,
            child: AnimatedContainer(
              duration: Duration(milliseconds: 150),
              decoration: BoxDecoration(
                border: Border.all(
                  width: 4,
                  color: isHovered.value ? Colors.white : Colors.transparent,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
