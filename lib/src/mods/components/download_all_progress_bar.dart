import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useMemoized;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/state/provider.dart' show bulkActionsProvider;

class DownloadAllProgressBar extends HookConsumerWidget {
  const DownloadAllProgressBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadingAllMods =
        ref.watch(bulkActionsProvider).downloadingAllMods;
    final cancelledDownloadingAllMods =
        ref.watch(bulkActionsProvider).cancelledDownloadingAllMods;
    final currentNumber = ref.watch(bulkActionsProvider).currentModNumber;
    final totalNumber = ref.watch(bulkActionsProvider).totalModNumber;

    final progress = useMemoized(() {
      return (totalNumber > 0) ? currentNumber / totalNumber : 0.0;
    }, [currentNumber, totalNumber]);

    if (!downloadingAllMods) {
      return SizedBox.shrink();
    }

    return SizedBox(
      height: 70,
      child: Padding(
        padding: const EdgeInsets.only(
          left: 8,
          right: 8,
          bottom: 12,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          spacing: 4,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!cancelledDownloadingAllMods) ...[
                  Expanded(
                    child: Text(
                      "Downloading all mods: $currentNumber / $totalNumber",
                      style: TextStyle(fontSize: 16),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 6.0),
                    child: ElevatedButton(
                      onPressed: () {
                        ref
                            .read(bulkActionsProvider.notifier)
                            .cancelAllDownloads();
                      },
                      child: Text('Cancel all downloads'),
                    ),
                  ),
                ] else
                  Expanded(
                    child: Text(
                      'Cancelling all downloads',
                      style: TextStyle(fontSize: 16),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
            Container(
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
          ],
        ),
      ),
    );
  }
}
