import 'dart:io' show File;

import 'package:flutter/gestures.dart' show kPrimaryButton, kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useMemoized, useState;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:path/path.dart' as p;

import 'package:tts_mod_vault/src/mods/components/components.dart'
    show CustomTooltip;
import 'package:tts_mod_vault/src/state/backup/models/existing_backup_model.dart'
    show ExistingBackup;
import 'package:tts_mod_vault/src/utils.dart'
    show formatTimestamp, showBackupContextMenu;

class BackupsListItem extends HookConsumerWidget {
  final ExistingBackup backup;

  const BackupsListItem({super.key, required this.backup});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matchingModImagePath = useMemoized(() {
      if (backup.matchingModFilepath == null) return null;

      final jsonPath = backup.matchingModFilepath!;
      if (!jsonPath.toLowerCase().endsWith('.json')) return null;

      return '${jsonPath.substring(0, jsonPath.length - 5)}.png';
    }, [backup.matchingModFilepath]);

    final imageExists = useMemoized(() {
      return matchingModImagePath != null
          ? File(matchingModImagePath).existsSync()
          : false;
    }, [matchingModImagePath]);

    final hasMatchingMod = useMemoized(() {
      return backup.matchingModFilepath != null;
    }, [backup.matchingModFilepath]);

    final backupFilename = useMemoized(() {
      return p.basenameWithoutExtension(backup.filename);
    }, [backup]);

    final isHovered = useState(false);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => isHovered.value = true,
      onExit: (_) => isHovered.value = false,
      child: Listener(
        onPointerDown: (event) {
          if (event.buttons == kSecondaryButton ||
              event.buttons == kPrimaryButton) {
            showBackupContextMenu(
              context,
              ref,
              event.position,
              backup,
              hasMatchingMod,
            );
          }
        },
        child: Card(
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          color: Colors.grey[850],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: BorderSide(
              color: isHovered.value ? Colors.white : Colors.transparent,
              width: 2,
            ),
          ),
          child: Row(
            children: [
              // Thumbnail
              if (imageExists)
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.file(
                    File(matchingModImagePath!),
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                  ),
                )
              else
                Container(
                  width: 64,
                  height: 64,
                  color: Colors.grey,
                  child: const Icon(Icons.folder_zip_outlined, size: 40),
                ),

              const SizedBox(width: 8),

              // Main info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      backupFilename,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    CustomTooltip(
                      message:
                          "${hasMatchingMod ? "Imported" : "Not imported"}\n${backup.fileSizeMB}\n${backup.totalAssetCount} asset files\n${formatTimestamp(backup.lastModifiedTimestamp.toString())}",
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            backup.totalAssetCount.toString(),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          SizedBox(width: 2),
                          Icon(
                            Icons.extension,
                            size: 22,
                            color: hasMatchingMod ? Colors.green : Colors.red,
                          ),
                          SizedBox(width: 8),
                          Text(
                            backup.fileSizeMB,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
