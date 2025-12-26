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
      return backup.matchingModImagePath;
    }, [backup]);

    final imageExists = useMemoized(() {
      return matchingModImagePath != null
          ? File(matchingModImagePath).existsSync()
          : false;
    }, [matchingModImagePath]);

    final hasMatchingMod = useMemoized(() {
      return matchingModImagePath != null;
    }, [matchingModImagePath]);

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
                // Background image or color
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
                    width: double.infinity,
                    height: double.infinity,
                    child: Icon(
                      Icons.folder_zip_outlined,
                      size: 60,
                    ),
                  ),

                // Corner icon
                Align(
                  alignment: AlignmentGeometry.topRight,
                  child: Padding(
                    padding: EdgeInsets.all(4),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.all(Radius.circular(4)),
                        color: Colors.black.withAlpha(180),
                      ),
                      child: CustomTooltip(
                        message: hasMatchingMod ? "Imported" : "Not imported",
                        waitDuration: Duration(milliseconds: 300),
                        child: Icon(
                          Icons.extension_outlined,
                          size: 32,
                          color: hasMatchingMod ? Colors.green : Colors.red,
                        ),
                      ),
                    ),
                  ),
                ),

                // Bottom text
                Align(
                  alignment: AlignmentGeometry.bottomLeft,
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(180),
                        ),
                        padding: EdgeInsets.all(4),
                        width: double.infinity,
                        child: Column(
                          spacing: 4,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              formattedDate, // + ' ' + formattedDate,
                              style: TextStyle(fontSize: 14),
                            ),
                            Divider(height: 1),
                            Text(
                              p.basenameWithoutExtension(backup.filename),
                              maxLines: 4,
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 16,
                              ),
                            ),
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
