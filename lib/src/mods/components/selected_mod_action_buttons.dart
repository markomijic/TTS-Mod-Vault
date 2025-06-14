import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useMemoized;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show Mod;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        actionInProgressProvider,
        backupProvider,
        downloadProvider,
        modsProvider;
import 'package:tts_mod_vault/src/utils.dart' show showSnackBar;

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
    final downloadNotifier = ref.watch(downloadProvider.notifier);
    final actionInProgress = ref.watch(actionInProgressProvider);

    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: 10,
      children: [
        ElevatedButton(
          onPressed: hasMissingFiles && !actionInProgress
              ? () async {
                  await downloadNotifier.downloadAllFiles(selectedMod);
                  await modsNotifier.updateModBySaveName(selectedMod.saveName);
                }
              : null,
          child: const Text('Download'),
        ),
        ElevatedButton(
          onPressed: () async {
            if (actionInProgress) {
              return;
            }

            final result =
                await ref.read(backupProvider.notifier).createBackup();

            if (result.isNotEmpty && context.mounted) {
              showSnackBar(context, result);
            }
          },
          child: const Text('Backup'),
        ),
      ],
    );
  }
}
