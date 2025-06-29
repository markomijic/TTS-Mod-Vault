import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useMemoized;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show ModsListItem;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart'
    show Mod, ModTypeEnum;
import 'package:tts_mod_vault/src/state/mods/mods_state.dart' show ModsState;
import 'package:tts_mod_vault/src/state/provider.dart'
    show searchQueryProvider, selectedModTypeProvider;

class ModsList extends HookConsumerWidget {
  final ModsState state;

  const ModsList({super.key, required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

    return ListView.builder(
      itemCount: filteredMods.length,
      itemBuilder: (context, index) {
        final mod = filteredMods[index];

        return ModsListItem(
          mod: mod,
          index: index,
          filteredModsLength: filteredMods.length,
        );
      },
    );
  }
}
