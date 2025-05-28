import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useEffect;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show AsyncValueX, HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show AssetsList, ErrorMessage, ModsGrid, ModsList, Toolbar;
import 'package:tts_mod_vault/src/state/cleanup/cleanup_state.dart'
    show CleanUpStatusEnum;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        backupProvider,
        cleanupProvider,
        modsProvider,
        selectedModProvider,
        settingsProvider;
import 'package:tts_mod_vault/src/utils.dart' show showSnackBar;

class ModsPage extends HookConsumerWidget {
  const ModsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final useModsListView = ref.watch(settingsProvider).useModsListView;
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
                      if (data.mods.isEmpty) {
                        return Center(
                          child: Text(
                              style: TextStyle(fontSize: 26),
                              textAlign: TextAlign.center,
                              "You don't seem to have any mods!\nSubscribe to some on the Steam workshop and then run Tabletop Simulator atleast once before restarting TTS Mod Vault!"),
                        );
                      }

                      return Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: useModsListView
                                  ? ModsList(mods: data.mods)
                                  : ModsGrid(mods: data.mods),
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
                      child: ErrorMessage(e: e),
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
