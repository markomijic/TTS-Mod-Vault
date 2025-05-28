import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show ConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show ModsGridCard;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show Mod;

class ModsGrid extends ConsumerWidget {
  final List<Mod> mods;

  const ModsGrid({super.key, required this.mods});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
