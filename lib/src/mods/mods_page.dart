import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useState;
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
        ModsView,
        BulkActionsProgressBar,
        SortButton,
        BulkActionsMenu,
        Sidebar,
        CustomTooltip;
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
    final sidebarWidth = useState<double>(40);
    useCleanupSnackbar(context, ref);
    useBackupSnackbar(context, ref);

    return SafeArea(
      child: Scaffold(
        body: Stack(
          children: [
            mods.when(
              data: (data) {
                return Stack(
                  children: [
                    Row(
                      children: [
                        SizedBox(width: sidebarWidth.value),
                        Expanded(
                          flex: 2,
                          child: ModsColumn(),
                        ),
                        Expanded(
                          flex: 1,
                          child: SelectedModView(),
                        ),
                      ],
                    ),
                    Sidebar(width: sidebarWidth.value),
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
            ImportBackupOverlay(),
          ],
        ),
      ),
    );
  }
}

class ModsColumn extends StatelessWidget {
  const ModsColumn({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(
            top: 8,
            right: 4,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ModsSelector(),
                    Search(),
                    BulkActionsMenu(),
                    SortButton(),
                    FilterButton(),
                  ],
                ),
              ),
              CustomTooltip(
                message:
                    '• Right-click a mod to see options\n• Bulk actions are affected by sort, filters and search',
                child: Icon(
                  Icons.info_outline,
                  size: 26,
                ),
              )
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              top: 8,
              bottom: 8,
              right: 4,
            ),
            child: ModsView(),
          ),
        ),
        BulkActionsProgressBar(),
      ],
    );
  }
}
