import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show ConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/state/provider.dart' show downloadProvider;

class DownloadProgressBar extends ConsumerWidget {
  const DownloadProgressBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadState = ref.watch(downloadProvider);
    final canceling = downloadState.cancelledDownloads;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        spacing: 4,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!canceling && downloadState.statusMessage != null)
                Expanded(
                  child: Text(
                    downloadState.statusMessage!,
                    maxLines: 4,
                    style: TextStyle(fontSize: 18),
                  ),
                ),
              if (canceling)
                Text(
                  'Cancelling downloads',
                  style: TextStyle(fontSize: 18),
                ),
              if (!canceling)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ElevatedButton(
                    onPressed: () async {
                      await ref
                          .read(downloadProvider.notifier)
                          .handleCancelDownloadsButton();
                    },
                    child: Text(
                      'Cancel',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                )
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8, bottom: 8),
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(32),
              ),
              child: Stack(
                children: [
                  FractionallySizedBox(
                    widthFactor: downloadState.progress.clamp(0.0, 1.0),
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
      ),
    );
  }
}
