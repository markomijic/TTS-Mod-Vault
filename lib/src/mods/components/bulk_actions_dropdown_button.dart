import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show BulkBackupDialog;
import 'package:tts_mod_vault/src/state/bulk_actions/bulk_actions_state.dart'
    show BulkBackupBehaviorEnum;
import 'package:tts_mod_vault/src/state/provider.dart'
    show actionInProgressProvider, bulkActionsProvider, filteredModsProvider;

class BulkActionsDropDownButton extends HookConsumerWidget {
  const BulkActionsDropDownButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actionInProgress = ref.watch(actionInProgressProvider);

    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStateProperty.all(Colors.black),
      ),
      menuChildren: <Widget>[
        MenuItemButton(
          style: MenuItemButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
          ),
          leadingIcon: Icon(Icons.download, color: Colors.black),
          child: Text('Download all', style: TextStyle(color: Colors.black)),
          onPressed: () {
            if (actionInProgress) return;

            ref
                .read(bulkActionsProvider.notifier)
                .downloadAllMods(ref.read(filteredModsProvider));
          },
        ),
        MenuItemButton(
          style: MenuItemButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
          ),
          leadingIcon: Icon(Icons.archive, color: Colors.black),
          child: Text('Backup all', style: TextStyle(color: Colors.black)),
          onPressed: () {
            if (actionInProgress) return;

            showDialog(
              context: context,
              builder: (context) => BulkBackupDialog(
                title: 'Backup all',
                initialBehavior: BulkBackupBehaviorEnum.replaceIfOutOfDate,
                onConfirm: (behavior, folder) {
                  ref.read(bulkActionsProvider.notifier).backupAllMods(
                        ref.read(filteredModsProvider),
                        behavior,
                        folder,
                      );
                },
              ),
            );
          },
        ),
        MenuItemButton(
          style: MenuItemButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
          ),
          leadingIcon: Icon(Icons.download, color: Colors.black),
          trailingIcon: Icon(Icons.archive, color: Colors.black),
          child: Text('Download & backup all',
              style: TextStyle(color: Colors.black)),
          onPressed: () {
            if (actionInProgress) return;

            showDialog(
              context: context,
              builder: (context) => BulkBackupDialog(
                title: 'Download & backup all',
                initialBehavior: BulkBackupBehaviorEnum.replaceIfOutOfDate,
                onConfirm: (behavior, folder) {
                  ref
                      .read(bulkActionsProvider.notifier)
                      .downloadAndBackupAllMods(
                        ref.read(filteredModsProvider),
                        behavior,
                        folder,
                      );
                },
              ),
            );
          },
        ),
      ],
      builder: (
        BuildContext context,
        MenuController controller,
        Widget? child,
      ) {
        return ElevatedButton.icon(
          onPressed: () {
            if (actionInProgress) return;

            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
          label: Text('Bulk actions'),
          icon: Icon(
            Icons.arrow_drop_down,
            size: 26,
          ),
        );
      },
    );
  }
}
