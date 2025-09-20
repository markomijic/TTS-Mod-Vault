import 'dart:io' show File;
import 'dart:math' show Random;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useMemoized, useEffect;
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

class ModsListItem extends HookConsumerWidget {
  final Mod mod;

  const ModsListItem({super.key, required this.mod});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showBackupState = ref.watch(settingsProvider).showBackupState;
    final selectedMod = ref.watch(selectedModProvider);

    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (mod.assetLists == null) {
          try {
            await Future.delayed(
                Duration(milliseconds: 500 + Random().nextInt(501)));

            if (!context.mounted) return;
            final urls =
                await ref.read(modsProvider.notifier).getUrlsByMod(mod);
            if (!context.mounted) return;
            final completeMod =
                await ref.read(modsProvider.notifier).getCompleteMod(mod, urls);
            if (!context.mounted) return;
            ref.read(modsProvider.notifier).updateMod(completeMod);
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

    return GestureDetector(
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
                    File(mod.imageFilePath!),
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
                      mod.modType != ModTypeEnum.save
                          ? imageExists
                              ? mod.saveName
                              : '${mod.saveName} - ${mod.jsonFileName}'
                          : "${mod.saveName} - ${mod.jsonFileName}",
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
                          message: filesMessage,
                          child: Text(
                            showAssetCount
                                ? "${mod.totalExistsCount}/${mod.totalCount}"
                                : " ",
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w500,
                              color: mod.totalExistsCount == mod.totalCount
                                  ? Colors.green
                                  : Colors.white,
                            ),
                          ),
                        ),
                        if (mod.backup != null &&
                            showAssetCount &&
                            showBackupState)
                          CustomTooltip(
                            waitDuration: Duration(milliseconds: 300),
                            message:
                                'Update: ${formatTimestamp(mod.dateTimeStamp) ?? 'N/A'}\n'
                                'Backup: ${formatTimestamp(mod.backup!.lastModifiedTimestamp.toString())}'
                                '${backupHasSameAssetCount || mod.backup!.totalAssetCount == null ? '' : '\n\nBackup asset files count: ${mod.backup!.totalAssetCount}\nExisting asset files count: ${mod.totalExistsCount}'}',
                            child: Icon(
                              Icons.folder_zip_outlined,
                              size: 28,
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
                  ],
                ),
              ),
            ],
          ),
        ));
  }
}
