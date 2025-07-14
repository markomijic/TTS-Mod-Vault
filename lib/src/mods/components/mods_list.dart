import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show ConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show ModsListItem;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show Mod;

class ModsList extends ConsumerWidget {
  final List<Mod> mods;

  const ModsList({super.key, required this.mods});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.builder(
      itemCount: mods.length,
      itemBuilder: (context, index) {
        final mod = mods[index];

        return ModsListItem(
          mod: mod,
          index: index,
          filteredModsLength: mods.length,
        );
      },
    );
  }
}
