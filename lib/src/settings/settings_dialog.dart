import 'dart:ui' show ImageFilter;

import 'package:file_picker/file_picker.dart' show FilePicker;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show FilteringTextInputFormatter, LengthLimitingTextInputFormatter;
import 'package:flutter_hooks/flutter_hooks.dart'
    show HookWidget, useFocusNode, useState, useTextEditingController;
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
        multiModsProvider,
        selectedModTypeProvider,
        settingsProvider;
import 'package:tts_mod_vault/src/models/url_replacement_preset.dart'
    show UrlReplacementPreset;
import 'package:tts_mod_vault/src/state/settings/settings_state.dart'
    show SettingsState;
import 'package:tts_mod_vault/src/state/sort_and_filter/sort_and_filter_state.dart'
    show SortOptionEnum;
import 'package:tts_mod_vault/src/utils.dart' show showSnackBar;

enum SettingsSection {
  features,
  interface,
  folders,
  network,
  updateUrlsPresets,
}

extension SettingsSectionX on SettingsSection {
  String get label {
    switch (this) {
      case SettingsSection.interface:
        return 'Interface';
      case SettingsSection.network:
        return 'Network';
      case SettingsSection.features:
        return 'Features';
      case SettingsSection.updateUrlsPresets:
        return 'Update URLs Presets';
      case SettingsSection.folders:
        return 'Folders';
    }
  }

  IconData get icon {
    switch (this) {
      case SettingsSection.interface:
        return Icons.display_settings;
      case SettingsSection.network:
        return Icons.cloud_outlined;
      case SettingsSection.features:
        return Icons.extension_outlined;
      case SettingsSection.updateUrlsPresets:
        return Icons.edit;
      case SettingsSection.folders:
        return Icons.folder_outlined;
    }
  }
}

class SettingsDialog extends HookConsumerWidget {
  const SettingsDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final directoriesNotifier = ref.watch(directoriesProvider.notifier);
    final settings = ref.watch(settingsProvider);

    final selectedSection = useState<SettingsSection>(SettingsSection.features);

    // UI
    final useModsListViewBox = useState(settings.useModsListView);
    final showTitleOnCardsBox = useState(settings.showTitleOnCards);
    final defaultSortOption = useState(settings.defaultSortOption);
    final assetUrlFontSize = useState(settings.assetUrlFontSize);
    final assetUrlFontSizeController =
        useTextEditingController(text: settings.assetUrlFontSize.toString());
    final assetUrlFontSizeFocusNode = useFocusNode();

    // Network
    final concurrentDownloadsValue = useState(settings.concurrentDownloads);
    final textFieldController = useTextEditingController(
        text: concurrentDownloadsValue.value.toString());
    final textFieldFocusNode = useFocusNode();

    // Features
    final checkForUpdatesOnStartBox = useState(settings.checkForUpdatesOnStart);
    final forceBackupJsonFilename = useState(settings.forceBackupJsonFilename);
    final showSavedObjects = useState(settings.showSavedObjects);
    final showBackupState = useState(settings.showBackupState);
    final ignoreAudioAssets = useState(settings.ignoreAudioAssets);
    final urlPresets = useState<List<UrlReplacementPreset>>(
      List.from(settings.urlReplacementPresets),
    );

    // Folders
    final modsDir = useState(ref.read(directoriesProvider).modsDir);
    final savesDir = useState(ref.read(directoriesProvider).savesDir);
    final backupsDir = useState(ref.read(directoriesProvider).backupsDir);

    Future<void> saveSettingsChanges() async {
      int concurrentDownloads = int.tryParse(textFieldController.text) ?? 5;
      concurrentDownloads = concurrentDownloads.clamp(1, 99);

      final newState = SettingsState(
        useModsListView: useModsListViewBox.value,
        showTitleOnCards: showTitleOnCardsBox.value,
        checkForUpdatesOnStart: checkForUpdatesOnStartBox.value,
        concurrentDownloads: concurrentDownloads,
        showSavedObjects: showSavedObjects.value,
        showBackupState: showBackupState.value,
        defaultSortOption: defaultSortOption.value,
        forceBackupJsonFilename: forceBackupJsonFilename.value,
        ignoreAudioAssets: ignoreAudioAssets.value,
        urlReplacementPresets: urlPresets.value
            .where((p) =>
                p.label.trim().isNotEmpty ||
                p.oldUrl.trim().isNotEmpty ||
                p.newUrl.trim().isNotEmpty)
            .toList(),
        assetUrlFontSize: assetUrlFontSize.value,
      );

      if (ref.read(selectedModTypeProvider) == ModTypeEnum.savedObject &&
          !showSavedObjects.value) {
        ref.read(selectedModTypeProvider.notifier).state = ModTypeEnum.mod;
        ref.read(multiModsProvider.notifier).state = {};
      }

      final oldIgnoreAudioAssets = ref.read(settingsProvider).ignoreAudioAssets;

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
      } else if (oldIgnoreAudioAssets != ignoreAudioAssets.value) {
        ref.read(modsProvider.notifier).loadModsData();
      }

