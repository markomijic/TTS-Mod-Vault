import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show ConsumerWidget, HookConsumer, WidgetRef;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show Mod;
import 'package:tts_mod_vault/src/state/provider.dart'
    show actionInProgressProvider, modsProvider, selectedModProvider;
import 'package:tts_mod_vault/src/utils.dart' show showModContextMenu;

class ModsList extends ConsumerWidget {
  final List<Mod> mods;

  const ModsList({super.key, required this.mods});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.builder(
      itemCount: mods.length,
      itemBuilder: (context, index) {
        final mod = mods[index];

        return HookConsumer(
          builder: (context, ref, child) {
            final selectedMod = ref.watch(selectedModProvider);

            return GestureDetector(
              onSecondaryTapDown: (details) {
                showModContextMenu(context, ref, details.globalPosition, mod);
              },
              child: ListTile(
                selected: selectedMod == mod,
                title: Text(mod.saveName),
                subtitle: mod.totalCount != null && mod.totalCount! > 0
                    ? Text('${mod.totalExistsCount}/${mod.totalCount}')
                    : null,
                selectedTileColor: Colors.white,
                selectedColor: Colors.black,
                splashColor: Colors.transparent,
                titleTextStyle: TextStyle(fontSize: 18),
                subtitleTextStyle: TextStyle(
                  fontSize: 16,
                  color: selectedMod == mod
                      ? Colors.black
                      : mod.totalExistsCount == mod.totalCount
                          ? Colors.green
                          : Colors.white,
                ),
                shape: Border.all(color: Colors.white, width: 2),
                onTap: () {
                  if (ref.read(actionInProgressProvider)) return;

                  ref.read(modsProvider.notifier).setSelectedMod(mod);
                },
              ),
            );
          },
        );
      },
    );
  }
}
