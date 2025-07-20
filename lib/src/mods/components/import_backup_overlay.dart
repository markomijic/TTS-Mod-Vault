import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useMemoized;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show MessageProgressIndicator;

import 'package:tts_mod_vault/src/state/backup/import_backup_state.dart'
    show ImportBackupStatusEnum;
import 'package:tts_mod_vault/src/state/provider.dart'
    show importBackupProvider;

class ImportBackupOverlay extends HookConsumerWidget {
  const ImportBackupOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final importBackup = ref.watch(importBackupProvider);

    final message = useMemoized(() {
      switch (importBackup.status) {
        case ImportBackupStatusEnum.awaitingBackupFile:
          return "Select a backup to import";

        case ImportBackupStatusEnum.importingBackup:
          if (importBackup.importFileName.isNotEmpty) {
            final progressText = importBackup.totalCount > 0
                ? "\n${importBackup.currentCount}/${importBackup.totalCount}"
                : "";
            return "Importing ${importBackup.importFileName}$progressText";
          }

          return "Importing ${importBackup.importFileName}";

        case ImportBackupStatusEnum.idle:
          return "";
      }
    }, [importBackup]);

    if (importBackup.status == ImportBackupStatusEnum.idle) {
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
