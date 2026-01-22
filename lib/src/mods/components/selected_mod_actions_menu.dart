import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'dart:ui' show ImageFilter;
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show showUpdateUrlsDialog;
import 'package:tts_mod_vault/src/mods/components/url_check_results_dialog.dart'
    show buildUrlCheckResultsDialog;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show Mod;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        actionInProgressProvider,
        deleteAssetsProvider,
        downloadProvider,
        modsProvider;
import 'package:tts_mod_vault/src/utils.dart'
    show showSnackBar, copyToClipboard;
import 'package:tts_mod_vault/src/state/delete_assets/delete_assets_state.dart'
    show DeleteAssetsStatusEnum, SharedAssetInfo;
import 'package:tts_mod_vault/src/state/delete_assets/delete_assets.dart'
    show DeleteAssetsNotifier;

class SelectedModActionsMenu extends HookConsumerWidget {
  final Mod selectedMod;

  const SelectedModActionsMenu({super.key, required this.selectedMod});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actionInProgress = ref.watch(actionInProgressProvider);
    final modsNotifier = ref.watch(modsProvider.notifier);

    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStateProperty.all(Colors.white),
      ),
      menuChildren: <Widget>[
        MenuItemButton(
          style: MenuItemButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
          ),
          leadingIcon: Icon(Icons.link, color: Colors.black),
          child: Text('Check for invalid URLs',
              style: TextStyle(color: Colors.black)),
          onPressed: () async {
            if (actionInProgress) return;

            if (selectedMod.assetLists == null) {
              if (context.mounted) {
                showSnackBar(context, 'No assets found in this mod');
              }
              return;
            }

            // Get the navigator context before the menu closes
            final navigator = Navigator.of(context);

            await ref.read(downloadProvider.notifier).checkModUrlsLive(
              selectedMod,
              onComplete: (invalidUrls) {
                showDialog(
                  context: navigator.context,
                  builder: (builderContext) => buildUrlCheckResultsDialog(
                    builderContext,
                    invalidUrls,
                    selectedMod,
                  ),
                );
              },
            );
          },
        ),
        MenuItemButton(
          style: MenuItemButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
          ),
          leadingIcon: Icon(Icons.copy, color: Colors.black),
          child:
              Text('Copy missing URLs', style: TextStyle(color: Colors.black)),
          onPressed: () async {
            if (actionInProgress) return;

            final missingAssets = selectedMod
                .getAllAssets()
                .where((asset) => !asset.fileExists)
                .toList();

            if (missingAssets.isEmpty && context.mounted) {
              showSnackBar(context, 'No missing assets found');

              return;
            }

            final urls = missingAssets.map((asset) => asset.url).join('\n');
            await Clipboard.setData(ClipboardData(text: urls));

            if (context.mounted) {
              showSnackBar(context,
                  'Copied ${missingAssets.length} missing ${missingAssets.length > 1 ? 'URLs' : 'URL'} to clipboard');
            }
          },
        ),
        MenuItemButton(
          style: MenuItemButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
          ),
          leadingIcon: Icon(Icons.delete_sweep, color: Colors.black),
          child:
              Text('Delete asset files', style: TextStyle(color: Colors.black)),
          onPressed: () async {
            if (actionInProgress) return;

            final deleteAssetsNotifier =
                ref.read(deleteAssetsProvider.notifier);

            // Start scanning for deletable assets
            await deleteAssetsNotifier.scanModAssets(selectedMod);

            final deleteAssetsState = ref.read(deleteAssetsProvider);

            switch (deleteAssetsState.status) {
              case DeleteAssetsStatusEnum.idle:
              case DeleteAssetsStatusEnum.scanning:
              case DeleteAssetsStatusEnum.deleting:
                break;
              case DeleteAssetsStatusEnum.awaitingConfirmation:
                if (context.mounted) {
                  final multipleAssets =
                      deleteAssetsState.filesToDelete.length > 1;
                  final sharedInfo = deleteAssetsState.sharedAssetInfo;

                  // Build message about shared assets
                  final sharedParts = <String>[];
                  if (sharedInfo != null) {
                    if (sharedInfo.sharedWithMods > 0) {
                      sharedParts.add(
                          '${sharedInfo.sharedWithMods} ${sharedInfo.sharedWithMods > 1 ? "mods" : "mod"}');
                    }
                    if (sharedInfo.sharedWithSaves > 0) {
                      sharedParts.add(
                          '${sharedInfo.sharedWithSaves} ${sharedInfo.sharedWithSaves > 1 ? "saves" : "save"}');
                    }
                    if (sharedInfo.sharedWithSavedObjects > 0) {
                      sharedParts.add(
                          '${sharedInfo.sharedWithSavedObjects} saved ${sharedInfo.sharedWithSavedObjects > 1 ? "objects" : "object"}');
                    }
                  }

                  final sharedMessage = sharedParts.isNotEmpty
                      ? '\n\nAssets shared with other ${sharedParts.join(", ")} will NOT be deleted.'
                      : '';

                  _showDeleteConfirmDialog(
                    context,
                    deleteAssetsState,
                    multipleAssets,
                    sharedMessage,
                    sharedInfo,
                    deleteAssetsNotifier,
                    modsNotifier,
                    selectedMod,
                    ref,
                  );
                }
                break;

              case DeleteAssetsStatusEnum.completed:
                if (context.mounted) {
                  showSnackBar(context,
                      deleteAssetsState.statusMessage ?? 'Operation completed');

                  deleteAssetsNotifier.resetState();
                }
                break;

              case DeleteAssetsStatusEnum.error:
                if (context.mounted) {
                  showSnackBar(context,
                      deleteAssetsState.statusMessage ?? 'An error occurred');

                  deleteAssetsNotifier.resetState();
                }
                break;
            }
          },
        ),
        MenuItemButton(
          style: MenuItemButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
          ),
          leadingIcon: Icon(Icons.edit, color: Colors.black),
          child: Text('Update URLs', style: TextStyle(color: Colors.black)),
          onPressed: () async {
            if (actionInProgress) return;

            showUpdateUrlsDialog(
              context,
              ref,
              onConfirm: (oldUrlPrefix, newUrlPrefix, renameFile) async {
                await ref.read(modsProvider.notifier).updateUrlPrefixes(
                      selectedMod,
                      oldUrlPrefix.split('|'),
                      newUrlPrefix,
                      renameFile,
                    );
              },
            );
          },
        ),
      ],
      builder: (
        BuildContext context,
        MenuController controller,
        Widget? child,
      ) {
        return IconButton(
          style: IconButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            minimumSize: Size(32, 32),
            maximumSize: Size(32, 32),
          ),
          onPressed: () {
            if (actionInProgress) return;

            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
          icon: Icon(Icons.more_vert, size: 16),
        );
      },
    );
  }
}

