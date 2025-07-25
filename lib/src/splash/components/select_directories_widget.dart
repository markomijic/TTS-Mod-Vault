import 'dart:io' show exit;

import 'package:file_picker/file_picker.dart' show FilePicker;
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useState;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show AsyncLoading, HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show MessageProgressIndicator;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        directoriesProvider,
        loaderProvider,
        loadingMessageProvider,
        modsProvider;
import 'package:tts_mod_vault/src/utils.dart' show showSnackBar;

class SelectDirectoriesWidget extends HookConsumerWidget {
  final bool initialModsDirExists;
  final bool initialSavesDirExists;

  const SelectDirectoriesWidget({
    super.key,
    required this.initialModsDirExists,
    required this.initialSavesDirExists,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final directoriesNotifier = ref.watch(directoriesProvider.notifier);
    final loadingMessage = ref.watch(loadingMessageProvider);

    final directories = ref.watch(directoriesProvider);
    final loaderNotifier = ref.watch(loaderProvider);
    final modsState = ref.watch(modsProvider);

    final separateSavesDir =
        useState(initialModsDirExists != initialSavesDirExists);

    final modsDirExists = useState(initialModsDirExists);
    final savesDirExists = useState(initialSavesDirExists);

    Future<void> loadData() async {
      await loaderNotifier.loadApp(
        () => Navigator.of(context).pushReplacementNamed('/mods'),
      );
    }

    if (modsState is AsyncLoading) {
      return MessageProgressIndicator(message: loadingMessage);
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: 16,
      children: [
        Text(
          "Mods and/or Saves folders have not been found, please locate them manually.\nTabletop Simulator data folder usually contains folders: DLC, Mods, Saves, Screenshots.\nOnly Mods and Saves folders are required.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Checkbox(
              value: separateSavesDir.value,
              checkColor: Colors.black,
              activeColor: Colors.white,
              onChanged: (value) {
                separateSavesDir.value = value ?? false;
              },
            ),
            Text(
              'I have separate Mods and Saves folders',
              style: TextStyle(fontSize: 18),
            ),
          ],
        ),
        if (modsDirExists.value && separateSavesDir.value)
          Text(
            'Mods folder path: ${directories.modsDir}',
            style: TextStyle(fontSize: 18),
          ),
        if (savesDirExists.value && separateSavesDir.value)
          Text(
            'Saves folder path: ${directories.savesDir}',
            style: TextStyle(fontSize: 18),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 8,
          children: [
            if (!separateSavesDir.value)
              ElevatedButton(
                child: Text(
                  'Select TTS data folder',
                  style: TextStyle(fontSize: 16),
                ),
                onPressed: () async {
                  String? ttsDir;
                  try {
                    ttsDir = await FilePicker.platform.getDirectoryPath(
                      lockParentWindow: true,
                    );
                  } catch (e) {
                    debugPrint("File picker error $e");
                    if (context.mounted) {
                      showSnackBar(context, "Failed to open file picker");
                      Navigator.pop(context);
                    }
                    return;
                  }

                  if (ttsDir == null) return;

                  if (!await directoriesNotifier.isModsDirectoryValid(ttsDir) ||
                      !await directoriesNotifier
                          .isSavesDirectoryValid(ttsDir)) {
                    if (context.mounted) {
                      showSnackBar(
                        context,
                        separateSavesDir.value
                            ? 'Invalid Mods folder'
                            : 'Invalid Tabletop Simulator data folder',
                      );
                    }
                  } else {
                    modsDirExists.value = true;
                    savesDirExists.value = true;
                  }
                },
              ),
            if (separateSavesDir.value) ...[
              ElevatedButton(
                child: Text(
                  'Select Mods folder',
                  style: TextStyle(fontSize: 16),
                ),
                onPressed: () async {
                  String? ttsDir;
                  try {
                    ttsDir = await FilePicker.platform.getDirectoryPath(
                      lockParentWindow: true,
                    );
                  } catch (e) {
                    debugPrint("File picker error $e");
                    if (context.mounted) {
                      showSnackBar(context, "Failed to open file picker");
                      Navigator.pop(context);
                    }
                    return;
                  }

                  if (ttsDir == null) return;

                  if (!await directoriesNotifier.isModsDirectoryValid(ttsDir)) {
                    if (context.mounted) {
                      showSnackBar(context, 'Invalid Mods folder');
                    }
                  } else {
                    modsDirExists.value = true;
                  }
                },
              ),
              ElevatedButton(
                child: Text(
                  'Select Saves folder',
                  style: TextStyle(fontSize: 16),
                ),
                onPressed: () async {
                  String? ttsDir;
                  try {
                    ttsDir = await FilePicker.platform.getDirectoryPath(
                      lockParentWindow: true,
                    );
                  } catch (e) {
                    debugPrint("File picker error $e");
                    if (context.mounted) {
                      showSnackBar(context, "Failed to open file picker");
                      Navigator.pop(context);
                    }
                    return;
                  }

                  if (ttsDir == null) return;

                  if (!await directoriesNotifier
                      .isSavesDirectoryValid(ttsDir)) {
                    if (context.mounted) {
                      showSnackBar(context, 'Invalid Saves folder');
                    }
                  } else {
                    savesDirExists.value = true;
                  }
                },
              ),
            ],
            ElevatedButton(
              onPressed: () => exit(0),
              child: Text(
                'Exit',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
        ElevatedButton(
          onPressed: !modsDirExists.value || !savesDirExists.value
              ? null
              : () async => await loadData(),
          child: Text(
            'Load',
            style: TextStyle(fontSize: 16),
          ),
        ),
      ],
    );
  }
}
