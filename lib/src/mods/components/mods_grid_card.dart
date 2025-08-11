import 'dart:io' show File;
import 'dart:math' show Random;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart'
    show useMemoized, useState, useEffect;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show CustomTooltip;
import 'package:tts_mod_vault/src/state/backup/backup_status_enum.dart'
    show ExistingBackupStatusEnum;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart'
    show Mod, ModTypeEnum;

import 'package:tts_mod_vault/src/state/provider.dart'
    show
        actionInProgressProvider,
        modsProvider,
        selectedModProvider,
        settingsProvider;
import 'package:tts_mod_vault/src/utils.dart'
    show showModContextMenu, formatTimestamp;

class ModsGridCard extends HookConsumerWidget {
  final Mod mod;

  const ModsGridCard({super.key, required this.mod});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showTitleOnCards = ref.watch(settingsProvider).showTitleOnCards;
    final showBackupState = ref.watch(settingsProvider).showBackupState;
    final selectedMod = ref.watch(selectedModProvider);

    final isHovered = useState(false);

    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (mod.assetLists == null) {
          try {
            await Future.delayed(
                Duration(milliseconds: 500 + Random().nextInt(501)));

            if (context.mounted) {
              final urls =
                  await ref.read(modsProvider.notifier).getUrlsByMod(mod);
              final completeMod =
                  ref.read(modsProvider.notifier).getCompleteMod(mod, urls);

              ref.read(modsProvider.notifier).updateMod(completeMod);
            }
          } catch (e) {
            debugPrint('Error loading ${mod.modType} ${mod.saveName}: $e');
          }
        }
      });

      return null;
    }, [mod.jsonFilePath]);

    final imageExists = useMemoized(() {
      return mod.imageFilePath != null
          ? File(mod.imageFilePath!).existsSync()
          : false;
    }, [mod.imageFilePath]);

    final showAssetCount = useMemoized(() {
      return mod.totalExistsCount != null && mod.totalCount != null;
    }, [mod]);

    final isSelected = useMemoized(() {
      return selectedMod?.jsonFilePath == mod.jsonFilePath;
    }, [selectedMod, mod]);

    final filesMessage = useMemoized(() {
      if (mod.totalCount == null || mod.totalExistsCount == null) {
        return "";
      }
      final missingCount = mod.totalCount! - mod.totalExistsCount!;
      if (missingCount <= 0) return '';
      final fileLabel = missingCount == 1 ? 'file' : 'files';
      return '$missingCount missing $fileLabel';
    }, [mod.totalExistsCount]);

    final backupHasSameAssetCount = useMemoized(() {
      if (mod.backup != null &&
          mod.backup?.totalAssetCount != null &&
          mod.totalExistsCount != null) {
        return mod.backup!.totalAssetCount == mod.totalExistsCount!;
      }
      return true;
    }, [mod.backup, mod.totalExistsCount]);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => isHovered.value = true,
      onExit: (_) => isHovered.value = false,
      child: GestureDetector(
        onTap: () {
          if (ref.read(actionInProgressProvider) || mod.assetLists == null) {
            return;
          }

          ref.read(modsProvider.notifier).setSelectedMod(mod);
        },
        onSecondaryTapDown: (details) {
          if (ref.read(actionInProgressProvider) || mod.assetLists == null) {
            return;
          }

          ref.read(modsProvider.notifier).setSelectedMod(mod);
          showModContextMenu(context, ref, details.globalPosition, mod);
        },
        child: AnimatedContainer(
          duration: Duration(milliseconds: 150),
          decoration: BoxDecoration(
            border: Border.all(
              width: 4,
              color: isSelected
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
                      color: Colors.grey[850],
                      alignment: Alignment.center,
                      child: Text(
                        mod.saveName,
                        maxLines: 5,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
              if (showTitleOnCards || mod.modType != ModTypeEnum.mod)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
                      child: Container(
                        color: Colors.black.withAlpha(140),
                        width: double.infinity,
                        padding: EdgeInsets.all(4),
                        child: Text(
                          mod.modType != ModTypeEnum.save
                              ? mod.saveName
                              : '${mod.jsonFileName}\n${mod.saveName}',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
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
                            mainAxisSize: MainAxisSize.min,
                            spacing: 4,
                            children: [
                              CustomTooltip(
                                waitDuration: Duration(milliseconds: 300),
                                message: filesMessage,
                                child: Text(
                                  "${mod.totalExistsCount}/${mod.totalCount}",
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    color:
                                        mod.totalExistsCount == mod.totalCount
                                            ? Colors.green
                                            : Colors.white,
                                  ),
                                ),
                              ),
                              if (mod.backup != null && showBackupState)
                                CustomTooltip(
                                  waitDuration: Duration(milliseconds: 300),
                                  message:
                                      'Update: ${formatTimestamp(mod.dateTimeStamp) ?? 'N/A'}\n'
                                      'Backup: ${formatTimestamp(mod.backup!.lastModifiedTimestamp.toString())}'
                                      '${backupHasSameAssetCount || mod.backup!.totalAssetCount == null ? '' : '\n\nBackup asset files count: ${mod.backup!.totalAssetCount}\nExisting asset files count: ${mod.totalExistsCount}'}',
                                  child: Icon(
                                    Icons.folder_zip_outlined,
                                    size: 20,
                                    color: mod.backupStatus ==
                                            ExistingBackupStatusEnum.upToDate
                                        ? backupHasSameAssetCount
                                            ? Colors.green
                                            : Colors.yellow
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
