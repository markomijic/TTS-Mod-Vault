import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useMemoized;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show SelectedModActionsMenu, SingleModBackupDialog;
import 'package:tts_mod_vault/src/state/bulk_actions/bulk_actions_state.dart'
    show PostBackupDeletionEnum;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show Mod;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        actionInProgressProvider,
        backupProvider,
        deleteAssetsProvider,
        downloadProvider,
        modsProvider;

class SelectedModActionButtons extends HookConsumerWidget {
  final Mod selectedMod;

  const SelectedModActionButtons({super.key, required this.selectedMod});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasMissingFiles = useMemoized(() {
      return selectedMod.getAllAssets().any((asset) => !asset.fileExists);
    }, [selectedMod]);

    final modsNotifier = ref.watch(modsProvider.notifier);
    final backupNotifier = ref.watch(backupProvider.notifier);
    final downloadNotifier = ref.watch(downloadProvider.notifier);
    final deleteAssetsNotifier = ref.watch(deleteAssetsProvider.notifier);
    final actionInProgress = ref.watch(actionInProgressProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ElevatedButton.icon(
            icon: Icon(Icons.download),
            onPressed: hasMissingFiles
                ? () async {
                    if (actionInProgress) {
                      return;
                    }

                    final downloaded =
                        await downloadNotifier.downloadAllFiles(selectedMod);
                    await modsNotifier.updateSelectedMod(selectedMod);
                    if (downloaded.isNotEmpty) {
                      await modsNotifier.refreshModsWithSharedAssets(downloaded,
                          excludeJsonFileName: selectedMod.jsonFileName);
                    }
                  }
                : null,
            label: const Text('Download'),
          ),
          ElevatedButton.icon(
            icon: Icon(Icons.archive),
            onPressed: () {
              if (actionInProgress) {
                return;
              }

              showDialog(
                context: context,
                builder: (context) => SingleModBackupDialog(
                  mod: selectedMod,
                  onConfirm:
                      (backupFolder, downloadFirst, postBackupDeletion) async {
                    // Capture provider references before any async operations
                    final modsRef = modsNotifier;
                    final downloadRef = downloadNotifier;
                    final backupRef = backupNotifier;
                    final deleteRef = deleteAssetsNotifier;

                    // Use a mutable reference so we always have the fresh mod
                    var currentMod = selectedMod;

                    // 1. Download if requested
                    Set<String> downloadedFilenames = {};
                    if (downloadFirst) {
                      downloadedFilenames =
                          await downloadRef.downloadAllFiles(currentMod);
                      currentMod = await modsRef.updateSelectedMod(currentMod);
                    }

                    // 2. Create backup
                    await backupRef.createBackup(currentMod, backupFolder);
                    currentMod = await modsRef.updateModBackup(currentMod);

                    // 3. Delete assets if requested
                    Set<String> deletedFilenames = {};
                    if (postBackupDeletion != PostBackupDeletionEnum.none) {
                      final deleted =
                          await deleteRef.deleteModAssetsAfterBackup(
                        currentMod,
                        postBackupDeletion,
                      );
                      deletedFilenames = deleted.toSet();

                      if (deleted.isNotEmpty) {
                        await modsRef.updateSelectedMod(currentMod);
                      }
                    }

                    // 4. Refresh other mods that share affected assets
                    final allAffected = {
                      ...downloadedFilenames,
                      ...deletedFilenames
                    };
                    if (allAffected.isNotEmpty) {
                      await modsRef.refreshModsWithSharedAssets(allAffected,
                          excludeJsonFileName: currentMod.jsonFileName);
                    }
                  },
                ),
              );
            },
            label: const Text('Backup'),
          ),
          SelectedModActionsMenu(selectedMod: selectedMod),
        ],
      ),
    );
  }
}
