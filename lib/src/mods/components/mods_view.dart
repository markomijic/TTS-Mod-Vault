import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useMemoized;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show ModsList, ModsGrid;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart'
    show Mod, ModTypeEnum;
import 'package:tts_mod_vault/src/state/mods/mods_state.dart' show ModsState;
import 'package:tts_mod_vault/src/state/provider.dart'
    show searchQueryProvider, selectedModTypeProvider, settingsProvider;

class ModsView extends HookConsumerWidget {
  final ModsState state;

  const ModsView({super.key, required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final useModsListView = ref.watch(settingsProvider).useModsListView;
    final searchQuery = ref.watch(searchQueryProvider);
    final selectedModType = ref.watch(selectedModTypeProvider);

    final filteredMods = useMemoized(() {
      List<Mod> mods = switch (selectedModType) {
        ModTypeEnum.mod => state.mods,
        ModTypeEnum.save => state.saves,
        ModTypeEnum.savedObject => state.savedObjects,
      };

      return mods
          .where((element) => element.saveName
              .toLowerCase()
              .contains(searchQuery.toLowerCase()))
          .toList();
    }, [state, searchQuery, selectedModType]);

    return useModsListView
        ? ModsList(mods: filteredMods)
        : ModsGrid(mods: filteredMods);
  }
}
