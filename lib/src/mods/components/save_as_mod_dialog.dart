import 'dart:ui' show ImageFilter;

import 'package:file_picker/file_picker.dart' show FilePicker;
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart'
    show useState, useTextEditingController;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show Mod;
import 'package:tts_mod_vault/src/state/provider.dart'
    show directoriesProvider, modsProvider;
import 'package:tts_mod_vault/src/utils.dart' show showSnackBar;

class SaveAsModDialog extends HookConsumerWidget {
  final Mod save;

  const SaveAsModDialog({super.key, required this.save});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fileNameController = useTextEditingController(
      text: p.basenameWithoutExtension(save.jsonFilePath),
    );
    final targetDirectory =
        useState(p.normalize(ref.read(directoriesProvider).workshopDir));
    final isSaving = useState(false);

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
      child: AlertDialog(
        content: SizedBox(
          width: 700,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            spacing: 16,
            children: [
              Text(
                'Save as Mod',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
              ),
              Text(
                'Copies this save\'s file and image into the selected folder so it '
                'appears as a mod.\nThe original save is kept.',
                style: TextStyle(fontSize: 16),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 4,
                children: [
                  Text('File name', style: TextStyle(fontSize: 16)),
                  TextField(
                    controller: fileNameController,
                    cursorColor: Colors.black,
                    style: TextStyle(
                        color: Colors.black, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      fillColor: Colors.white,
                      filled: true,
                      border: OutlineInputBorder(),
                      suffixIcon: Align(
                        widthFactor: 1.0,
                        heightFactor: 1.0,
                        child: Padding(
                          padding: EdgeInsets.only(left: 4, right: 12),
                          child: Text(
                            '.json',
                            style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                'Save to: ${targetDirectory.value}',
                style: TextStyle(fontSize: 16),
              ),
              Row(
                spacing: 8,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton.icon(
                    onPressed: isSaving.value
                        ? null
                        : () async {
                            String? dir;
                            try {
                              dir = await FilePicker.platform.getDirectoryPath(
                                lockParentWindow: true,
                                initialDirectory: targetDirectory.value,
                              );
                            } catch (e) {
                              debugPrint("File picker error $e");
                              if (context.mounted) {
                                showSnackBar(
                                    context, "Failed to open file picker");
                              }
                              return;
                            }

                            if (dir == null) return;

                            targetDirectory.value = p.normalize(dir);
                          },
                    icon: Icon(Icons.folder),
                    label: Text('Select folder'),
                  ),
                  Spacer(),
                  ElevatedButton(
                    onPressed: isSaving.value
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton.icon(
                    onPressed: isSaving.value
                        ? null
                        : () async {
                            final fileName = fileNameController.text.trim();
                            if (fileName.isEmpty) {
                              showSnackBar(
                                  context, 'Please enter a valid file name');
                              return;
                            }

                            isSaving.value = true;

                            final message =
                                await ref.read(modsProvider.notifier).saveAsMod(
                                      save,
                                      targetDirectory.value,
                                      fileName,
                                    );

                            if (context.mounted) {
                              Navigator.of(context).pop();
                              showSnackBar(context, message);
                            }
                          },
                    icon: Icon(Icons.drive_file_move),
                    label: const Text('Save as Mod'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
