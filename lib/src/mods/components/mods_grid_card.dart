import 'dart:io' show File;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useMemoized, useState;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show AsyncValue, AsyncValueX, HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show CustomTooltip;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart'
    show Mod, ModTypeEnum;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        actionInProgressProvider,
        cardModProvider,
        modsProvider,
        selectedModProvider,
        settingsProvider;
import 'package:tts_mod_vault/src/utils.dart' show showModContextMenu;

class ModsGridCard extends HookConsumerWidget {
  final Mod mod;

  const ModsGridCard({super.key, required this.mod});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showTitleOnCards = ref.watch(settingsProvider).showTitleOnCards;
    final selectedMod = ref.watch(selectedModProvider);
    final isHovered = useState(false);

    final loadedModAsync = mod.assetLists != null
        ? AsyncValue.data(mod)
        : ref.watch(cardModProvider(mod.jsonFileName));

    final displayMod = loadedModAsync.when(
      data: (loadedMod) => loadedMod,
      loading: () => mod,
      error: (_, __) => mod,
    );

    final imageExists = useMemoized(() {
      return mod.imageFilePath != null
          ? File(mod.imageFilePath!).existsSync()
          : false;
    }, [mod.imageFilePath]);

    final showAssetCount = useMemoized(() {
      return displayMod.totalExistsCount != null &&
          displayMod.totalCount != null &&
          displayMod.totalCount! > 0;
    }, [displayMod]);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => isHovered.value = true,
      onExit: (_) => isHovered.value = false,
      child: GestureDetector(
        onTap: () {
          if (ref.read(actionInProgressProvider) || !loadedModAsync.hasValue) {
            return;
          }

          ref.read(modsProvider.notifier).setSelectedMod(displayMod);
        },
        onSecondaryTapDown: (details) {
          if (ref.read(actionInProgressProvider) || !loadedModAsync.hasValue) {
            return;
          }

          ref.read(modsProvider.notifier).setSelectedMod(displayMod);
          showModContextMenu(context, ref, details.globalPosition, displayMod);
        },
        child: AnimatedContainer(
          duration: Duration(milliseconds: 150),
          decoration: BoxDecoration(
            border: Border.all(
              width: 4,
              color: selectedMod == displayMod
                  ? Colors.white
                  : isHovered.value
                      ? Colors.white70
                      : Colors.transparent,
            ),
          ),
          child: Stack(
            children: [
              imageExists
                  ? Image.file(
                      File(displayMod.imageFilePath!),
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      color: Colors.blueGrey,
                      alignment: Alignment.center,
                      child: Text(
                        displayMod.saveName,
                        textAlign: TextAlign.center,
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
              if (showTitleOnCards || displayMod.modType != ModTypeEnum.mod)
                Align(
                  alignment: Alignment.bottomLeft,
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
                      child: Container(
                        color: Colors.black.withAlpha(160),
                        width: double.infinity,
                        padding: EdgeInsets.all(4),
                        child: Text(displayMod.modType != ModTypeEnum.save
                            ? displayMod.saveName
                            : '${displayMod.jsonFileName}\n${displayMod.saveName}'),
                      ),
                    ),
                  ),
                ),
              if (showAssetCount)
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: ClipRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 2.0, sigmaY: 2.0),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.all(Radius.circular(4)),
                            color: Colors.black.withAlpha(180),
                          ),
                          padding: EdgeInsets.all(2),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            spacing: 4,
                            children: [
                              Text(
                                "${displayMod.totalExistsCount}/${displayMod.totalCount}",
                                style: TextStyle(
                                  color: displayMod.totalExistsCount ==
                                          displayMod.totalCount
                                      ? Colors.green
                                      : Colors.white,
                                ),
                              ),
                              // TODO update
                              if (mod.saveName.length < 30)
                                CustomTooltip(
                                  message: 'Mod date: 123\nBackup date: XYZ',
                                  waitDuration: Duration(milliseconds: 300),
                                  child: Icon(
                                    Icons.folder_zip_outlined,
                                    size: 20,
                                    color: mod.saveName.length > 20
                                        ? Colors.green
                                        : Colors.red,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
