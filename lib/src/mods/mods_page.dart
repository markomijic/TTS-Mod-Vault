import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show AsyncValueX, HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/mods/components/import_backup_overlay.dart'
    show ImportBackupOverlay;
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show
        ErrorMessage,
        MessageProgressIndicator,
        ModsSelector,
        Search,
        SelectedModView,
        Toolbar,
        ModsView,
        BulkActionsProgressBar,
        SortButton;
import 'package:tts_mod_vault/src/mods/components/filter_button.dart'
    show FilterButton;
import 'package:tts_mod_vault/src/mods/hooks/hooks.dart'
    show useCleanupSnackbar, useBackupSnackbar;
import 'package:tts_mod_vault/src/state/provider.dart'
    show loadingMessageProvider, modsProvider;

class ModsPage extends HookConsumerWidget {
  const ModsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loadingMessage = ref.watch(loadingMessageProvider);
    final mods = ref.watch(modsProvider);

    useCleanupSnackbar(context, ref);
    useBackupSnackbar(context, ref);

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
                                          SortButton(),
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
                                BulkActionsProgressBar(),
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
            ImportBackupOverlay(),
          ],
        ),
      ),
    );
  }
}
