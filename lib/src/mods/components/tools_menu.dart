import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show ConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show DownloadModByIdDialog;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        actionInProgressProvider,
        cleanupProvider,
        loaderProvider,
        settingsProvider;
import 'package:tts_mod_vault/src/utils.dart'
    show showConfirmDialog, showSnackBar;

class ToolsMenu extends ConsumerWidget {
  const ToolsMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actionInProgress = ref.watch(actionInProgressProvider);
    final cleanupNotifier = ref.watch(cleanupProvider.notifier);

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
          onPressed: () async {
            await cleanupNotifier.startCleanup(
              (count) {
                if (count > 0) {
                  final itemTypes = ref.read(settingsProvider).showSavedObjects
                      ? "mods, saves and saved objects"
                      : "mods and saves";

                  showConfirmDialog(
                    context,
                    '$count files found that are not used by any of your $itemTypes.\nAre you sure you want to delete them?',
                    () async {
                      await cleanupNotifier.executeDelete();
                    },
                    () {
                      cleanupNotifier.resetState();
                    },
                  );
                } else {
                  showSnackBar(context, 'No files found to delete');
                }
              },
            );
          },
          leadingIcon: Icon(Icons.delete, color: Colors.black),
          child: Text(
            'Cleanup',
            style: TextStyle(color: Colors.black),
          ),
        ),

        /* MenuItemButton(
          style: MenuItemButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
          ),
          onPressed: () => showDialog(
            context: context,
            builder: (context) => RenameOldBackupsDialog(),
          ),
          leadingIcon: Icon(Icons.edit, color: Colors.black),
          child: Text(
            'Rename old backups',
            style: TextStyle(color: Colors.black),
          ),
        ), */
        MenuItemButton(
          style: MenuItemButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
          ),
          onPressed: () {
            showConfirmDialog(
              context,
              'Are you sure you want to clear all cached mod data?\nData will be refreshed after clearing.',
              () async => await ref.read(loaderProvider).refreshAppData(true),
            );
          },
          leadingIcon: const Icon(
            Icons.clear_all,
            color: Colors.black,
          ),
          child: const Text(
            'Clear cache',
            style: TextStyle(color: Colors.black),
          ),
        ),
        MenuItemButton(
          style: MenuItemButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
          ),
          onPressed: () => showDialog(
            context: context,
            builder: (context) => DownloadModByIdDialog(),
          ),
          leadingIcon: const Icon(
            Icons.download,
            color: Colors.black,
          ),
          child: const Text('Download Workshop Mod by ID',
              style: TextStyle(
                color: Colors.black,
              )),
        ),
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
          label: Text('Tools'),
          icon: Icon(Icons.build),
        );
      },
    );
  }
}
