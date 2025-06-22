import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useMemoized;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show MessageProgressIndicator;
import 'package:tts_mod_vault/src/state/provider.dart'
    show backupProvider, selectedModProvider;

class BackupOverlay extends HookConsumerWidget {
  const BackupOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedMod = ref.watch(selectedModProvider);
    final backup = ref.watch(backupProvider);

    final message = useMemoized(() {
      if (backup.importInProgress) {
        if (backup.importFileName.isNotEmpty && backup.totalCount > 0) {
          return "Importing ${backup.importFileName}\n${backup.currentCount}/${backup.totalCount}";
        }

        return "Select a backup to import";
      }

      if (selectedMod == null) return "";

      if (backup.backupInProgress && backup.totalCount > 0) {
        return "Backing up ${selectedMod.saveName}\n${backup.currentCount}/${backup.totalCount}";
      }

      return "Select a folder to backup ${selectedMod.saveName}";
    }, [backup, selectedMod]);

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
      child: Container(
        color: Colors.black.withAlpha(180),
        child: Center(
            child: MessageProgressIndicator(
                message: message,
                showCircularIndicator: ((backup.importFileName.isNotEmpty &&
                        backup.totalCount > 0) ||
                    (backup.backupInProgress && backup.totalCount > 0)))),
      ),
    );
  }
}
