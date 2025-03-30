import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show ConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        actionInProgressProvider,
        backupProvider,
        cleanupProvider,
        directoriesProvider,
        existingAssetListsProvider,
        modsProvider;
import 'package:tts_mod_vault/src/utils.dart'
    show showAlertDialog, showSnackBar;

class Toolbar extends ConsumerWidget {
  const Toolbar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actionInProgress = ref.watch(actionInProgressProvider);
    final cleanupNotifier = ref.watch(cleanupProvider.notifier);
    final backupNotifier = ref.watch(backupProvider.notifier);

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
                          '$count files found that are not used by any of your mods.\nAre you sure you want to delete them?',
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
          child: const Text('Cleanup'),
        ),
        ElevatedButton(
          onPressed: actionInProgress
              ? null
              : () => showAlertDialog(
                    context,
                    'Are you sure you want to refresh all mods?',
                    () async {
                      ref.read(modsProvider.notifier).setLoading();
                      WidgetsBinding.instance.addPostFrameCallback((_) async {
                        await ref
                            .read(existingAssetListsProvider.notifier)
                            .loadAssetTypeLists();
                        await ref
                            .read(modsProvider.notifier)
                            .loadModsData(null);
                      });
                    },
                  ),
          child: const Text('Refresh'),
        ),
        ElevatedButton(
          onPressed: actionInProgress
              ? null
              : () async {
                  final backupResult = await backupNotifier
                      .importBackup(ref.read(directoriesProvider).ttsDir);

                  if (backupResult && context.mounted) {
                    showSnackBar(context, 'Import finished. Refreshing data...',
                        Duration(seconds: 2));
                    Future.delayed(
                        kThemeChangeDuration,
                        () => WidgetsBinding.instance
                                .addPostFrameCallback((_) async {
                              ref.read(modsProvider.notifier).setLoading();
                              await ref
                                  .read(existingAssetListsProvider.notifier)
                                  .loadAssetTypeLists();
                              await ref
                                  .read(modsProvider.notifier)
                                  .loadModsData(null);
                            }));
                  }
                },
          child: const Text('Import backup'),
        ),
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
