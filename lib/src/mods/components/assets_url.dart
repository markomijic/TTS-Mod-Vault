import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useMemoized;
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
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show ModTypeEnum;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        actionInProgressProvider,
        deleteAssetsProvider,
        downloadProvider,
        modsProvider,
        selectedModProvider,
        selectedUrlProvider,
        settingsProvider;
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
    final assetUrlFontSize = ref.watch(settingsProvider).assetUrlFontSize;
    final mod = ref.watch(selectedModProvider);
    final url = ref.watch(selectedUrlProvider);
    final isSelected = useMemoized(
      () => asset.url == url,
      [url, mod],
    );

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
            value: ContextMenuActionEnum.checkUrl,
            child: Row(
              spacing: 8,
              children: [
                Icon(Icons.link),
                Text('Check if invalid'),
              ],
            ),
          ),
          PopupMenuItem(
            value: ContextMenuActionEnum.checkShared,
            child: Row(
              spacing: 8,
              children: [
                Icon(Icons.share),
                Text('Check if shared'),
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
          if (asset.fileExists)
            PopupMenuItem(
              value: ContextMenuActionEnum.deleteAsset,
              child: Row(
                spacing: 8,
                children: [
                  Icon(Icons.delete),
                  Text('Delete asset file'),
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
        ],
      ).then((value) async {
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
              final selectedMod = ref.read(selectedModProvider);
              if (selectedMod == null || !context.mounted) break;

              showReplaceUrlDialog(context, ref, asset, type, selectedMod);
              break;

            case ContextMenuActionEnum.download:
              final selectedMod = ref.read(selectedModProvider);
              if (selectedMod == null) break;

              final downloaded = await ref.read(downloadProvider.notifier).downloadFiles(
                modAssetListUrls: [asset.url],
                type: type,
                downloadingAllFiles: false,
              );
              await ref
                  .read(modsProvider.notifier)
                  .updateSelectedMod(selectedMod);
              if (downloaded.isNotEmpty) {
                await ref.read(modsProvider.notifier).refreshModsWithSharedAssets(
                      downloaded.toSet(),
                      excludeJsonFileName: selectedMod.jsonFileName);
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

            case ContextMenuActionEnum.checkShared:
              final selectedMod = ref.read(selectedModProvider);
              if (selectedMod == null || !context.mounted) break;

              final sharingMods = await ref
                  .read(deleteAssetsProvider.notifier)
                  .getModsSharingAsset(asset.url, selectedMod.jsonFileName);

              if (!context.mounted) break;
              if (sharingMods.isEmpty) {
                showSnackBar(context, 'Asset is not shared with other mods');
              } else {
                final summaryParts = <String>[];
                final detailParts = <String>[];
                for (final type in ModTypeEnum.values) {
                  final names = sharingMods[type];
                  if (names == null || names.isEmpty) continue;
                  summaryParts.add(
                      '${names.length} ${type.label}${names.length > 1 ? "s" : ""}');
                  detailParts.add(
                      '${type.label[0].toUpperCase()}${type.label.substring(1)}s:\n${names.join("\n")}');
                }
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Shared Asset'),
                    content: SingleChildScrollView(
                      child: Text(
                          'This asset is shared with ${summaryParts.join(", ")}.\n\n${detailParts.join("\n\n")}'),
                    ),
                    actions: [
                      ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                );
              }
              break;

            case ContextMenuActionEnum.deleteAsset:
              final selectedMod = ref.read(selectedModProvider);
              if (selectedMod == null || !context.mounted) break;

              final sharingMods = await ref
                  .read(deleteAssetsProvider.notifier)
                  .getModsSharingAsset(asset.url, selectedMod.jsonFileName);

              final isShared = sharingMods.isNotEmpty;
              String deleteMessage;
              String? detailsText;
              if (isShared) {
                final summaryParts = <String>[];
                final detailParts = <String>[];
                for (final type in ModTypeEnum.values) {
                  final names = sharingMods[type];
                  if (names == null || names.isEmpty) continue;
                  summaryParts.add(
                      '${names.length} ${type.label}${names.length > 1 ? "s" : ""}');
                  detailParts.add(
                      '${type.label[0].toUpperCase()}${type.label.substring(1)}s:\n${names.join("\n")}');
                }
                deleteMessage =
                    'This asset is shared with ${summaryParts.join(", ")}.\n\nDelete anyway?';
                detailsText = detailParts.join('\n\n');
              } else {
                deleteMessage =
                    'Are you sure you want to delete this file?\n\n${getFileNameFromURL(asset.url)}';
              }
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: Text(isShared
                      ? 'Delete shared asset file'
                      : 'Delete asset file'),
                  content: Text(deleteMessage),
                  actions: [
                    if (detailsText != null)
                      TextButton(
                        onPressed: () {
                          showDialog(
                            context: dialogContext,
                            builder: (context) => AlertDialog(
                              title: const Text('Shared with'),
                              content: SingleChildScrollView(
                                child: Text(detailsText!),
                              ),
                              actions: [
                                ElevatedButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(),
                                  child: const Text('Close'),
                                ),
                              ],
                            ),
                          );
                        },
                        child: const Text('View Details'),
                      ),
                    ElevatedButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      icon: Icon(Icons.delete),
                      label: const Text('Delete'),
                    ),
                  ],
                ),
              );
              if (confirmed != true || !context.mounted) break;

              final deleted = await ref
                  .read(deleteAssetsProvider.notifier)
                  .deleteSingleAsset(asset.filePath, type);

              if (!context.mounted) break;
              if (deleted) {
                await ref
                    .read(modsProvider.notifier)
                    .updateSelectedMod(selectedMod);
                final filename = getFileNameFromURL(asset.url);
                await ref.read(modsProvider.notifier).refreshModsWithSharedAssets(
                      {filename},
                      excludeJsonFileName: selectedMod.jsonFileName);
                if (context.mounted) showSnackBar(context, 'File deleted');
              } else {
                showSnackBar(context, 'Failed to delete file');
              }
              break;

            default:
              break;
          }
        }
      });
    }

    void onTapDown(TapDownDetails details) {
      if (ref.read(actionInProgressProvider)) return;

      if (!isSelected) {
        showURLContextMenu(context, details.globalPosition);
      }

      ref.read(selectedUrlProvider.notifier).state =
          isSelected ? '' : asset.url;
    }

    void onSecondaryTapDown(TapDownDetails details) {
      if (ref.read(actionInProgressProvider)) return;

      showURLContextMenu(context, details.globalPosition);

      ref.read(selectedUrlProvider.notifier).state = asset.url;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (details) => onTapDown(details),
        onSecondaryTapDown: (details) => onSecondaryTapDown(details),
        child: Text(
          asset.url,
          style: TextStyle(
            fontSize: assetUrlFontSize,
            color: isSelected
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
