import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/src/state/mods/mod_model.dart';
import 'package:tts_mod_vault/src/state/provider.dart';

class ModsGridCard extends HookConsumerWidget {
  final Mod mod;

  const ModsGridCard({super.key, required this.mod});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actionInProgress = ref.watch(actionInProgressProvider);
    final selectedMod = ref.watch(modsProvider).selectedMod;

    final imageExists = useMemoized(() {
      return mod.imageFilePath != null
          ? File(mod.imageFilePath!).existsSync()
          : false;
    }, [mod]);
    final isHovered = useState(false);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => isHovered.value = true,
      onExit: (_) => isHovered.value = false,
      child: GestureDetector(
        onTap: () {
          if (actionInProgress) return;

          ref.read(modsProvider.notifier).selectItem(mod);
          ref.read(selectedAssetProvider.notifier).resetState();
        },
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: selectedMod != null && mod.fileName == selectedMod.fileName
                  ? Colors.white
                  : isHovered.value
                      ? Colors.white70
                      : Colors.transparent,
              width: 4,
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
              if (mod.totalCount != null && mod.totalCount! > 0)
                Align(
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.white,
                          width: 1,
                        ),
                        borderRadius: BorderRadius.all(Radius.circular(6)),
                        color: Colors.black.withAlpha(200),
                      ),
                      padding: EdgeInsets.all(6),
                      child: Text(
                        '${mod.totalExistsCount}/${mod.totalCount}',
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
