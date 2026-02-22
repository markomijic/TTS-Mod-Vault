import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show ConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/backups/components/backups_grid.dart';
import 'package:tts_mod_vault/src/backups/components/backups_list.dart';
import 'package:tts_mod_vault/src/state/provider.dart'
    show filteredBackupsProvider, settingsProvider;

class BackupsView extends ConsumerWidget {
  const BackupsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final useBackupsListView = ref.watch(settingsProvider).useBackupsListView;
    final backups = ref.watch(filteredBackupsProvider);

    return useBackupsListView
        ? BackupsList(backups: backups)
        : BackupsGrid(backups: backups);
  }
}
