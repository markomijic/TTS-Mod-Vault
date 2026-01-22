import 'dart:ui' show ImageFilter;

import 'package:file_picker/file_picker.dart' show FilePicker;
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart'
    show useMemoized, useState, useTextEditingController;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/src/state/provider.dart'
    show directoriesProvider, downloadProvider;
import 'package:tts_mod_vault/src/utils.dart' show showSnackBar;
import 'package:tts_mod_vault/src/mods/components/download_results_dialog.dart'
    show showDownloadResultsDialog;

class DownloadModsDialog extends HookConsumerWidget {
  const DownloadModsDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(downloadProvider).progress;

    // Depend only on progress and not boolean in order to not have download progress bar in selected mod view
    final isDownloading = useMemoized(() => progress > 0, [progress]);
    final textController = useTextEditingController();
    final targetDirectory =
        useState(p.normalize(ref.read(directoriesProvider).workshopDir));

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
                'Download Workshop Mods',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
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
              Text(
                'Save to: ${targetDirectory.value}',
                style: TextStyle(fontSize: 16),
              ),
              Row(
                spacing: 8,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton.icon(
                    onPressed: isDownloading
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
                    icon: Icon(Icons.folder),
                    label: Text('Select folder'),
                  ),
                  Spacer(),
                  ElevatedButton(
                    onPressed: isDownloading
                        ? null
                        : () {
                            Navigator.of(context).pop();
                          },
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton.icon(
                    onPressed: isDownloading
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
                              Navigator.of(context).pop();
                              if (resultMessage.isNotEmpty) {
                                showDownloadResultsDialog(
                                    context, resultMessage);
                              }
                            }
                          },
                    icon: Icon(Icons.download),
                    label: const Text('Download'),
                  ),
                ],
              ),
              if (isDownloading)
                Column(
                  spacing: 4,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      children: [
                        LinearProgressIndicator(
                          value: progress,
                          minHeight: 24,
                          backgroundColor: Colors.grey.shade300,
                          color: Colors.green,
                          borderRadius: BorderRadius.all(Radius.circular(32)),
                        ),
                        Center(
                          child: Text(
                            '${(progress * 100).toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
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