void _showDeleteConfirmDialog(
  BuildContext context,
  deleteAssetsState,
  bool multipleAssets,
  String sharedMessage,
  SharedAssetInfo? sharedInfo,
  DeleteAssetsNotifier deleteAssetsNotifier,
  modsNotifier,
  Mod selectedMod,
  WidgetRef ref,
) async {
  final result = await showDialog<String>(
    context: context,
    builder: (BuildContext context) {
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
        child: AlertDialog(
          content: Text(
              'Delete ${deleteAssetsState.filesToDelete.length} ${multipleAssets ? "asset files" : "asset file"} that ${multipleAssets ? "are" : "is"} only used by this mod?$sharedMessage\n\nThis action cannot be undone.'),
          actions: [
            if (sharedInfo != null && sharedInfo.sharedAssetDetails.isNotEmpty)
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop('details');
                },
                child: const Text('View Details'),
              ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop('cancel'),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop('confirm'),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
    },
  );

  if (!context.mounted) return;

  switch (result) {
    case 'confirm':
      await deleteAssetsNotifier.executeDelete();
      await modsNotifier.updateSelectedMod(selectedMod);
      break;
    case 'details':
      if (sharedInfo != null) {
        await _showSharedAssetsDetailsDialog(context, sharedInfo, ref);
        // Show the confirm dialog again after closing details
        if (context.mounted) {
          _showDeleteConfirmDialog(
            context,
            deleteAssetsState,
            multipleAssets,
            sharedMessage,
            sharedInfo,
            deleteAssetsNotifier,
            modsNotifier,
            selectedMod,
            ref,
          );
        }
      }
      break;
    case 'cancel':
    case null:
    default:
      deleteAssetsNotifier.resetState();
      break;
  }
}

Future<void> _showSharedAssetsDetailsDialog(
  BuildContext context,
  SharedAssetInfo sharedInfo,
  WidgetRef ref,
) async {
  // Get all mods to map jsonFileName to display name
  final allMods = ref.read(modsProvider.notifier).getAllMods();
  final modNameMap = {
    for (final mod in allMods)
      mod.jsonFileName: mod.saveName.isEmpty ? mod.jsonFileName : mod.saveName
  };

  await showDialog(
    context: context,
    builder: (BuildContext builderContext) {
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
        child: AlertDialog(
          title: const Text('Shared Assets Details'),
          content: ListView.builder(
            shrinkWrap: true,
            itemCount: sharedInfo.sharedAssetDetails.length,
            itemBuilder: (itemContext, index) {
              final entry =
                  sharedInfo.sharedAssetDetails.entries.elementAt(index);
              final assetUrl = entry.key;
              final sharingModJsonFileNames = entry.value;

              final displayNamesText = sharingModJsonFileNames
                  .map((jsonFileName) =>
                      modNameMap[jsonFileName] ?? jsonFileName)
                  .join('\n');

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SelectableText(
                          assetUrl,
                          selectionColor: Colors.blue,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          onPressed: () => copyToClipboard(
                            itemContext,
                            assetUrl,
                            showSnackBarAfterCopying: false,
                          ),
                          icon: Icon(Icons.copy),
                        )
                      ],
                    ),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.only(left: 16.0, top: 2.0),
                      child: SelectableText(
                        displayNamesText,
                        selectionColor: Colors.blue,
                      ),
                    ),
                    const Divider(),
                  ],
                ),
              );
            },
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    },
  );
}
