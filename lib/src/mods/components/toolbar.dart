import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show HelpMenu, ToolsMenu;
import 'package:tts_mod_vault/src/settings/settings_dialog.dart'
    show SettingsDialog;
import 'package:tts_mod_vault/src/state/provider.dart'
    show actionInProgressProvider, importBackupProvider, loaderProvider;
import 'package:tts_mod_vault/src/utils.dart' show showConfirmDialog;

// TODO delete?
class Toolbar extends HookConsumerWidget {
  const Toolbar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actionInProgress = ref.watch(actionInProgressProvider);
    final importBackupNotifier = ref.watch(importBackupProvider.notifier);

    return Row(
      spacing: 8,
      children: [
        ElevatedButton.icon(
          onPressed: actionInProgress
              ? null
              : () => showDialog(
                    context: context,
                    builder: (context) => SettingsDialog(),
                  ),
          icon: const Icon(Icons.settings),
          label: const Text('Settings'),
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
                  await importBackupNotifier.importBackup();
                },
          icon: const Icon(Icons.unarchive),
          label: const Text('Import backup'),
        ),
        ToolsMenu(),
        HelpMenu(),
      ],
    );
  }
}
