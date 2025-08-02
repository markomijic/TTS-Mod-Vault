import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useMemoized;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/src/state/backup/backup_status_enum.dart'
    show ExistingBackupStatusEnum;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show Mod;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        actionInProgressProvider,
        backupProvider,
        downloadProvider,
        modsProvider;
import 'package:tts_mod_vault/src/utils.dart' show showConfirmDialog;

class SelectedModActionButtons extends HookConsumerWidget {
  final Mod selectedMod;

  const SelectedModActionButtons({super.key, required this.selectedMod});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasMissingFiles = useMemoized(() {
      if (selectedMod.assetLists == null) return false;

      return selectedMod.getAllAssets().any((asset) => !asset.fileExists);
    }, [selectedMod]);

    final modsNotifier = ref.watch(modsProvider.notifier);
    final backupNotifier = ref.watch(backupProvider.notifier);
    final downloadNotifier = ref.watch(downloadProvider.notifier);
    final actionInProgress = ref.watch(actionInProgressProvider);

    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: 8,
      children: [
        ElevatedButton(
          onPressed: hasMissingFiles
              ? () async {
                  if (actionInProgress) {
                    return;
                  }

                  await downloadNotifier.downloadAllFiles(selectedMod);
                  await modsNotifier.updateSelectedMod(selectedMod);
                }
              : null,
          child: const Text('Download'),
        ),
        ElevatedButton(
          onPressed: () async {
            if (actionInProgress) {
              return;
            }

            if (selectedMod.backupStatus == ExistingBackupStatusEnum.noBackup) {
              await backupNotifier.createBackup(selectedMod);
              await modsNotifier.updateSelectedMod(selectedMod);
              return;
            }

            showConfirmDialog(
              context,
              'Backup already exists. Replace existing file?',
              () async {
                final backupFolder = p.dirname(selectedMod.backup!.filepath);

                await backupNotifier.createBackup(selectedMod, backupFolder);
                await modsNotifier.updateSelectedMod(selectedMod);
              },
              () async {
                await backupNotifier.createBackup(selectedMod);
                await modsNotifier.updateSelectedMod(selectedMod);
              },
            );
          },
          child: const Text('Backup'),
        ),
      ],
    );
  }
}
