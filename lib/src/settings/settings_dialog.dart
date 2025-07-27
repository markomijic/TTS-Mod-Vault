import 'dart:ui' show ImageFilter;

import 'package:file_picker/file_picker.dart' show FilePicker;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show FilteringTextInputFormatter, LengthLimitingTextInputFormatter;
import 'package:flutter_hooks/flutter_hooks.dart'
    show useFocusNode, useState, useTextEditingController;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:path/path.dart' as path;
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show CustomTooltip;
import 'package:tts_mod_vault/src/state/directories/directories.dart'
    show DirectoriesNotifier;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show ModTypeEnum;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        directoriesProvider,
        modsProvider,
        selectedModProvider,
        selectedModTypeProvider,
        settingsProvider;
import 'package:tts_mod_vault/src/state/settings/settings_state.dart'
    show SettingsState;
import 'package:tts_mod_vault/src/utils.dart' show showSnackBar;

class SettingsDialog extends HookConsumerWidget {
  const SettingsDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final directoriesNotifier = ref.watch(directoriesProvider.notifier);
    final settings = ref.watch(settingsProvider);

    // User interface
    final useModsListViewBox = useState(settings.useModsListView);
    final showTitleOnCardsBox = useState(settings.showTitleOnCards);

    // Network
    final numberValue = useState(settings.concurrentDownloads);

    // Features
    final checkForUpdatesOnStartBox = useState(settings.checkForUpdatesOnStart);
    final enableTtsModdersFeatures =
        useState(settings.enableTtsModdersFeatures);
    final showSavedObjects = useState(settings.showSavedObjects);
    final showBackupState = useState(settings.showBackupState);

    // Folders
    final modsDir = useState(ref.read(directoriesProvider).modsDir);
    final savesDir = useState(ref.read(directoriesProvider).savesDir);
    final backupsDir = useState(ref.read(directoriesProvider).backupsDir);
    final textFieldController =
        useTextEditingController(text: numberValue.value.toString());
    final textFieldFocusNode = useFocusNode();

    textFieldFocusNode.addListener(() {
      if (!textFieldFocusNode.hasFocus && textFieldController.text.isEmpty) {
        textFieldController.text = "5";
      }
    });

