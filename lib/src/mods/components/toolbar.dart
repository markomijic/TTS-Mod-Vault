import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show ConsumerWidget, WidgetRef;
import 'package:package_info_plus/package_info_plus.dart' show PackageInfo;
import 'package:tts_mod_vault/src/changelog.dart' show showChangelogDialog;
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show HelpAndFeedbackButton;
import 'package:tts_mod_vault/src/settings/settings_dialog.dart'
    show SettingsDialog;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        actionInProgressProvider,
        backupProvider,
        cleanupProvider,
        loaderProvider,
        modsProvider;
import 'package:tts_mod_vault/src/utils.dart'
    show
        checkForUpdatesOnGitHub,
        showConfirmDialog,
        showDownloadDialog,
        showSnackBar;

class Toolbar extends ConsumerWidget {
  const Toolbar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actionInProgress = ref.watch(actionInProgressProvider);
    final cleanupNotifier = ref.watch(cleanupProvider.notifier);
    final backupNotifier = ref.watch(backupProvider.notifier);

    Future<void> refreshData() async {
      ref.read(modsProvider.notifier).setLoading();

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await ref.read(loaderProvider).refreshAppData();
      });
    }

    return Row(
      spacing: 10,
      children: [
        ElevatedButton(
          onPressed: actionInProgress
              ? null
              : () => showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return SettingsDialog();
                  }),
          child: const Text('Settings'),
        ),
        ElevatedButton(
          onPressed: actionInProgress
              ? null
              : () async {
                  await cleanupNotifier.startCleanup(
                    (count) {
                      if (count > 0) {
                        showConfirmDialog(
                          context,
                          '$count files found that are not used by any of your mods.\nAre you sure you want to delete them?',
                          () async {
                            await cleanupNotifier.executeDelete();
                          },
                          () {
                            cleanupNotifier.resetState();
                          },
                        );
                      } else {
                        showSnackBar(context, 'No files found to delete');
                      }
                    },
                  );
                },
          child: const Text('Cleanup'),
        ),
        ElevatedButton(
          onPressed: actionInProgress
              ? null
              : () => showConfirmDialog(
                    context,
                    'Are you sure you want to refresh data for all mods?',
                    () async {
                      await refreshData();
                    },
                  ),
          child: const Text('Refresh'),
        ),
        ElevatedButton(
          onPressed: () async {
            if (actionInProgress) {
              return;
            }

            final backupResult = await backupNotifier.importBackup();

            if (backupResult && context.mounted) {
              showSnackBar(context, 'Import finished, refreshing data');
              Future.delayed(
                  kThemeChangeDuration, () async => await refreshData());
            }
          },
          child: const Text('Import backup'),
        ),
        ElevatedButton(
          onPressed: () => showChangelogDialog(context),
          child: const Text('Changelog'),
        ),
        ElevatedButton(
          onPressed: () async {
            final newTagVersion = await checkForUpdatesOnGitHub();

            if (newTagVersion.isNotEmpty) {
              final packageInfo = await PackageInfo.fromPlatform();
              final currentVersion = packageInfo.version;

              if (!context.mounted) return;

              await showDownloadDialog(context, currentVersion, newTagVersion);
            } else {
              if (context.mounted) {
                showSnackBar(context, 'No new updates found');
              }
            }
          },
          child: const Text('Check for updates'),
        ),
        HelpAndFeedbackButton(),
      ],
    );
  }
}
