import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/src/state/provider.dart';
import 'package:tts_mod_vault/src/utils.dart';

class Toolbar extends ConsumerWidget {
  const Toolbar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actionInProgress = ref.watch(actionInProgressProvider);
    final cleanupNotifier = ref.watch(cleanupProvider.notifier);

    return Row(
      spacing: 10,
      children: [
        ElevatedButton(
          onPressed: null,
          child: const Text('Settings'),
        ),
        ElevatedButton(
          onPressed: actionInProgress
              ? null
              : () async {
                  await cleanupNotifier.startCleanup(
                    (count) {
                      if (count > 0) {
                        showAlertDialog(
                          context,
                          '$count files found, are you sure you want to delete them?',
                          () async {
                            await cleanupNotifier.executeDelete();
                          },
                          () {
                            cleanupNotifier.resetState();
                            Navigator.of(context).pop();
                          },
                        );
                      } else {
                        showSnackBar(context, 'No files found to delete.');
                      }
                    },
                  );
                },
          child: const Text('Clean Up'),
        ),
        ElevatedButton(
          onPressed: actionInProgress
              ? null
              : () => showAlertDialog(
                    context,
                    'Are you sure you want to refresh all mods?',
                    () => Navigator.of(context).pushNamed('/'),
                  ),
          child: const Text('Refresh'),
        ),
        SizedBox(width: 50),
        ElevatedButton(
          onPressed: null,
          /*    onPressed: () {
                ref.read(downloadProvider.notifier).downloadAllMods(
                  ref.read(modsProvider).mods,
                  (mod) async {
                    await ref.read(modsProvider.notifier).updateMod(mod.name);
                  },
                );
              }, */
          child: const Text('Download all mods'),
        ),
        ElevatedButton(
          onPressed: null,
          child: const Text('Backup all mods'),
        ),
      ],
    );
  }
}
