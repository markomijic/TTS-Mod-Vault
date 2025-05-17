import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show ConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        downloadProvider,
        modsProvider,
        selectedAssetProvider,
        selectedModProvider;

class DownloadProgressBar extends ConsumerWidget {
  const DownloadProgressBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(downloadProvider).progress;
    final downloadingType = ref.watch(downloadProvider).downloadingType;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (downloadingType != null)
              Text('Downloading ${downloadingType.label}'),
            Padding(
              padding: const EdgeInsets.only(right: 6.0),
              child: ElevatedButton(
                onPressed: () async {
                  await ref
                      .read(downloadProvider.notifier)
                      .cancelAllDownloads();
                  await ref
                      .read(modsProvider.notifier)
                      .updateMod(ref.read(selectedModProvider)!.name);
                  ref.read(selectedAssetProvider.notifier).resetState();
                },
                child: Text('Cancel'),
              ),
            )
          ],
        ), // ${downloadingType.label}'),
        SizedBox(height: 5),
        Padding(
          padding: const EdgeInsets.only(right: 6.0),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(32),
            ),
            child: Stack(
              children: [
                FractionallySizedBox(
                  widthFactor: progress.clamp(0.0, 1.0),
                  child: Container(
                    height: 20,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(32),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
