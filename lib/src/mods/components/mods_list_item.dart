import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useMemoized;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show AsyncValue, AsyncValueX, HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show CustomTooltip;
import 'package:tts_mod_vault/src/state/backup/backup_status_enum.dart'
    show BackupStatusEnum;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart'
    show Mod, ModTypeEnum;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        actionInProgressProvider,
        cardModProvider,
        modsProvider,
        selectedModProvider,
        settingsProvider;
import 'package:tts_mod_vault/src/utils.dart'
    show showModContextMenu, formatTimestamp;

class ModsListItem extends HookConsumerWidget {
  final int index;
  final Mod mod;

  const ModsListItem({
    super.key,
    required this.index,
    required this.mod,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showBackupState = ref.watch(settingsProvider).showBackupState;
    final selectedMod = ref.watch(selectedModProvider);

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

    final isSelected = useMemoized(() {
      return selectedMod?.jsonFilePath == displayMod.jsonFilePath;
    }, [selectedMod]);

    final backupHasSameAssetCount = useMemoized(() {
      if (displayMod.backup != null && displayMod.totalExistsCount != null) {
        return displayMod.backup!.totalAssetCount ==
            displayMod.totalExistsCount!;
      }
      return true;
    }, [displayMod.backup, displayMod.totalExistsCount]);

    return GestureDetector(
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
        child: Card(
          margin: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          color: Colors.grey[850],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: BorderSide(
              color: isSelected ? Colors.white : Colors.transparent,
              width: 2,
            ),
          ),
          child: Padding(
            padding: EdgeInsets.all(4),
            child: Row(
              spacing: 8,
              children: [
                SizedBox.shrink(),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: Colors.grey[700],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: imageExists
                        ? Image.file(
                            File(displayMod.imageFilePath!),
                            width: 32,
                            height: 32,
                            fit: BoxFit.fitHeight,
                          )
                        : Icon(
                            Icons.image,
                            color: Colors.white,
                          ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayMod.modType != ModTypeEnum.save
                            ? displayMod.saveName
                            : "${displayMod.saveName} - ${displayMod.jsonFileName}",
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 4,
                        children: [
                          CustomTooltip(
                            waitDuration: Duration(milliseconds: 300),
                            message: showAssetCount
                                ? (displayMod.totalCount! -
                                            displayMod.totalExistsCount! >
                                        0
                                    ? '${displayMod.totalCount! - displayMod.totalExistsCount!} missing files'
                                    : '')
                                : '',
                            child: Text(
                              showAssetCount
                                  ? "${displayMod.totalExistsCount}/${displayMod.totalCount}"
                                  : " ",
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                color: displayMod.totalExistsCount ==
                                        displayMod.totalCount
                                    ? Colors.green
                                    : Colors.white,
                              ),
                            ),
                          ),
                          if (displayMod.backup != null && showBackupState)
                            CustomTooltip(
                              message:
                                  'Update: ${formatTimestamp(displayMod.dateTimeStamp!) ?? 'N/A'}\n'
                                  'Backup: ${formatTimestamp(displayMod.backup!.lastModifiedTimestamp.toString())}'
                                  '${backupHasSameAssetCount ? '\n\nBackup contains ${displayMod.backup!.totalAssetCount} assets' : '\n\nYour backup assets count (${displayMod.backup!.totalAssetCount}) does not match existing assets count (${displayMod.totalExistsCount})'}',
                              child: Icon(
                                Icons.folder_zip_outlined,
                                size: 20,
                                color: displayMod.backupStatus ==
                                        BackupStatusEnum.upToDate
                                    ? backupHasSameAssetCount
                                        ? Colors.green
                                        : Colors.yellow
                                    : Colors.red,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ));
  }
}
