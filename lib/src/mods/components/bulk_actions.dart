import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/state/provider.dart';

class BulkActions extends HookConsumerWidget {
  const BulkActions({super.key});

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
            if (ref.read(actionInProgressProvider)) return;

            ref
                .read(bulkActionsProvider.notifier)
                .downloadAllMods(ref.read(filteredModsProvider));
          },
        ),
/*         MenuItemButton(
          style: MenuItemButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
          ),
          onPressed: () {},
          leadingIcon: Icon(Icons.archive, color: Colors.black),
          child: Text('Backup all', style: TextStyle(color: Colors.black)),
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
          onPressed: () {},
        ), */
      ],
      builder: (
        BuildContext context,
        MenuController controller,
        Widget? child,
      ) {
        return ElevatedButton.icon(
          onPressed: actionInProgress
              ? null
              : () {
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