    Future<void> saveSettingsChanges(BuildContext context) async {
      int concurrentDownloads = int.tryParse(textFieldController.text) ?? 5;
      if (concurrentDownloads < 1 || concurrentDownloads > 99) {
        concurrentDownloads = 5;
      }

      final newState = SettingsState(
        useModsListView: useModsListViewBox.value,
        showTitleOnCards: showTitleOnCardsBox.value,
        checkForUpdatesOnStart: checkForUpdatesOnStartBox.value,
        concurrentDownloads: concurrentDownloads,
        enableTtsModdersFeatures: enableTtsModdersFeatures.value,
        showSavedObjects: showSavedObjects.value,
        showBackupState: showBackupState.value,
      );

      if (ref.read(selectedModTypeProvider) == ModTypeEnum.savedObject &&
          !showSavedObjects.value) {
        ref.read(selectedModTypeProvider.notifier).state = ModTypeEnum.mod;
        ref.read(selectedModProvider.notifier).state = null;
      }

      await ref.read(settingsProvider.notifier).saveSettings(newState);

      if (ref.read(directoriesProvider).modsDir != modsDir.value ||
          ref.read(directoriesProvider).savesDir != savesDir.value ||
          ref.read(directoriesProvider).backupsDir != backupsDir.value) {
        if (await directoriesNotifier.isModsDirectoryValid(modsDir.value) &&
            await directoriesNotifier.isSavesDirectoryValid(savesDir.value)) {
          if (ref.read(directoriesProvider).backupsDir != backupsDir.value) {
            await directoriesNotifier.isBackupsDirectoryValid(backupsDir.value);
          }

          await directoriesNotifier.saveDirectories();
          ref.read(modsProvider.notifier).loadModsData();
        }
      }

      if (context.mounted) Navigator.pop(context);
    }

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
      child: Dialog(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 32,
            children: [
              const Text(
                'Settings',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 32,
                children: [
                  /// Column 1: User Interface & Network
                  Expanded(
                    child: SettingsUINetworkColumn(
                        useModsListViewBox: useModsListViewBox,
                        showTitleOnCardsBox: showTitleOnCardsBox,
                        textFieldController: textFieldController,
                        textFieldFocusNode: textFieldFocusNode,
                        numberValue: numberValue),
                  ),

                  /// Column 2: Features
                  Expanded(
                    child: SettingsFeaturesColumn(
                        checkForUpdatesOnStartBox: checkForUpdatesOnStartBox,
                        showSavedObjects: showSavedObjects,
                        showBackupState: showBackupState,
                        enableTtsModdersFeatures: enableTtsModdersFeatures),
                  ),

                  /// Column 3: Folders
                  Expanded(
                    child: SettingsFoldersColumn(
                        modsDir: modsDir,
                        directoriesNotifier: directoriesNotifier,
                        savesDir: savesDir,
                        backupsDir: backupsDir),
                  ),
                ],
              ),
              Row(
                spacing: 8,
                children: [
                  ElevatedButton(
                    onPressed: () async {
                      await ref
                          .read(settingsProvider.notifier)
                          .resetToDefaultSettings();
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: const Text('Reset to default settings'),
                  ),
                  Spacer(),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final inputValue = int.tryParse(textFieldController.text);
                      if (inputValue == null ||
                          inputValue < 1 ||
                          inputValue > 99) {
                        showSnackBar(
                            context, 'Please enter a number between 1 and 99');
                        if (context.mounted) Navigator.pop(context);
                        return;
                      }
                      await saveSettingsChanges(context);
                    },
                    icon: Icon(Icons.save),
                    label: const Text('Save'),
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

class SectionHeader extends StatelessWidget {
  final String title;
  const SectionHeader({
    super.key,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500)),
    );
  }
}

class SettingsFoldersColumn extends StatelessWidget {
  const SettingsFoldersColumn({
    super.key,
    required this.modsDir,
    required this.directoriesNotifier,
    required this.savesDir,
    required this.backupsDir,
  });

  final ValueNotifier<String> modsDir;
  final DirectoriesNotifier directoriesNotifier;
  final ValueNotifier<String> savesDir;
  final ValueNotifier<String> backupsDir;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: "Mods Folder"),
        Row(
          children: [
            Expanded(
              child: Container(
                //padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white),
                  borderRadius: BorderRadius.circular(4),
                  color: Colors.white,
                ),
                child: SelectableText(
                  modsDir.value,
                  style: const TextStyle(color: Colors.black),
                ),
              ),
            ),
            const SizedBox(width: 8),
            CustomTooltip(
              message:
                  'All subfolders of the chosen folder are included\nData will be refreshed if saving changes to a folder',
              child: ElevatedButton(
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

                  if (!await directoriesNotifier.isModsDirectoryValid(
                      ttsDir, false)) {
                    if (context.mounted) {
                      showSnackBar(context, 'Invalid Mods folder');
                    }
                  } else {
                    modsDir.value = ttsDir.endsWith('Mods')
                        ? ttsDir
                        : path.join(ttsDir, 'Mods');
                  }
                },
                child: const Text('Select'),
              ),
            ),
          ],
        ),
        SectionHeader(title: "Saves Folder"),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white),
                  borderRadius: BorderRadius.circular(4),
                  color: Colors.white,
                ),
                child: SelectableText(
                  savesDir.value,
                  style: const TextStyle(color: Colors.black),
                ),
              ),
            ),
            const SizedBox(width: 8),
            CustomTooltip(
              message:
                  'All subfolders of the chosen folder are included\nData will be refreshed if saving changes to a folder',
              child: ElevatedButton(
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

                  if (!await directoriesNotifier.isSavesDirectoryValid(
                      ttsDir, false)) {
                    if (context.mounted) {
                      showSnackBar(context, 'Invalid Saves folder');
                    }
                  } else {
                    savesDir.value = ttsDir.endsWith('Saves')
                        ? ttsDir
                        : path.join(ttsDir, 'Saves');
                  }
                },
                child: const Text('Select'),
              ),
            ),
          ],
        ),
        SectionHeader(title: "Backups Folder"),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white),
                  borderRadius: BorderRadius.circular(4),
                  color: Colors.white,
                ),
                child: SelectableText(
                  backupsDir.value,
                  style: const TextStyle(color: Colors.black),
                ),
              ),
            ),
            const SizedBox(width: 8),
            CustomTooltip(
              message:
                  'All subfolders of the chosen folder are included\nData will be refreshed if saving changes to a folder',
              child: ElevatedButton(
                onPressed: () async {
                  String? dir;
                  try {
                    dir = await FilePicker.platform.getDirectoryPath(
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

                  if (dir != null) {
                    backupsDir.value = dir;
                  }
                },
                child: const Text('Select'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class SettingsFeaturesColumn extends StatelessWidget {
  const SettingsFeaturesColumn({
    super.key,
    required this.checkForUpdatesOnStartBox,
    required this.showSavedObjects,
    required this.showBackupState,
    required this.enableTtsModdersFeatures,
  });

  final ValueNotifier<bool> checkForUpdatesOnStartBox;
  final ValueNotifier<bool> showSavedObjects;
  final ValueNotifier<bool> showBackupState;
  final ValueNotifier<bool> enableTtsModdersFeatures;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: "Features"),
        CheckboxListTile(
          title: const Text('Check for updates on start'),
          value: checkForUpdatesOnStartBox.value,
          checkColor: Colors.black,
          activeColor: Colors.white,
          contentPadding: EdgeInsets.all(0),
          onChanged: (value) {
            checkForUpdatesOnStartBox.value =
                value ?? checkForUpdatesOnStartBox.value;
          },
        ),
        CustomTooltip(
          message:
              "Show Saved Objects next to Mods and Saves, manual refresh of data is needed after enabling if TTS Mod Vault was opened while this setting was disabled",
          child: CheckboxListTile(
            title: const Text('Show Saved Objects'),
            value: showSavedObjects.value,
            checkColor: Colors.black,
            activeColor: Colors.white,
            contentPadding: EdgeInsets.all(0),
            onChanged: (value) {
              showSavedObjects.value = value ?? showSavedObjects.value;
            },
          ),
        ),
        CustomTooltip(
          message: "Backups folder is required to show backup state",
          child: CheckboxListTile(
            title: const Text('Show Backup State'),
            value: showBackupState.value,
            checkColor: Colors.black,
            activeColor: Colors.white,
            contentPadding: EdgeInsets.all(0),
            onChanged: (value) {
              showBackupState.value = value ?? showBackupState.value;
            },
          ),
        ),
        CustomTooltip(
          message: "Enables:\nReplace URL in asset lists and viewing images",
          child: CheckboxListTile(
            title: const Text('Enable TTS Modders features'),
            value: enableTtsModdersFeatures.value,
            checkColor: Colors.black,
            activeColor: Colors.white,
            contentPadding: EdgeInsets.all(0),
            onChanged: (value) {
              enableTtsModdersFeatures.value =
                  value ?? enableTtsModdersFeatures.value;
            },
          ),
        ),
      ],
    );
  }
}

class SettingsUINetworkColumn extends StatelessWidget {
  const SettingsUINetworkColumn({
    super.key,
    required this.useModsListViewBox,
    required this.showTitleOnCardsBox,
    required this.textFieldController,
    required this.textFieldFocusNode,
    required this.numberValue,
  });

  final ValueNotifier<bool> useModsListViewBox;
  final ValueNotifier<bool> showTitleOnCardsBox;
  final TextEditingController textFieldController;
  final FocusNode textFieldFocusNode;
  final ValueNotifier<int> numberValue;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: "User Interface"),
        CheckboxListTile(
          title: const Text('Display mods as a list instead of grid'),
          value: useModsListViewBox.value,
          checkColor: Colors.black,
          activeColor: Colors.white,
          contentPadding: EdgeInsets.all(0),
          onChanged: (value) {
            useModsListViewBox.value = value ?? useModsListViewBox.value;
          },
        ),
        CheckboxListTile(
          title: const Text('Display mod names on grid cards'),
          value: showTitleOnCardsBox.value,
          checkColor: Colors.black,
          activeColor: Colors.white,
          contentPadding: EdgeInsets.all(0),
          onChanged: (value) {
            showTitleOnCardsBox.value = value ?? showTitleOnCardsBox.value;
          },
        ),
        SectionHeader(title: "Network"),
        Row(
          children: [
            const Expanded(
              child: Text('Number of concurrent downloads\n(default: 5)'),
            ),
            SizedBox(
              width: 50,
              child: TextField(
                textAlign: TextAlign.center,
                controller: textFieldController,
                cursorColor: Colors.black,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(2),
                ],
                style:
                    TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  fillColor: Colors.white,
                  border: OutlineInputBorder(),
                ),
                focusNode: textFieldFocusNode,
                onChanged: (value) {
                  final num = int.tryParse(value);
                  if (value.startsWith("0")) {
                    textFieldController.text = '1';
                    textFieldController.selection = TextSelection.fromPosition(
                      TextPosition(offset: textFieldController.text.length),
                    );
                    numberValue.value = 1;
                  } else if (num != null && num >= 1 && num <= 99) {
                    numberValue.value = num;
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}
