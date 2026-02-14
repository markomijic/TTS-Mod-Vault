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
    show showSnackBar;
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
                }
                deleteAssetsNotifier.resetState();
                break;

              case DeleteAssetsStatusEnum.error:
                if (context.mounted) {
                  showSnackBar(context,
                      deleteAssetsState.statusMessage ?? 'An error occurred');
                }
                deleteAssetsNotifier.resetState();
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
  bool includeShared = false;
  final hasSharedAssets = deleteAssetsState.sharedFilesToDelete.isNotEmpty;

  final result = await showDialog<String>(
    context: context,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder: (context, setState) {
          final safeCount = deleteAssetsState.filesToDelete.length;
          final sharedCount = deleteAssetsState.sharedFilesToDelete.length;
          final totalCount =
              includeShared ? safeCount + sharedCount : safeCount;
          final isMultiple = totalCount != 1;

          String message;
          if (safeCount > 0) {
            message =
                'Delete $safeCount ${isMultiple ? "asset files" : "asset file"} that ${isMultiple ? "are" : "is"} only used by this mod?$sharedMessage';
          } else {
            message =
                'All assets are shared with other mods. Check the box below to delete them anyway.';
          }

          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
            child: AlertDialog(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$message\n\nThis action cannot be undone.'),
                  if (hasSharedAssets) ...[
                    const SizedBox(height: 16),
                    CheckboxListTile(
                      value: includeShared,
                      onChanged: (value) {
                        setState(() {
                          includeShared = value ?? false;
                        });
                      },
                      title: Text(
                        'Also delete $sharedCount shared ${sharedCount == 1 ? "asset" : "assets"}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ],
                ],
              ),
              actions: [
                if (sharedInfo != null &&
                    sharedInfo.sharedAssetDetails.isNotEmpty)
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
                  onPressed: (safeCount > 0 || includeShared)
                      ? () => Navigator.of(context)
                          .pop(includeShared ? 'confirm_shared' : 'confirm')
                      : null,
                  child: const Text('Confirm'),
                ),
              ],
            ),
          );
        },
      );
    },
  );

  if (!context.mounted) return;

  switch (result) {
    case 'confirm':
      final deletedFilenames =
          await deleteAssetsNotifier.executeDelete(includeShared: false);
      await modsNotifier.updateSelectedMod(selectedMod);
      if (deletedFilenames.isNotEmpty) {
        await modsNotifier.refreshModsWithSharedAssets(deletedFilenames.toSet(),
            excludeJsonFileName: selectedMod.jsonFileName);
      }
      deleteAssetsNotifier.resetState();
      break;
    case 'confirm_shared':
      final deletedSharedFilenames =
          await deleteAssetsNotifier.executeDelete(includeShared: true);
      await modsNotifier.updateSelectedMod(selectedMod);
      if (deletedSharedFilenames.isNotEmpty) {
        await modsNotifier.refreshModsWithSharedAssets(
            deletedSharedFilenames.toSet(),
            excludeJsonFileName: selectedMod.jsonFileName);
      }
      deleteAssetsNotifier.resetState();
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

  // Invert the map: asset -> [mods] becomes mod -> [assets]
  final Map<String, List<String>> modToAssets = {};
  for (final entry in sharedInfo.sharedAssetDetails.entries) {
    final assetUrl = entry.key;
    for (final modJsonFileName in entry.value) {
      modToAssets.putIfAbsent(modJsonFileName, () => []).add(assetUrl);
    }
  }

  final modEntries = modToAssets.entries.toList();

  await showDialog(
    context: context,
    builder: (BuildContext builderContext) {
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
        child: AlertDialog(
          title: const Text('Shared Assets Details'),
          content: SizedBox(
            width: 500,
            height: 400,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: modEntries.length,
              itemBuilder: (itemContext, index) {
                final entry = modEntries[index];
                final modJsonFileName = entry.key;
                final assetUrls = entry.value;
                final displayName =
                    modNameMap[modJsonFileName] ?? modJsonFileName;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(
                        displayName,
                        selectionColor: Colors.blue,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.only(left: 16.0, top: 2.0),
                        child: SelectableText(
                          assetUrls.join('\n'),
                          selectionColor: Colors.blue,
                        ),
                      ),
                      const Divider(),
                    ],
                  ),
                );
              },
            ),
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
