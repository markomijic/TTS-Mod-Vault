import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show AsyncValueX, HookConsumerWidget, WidgetRef;

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
        CustomTooltip;
import 'package:tts_mod_vault/src/mods/components/filter_button.dart'
    show FilterButton;

import 'package:tts_mod_vault/src/state/provider.dart'
    show loadingMessageProvider, modsProvider;

class ModsPage extends HookConsumerWidget {
  const ModsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loadingMessage = ref.watch(loadingMessageProvider);
    final mods = ref.watch(modsProvider);

    return mods.when(
      data: (data) {
        return Row(
          children: [
            Expanded(
              flex: 2,
              child: ModsColumn(),
            ),
            Expanded(
              flex: 1,
              child: SelectedModView(),
            ),
          ],
        );
      },
      error: (e, st) => Center(
        child: Padding(
          padding: const EdgeInsets.only(right: 40),
          child: ErrorMessage(e: e),
        ),
      ),
      loading: () => Center(
        child: Padding(
          padding: const EdgeInsets.only(right: 40),
          child: MessageProgressIndicator(message: loadingMessage),
        ),
      ),
    );
  }
}

class ModsColumn extends StatelessWidget {
  const ModsColumn({super.key});

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
                    SortButton(),
                    FilterButton(),
                    BulkActionsMenu(),
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
