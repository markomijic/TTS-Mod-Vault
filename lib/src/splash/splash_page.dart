import 'dart:io' show exit;

import 'package:file_picker/file_picker.dart' show FilePicker;
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useEffect, useState;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:package_info_plus/package_info_plus.dart' show PackageInfo;
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show ErrorMessage;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        directoriesProvider,
        loaderProvider,
        modsProvider,
        settingsProvider,
        storageProvider;
import 'package:tts_mod_vault/src/utils.dart'
    show checkForUpdatesOnGitHub, showDownloadDialog, showSnackBar;

class SplashPage extends HookConsumerWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final directoriesNotifier = ref.watch(directoriesProvider.notifier);
    final loaderNotifier = ref.watch(loaderProvider);
    final modsError = ref.watch(modsProvider).error;

    final showTtsDirNotFound = useState(false);

    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // Initialize storage, TTS Data Directory and Settings
        await ref.read(storageProvider).initializeStorage();
        await ref.read(settingsProvider.notifier).initializeSettings();
        directoriesNotifier.initializeDirectories();

        // Check for updates on start
        if (ref.read(settingsProvider).checkForUpdatesOnStart) {
          final newTagVersion = await checkForUpdatesOnGitHub();

          if (newTagVersion.isNotEmpty) {
            final packageInfo = await PackageInfo.fromPlatform();
            final currentVersion = packageInfo.version;

            if (context.mounted) {
              await showDownloadDialog(context, currentVersion, newTagVersion);
            }
          }
        }

        // Load existing assets lists and mods data if TTS Data Directories exist
        if (await directoriesNotifier
            .isTtsDirectoryValid(ref.read(directoriesProvider).ttsDir)) {
          await loaderNotifier.loadAppData(
            () => Navigator.of(context).pushReplacementNamed('/mods'),
          );
        } else {
          showTtsDirNotFound.value = true;
        }
      });
      return null;
    }, []);

    return SafeArea(
      child: Scaffold(
        body: Center(
          child: modsError != null
              ? ErrorMessage(e: modsError)
              : !showTtsDirNotFound.value
                  ? Text(
                      "Loading",
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      spacing: 10,
                      children: [
                        Text(
                          "Tabletop Simulator data directory has not been found, please locate it manually.\nIt typically contains folders: DLC, Mods, Saves, Screenshots.\nCurrent version uses only the Mods folder.",
                          textAlign: TextAlign.center,
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          spacing: 10,
                          children: [
                            ElevatedButton(
                              onPressed: () async {
                                String? ttsDir;
                                try {
                                  ttsDir = await FilePicker.platform
                                      .getDirectoryPath();
                                } catch (e) {
                                  debugPrint("File picker error $e");
                                  if (context.mounted) {
                                    showSnackBar(
                                        context, "Failed to open file picker");
                                    Navigator.pop(context);
                                  }
                                  return;
                                }

                                if (ttsDir == null) return;
                                showTtsDirNotFound.value = false;

                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) async {
                                  if (!await directoriesNotifier
                                      .isTtsDirectoryValid(ttsDir!)) {
                                    showTtsDirNotFound.value = true;

                                    if (context.mounted) {
                                      showSnackBar(
                                        context,
                                        'Invalid Tabletop Simulator data directory',
                                      );
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
