import 'dart:io' show File;
import 'dart:ui' show ImageFilter;
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

class BackupsGridCard extends HookConsumerWidget {
  final ExistingBackup backup;

  const BackupsGridCard({super.key, required this.backup});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isHovered = useState(false);

    final matchingModImagePath = useMemoized(() {
      if (backup.matchingModFilepath == null) return null;

      // Replace .json extension with .png
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
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              width: 4,
              color: isHovered.value ? Colors.white : Colors.transparent,
            ),
          ),
          child: ClipRect(
            child: Stack(
              children: [
                // Background image or fallback
                if (imageExists)
                  Positioned.fill(
                    child: Image.file(
                      File(matchingModImagePath!),
                      fit: BoxFit.cover,
                    ),
                  ),

                if (!imageExists)
                  Container(
                    color: Colors.grey[850],
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.folder_zip_outlined,
                      size: 60,
                    ),
                  ),

                // Top-right status icon (only overlay left)
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: CustomTooltip(
                      message:
                          "${hasMatchingMod ? "Imported" : "Not imported"}\n${backup.fileSizeMB}\n${backup.totalAssetCount} asset files\n${formatTimestamp(backup.lastModifiedTimestamp.toString())}",
                      waitDuration: const Duration(milliseconds: 300),
                      child: Container(
                        padding: EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          color: Colors.black.withAlpha(180),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              spacing: 2,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  backup.totalAssetCount.toString(),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white,
                                  ),
                                ),
                                Icon(
                                  Icons.extension,
                                  size: 20,
                                  color: hasMatchingMod
                                      ? Colors.green
                                      : Colors.red,
                                ),
                              ],
                            ),
                            Text(
                              backup.fileSizeMB,
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
                      child: Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(140),
                        ),
                        child: Text(
                          backupFilename,
                          maxLines: 5,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
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
      ),
    );
  }
}
