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
    show
        actionInProgressProvider,
        downloadProvider,
        modsProvider,
        selectedModProvider;
import 'package:tts_mod_vault/src/utils.dart'
    show
        copyToClipboard,
        getFileNameFromPath,
        getFileNameFromURL,
        openFile,
        openInFileExplorer,
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

    void showURLContextMenu(BuildContext context, Offset position) {
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
          if (asset.fileExists &&
              [AssetTypeEnum.audio, AssetTypeEnum.image, AssetTypeEnum.pdf]
                  .contains(type))
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
                Text('Open URL in Browser'),
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
                Text('Replace URL'),
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
            case ContextMenuActionEnum.openFile:
              if (asset.filePath != null && asset.filePath!.isNotEmpty) {
                openFile(asset.filePath!);
              }
              break;

            case ContextMenuActionEnum.openInExplorer:
              if (asset.filePath != null && asset.filePath!.isNotEmpty) {
                openInFileExplorer(asset.filePath!);
              }
              break;

            case ContextMenuActionEnum.openInBrowser:
              final result = await openUrl(asset.url);
              if (!result && context.mounted) {
                showSnackBar(context, "Failed to open: ${asset.url}");
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
                  asset.filePath != null && asset.filePath!.isNotEmpty
                      ? getFileNameFromPath(asset.filePath ?? '')
                      : getFileNameFromURL(asset.url),
                );
              }
              break;

            case ContextMenuActionEnum.replaceUrl:
              if (context.mounted) {
                showReplaceUrlDialog(context, ref);
              }
              break;

            case ContextMenuActionEnum.download:
              final selectedMod = ref.read(selectedModProvider);
              if (selectedMod == null) break;

              await ref.read(downloadProvider.notifier).downloadFiles(
                modAssetListUrls: [asset.url],
                type: type,
                downloadingAllFiles: false,
              );
              await ref
                  .read(modsProvider.notifier)
                  .updateModByJsonFilename(selectedMod.jsonFileName);
              break;

            default:
              break;
          }
        }
      });
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onSecondaryTapDown: (details) {
          if (ref.read(actionInProgressProvider)) return;

          isSelected.value = true;
          showURLContextMenu(context, details.globalPosition);
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
    );
  }
}
