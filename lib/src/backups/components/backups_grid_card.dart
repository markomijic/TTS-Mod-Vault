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

    final formattedDate = useMemoized(() {
      return formatTimestamp(backup.lastModifiedTimestamp.toString()) ??
          'Last modified: N/A';
    }, [backup]);

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
                  )
                else
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
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: Colors.black.withAlpha(180),
                      ),
                      child: CustomTooltip(
                        message: hasMatchingMod ? "Imported" : "Not imported",
                        waitDuration: const Duration(milliseconds: 300),
                        child: Icon(
                          Icons.extension_outlined,
                          size: 28,
                          color: hasMatchingMod ? Colors.green : Colors.red,
                        ),
                      ),
                    ),
                  ),
                ),

                // Bottom info bar
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
                        child: Column(
                          spacing: 2,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              p.basenameWithoutExtension(backup.filename),
                              maxLines: 5,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(formattedDate),
                            Text(backup.fileSizeMB),
                          ],
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
