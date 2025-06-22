import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useMemoized;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, HookConsumer, WidgetRef;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart'
    show Mod, ModTypeEnum;
import 'package:tts_mod_vault/src/state/mods/mods_state.dart' show ModsState;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        actionInProgressProvider,
        modsProvider,
        searchQueryProvider,
        selectedModProvider,
        selectedModTypeProvider;
import 'package:tts_mod_vault/src/utils.dart' show showModContextMenu;

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

        return HookConsumer(
          builder: (context, ref, child) {
            final selectedMod = ref.watch(selectedModProvider);

            return GestureDetector(
              onSecondaryTapDown: (details) {
                showModContextMenu(context, ref, details.globalPosition, mod);
              },
              child: ListTile(
                selected: selectedMod == mod,
                title: Text(mod.modType == ModTypeEnum.mod
                    ? mod.saveName
                    : "${mod.jsonFileName}\n${mod.saveName}"),
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
                shape: Border(
                  top: BorderSide(color: Colors.white, width: 2),
                  left: BorderSide(color: Colors.white, width: 2),
                  right: BorderSide(color: Colors.white, width: 2),
                  bottom: index == filteredMods.length - 1
                      ? BorderSide(color: Colors.white, width: 2)
                      : BorderSide.none,
                ),
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
