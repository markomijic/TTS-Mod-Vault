import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useEffect;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show AsyncValueX, HookConsumerWidget, WidgetRef;
import 'package:package_info_plus/package_info_plus.dart' show PackageInfo;
import 'package:tts_mod_vault/src/mods/components/assets_list.dart'
    show AssetsList;
import 'package:tts_mod_vault/src/mods/components/mods_grid.dart' show ModsGrid;
import 'package:tts_mod_vault/src/mods/components/toolbar.dart' show Toolbar;
import 'package:tts_mod_vault/src/state/cleanup/cleanup_state.dart'
    show CleanUpStatusEnum;
import 'package:tts_mod_vault/src/state/provider.dart'
    show backupProvider, cleanupProvider, modsProvider, selectedModProvider;
import 'package:tts_mod_vault/src/utils.dart'
    show
        checkForUpdatesOnGitHub,
        getGitHubReleaseUrl,
        openUrl,
        showAlertDialog,
        showSnackBar;

class ModsPage extends HookConsumerWidget {
  const ModsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cleanUpNotifier = ref.watch(cleanupProvider.notifier);
    final cleanUpState = ref.watch(cleanupProvider);
    final backup = ref.watch(backupProvider);
    final mods = ref.watch(modsProvider);

    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (cleanUpState.status == CleanUpStatusEnum.completed) {
          showSnackBar(context, 'Cleanup finished!');
          cleanUpNotifier.resetState();
        } else if (cleanUpState.status == CleanUpStatusEnum.error) {
          showSnackBar(
            context,
            'Cleanup error: ${ref.read(cleanupProvider).errorMessage}',
          );
          cleanUpNotifier.resetState();
        }
      });

      return null;
    }, [cleanUpState]);

    // Check for updates on initial opening of page
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // TODO add a check if checking for updates at startup is enabled
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
      });
      return null;
    }, []);

    return SafeArea(
      child: Scaffold(
        body: Stack(
          children: [
            Column(
              children: [
                Container(
                  height: 50,
                  padding: const EdgeInsets.only(left: 12.0, bottom: 4),
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Toolbar(),
                  ),
                ),
                Expanded(
                  child: mods.when(
                    data: (data) {
                      return Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: ModsGrid(mods: data.mods),
                            ),
                          ),
                          Expanded(
                            flex: 1,
                            child: AssetsList(),
                          ),
                        ],
                      );
                    },
                    error: (e, st) => Center(
                      child: Text(
                        'Something went wrong, please try restarting the application\nError: '
                        '$e',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    loading: () => Center(
                      child: Text(
                        "Loading",
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (backup.backupInProgress || backup.importInProgress)
              Container(
                color: Colors.black.withAlpha(180),
                child: Center(
                  child: Text(
                    backup.importInProgress
                        ? (backup.importFileName.isNotEmpty == true
                            ? "Import of ${backup.importFileName} in progress"
                            : "Import in progress")
                        : backup.backupInProgress
                            ? "Backing up ${ref.read(selectedModProvider)?.name ?? ''}"
                            : "",
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
