import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show ConsumerWidget, WidgetRef;
import 'package:package_info_plus/package_info_plus.dart' show PackageInfo;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        actionInProgressProvider,
        backupProvider,
        cleanupProvider,
        existingAssetListsProvider,
        loaderProvider,
        modsProvider;
import 'package:tts_mod_vault/src/utils.dart'
    show
        checkForUpdatesOnGitHub,
        getGitHubReleaseUrl,
        openUrl,
        showAlertDialog,
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
        await ref.read(loaderProvider.notifier).refreshAppData();
      });
    }

/* // Example usage in your app
    void showSettingsDialog(BuildContext context) async {
      try {
        print('Loading settings...');
        final currentSettings = await SettingsManager.loadSettings();
        print('Settings loaded: ${currentSettings.toJson()}');

        if (context.mounted) {
          showDialog(
            context: context,
            builder: (context) => SettingsDialog(
              initialSettings: currentSettings,
              onSettingsSaved: (newSettings) {
                // Apply settings to your app
                print('Settings applied: ${newSettings.toJson()}');

                // Show a message to confirm settings were applied
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Settings applied successfully'),
                    duration: Duration(seconds: 2),
                  ),
                );

                // Example: Apply theme
                // ThemeProvider.of(context).setDarkMode(newSettings.darkMode);

                // Example: Apply font size
                // YourAppState.of(context).updateFontSize(newSettings.fontSize);

                // Example: Apply language
                // LocalizationProvider.of(context).changeLanguage(newSettings.language);
              },
            ),
          );
        }
      } catch (e) {
        print('Error showing settings dialog: $e');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error loading settings: ${e.toString()}')),
          );
        }
      }
    } */

    return Row(
      spacing: 10,
      children: [
        /*    ElevatedButton(
          onPressed: () => showSettingsDialog(context),
          child: const Text('Settings'),
        ), */
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
              showSnackBar(context, 'Import finished, refreshing data',
                  Duration(seconds: 1));
              Future.delayed(
                  kThemeChangeDuration, () async => await refreshData());
            }
          },
          child: const Text('Import backup'),
        ),
        ElevatedButton(
          onPressed: () async {
            final newTagVersion = await checkForUpdatesOnGitHub();

            if (newTagVersion.isNotEmpty) {
              final packageInfo = await PackageInfo.fromPlatform();
              final currentVersion = packageInfo.version;

              if (!context.mounted) return;

              showAlertDialog(context,
                  "Your version: $currentVersion\nLatest version: $newTagVersion\n\nA new application version is available.\nWould you like to open the download page?",
                  () async {
                final url = getGitHubReleaseUrl(newTagVersion);
                final result = await openUrl(url);
                if (!result && context.mounted) {
                  showSnackBar(context, "Failed to open url: $url");
                }
              });
            }
          },
          child: const Text('Check for updates'),
        ),
        ElevatedButton(
          onPressed: () async {
            final url = ""; // TODO replace with steam forum thread
            final result = await openUrl(url);
            if (!result && context.mounted) {
              showSnackBar(context, "Failed to open url: $url");
            }
          },
          child: const Text('Help / Feedback'),
        ),
/*         ElevatedButton(
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
        ), */
      ],
    );
  }
}
