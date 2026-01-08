import 'dart:io' show File;

import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kPrimaryButton, kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HardwareKeyboard;
import 'package:flutter_hooks/flutter_hooks.dart' show useMemoized;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show CustomTooltip;
import 'package:tts_mod_vault/src/state/backup/backup_status_enum.dart'
    show ExistingBackupStatusEnum;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart'
    show AudioAssetVisibility, Mod, ModTypeEnum;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        actionInProgressProvider,
        modsProvider,
        selectedModProvider,
        settingsProvider,
        multiModsProvider;
import 'package:tts_mod_vault/src/utils.dart'
    show showModContextMenu, formatTimestamp;

class ModsListItem extends HookConsumerWidget {
  final Mod mod;

  const ModsListItem({super.key, required this.mod});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showBackupState = ref.watch(settingsProvider).showBackupState;
    final selectedMod = ref.watch(selectedModProvider);
    final multiSelectMods = ref.watch(multiModsProvider);

    final imageExists = useMemoized(() {
      return mod.imageFilePath != null
          ? File(mod.imageFilePath!).existsSync()
          : false;
    }, [mod.imageFilePath]);

    final showAssetCount = useMemoized(() {
      return mod.existingAssetCount != null && mod.assetCount != null;
    }, [mod]);

    final isSelected = useMemoized(() {
      return multiSelectMods.contains(mod);
    }, [selectedMod, multiSelectMods, mod]);

    final filesMessage = useMemoized(() {
      final missingCount = mod.missingAssetCount ?? 0;
      if (missingCount <= 0) return '';
      final fileLabel = missingCount == 1 ? 'file' : 'files';
      return '$missingCount missing $fileLabel';
    }, [mod.existingAssetCount]);

    final backupHasSameAssetCount = useMemoized(() {
      if (mod.backup != null &&
          mod.backup?.totalAssetCount != null &&
          mod.existingAssetCount != null) {
        return mod.backup!.totalAssetCount == mod.existingAssetCount!;
      }
      return true;
    }, [mod.backup, mod.existingAssetCount]);

    return Listener(
        onPointerDown: (event) {
          if (ref.read(actionInProgressProvider)) {
            return;
          }

          final isCtrlPressed = event.kind == PointerDeviceKind.mouse &&
              (event.buttons == kPrimaryButton) &&
              (HardwareKeyboard.instance.isControlPressed ||
                  HardwareKeyboard.instance.isMetaPressed);

          if (event.buttons == kSecondaryButton) {
            // Right-click
            ref.read(modsProvider.notifier).setSelectedMod(mod);
            showModContextMenu(context, ref, event.position, mod);
          } else if (event.buttons == kPrimaryButton) {
            // Left-click
            if (isCtrlPressed) {
              // Ctrl+Click: Toggle multi-selection
              final currentSelected = ref.read(multiModsProvider);
              final newSelected = Set<Mod>.from(currentSelected);

              if (newSelected.contains(mod)) {
                newSelected.remove(mod);
              } else {
                newSelected.add(mod);
              }

              ref.read(multiModsProvider.notifier).state = newSelected;
            } else {
              // Normal left-click: Single selection
              ref.read(modsProvider.notifier).setSelectedMod(mod);
            }
          }
        },
        child: Card(
          margin: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          color: Colors.grey[850],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: BorderSide(
              color: isSelected
                  ? multiSelectMods.length > 1
                      ? Colors.cyan
                      : Colors.white
                  : Colors.transparent,
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
                                ? "${mod.existingAssetCount}/${mod.assetCount}"
                                : " ",
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w500,
                              color: mod.existingAssetCount == mod.assetCount
                                  ? Colors.green
                                  : Colors.white,
                            ),
                          ),
                        ),
                        if (mod.audioVisibility !=
                            AudioAssetVisibility.useGlobalSetting)
                          CustomTooltip(
                            waitDuration: Duration(milliseconds: 300),
                            message: mod.audioVisibility ==
                                    AudioAssetVisibility.alwaysShow
                                ? 'Override: Show audio assets'
                                : 'Override: hide audio assets',
                            child: Icon(
                              mod.audioVisibility ==
                                      AudioAssetVisibility.alwaysShow
                                  ? Icons.volume_up
                                  : Icons.volume_off,
                              size: 28,
                              color: Colors.blue,
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
                                '${backupHasSameAssetCount || mod.backup!.totalAssetCount == null ? '' : '\n\nBackup asset files count: ${mod.backup!.totalAssetCount}\nExisting asset files count: ${mod.existingAssetCount}'}',
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
