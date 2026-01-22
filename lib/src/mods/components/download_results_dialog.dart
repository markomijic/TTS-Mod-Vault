import 'package:flutter/material.dart';
import 'dart:ui' show ImageFilter;
import 'package:tts_mod_vault/src/utils.dart' show copyToClipboard;

void showDownloadResultsDialog(BuildContext context, String resultMessage) {
  showDialog(
    context: context,
    builder: (builderContext) => BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
      child: AlertDialog(
        title: Text('Download Results', style: TextStyle(fontSize: 18)),
        content: SizedBox(
          width: 700,
          child: SingleChildScrollView(
            child: SelectableText(
              resultMessage,
              style: TextStyle(fontSize: 16),
            ),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(builderContext).pop(),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              copyToClipboard(builderContext, resultMessage,
                  showSnackBarAfterCopying: false);
            },
            icon: Icon(Icons.copy),
            label: const Text('Copy'),
          ),
        ],
      ),
    ),
  );
}
