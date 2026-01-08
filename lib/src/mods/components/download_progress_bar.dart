import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show ConsumerWidget, HookConsumer, WidgetRef;
import 'package:tts_mod_vault/src/state/provider.dart' show downloadProvider;

class DownloadProgressBar extends ConsumerWidget {
  const DownloadProgressBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadingType = ref.watch(downloadProvider).downloadingType;
    final canceling = ref.watch(downloadProvider).cancelledDownloads;

    return SizedBox(
      height: 80,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        spacing: 4,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (downloadingType != null && !canceling)
                Text(
                  'Downloading ${downloadingType.label}',
                  style: TextStyle(fontSize: 16),
                ),
              if (canceling)
                Text(
                  'Cancelling downloads',
                  style: TextStyle(fontSize: 16),
                ),
              if (!canceling)
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
            padding: const EdgeInsets.only(right: 6.0, bottom: 12),
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
      ),
    );
  }
}
