import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show AsyncValueX, ConsumerWidget, HookConsumerWidget, WidgetRef;
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
    show
        loadingMessageProvider,
        modsProvider,
        modsSearchQueryProvider,
        selectedModTypeProvider;

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

class ModsColumn extends ConsumerWidget {
  const ModsColumn({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = ref.watch(selectedModTypeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(
            top: 8,
            right: 4,
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ModsSelector(),
              Search(searchQueryProvider: modsSearchQueryProvider),
              SortButton(),
              FilterButton(),
              BulkActionsMenu(),
              CustomTooltip(
                message:
                    """• Left-click a ${type.label} to see assets and actions
• Right-click a ${type.label} to see additional actions
• Left-click while holding ${Platform.isMacOS ? 'command' : 'control button'} to select multiple ${type.label}s
• Hovering over the backup icon on ${type.label}s shows times and file count mismatches
• Bulk actions are affected by search and filters""",
                messageTextStyle: TextStyle(fontSize: 16, height: 2),
                child: Icon(
                  Icons.info_outline,
                  size: 32,
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
        //  LogPanel(),
        BulkActionsProgressBar(),
      ],
    );
  }
}
