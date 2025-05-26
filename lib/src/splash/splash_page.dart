import 'dart:io' show exit;

import 'package:file_picker/file_picker.dart' show FilePicker;
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useEffect;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/mods/components/error_message.dart'
    show ErrorMessage;
import 'package:tts_mod_vault/src/state/provider.dart'
    show directoriesProvider, loaderProvider, modsProvider, storageProvider;
import 'package:tts_mod_vault/src/utils.dart' show showSnackBar;

class SplashPage extends HookConsumerWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final directoriesNotifier = ref.watch(directoriesProvider.notifier);
    final ttsDirNotFound = ref.watch(loaderProvider).ttsDirNotFound;
    final loaderNotifier = ref.watch(loaderProvider.notifier);
    final modsError = ref.watch(modsProvider).error;

    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // Initialize storage and TTS Directory
        await ref.read(storageProvider).init();
        directoriesNotifier.initTtsDirectory();

        // Load existing assets lists and mods data if TTS Directory exists
        await loaderNotifier.loadAppData(
          () => Navigator.of(context).pushReplacementNamed('/mods'),
        );
      });
      return null;
    }, []);

    return SafeArea(
      child: Scaffold(
        body: Center(
          child: modsError != null
              ? ErrorMessage(e: modsError)
              : !ttsDirNotFound
                  ? Text(
                      "Loading",
                      style:
                          TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      spacing: 10,
                      children: [
                        Text(
                          'Tabletop Simulator directory has not been found, please locate it manually.\nIt should contain folders: DLC, Mods, Saves, Screenshots.',
                          textAlign: TextAlign.center,
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          spacing: 10,
                          children: [
                            ElevatedButton(
                              onPressed: () async {
                                String? ttsDir = await FilePicker.platform
                                    .getDirectoryPath();

                                if (ttsDir == null) return;

                                directoriesNotifier.updateTtsDirectory(ttsDir);

                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) async {
                                  if (!await directoriesNotifier
                                      .checkIfTtsDirectoryFoldersExist(
                                          ttsDir)) {
                                    if (context.mounted) {
                                      showSnackBar(
                                          context, 'Invalid directory');
                                    }
                                    return;
                                  }

                                  await loaderNotifier.loadAppData(
                                    () => Navigator.of(context)
                                        .pushReplacementNamed('/mods'),
                                  );
                                });
                              },
                              child: Text('Select TTS directory'),
                            ),
                            ElevatedButton(
                              onPressed: () => exit(0),
                              child: Text('Exit'),
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
