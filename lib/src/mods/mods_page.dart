import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useEffect;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show AsyncValueX, HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/mods/components/backup_overlay.dart'
    show BackupOverlay;
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show
        ErrorMessage,
        ModsSelector,
        ModsGrid,
        ModsList,
        Search,
        SelectedModView,
        Toolbar;
import 'package:tts_mod_vault/src/state/cleanup/cleanup_state.dart'
    show CleanUpStatusEnum;
import 'package:tts_mod_vault/src/state/provider.dart'
    show backupProvider, cleanupProvider, modsProvider, settingsProvider;
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
                  padding: const EdgeInsets.only(top: 8, left: 8),
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: Toolbar(),
                ),
                Expanded(
                  child: mods.when(
                    data: (data) {
                      return Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Column(
                              children: [
                                Container(
                                  padding: EdgeInsets.only(top: 8, left: 8),
                                  color:
                                      Theme.of(context).scaffoldBackgroundColor,
                                  child: Row(
                                    spacing: 8,
                                    children: [
                                      ModsSelector(),
                                      Search(),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      top: 8,
                                      left: 4,
                                      right: 8,
                                    ),
                                    child: useModsListView
                                        ? ModsList(state: data)
                                        : ModsGrid(state: data),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 1,
                            child: SelectedModView(),
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
              BackupOverlay(),
          ],
        ),
      ),
    );
  }
}
