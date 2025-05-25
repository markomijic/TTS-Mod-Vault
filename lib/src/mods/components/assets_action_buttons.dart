import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useMemoized;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        actionInProgressProvider,
        backupProvider,
        downloadProvider,
        modsProvider,
        selectedAssetProvider,
        selectedModProvider;
import 'package:tts_mod_vault/src/utils.dart' show showSnackBar;

class AssetsActionButtons extends HookConsumerWidget {
  const AssetsActionButtons({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedMod = ref.watch(selectedModProvider);

    final hasMissingFiles = useMemoized(() {
      if (selectedMod == null || selectedMod.assetLists == null) return false;

      return selectedMod.getAllAssets().any((asset) => !asset.fileExists);
    }, [selectedMod]);

    if (selectedMod == null) {
      return SizedBox.shrink();
    }

    final selectedAsset = ref.watch(selectedAssetProvider);
    final selectedAssetNotifier = ref.watch(selectedAssetProvider.notifier);
    final modsLibraryNotifier = ref.watch(modsProvider.notifier);
    final downloadNotifier = ref.watch(downloadProvider.notifier);
    final actionInProgress = ref.watch(actionInProgressProvider);

    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: 10,
      children: [
        ElevatedButton(
          onPressed: selectedAsset != null && !actionInProgress
              ? () async {
                  await downloadNotifier.downloadFiles(
                    modName: selectedMod.name,
                    urls: [selectedAsset.asset.url],
                    type: selectedAsset.type,
                    downloadingAllFiles: false,
                  );
                  await modsLibraryNotifier.updateMod(selectedMod.name);
                  selectedAssetNotifier.resetState();
                }
              : null,
          child: Text('Download',
              style: TextStyle(
                color: selectedAsset != null ? Colors.black : null,
              )),
        ),
        ElevatedButton(
          onPressed: hasMissingFiles && !actionInProgress
              ? () async {
                  await downloadNotifier.downloadAllFiles(selectedMod);
                  await modsLibraryNotifier.updateMod(selectedMod.name);
                  selectedAssetNotifier.resetState();
                }
              : null,
          child: const Text('Download all'),
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
