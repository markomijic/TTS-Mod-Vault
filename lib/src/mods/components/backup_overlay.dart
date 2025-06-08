import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show ConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/state/provider.dart'
    show backupProvider, selectedModProvider;

class BackupOverlay extends ConsumerWidget {
  const BackupOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedMod = ref.watch(selectedModProvider);
    final backup = ref.watch(backupProvider);

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
      child: Container(
        color: Colors.black.withAlpha(180),
        child: Center(
          child: Text(
            backup.importInProgress
                ? (backup.importFileName.isNotEmpty == true
                    ? "Import of ${backup.importFileName} in progress"
                    : "Import in progress")
                : backup.backupInProgress
                    ? "Backing up ${selectedMod?.saveName ?? ''}"
                    : "",
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
