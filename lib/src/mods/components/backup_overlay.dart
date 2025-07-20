import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useMemoized;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show MessageProgressIndicator;
import 'package:tts_mod_vault/src/state/backup/backup_state.dart'
    show BackupStatusEnum;
import 'package:tts_mod_vault/src/state/bulk_actions/bulk_actions_state.dart';
import 'package:tts_mod_vault/src/state/provider.dart'
    show backupProvider, selectedModProvider, bulkActionsProvider;

class BackupOverlay extends HookConsumerWidget {
  const BackupOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bulkActionStatus = ref.watch(bulkActionsProvider).status;
    final selectedMod = ref.watch(selectedModProvider);
    final backup = ref.watch(backupProvider);

    final message = useMemoized(() {
      if (selectedMod == null) return "";

      switch (backup.status) {
        case BackupStatusEnum.idle:
          return "";

        case BackupStatusEnum.awaitingBackupFolder:
          return "Select a folder to backup ${selectedMod.saveName}";

        case BackupStatusEnum.importingBackup:
          if (backup.importFileName.isNotEmpty) {
            final progressText = backup.totalCount > 0
                ? "\n${backup.currentCount}/${backup.totalCount}"
                : "";
            return "Importing ${backup.importFileName}$progressText";
          }

          return "Select a backup to import";

        case BackupStatusEnum.backingUp:
          final progressText = backup.totalCount > 0
              ? "\n${backup.currentCount}/${backup.totalCount}"
              : "";
          return "Backing up ${selectedMod.saveName}$progressText";
      }
    }, [backup, selectedMod]);

    if (backup.status == BackupStatusEnum.idle ||
        bulkActionStatus != BulkActionEnum.idle) {
      return SizedBox.shrink();
    }

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
      child: Container(
        color: Colors.black.withAlpha(180),
        child: Center(
          child: MessageProgressIndicator(
            message: message,
            showCircularIndicator: false,
          ),
        ),
      ),
    );
  }
}
