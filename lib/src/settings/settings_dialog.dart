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
import 'package:tts_mod_vault/src/state/sort_and_filter/sort_and_filter_state.dart'
    show SortOptionEnum;
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
    final defaultSortOption = useState(settings.defaultSortOption);

    // Network
    final numberValue = useState(settings.concurrentDownloads);

    // Features
    final checkForUpdatesOnStartBox = useState(settings.checkForUpdatesOnStart);
    final enableTtsModdersFeatures =
        useState(settings.enableTtsModdersFeatures);
    final forceBackupJsonFilename = useState(settings.forceBackupJsonFilename);
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
        defaultSortOption: defaultSortOption.value,
        forceBackupJsonFilename: forceBackupJsonFilename.value,
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
            directoriesNotifier.updateBackupsDirectory(backupsDir.value);
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
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 32,
              children: [
                const Text(
                  'Settings',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  spacing: 32,
                  children: [
                    // Column 1: User Interface & Network
                    Expanded(
                      child: SettingsUINetworkColumn(
                        useModsListViewBox: useModsListViewBox,
                        showTitleOnCardsBox: showTitleOnCardsBox,
                        defaultSortOption: defaultSortOption,
                        textFieldController: textFieldController,
                        textFieldFocusNode: textFieldFocusNode,
                        numberValue: numberValue,
                      ),
                    ),

                    // Column 2: Features
                    Expanded(
                      child: SettingsFeaturesColumn(
                        checkForUpdatesOnStartBox: checkForUpdatesOnStartBox,
                        showSavedObjects: showSavedObjects,
                        showBackupState: showBackupState,
                        enableTtsModdersFeatures: enableTtsModdersFeatures,
                        forceBackupJsonFilename: forceBackupJsonFilename,
                      ),
                    ),

                    // Column 3: Folders
                    Expanded(
                      child: SettingsFoldersColumn(
                        modsDir: modsDir,
                        directoriesNotifier: directoriesNotifier,
                        savesDir: savesDir,
                        backupsDir: backupsDir,
                      ),
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
                        final inputValue =
                            int.tryParse(textFieldController.text);
                        if (inputValue == null ||
                            inputValue < 1 ||
                            inputValue > 99) {
                          showSnackBar(context,
                              'Please enter a number between 1 and 99');
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w500,
        ),
      ),
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
        Row(
          spacing: 4,
          children: [
            SectionHeader(title: "Mods Folder"),
            CustomTooltip(
              message:
                  'All subfolders of the chosen folder are included\nData will be refreshed if saving changes to a folder',
              child: Icon(Icons.info_outline),
            ),
          ],
        ),
        Row(
          spacing: 8,
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
                  modsDir.value,
                  style: const TextStyle(color: Colors.black),
                ),
              ),
            ),
            ElevatedButton(
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
          ],
        ),
        Row(
          spacing: 4,
          children: [
            SectionHeader(title: "Saves Folder"),
            CustomTooltip(
              message:
                  'All subfolders of the chosen folder are included\nData will be refreshed if saving changes to a folder',
              child: Icon(Icons.info_outline),
            ),
          ],
        ),
        Row(
          spacing: 8,
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
            ElevatedButton(
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
          ],
        ),
        Row(
          spacing: 4,
          children: [
            SectionHeader(title: "Backups Folder"),
            CustomTooltip(
              message:
                  'Backup Folder is required for Backup State feature to work after a restart or data refresh\nData will be refreshed if saving changes to a folder',
              child: Icon(Icons.info_outline),
            ),
          ],
        ),
        Row(
          spacing: 8,
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
            ElevatedButton(
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
            ElevatedButton(
              onPressed: () {
                backupsDir.value = '';
              },
              child: const Text('Reset'),
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
    required this.forceBackupJsonFilename,
  });

  final ValueNotifier<bool> checkForUpdatesOnStartBox;
  final ValueNotifier<bool> showSavedObjects;
  final ValueNotifier<bool> showBackupState;
  final ValueNotifier<bool> enableTtsModdersFeatures;
  final ValueNotifier<bool> forceBackupJsonFilename;

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
        CheckboxListTile(
          title: Row(
            spacing: 4,
            children: [
              const Text('Show Saved Objects'),
              CustomTooltip(
                message:
                    "Show Saved Objects next to Mods and Saves, manual refresh of data is needed after enabling if TTS Mod Vault was opened while this setting was disabled",
                child: Icon(Icons.info_outline),
              ),
            ],
          ),
          value: showSavedObjects.value,
          checkColor: Colors.black,
          activeColor: Colors.white,
          contentPadding: EdgeInsets.all(0),
          onChanged: (value) {
            showSavedObjects.value = value ?? showSavedObjects.value;
          },
        ),
        CheckboxListTile(
          title: Row(
            spacing: 4,
            children: [
              const Text(
                'Force JSON name in Backup filename',
                overflow: TextOverflow.ellipsis,
              ),
              CustomTooltip(
                message:
                    """By default, the JSON filename is included in the Mod backup filename only if the JSON filename is a number.
This setting has no effect on backups of Saves and Saved Objects because they already always include the JSON filename.

Mod backup filenames example:
JSON file name: 1234.json + Mod name: ExampleGame => Backup name: ExampleGame (1234).ttsmod
JSON file name: test.json + Mod name: ExampleGame => Backup name: ExampleGame.ttsmod

By enabling this setting, the JSON filename will be included even if it's not a number.
JSON file name: test.json + Mod name: ExampleGame => Backup name: ExampleGame (test).ttsmod

Additionally, when this setting is enabled and the tool tries to find a matching backup file, it will first try to find it
by name containing the JSON filename (ExampleGame (test).ttsmod). If that fails, it will try to find it without
the JSON filename (ExampleGame.ttsmod).""",
                child: Icon(Icons.info_outline),
              ),
            ],
          ),
          value: forceBackupJsonFilename.value,
          checkColor: Colors.black,
          activeColor: Colors.white,
          contentPadding: EdgeInsets.all(0),
          onChanged: (value) {
            forceBackupJsonFilename.value =
                value ?? forceBackupJsonFilename.value;
          },
        ),
        CheckboxListTile(
          title: Row(
            spacing: 4,
            children: [
              const Text('Show Backup State'),
              CustomTooltip(
                message:
                    "Backups Folder is required to show Backup State after a restart or data refresh",
                child: Icon(Icons.info_outline),
              ),
            ],
          ),
          value: showBackupState.value,
          checkColor: Colors.black,
          activeColor: Colors.white,
          contentPadding: EdgeInsets.all(0),
          onChanged: (value) {
            showBackupState.value = value ?? showBackupState.value;
          },
        ),
        CheckboxListTile(
          title: Row(
            spacing: 4,
            children: [
              const Text('Enable URL replacement features'),
              CustomTooltip(
                message: """Enables:
Replace URL - accessible from the context menu of asset URLs and images in the Image Viewer
Update URLs - accessible next to the Download and Backup buttons, and in Bulk Actions""",
                child: Icon(Icons.info_outline),
              ),
            ],
          ),
          value: enableTtsModdersFeatures.value,
          checkColor: Colors.black,
          activeColor: Colors.white,
          contentPadding: EdgeInsets.all(0),
          onChanged: (value) {
            enableTtsModdersFeatures.value =
                value ?? enableTtsModdersFeatures.value;
          },
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
    required this.defaultSortOption,
    required this.textFieldController,
    required this.textFieldFocusNode,
    required this.numberValue,
  });

  final ValueNotifier<bool> useModsListViewBox;
  final ValueNotifier<bool> showTitleOnCardsBox;
  final ValueNotifier<SortOptionEnum> defaultSortOption;
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
        Row(
          children: [
            Expanded(
              child: Text(
                'Default sort',
                style: TextStyle(fontSize: 16),
              ),
            ),
            DropdownButton<SortOptionEnum>(
              value: defaultSortOption.value,
              dropdownColor: Colors.white,
              style: TextStyle(color: Colors.white),
              underline: Container(
                height: 2,
                color: Colors.white,
              ),
              focusColor: Colors.transparent,
              selectedItemBuilder: (BuildContext context) {
                return SortOptionEnum.values.map<Widget>((item) {
                  return Container(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      item.label,
                      style: TextStyle(color: Colors.white),
                    ),
                  );
                }).toList();
              },
              items: SortOptionEnum.values.map((sortOption) {
                return DropdownMenuItem<SortOptionEnum>(
                  value: sortOption,
                  child: Text(
                    sortOption.label,
                    style: TextStyle(color: Colors.black),
                  ),
                );
              }).toList(),
              onChanged: (SortOptionEnum? newValue) {
                if (newValue != null) {
                  defaultSortOption.value = newValue;
                }
              },
            ),
          ],
        ),
        SectionHeader(title: "Network"),
        Row(
          children: [
            const Expanded(
              child: Row(
                spacing: 4,
                children: [
                  Text(
                    'Number of concurrent downloads',
                    style: TextStyle(fontSize: 16),
                  ),
                  CustomTooltip(
                    message:
                        "Lower the value if you experience working URLs failing to download when downloading from multiple URLs at once\nDefault value: 5",
                    child: Icon(Icons.info_outline),
                  ),
                ],
              ),
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
