import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useEffect;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show AsyncValueX, HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/mods/components/backup_overlay.dart'
    show BackupOverlay;
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show
        ErrorMessage,
        MessageProgressIndicator,
        ModsSelector,
        Search,
        SelectedModView,
        Toolbar,
        ModsView,
        BulkActions,
        DownloadAllProgressBar;
import 'package:tts_mod_vault/src/mods/components/filter.dart'
    show FilterButton;
import 'package:tts_mod_vault/src/state/cleanup/cleanup_state.dart'
    show CleanUpStatusEnum;
import 'package:tts_mod_vault/src/state/provider.dart'
    show backupProvider, cleanupProvider, loadingMessageProvider, modsProvider;
import 'package:tts_mod_vault/src/utils.dart' show showSnackBar;

class ModsPage extends HookConsumerWidget {
  const ModsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loadingMessage = ref.watch(loadingMessageProvider);
    final cleanUpNotifier = ref.watch(cleanupProvider.notifier);
    final cleanUpState = ref.watch(cleanupProvider);
    final backup = ref.watch(backupProvider);
    final mods = ref.watch(modsProvider);

    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        switch (cleanUpState.status) {
          case CleanUpStatusEnum.idle:
          case CleanUpStatusEnum.awaitingConfirmation:
            break;

          case CleanUpStatusEnum.deleting:
            showSnackBar(context, 'Deleting files...');
            break;

          case CleanUpStatusEnum.scanning:
            showSnackBar(context, 'Scanning for files...');
            break;

          case CleanUpStatusEnum.completed:
            showSnackBar(context, 'Cleanup finished!');
            cleanUpNotifier.resetState();
            break;

          case CleanUpStatusEnum.error:
            showSnackBar(
              context,
              'Cleanup error: ${ref.read(cleanupProvider).errorMessage}',
            );
            cleanUpNotifier.resetState();
            break;
        }
      });

      return null;
    }, [cleanUpState.status]);

    return SafeArea(
      child: Scaffold(
        body: Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8, left: 8),
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
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: EdgeInsets.only(top: 8, left: 8),
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: SizedBox(
                                      height: 32,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        spacing: 8,
                                        children: [
                                          ModsSelector(),
                                          Search(),
                                          BulkActions(),
                                          FilterButton(),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 8,
                                    ),
                                    child: ModsView(),
                                  ),
                                ),
                                DownloadAllProgressBar(),
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
                      child: MessageProgressIndicator(message: loadingMessage),
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
