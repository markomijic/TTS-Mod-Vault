import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show ConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show HelpMenu;
import 'package:tts_mod_vault/src/settings/settings_dialog.dart'
    show SettingsDialog;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        actionInProgressProvider,
        cleanupProvider,
        loaderProvider,
        importBackupProvider,
        settingsProvider;
import 'package:tts_mod_vault/src/utils.dart'
    show showConfirmDialog, showSnackBar;

class Toolbar extends ConsumerWidget {
  const Toolbar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actionInProgress = ref.watch(actionInProgressProvider);
    final cleanupNotifier = ref.watch(cleanupProvider.notifier);
    final importBackupNotifier = ref.watch(importBackupProvider.notifier);

    return Row(
      spacing: 8,
      children: [
        ElevatedButton.icon(
          onPressed: actionInProgress
              ? null
              : () => showDialog(
                    context: context,
                    builder: (context) => Dialog(
                      insetPadding: EdgeInsets.all(20),
                      child: SizedBox(
                        width: 1280 * 0.95,
                        height: 720 * 0.65,
                        child: SettingsDialog(),
                      ),
                    ),
                  ),
          icon: const Icon(Icons.settings),
          label: const Text('Settings'),
        ),
        ElevatedButton.icon(
          onPressed: actionInProgress
              ? null
              : () async {
                  await cleanupNotifier.startCleanup(
                    (count) {
                      if (count > 0) {
                        final itemTypes =
                            ref.read(settingsProvider).showSavedObjects
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
          icon: const Icon(Icons.cleaning_services),
          label: const Text('Cleanup'),
        ),
        ElevatedButton.icon(
          onPressed: actionInProgress
              ? null
              : () => showConfirmDialog(
                    context,
                    'Are you sure you want to refresh data for all mods?',
                    () async {
                      await ref.read(loaderProvider).refreshAppData();
                    },
                  ),
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh'),
        ),
        ElevatedButton.icon(
          onPressed: actionInProgress
              ? null
              : () async {
                  final backupResult =
                      await importBackupNotifier.importBackup();

                  if (backupResult && context.mounted) {
                    showSnackBar(context, 'Import finished, refreshing data');
                    await ref.read(loaderProvider).refreshAppData();
                  }
                },
          icon: const Icon(Icons.unarchive),
          label: const Text('Import backup'),
        ),
        HelpMenu(),
      ],
    );
  }
}