      if (context.mounted) Navigator.pop(context);
    }

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
      child: Dialog(
        child: SizedBox(
          width: 900,
          height: 520,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Settings',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Row(
                    children: [
                      NavigationRail(
                        extended: true,
                        selectedIndex: selectedSection.value.index,
                        onDestinationSelected: (index) {
                          selectedSection.value = SettingsSection.values[index];
                        },
                        destinations: SettingsSection.values.map((section) {
                          return NavigationRailDestination(
                            icon: Icon(section.icon),
                            label: Text(section.label),
                          );
                        }).toList(),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 24),
                          child: IndexedStack(
                            index: selectedSection.value.index,
                            children: SettingsSection.values.map((e) {
                              switch (e) {
                                case SettingsSection.features:
                                  return SettingsFeaturesColumn(
                                    checkForUpdatesOnStartBox:
                                        checkForUpdatesOnStartBox,
                                    showSavedObjects: showSavedObjects,
                                    showBackupState: showBackupState,
                                    forceBackupJsonFilename:
                                        forceBackupJsonFilename,
                                    ignoreAudioAssets: ignoreAudioAssets,
                                  );

                                case SettingsSection.interface:
                                  return SettingsInterfaceColumn(
                                    useModsListViewBox: useModsListViewBox,
                                    showTitleOnCardsBox: showTitleOnCardsBox,
                                    defaultSortOption: defaultSortOption,
                                    assetUrlFontSize: assetUrlFontSize,
                                    assetUrlFontSizeController:
                                        assetUrlFontSizeController,
                                    assetUrlFontSizeFocusNode:
                                        assetUrlFontSizeFocusNode,
                                  );

                                case SettingsSection.folders:
                                  return SettingsFoldersColumn(
                                    modsDir: modsDir,
                                    directoriesNotifier: directoriesNotifier,
                                    savesDir: savesDir,
                                    backupsDir: backupsDir,
                                  );

                                case SettingsSection.network:
                                  return SettingsNetworkColumn(
                                    textFieldController: textFieldController,
                                    textFieldFocusNode: textFieldFocusNode,
                                    numberValue: concurrentDownloadsValue,
                                  );

                                case SettingsSection.updateUrlsPresets:
                                  return SettingsUpdateUrlsPresetsColumn(
                                    urlPresets: urlPresets,
                                  );
                              }
                            }).toList(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
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
                      child: const Text('Reset to defaults'),
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
                        await saveSettingsChanges();
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
    return SingleChildScrollView(
      child: Column(
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
          SizedBox(height: 16),
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
          SizedBox(height: 16),
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
      ),
    );
  }
}

class SettingsFeaturesColumn extends StatelessWidget {
  const SettingsFeaturesColumn({
    super.key,
    required this.checkForUpdatesOnStartBox,
    required this.showSavedObjects,
    required this.showBackupState,
    required this.forceBackupJsonFilename,
    required this.ignoreAudioAssets,
  });

  final ValueNotifier<bool> checkForUpdatesOnStartBox;
  final ValueNotifier<bool> showSavedObjects;
  final ValueNotifier<bool> showBackupState;
  final ValueNotifier<bool> forceBackupJsonFilename;
  final ValueNotifier<bool> ignoreAudioAssets;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
              const Text('Exclude audio assets'),
              CustomTooltip(
                message:
                    "When enabled, audio assets will not be available for download and backup unless modified on per-mod basis\nData will be refreshed after changing this setting",
                child: Icon(Icons.info_outline),
              ),
            ],
          ),
          value: ignoreAudioAssets.value,
          checkColor: Colors.black,
          activeColor: Colors.white,
          contentPadding: EdgeInsets.all(0),
          onChanged: (value) {
            ignoreAudioAssets.value = value ?? ignoreAudioAssets.value;
          },
        ),
      ],
    );
  }
}

class SettingsUpdateUrlsPresetsColumn extends StatelessWidget {
  const SettingsUpdateUrlsPresetsColumn({
    super.key,
    required this.urlPresets,
  });

