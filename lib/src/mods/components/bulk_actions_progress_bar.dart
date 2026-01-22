import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useMemoized;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/state/bulk_actions/bulk_actions_state.dart'
    show BulkActionsStatusEnum;
import 'package:tts_mod_vault/src/state/provider.dart' show bulkActionsProvider;

class BulkActionsProgressBar extends HookConsumerWidget {
  const BulkActionsProgressBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bulkActionsState = ref.watch(bulkActionsProvider);

    final progress = useMemoized(() {
      return (bulkActionsState.totalModNumber > 0)
          ? bulkActionsState.currentModNumber / bulkActionsState.totalModNumber
          : 0.0;
    }, [bulkActionsState]);

    if (bulkActionsState.status == BulkActionsStatusEnum.idle) {
      return SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4, right: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        spacing: 4,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!bulkActionsState.cancelledBulkAction) ...[
                Expanded(
                  child: Text(
                    bulkActionsState.statusMessage,
                    style: TextStyle(fontSize: 16),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (!bulkActionsState.cancelledBulkAction) {
                      ref.read(bulkActionsProvider.notifier).cancelBulkAction();
                    }
                  },
                  child: Text('Cancel all'),
                ),
              ] else
                Expanded(
                  child: Text(
                    bulkActionsState.statusMessage,
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
    );
  }
}
