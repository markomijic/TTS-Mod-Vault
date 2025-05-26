import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show ConsumerWidget, HookConsumer, WidgetRef;
import 'package:tts_mod_vault/src/state/provider.dart' show downloadProvider;

class DownloadProgressBar extends ConsumerWidget {
  const DownloadProgressBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadingType = ref.watch(downloadProvider).downloadingType;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: 5,
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
                      .handleCancelDownloadsButton();
                },
                child: Text('Cancel'),
              ),
            )
          ],
        ),
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
                HookConsumer(
                  builder: (context, ref, child) {
                    final progress = ref.watch(downloadProvider).progress;

                    return FractionallySizedBox(
                      widthFactor: progress.clamp(0.0, 1.0),
                      child: Container(
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(32),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
