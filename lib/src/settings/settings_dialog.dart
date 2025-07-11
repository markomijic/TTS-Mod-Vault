import 'package:file_picker/file_picker.dart' show FilePicker;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show FilteringTextInputFormatter, LengthLimitingTextInputFormatter;
import 'package:flutter_hooks/flutter_hooks.dart'
    show useFocusNode, useState, useTextEditingController;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:path/path.dart' as path;
import 'package:tts_mod_vault/src/mods/components/custom_tooltip.dart'
    show CustomTooltip;
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

    final useModsListViewBox = useState(settings.useModsListView);
    final showTitleOnCardsBox = useState(settings.showTitleOnCards);
    final checkForUpdatesOnStartBox = useState(settings.checkForUpdatesOnStart);
    final enableTtsModdersFeatures =
        useState(settings.enableTtsModdersFeatures);
    final showSavedObjects = useState(settings.showSavedObjects);
    final numberValue = useState(settings.concurrentDownloads);
    final modsDir = useState(ref.read(directoriesProvider).modsDir);
    final savesDir = useState(ref.read(directoriesProvider).savesDir);

    final textFieldController =
        useTextEditingController(text: numberValue.value.toString());
    final textFieldFocusNode = useFocusNode();

    textFieldFocusNode.addListener(
      () {
        if (!textFieldFocusNode.hasFocus && textFieldController.text.isEmpty) {
          textFieldController.text = "5";
        }
      },
    );

    Future<void> saveSettingsChanges(BuildContext context) async {
      int concurrentDownloads = int.tryParse(textFieldController.text) ?? 5;

      if (concurrentDownloads < 1 || concurrentDownloads > 99) {
        concurrentDownloads = 5;
      }

      SettingsState newState = SettingsState(
        useModsListView: useModsListViewBox.value,
        showTitleOnCards: showTitleOnCardsBox.value,
        checkForUpdatesOnStart: checkForUpdatesOnStartBox.value,
        concurrentDownloads: concurrentDownloads,
        enableTtsModdersFeatures: enableTtsModdersFeatures.value,
        showSavedObjects: showSavedObjects.value,
      );

      if (ref.read(selectedModTypeProvider) == ModTypeEnum.savedObject &&
          !showSavedObjects.value) {
        ref.read(selectedModTypeProvider.notifier).state = ModTypeEnum.mod;
        ref.read(selectedModProvider.notifier).state = null;
      }

      await ref.read(settingsProvider.notifier).saveSettings(newState);

      if (ref.read(directoriesProvider).modsDir != modsDir.value ||
          ref.read(directoriesProvider).savesDir != savesDir.value) {
        if (await directoriesNotifier.isModsDirectoryValid(modsDir.value) &&
            await directoriesNotifier.isSavesDirectoryValid(savesDir.value)) {
          await ref.read(directoriesProvider.notifier).saveDirectories();
          ref.read(modsProvider.notifier).loadModsData();
        }
      }

      if (context.mounted) {
        Navigator.pop(context);
      }
    }

    return AlertDialog(
      title: Text('Settings'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.white))),
              child: Text('User Interface', style: TextStyle(fontSize: 20)),
            ),
            CheckboxListTile(
              title: Text('Display mods as a list instead of grid'),
              value: useModsListViewBox.value,
              checkColor: Colors.black,
              activeColor: Colors.white,
              onChanged: (value) {
                useModsListViewBox.value = value ?? useModsListViewBox.value;
              },
            ),
            CheckboxListTile(
              title: Text('Display mod names on grid cards'),
              value: showTitleOnCardsBox.value,
              checkColor: Colors.black,
              activeColor: Colors.white,
              onChanged: (value) {
                showTitleOnCardsBox.value = value ?? showTitleOnCardsBox.value;
              },
            ),
            Container(
              decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.white))),
              child: Text('Features', style: TextStyle(fontSize: 20)),
            ),
            CheckboxListTile(
              title: Text('Check for updates on start'),
              value: checkForUpdatesOnStartBox.value,
              checkColor: Colors.black,
              activeColor: Colors.white,
              onChanged: (value) {
                checkForUpdatesOnStartBox.value =
                    value ?? checkForUpdatesOnStartBox.value;
              },
            ),
            CustomTooltip(
              message:
                  "Show Saved Objects next to Mods and Saves, manual refresh of data is needed after enabling if TTS Mod Vault was opened while this setting was disabled",
              child: CheckboxListTile(
                title: Text('Show Saved Objects'),
                value: showSavedObjects.value,
                checkColor: Colors.black,
                activeColor: Colors.white,
                onChanged: (value) {
                  showSavedObjects.value = value ?? showSavedObjects.value;
                },
              ),
            ),
            CustomTooltip(
              message:
                  "Enables:\nReplace URL in asset lists and viewing images",
              child: CheckboxListTile(
                title: Text('Enable TTS Modders features'),
                value: enableTtsModdersFeatures.value,
                checkColor: Colors.black,
                activeColor: Colors.white,
                onChanged: (value) {
                  enableTtsModdersFeatures.value =
                      value ?? enableTtsModdersFeatures.value;
                },
              ),
            ),
            Container(
              decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.white))),
              child: Text('Network', style: TextStyle(fontSize: 20)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: Row(
                spacing: 8,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Number of concurrent downloads (default: 5)',
                    style: TextStyle(fontSize: 16),
                  ),
                  SizedBox(
                    width: 50,
                    child: TextField(
                      textAlign: TextAlign.center,
                      controller: textFieldController,
                      cursorColor: Colors.white,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(2),
                      ],
                      decoration: InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                      focusNode: textFieldFocusNode,
                      onChanged: (value) {
                        final num = int.tryParse(value);
                        if (value.startsWith("0")) {
                          // Reset to 1 if user enters 0
                          textFieldController.text = '1';
                          textFieldController.selection =
                              TextSelection.fromPosition(
                            TextPosition(
                                offset: textFieldController.text.length),
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
            ),
            Text('Mods folder', style: TextStyle(fontSize: 20)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              spacing: 8,
              children: [
                Container(
                  constraints: BoxConstraints(maxWidth: 950),
                  padding: EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white),
                    borderRadius: BorderRadius.circular(4),
                    color: Colors.white,
                  ),
                  child: SelectableText(
                    modsDir.value,
                    style: TextStyle(color: Colors.black),
                  ),
                ),
                CustomTooltip(
                  message: 'Saving changes to folders will refresh all data',
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
                          showSnackBar(
                            context,
                            'Invalid Mods folder',
                          );
                        }
                      } else {
                        modsDir.value = ttsDir.endsWith('Mods')
                            ? ttsDir
                            : (path.join(ttsDir, 'Mods'));
                      }
                    },
                    child: Text('Select Mods folder'),
                  ),
                ),
              ],
            ),
            Text('Saves folder', style: TextStyle(fontSize: 20)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              spacing: 8,
              children: [
                Container(
                  constraints: BoxConstraints(maxWidth: 950),
                  padding: EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white),
                    borderRadius: BorderRadius.circular(4),
                    color: Colors.white,
                  ),
                  child: SelectableText(
                    savesDir.value,
                    style: TextStyle(color: Colors.black),
                  ),
                ),
                CustomTooltip(
                  message: 'Saving changes to folders will refresh all data',
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
                          showSnackBar(
                            context,
                            'Invalid Saves folder',
                          );
                        }
                      } else {
                        savesDir.value = ttsDir.endsWith('Saves')
                            ? ttsDir
                            : (path.join(ttsDir, 'Saves'));
                      }
                    },
                    child: Text('Select Saves folder'),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
      actions: [
        ElevatedButton(
          onPressed: () async {
            await ref.read(settingsProvider.notifier).resetToDefaultSettings();
            if (context.mounted) {
              Navigator.pop(context);
            }
          },
          child: Text('Reset to default settings'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            // Validate number input
            final inputValue = int.tryParse(textFieldController.text);
            if (inputValue == null || inputValue < 1 || inputValue > 99) {
              showSnackBar(context, 'Please enter a number between 1 and 99');
              if (context.mounted) Navigator.pop(context);
              return;
            }

            await saveSettingsChanges(context);
          },
          child: Text('Save'),
        ),
      ],
    );
  }
}
