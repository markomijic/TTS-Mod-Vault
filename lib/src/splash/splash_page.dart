import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/src/state/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:tts_mod_vault/src/utils.dart';

class SplashPage extends HookConsumerWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final directoriesNotifier = ref.watch(directoriesProvider.notifier);
    final existingAssetListsNotifier =
        ref.watch(existingAssetListsProvider.notifier);
    final localStorageNotifier = ref.watch(storageProvider);
    final modsNotifier = ref.watch(modsProvider.notifier);

    final ttsDirNotFound = useState(false);

    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (await directoriesNotifier.checkIfTtsDirectoryExists()) {
          await localStorageNotifier.init();
          await existingAssetListsNotifier.loadAssetTypeLists();
          await modsNotifier.loadModsData(
            onDataLoaded: () =>
                Navigator.of(context).pushReplacementNamed('/mods'),
          );
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
                              directoriesNotifier.updateTtsDirectory(ttsDir);
                            } else {
                              return;
                            }

                            WidgetsBinding.instance
                                .addPostFrameCallback((_) async {
                              if (!await directoriesNotifier
                                  .checkIfTtsDirectoryFoldersExist(ttsDir)) {
                                if (!context.mounted) {
                                  return;
                                }

                                showSnackBar(context, 'Invalid directory');
                                return;
                              }

                              await localStorageNotifier.init();
                              // TODO fix bug and uncomment
                              //await stringsNotifier.loadStrings();
                              await modsNotifier.loadModsData(
                                onDataLoaded: () => Navigator.of(context)
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
                )
              : Text(
                  "Loading...",
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                ),
        ),
      ),
    );
  }
}