  final ValueNotifier<List<UrlReplacementPreset>> urlPresets;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          ...urlPresets.value.asMap().entries.map((entry) {
            final index = entry.key;
            final preset = entry.value;

            return Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.grey[850],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          preset.label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 16),
                        ),
                        Text(
                          'Old prefix: ${preset.oldUrl}',
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'New prefix: ${preset.newUrl}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    onPressed: () async {
                      final result = await showDialog<UrlReplacementPreset>(
                        context: context,
                        builder: (context) =>
                            _PresetEditorDialog(preset: preset),
                      );
                      if (result != null) {
                        final newList =
                            List<UrlReplacementPreset>.from(urlPresets.value);
                        newList[index] = result;
                        urlPresets.value = newList;
                      }
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () {
                      final newList =
                          List<UrlReplacementPreset>.from(urlPresets.value);
                      newList.removeAt(index);
                      urlPresets.value = newList;
                    },
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: () async {
              final result = await showDialog<UrlReplacementPreset>(
                context: context,
                builder: (context) => const _PresetEditorDialog(),
              );
              if (result != null) {
                urlPresets.value = [...urlPresets.value, result];
              }
            },
            icon: const Icon(Icons.add),
            label: const Text('Add Preset'),
          ),
        ],
      ),
    );
  }
}

class SettingsInterfaceColumn extends StatelessWidget {
  const SettingsInterfaceColumn({
    super.key,
    required this.useModsListViewBox,
    required this.showTitleOnCardsBox,
    required this.defaultSortOption,
    required this.assetUrlFontSize,
    required this.assetUrlFontSizeController,
    required this.assetUrlFontSizeFocusNode,
  });

  final ValueNotifier<bool> useModsListViewBox;
  final ValueNotifier<bool> showTitleOnCardsBox;
  final ValueNotifier<SortOptionEnum> defaultSortOption;
  final ValueNotifier<double> assetUrlFontSize;
  final TextEditingController assetUrlFontSizeController;
  final FocusNode assetUrlFontSizeFocusNode;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
        Row(
          spacing: 4,
          children: [
            Text(
              'Asset URL font size',
              style: TextStyle(fontSize: 16),
            ),
            CustomTooltip(
              message:
                  "Range: 1-99 (up to 1 decimal place)\nDefault value: 12.0",
              child: Icon(Icons.info_outline),
            ),
            Spacer(),
            SizedBox(
              width: 70,
              child: TextField(
                textAlign: TextAlign.center,
                controller: assetUrlFontSizeController,
                cursorColor: Colors.black,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d{0,2}\.?\d?$')),
                ],
                style:
                    TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  fillColor: Colors.white,
                  border: OutlineInputBorder(),
                ),
                focusNode: assetUrlFontSizeFocusNode,
                onChanged: (value) {
                  final num = double.tryParse(value);
                  if (num != null && num >= 1 && num <= 99) {
                    assetUrlFontSize.value = num;
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

class SettingsNetworkColumn extends StatelessWidget {
  const SettingsNetworkColumn({
    super.key,
    required this.textFieldController,
    required this.textFieldFocusNode,
    required this.numberValue,
  });

  final TextEditingController textFieldController;
  final FocusNode textFieldFocusNode;
  final ValueNotifier<int> numberValue;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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

class _PresetEditorDialog extends HookWidget {
  final UrlReplacementPreset? preset;

  const _PresetEditorDialog({this.preset});

  @override
  Widget build(BuildContext context) {
    final labelController = useTextEditingController(text: preset?.label ?? '');
    final oldUrlController =
        useTextEditingController(text: preset?.oldUrl ?? '');
    final newUrlController =
        useTextEditingController(text: preset?.newUrl ?? '');

    return AlertDialog(
      title: Text(preset == null ? 'Add Preset' : 'Edit Preset'),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Preset Label',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: labelController,
              autofocus: true,
              style: const TextStyle(fontSize: 14, color: Colors.black),
              decoration: const InputDecoration(
                fillColor: Colors.white,
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Old URL Prefix',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: oldUrlController,
              style: const TextStyle(fontSize: 14, color: Colors.black),
              decoration: const InputDecoration(
                fillColor: Colors.white,
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'New URL Prefix',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: newUrlController,
              style: const TextStyle(fontSize: 14, color: Colors.black),
              decoration: const InputDecoration(
                fillColor: Colors.white,
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
            ),
          ],
        ),
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: () {
            final label = labelController.text.trim();
            final oldUrl = oldUrlController.text.trim();
            final newUrl = newUrlController.text.trim();

            if (label.isEmpty || oldUrl.isEmpty || newUrl.isEmpty) {
              return;
            }

            Navigator.pop(
              context,
              UrlReplacementPreset(
                label: label,
                oldUrl: oldUrl,
                newUrl: newUrl,
              ),
            );
          },
          icon: Icon(preset == null ? Icons.add : Icons.edit),
          label: Text(preset == null ? 'Add' : 'Edit'),
        ),
      ],
    );
  }
}
