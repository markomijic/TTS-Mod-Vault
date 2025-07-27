import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useMemoized;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show AsyncValue, AsyncValueX, HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show CustomTooltip;
import 'package:tts_mod_vault/src/state/backup/backup_status_enum.dart'
    show ExistingBackupStatusEnum;
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
  final Mod mod;

  const ModsListItem({super.key, required this.mod});

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
          displayMod.totalCount != null;
    }, [displayMod]);

    final isSelected = useMemoized(() {
      return selectedMod?.jsonFilePath == mod.jsonFilePath;
    }, [selectedMod, mod]);

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
          child: Row(
            spacing: 8,
            children: [
              if (imageExists)
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.file(
                    File(displayMod.imageFilePath!),
                    width: 64,
                    height: 64,
                    fit: BoxFit.fitHeight,
                    cacheHeight: 64,
                    cacheWidth: 64,
                  ),
                )
              else
                Container(
                  color: Colors.grey,
                  width: 64,
                  height: 64,
                  child: Icon(Icons.image, size: 64),
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
                        fontSize: 24,
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
                              fontSize: 20,
                              fontWeight: FontWeight.w500,
                              color: displayMod.totalExistsCount ==
                                      displayMod.totalCount
                                  ? Colors.green
                                  : Colors.white,
                            ),
                          ),
                        ),
                        if (displayMod.backup != null &&
                            showAssetCount &&
                            showBackupState)
                          CustomTooltip(
                            waitDuration: Duration(milliseconds: 300),
                            message:
                                'Update: ${formatTimestamp(displayMod.dateTimeStamp!) ?? 'N/A'}\n'
                                'Backup: ${formatTimestamp(displayMod.backup!.lastModifiedTimestamp.toString())}'
                                '${backupHasSameAssetCount ? '\n\nBackup asset files count: ${displayMod.backup!.totalAssetCount}' : '\n\nBackup asset files count: ${displayMod.backup!.totalAssetCount}\nExisting asset files count: ${displayMod.totalExistsCount}'}',
                            child: Icon(
                              Icons.folder_zip_outlined,
                              size: 28,
                              color: displayMod.backupStatus ==
                                      ExistingBackupStatusEnum.upToDate
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
        ));
  }
}
