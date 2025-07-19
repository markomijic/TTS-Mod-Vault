import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/state/provider.dart';

class BulkActions extends HookConsumerWidget {
  const BulkActions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // TODO prevent clicking if action in progress
    return Row(
      spacing: 8,
      children: [
        ElevatedButton.icon(
          onPressed: () {
            ref
                .read(bulkActionsProvider.notifier)
                .downloadAllMods(ref.read(modsProvider).value!.mods);
          },
          // icon: Icon(Icons.download),
          label: Text('Bulk actions'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
          ),
        ),
        /*      ElevatedButton.icon(
          onPressed: () {},
          icon: Icon(Icons.archive),
          label: Text('Backup all'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
          ),
        ), */
      ],
    );
  }
}
