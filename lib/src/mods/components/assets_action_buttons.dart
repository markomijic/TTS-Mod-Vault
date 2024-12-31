import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:tts_mod_vault/src/state/provider.dart';

class AssetsActionButtons extends HookConsumerWidget {
  const AssetsActionButtons({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedMod = ref.watch(modsProvider).selectedMod;

    final hasMissingFiles = useMemoized(() {
      if (selectedMod == null || selectedMod.assetLists == null) return false;

      final assets = [
        ...selectedMod.assetLists!.assetBundles,
        ...selectedMod.assetLists!.audio,
        ...selectedMod.assetLists!.images,
        ...selectedMod.assetLists!.models,
        ...selectedMod.assetLists!.pdf,
      ];

      return assets.any((asset) => !asset.fileExists);
    }, [selectedMod]);

    if (selectedMod == null) {
      return SizedBox.shrink();
    }

    final selectedAsset = ref.watch(selectedAssetProvider);
    final selectedAssetNotifier = ref.watch(selectedAssetProvider.notifier);
    final modsLibraryNotifier = ref.watch(modsProvider.notifier);
    final downloadNotifier = ref.watch(downloadProvider.notifier);

    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: 10,
      children: [
        ElevatedButton(
          onPressed: selectedAsset != null
              ? () async {
                  await downloadNotifier.downloadFiles(
                    modName: selectedMod.name,
                    urls: [selectedAsset.asset.url],
                    type: selectedAsset.type,
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
          onPressed: hasMissingFiles
              ? () async {
                  await downloadNotifier.downloadAllFiles(selectedMod);

                  await modsLibraryNotifier.updateMod(selectedMod.name);

                  selectedAssetNotifier.resetState();
                }
              : null,
          child: const Text('Download all'),
        ),
        ElevatedButton(
          onPressed: null,
          child: const Text('Backup'),
        ),
      ],
    );
  }
}
