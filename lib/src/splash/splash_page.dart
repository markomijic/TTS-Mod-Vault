import 'dart:io' show Directory;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useEffect, useState;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:package_info_plus/package_info_plus.dart' show PackageInfo;
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show ErrorMessage, MessageProgressIndicator;
import 'package:tts_mod_vault/src/splash/components/select_directories_widget.dart'
    show SelectDirectoriesWidget;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        directoriesProvider,
        loaderProvider,
        loadingMessageProvider,
        modsProvider,
        settingsProvider,
        storageProvider;
import 'package:tts_mod_vault/src/utils.dart'
    show checkForUpdatesOnGitHub, showDownloadDialog;
import 'package:window_manager/window_manager.dart' show windowManager;

class SplashPage extends HookConsumerWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final directoriesNotifier = ref.watch(directoriesProvider.notifier);
    final loadingMessage = ref.watch(loadingMessageProvider);
    final loaderNotifier = ref.watch(loaderProvider);
    final modsError = ref.watch(modsProvider).error;

    final initialModsDirExists = useState(false);
    final initialSavesDirExists = useState(false);
    final showSelectDirectories = useState(false);

    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // Small delay as a workaround for Windows Release issue
        await Future.delayed(Duration(milliseconds: 100), () async {
          if (await windowManager.isMaximizable() &&
              !await windowManager.isMaximized()) {
            await windowManager.maximize();
          }
        });

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

        final modsDir = ref.read(directoriesProvider).modsDir;
        final savesDir = ref.read(directoriesProvider).savesDir;

        final modsDirExists = await Directory(modsDir).exists();
        final savesDirExists = await Directory(savesDir).exists();

        if (modsDirExists && savesDirExists) {
          await loaderNotifier.loadApp(
            () => Navigator.of(context).pushReplacementNamed('/vault'),
          );
        } else {
          initialModsDirExists.value = modsDirExists;
          initialSavesDirExists.value = savesDirExists;
          showSelectDirectories.value = true;
        }
      });
      return null;
    }, []);

    return SafeArea(
      child: Scaffold(
        body: Center(
          child: modsError != null
              ? ErrorMessage(e: modsError)
              : !showSelectDirectories.value
                  ? MessageProgressIndicator(message: loadingMessage)
                  : SelectDirectoriesWidget(
                      initialModsDirExists: initialModsDirExists.value,
                      initialSavesDirExists: initialSavesDirExists.value,
                    ),
        ),
      ),
    );
  }
}
