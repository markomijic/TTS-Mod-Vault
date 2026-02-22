import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show ConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/backups/components/backups_list_item.dart'
    show BackupsListItem;

import 'package:tts_mod_vault/src/state/backup/models/existing_backup_model.dart'
    show ExistingBackup;

class BackupsList extends ConsumerWidget {
  final List<ExistingBackup> backups;

  const BackupsList({super.key, required this.backups});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.builder(
      itemCount: backups.length,
      itemBuilder: (context, index) {
        return BackupsListItem(backup: backups[index]);
      },
    );
  }
}
