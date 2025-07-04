import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useMemoized;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show AsyncValue, AsyncValueX, HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart'
    show Mod, ModTypeEnum;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        actionInProgressProvider,
        cardModProvider,
        modsProvider,
        selectedModProvider;
import 'package:tts_mod_vault/src/utils.dart' show showModContextMenu;

class ModsListItem extends HookConsumerWidget {
  final Mod mod;
  final int index;
  final int filteredModsLength;

  const ModsListItem({
    super.key,
    required this.mod,
    required this.index,
    required this.filteredModsLength,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedMod = ref.watch(selectedModProvider);

    final loadedModAsync = mod.assetLists != null
        ? AsyncValue.data(mod)
        : ref.watch(cardModProvider(mod.jsonFileName));

    final displayMod = loadedModAsync.when(
      data: (loadedMod) => loadedMod,
      loading: () => mod,
      error: (_, __) => mod,
    );

    final showAssetCount = useMemoized(() {
      return displayMod.totalExistsCount != null &&
          displayMod.totalCount != null &&
          displayMod.totalCount! > 0;
    }, [displayMod]);

    return GestureDetector(
      onSecondaryTapDown: (details) {
        showModContextMenu(context, ref, details.globalPosition, displayMod);
      },
      child: ListTile(
        selected: selectedMod == displayMod,
        title: Text(displayMod.modType != ModTypeEnum.save
            ? displayMod.saveName
            : "${displayMod.jsonFileName}\n${displayMod.saveName}"),
        subtitle: showAssetCount
            ? Text('${displayMod.totalExistsCount}/${displayMod.totalCount}')
            : null,
        selectedTileColor: Colors.white,
        selectedColor: Colors.black,
        splashColor: Colors.transparent,
        titleTextStyle: TextStyle(fontSize: 18),
        subtitleTextStyle: TextStyle(
          fontSize: 16,
          color: selectedMod == displayMod
              ? Colors.black
              : displayMod.totalExistsCount == displayMod.totalCount
                  ? Colors.green
                  : Colors.white,
        ),
        shape: Border(
          top: BorderSide(color: Colors.white, width: 2),
          left: BorderSide(color: Colors.white, width: 2),
          right: BorderSide(color: Colors.white, width: 2),
          bottom: index == filteredModsLength - 1
              ? BorderSide(color: Colors.white, width: 2)
              : BorderSide.none,
        ),
        onTap: () {
          if (ref.read(actionInProgressProvider)) return;

          ref.read(modsProvider.notifier).setSelectedMod(displayMod);
        },
      ),
    );
  }
}
