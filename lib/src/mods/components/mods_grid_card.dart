import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useMemoized, useState;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show Mod;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        actionInProgressProvider,
        modsProvider,
        selectedModProvider,
        settingsProvider;

class ModsGridCard extends HookConsumerWidget {
  final Mod mod;

  const ModsGridCard({super.key, required this.mod});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showTitleOnCards = ref.watch(settingsProvider).showTitleOnCards;
    final selectedMod = ref.watch(selectedModProvider);

    final isHovered = useState(false);
    final imageExists = useMemoized(() {
      return mod.imageFilePath != null
          ? File(mod.imageFilePath!).existsSync()
          : false;
    }, [mod]);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => isHovered.value = true,
      onExit: (_) => isHovered.value = false,
      child: GestureDetector(
        onTap: () {
          if (ref.read(actionInProgressProvider)) return;

          ref.read(modsProvider.notifier).setSelectedMod(mod);
        },
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              width: 4,
              color: selectedMod == mod
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
                      File(mod.imageFilePath!),
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      color: Colors.blueGrey,
                      alignment: Alignment.center,
                      child: Text(
                        mod.name,
                        textAlign: TextAlign.center,
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
              if (showTitleOnCards)
                Align(
                  alignment: Alignment.bottomLeft,
                  child: Container(
                    color: Colors.black.withAlpha(200),
                    width: double.infinity,
                    padding: EdgeInsets.all(4),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: mod.name),
                          TextSpan(
                            text: mod.totalCount != null && mod.totalCount! > 0
                                ? "\n(${mod.totalExistsCount}/${mod.totalCount})"
                                : "",
                            style: TextStyle(
                              color: mod.totalExistsCount == mod.totalCount
                                  ? Colors.green
                                  : Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else if (mod.totalCount != null && mod.totalCount! > 0)
                Align(
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.all(Radius.circular(6)),
                        color: Colors.black.withAlpha(200),
                      ),
                      padding: EdgeInsets.all(4),
                      child: Text(
                        "${mod.totalExistsCount}/${mod.totalCount}",
                        style: TextStyle(
                          color: mod.totalExistsCount == mod.totalCount
                              ? Colors.green
                              : Colors.white,
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
