import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show ConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show ModsList, ModsGrid;
import 'package:tts_mod_vault/src/state/provider.dart'
    show filteredModsProvider, settingsProvider;

class ModsView extends ConsumerWidget {
  const ModsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final useModsListView = ref.watch(settingsProvider).useModsListView;
    final mods = ref.watch(filteredModsProvider);

    return useModsListView ? ModsList(mods: mods) : ModsGrid(mods: mods);
  }
}
