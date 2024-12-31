import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/src/mods/components/mods_grid_card.dart';
import 'package:tts_mod_vault/src/state/provider.dart';

class ModsGrid extends ConsumerWidget {
  const ModsGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mods = ref.watch(modsProvider).mods;

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount =
            constraints.maxWidth > 500 ? constraints.maxWidth ~/ 220 : 1;

        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            mainAxisSpacing: 20,
            crossAxisSpacing: 20,
            crossAxisCount: crossAxisCount,
          ),
          itemCount: mods.length,
          itemBuilder: (context, index) {
            return ModsGridCard(mod: mods[index]);
          },
        );
      },
    );
  }
}
