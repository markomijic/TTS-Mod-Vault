import 'dart:ui' show ImageFilter;

import 'package:file_picker/file_picker.dart' show FilePicker;
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart'
    show useTextEditingController, useState;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/src/state/provider.dart'
    show directoriesProvider, downloadProvider;
import 'package:tts_mod_vault/src/utils.dart' show showSnackBar;

class DownloadModByIdDialog extends HookConsumerWidget {
  const DownloadModByIdDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final targetDirectory =
        useState(p.normalize(ref.read(directoriesProvider).workshopDir));
    final downloadingMods = ref.watch(downloadProvider).downloadingMods;
    final textController = useTextEditingController();

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
      child: AlertDialog(
        content: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          spacing: 16,
          children: [
            Text(
              'Download Workshop Mods',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            TextField(
              controller: textController,
              cursorColor: Colors.black,
              keyboardType: TextInputType.number,
              style:
                  TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                fillColor: Colors.white,
                border: OutlineInputBorder(),
                hintText: 'Enter mod ID(s) separated by comma',
                hintStyle: TextStyle(color: Colors.black),
              ),
            ),
            Text('Save to: ${targetDirectory.value}'),
            Row(
              spacing: 8,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton(
                  onPressed: downloadingMods
                      ? null
                      : () async {
                          String? dir;
                          final initialDirectory = p.normalize(
                              ref.read(directoriesProvider).workshopDir);

                          try {
                            dir = await FilePicker.platform.getDirectoryPath(
                              lockParentWindow: true,
                              initialDirectory: initialDirectory,
                            );
                          } catch (e) {
                            debugPrint("File picker error $e");
                            if (context.mounted) {
                              showSnackBar(
                                  context, "Failed to open file picker");
                              Navigator.pop(context);
                            }
                            return;
                          }

                          if (dir == null) return;

                          targetDirectory.value = p.normalize(dir);
                        },
                  child: Text('Select folder'),
                ),
                Spacer(),
                ElevatedButton(
                  onPressed: downloadingMods
                      ? null
                      : () {
                          Navigator.of(context).pop();
                        },
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  onPressed: downloadingMods
                      ? null
                      : () async {
                          final input = textController.text;
                          if (input.isEmpty) {
                            return;
                          }

                          // Parse mod IDs from input (comma separated)
                          final modIds = input
                              .split(',')
                              .map((id) => id.trim())
                              .where((id) => id.isNotEmpty)
                              .toList();

                          if (modIds.isEmpty) return;

                          final resultMessage = await ref
                              .read(downloadProvider.notifier)
                              .downloadModsByIds(
                                modIds: modIds,
                                targetDirectory: targetDirectory.value,
                              );

                          if (context.mounted) {
                            if (resultMessage.isNotEmpty) {
                              showSnackBar(context, resultMessage);
                            }
                            Navigator.of(context).pop();
                          }
                        },
                  icon: Icon(Icons.download),
                  label: const Text('Download'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
