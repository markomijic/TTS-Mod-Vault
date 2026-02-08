import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useMemoized;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/state/backup/backup_state.dart'
    show BackupStatusEnum;
import 'package:tts_mod_vault/src/state/provider.dart'
    show backupProvider, selectedModProvider;

class BackupProgressBar extends HookConsumerWidget {
  const BackupProgressBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedMod = ref.watch(selectedModProvider);
    final backup = ref.watch(backupProvider);

    final progress = useMemoized(() {
      return (backup.totalCount > 0)
          ? backup.currentCount / backup.totalCount
          : 0.0;
    }, [backup]);

    final progressText = useMemoized(() {
      return backup.totalCount > 0
          ? "(${backup.currentCount}/${backup.totalCount})"
          : "";
    }, [backup.totalCount, backup.currentCount]);

    final message = useMemoized(() {
      if (selectedMod == null) return "";

      switch (backup.status) {
        case BackupStatusEnum.awaitingBackupFolder:
          return "Select a folder to backup ${selectedMod.saveName}";

        case BackupStatusEnum.backingUp:
          return "Backing up ${selectedMod.saveName}";

        case BackupStatusEnum.idle:
          return "";
      }
    }, [backup.status, selectedMod]);

    if (backup.status == BackupStatusEnum.idle) {
      return SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        spacing: 4,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 4,
            children: [
              Text(
                progressText,
                style: TextStyle(fontSize: 20),
              ),
              Expanded(
                child: Text(
                  message,
                  maxLines: 4,
                  style: TextStyle(fontSize: 20),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8, bottom: 8),
            child: Container(
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
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
