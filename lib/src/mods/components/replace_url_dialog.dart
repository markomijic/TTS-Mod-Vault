import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show FilteringTextInputFormatter, LengthLimitingTextInputFormatter;
import 'package:flutter_hooks/flutter_hooks.dart'
    show useFocusNode, useState, useTextEditingController;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/state/provider.dart' show settingsProvider;

void showReplaceUrlDialog(
  BuildContext context,
  WidgetRef ref,
) {
  if (context.mounted) {
    showDialog(
      context: context,
      builder: (context) {
        return ReplaceUrlDialog();
      },
    );
  }
}

class ReplaceUrlDialog extends HookConsumerWidget {
  const ReplaceUrlDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

/*     final useModsListViewBox = useState(settings.useModsListView);
    final showTitleOnCardsBox = useState(settings.showTitleOnCards);
    final checkForUpdatesOnStartBox = useState(settings.checkForUpdatesOnStart); */
    final numberValue = useState(settings.concurrentDownloads);

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

    /* Future<void> saveSettingsChanges(BuildContext context) async {
      int concurrentDownloads = int.tryParse(textFieldController.text) ?? 5;

      if (concurrentDownloads < 1 || concurrentDownloads > 99) {
        concurrentDownloads = 5;
      }

      SettingsState newState = SettingsState(
        useModsListView: useModsListViewBox.value,
        showTitleOnCards: showTitleOnCardsBox.value,
        checkForUpdatesOnStart: checkForUpdatesOnStartBox.value,
        concurrentDownloads: concurrentDownloads,
      );

      await ref.read(settingsProvider.notifier).saveSettings(newState);

      if (context.mounted) {
        Navigator.pop(context);
      }
    } */

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
      child: AlertDialog(
        title: Text('Replace URL'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                child: Row(
                  spacing: 8,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'New URL',
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
                          /*         final num = int.tryParse(value);
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
                          } */
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              /*            // Validate number input
              final inputValue = int.tryParse(textFieldController.text);
              if (inputValue == null || inputValue < 1 || inputValue > 99) {
                showSnackBar(context, 'Please enter a number between 1 and 99');
                if (context.mounted) Navigator.pop(context);
                return;
              }

              await saveSettingsChanges(context); */
            },
            child: Text('Save'),
          ),
        ],
      ),
    );
  }
}
