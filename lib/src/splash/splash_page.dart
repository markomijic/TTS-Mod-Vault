import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/src/state/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:tts_mod_vault/src/utils.dart';
import 'package:path/path.dart' as path;

class SplashPage extends HookConsumerWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final directoriesNotifier = ref.watch(directoriesProvider.notifier);
    final modsNotifier = ref.watch(modsProvider.notifier);

    final ttsDirNotFound = useState(false);

    Future<void> load() async {
      ttsDirNotFound.value = false;
      await modsNotifier.loadModsData().then(
            (value) => context.mounted
                ? Navigator.of(context).pushReplacementNamed('/mods')
                : null,
          );
    }

    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (await directoriesNotifier.checkIfTtsDirectoryExists()) {
          await load();
        } else {
          ttsDirNotFound.value = true;
        }
      });

      return null;
    }, []);

    return SafeArea(
      child: Scaffold(
        body: Center(
          child: ttsDirNotFound.value
              ? Column(
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
                            String? ttsDir =
                                await FilePicker.platform.getDirectoryPath();

                            if (ttsDir != null) {
                              if (await Directory(path.join(ttsDir, 'Mods'))
                                  .exists()) {
                                directoriesNotifier.updateTtsDirectory(ttsDir);
                                await load();
                              } else {
                                if (!context.mounted) {
                                  return;
                                }
                              }
                            } else {
                              if (!context.mounted) {
                                return;
                              }

                              showSnackBar(context, 'Invalid directory');
                            }
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
                )
              : CircularProgressIndicator(
                  color: Colors.white,
                ),
        ),
      ),
    );
  }
}
