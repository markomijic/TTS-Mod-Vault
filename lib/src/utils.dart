import 'package:flutter/material.dart';
import 'package:tts_mod_vault/src/state/directories/directories_state.dart';
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart';

String getFileNameFromURL(String url) {
  // Keep only letters and numbers, remove everything else
  return url.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
}

void showSnackBar(BuildContext context, String message, [Duration? duration]) {
  final snackBar = SnackBar(
    content: Text(message),
    duration: duration ?? Duration(seconds: 5),
    showCloseIcon: true,
  );

  ScaffoldMessenger.of(context).showSnackBar(snackBar);
}

void showAlertDialog(
  BuildContext context,
  String contentMessage,
  VoidCallback onConfirm,
) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        content: Text(contentMessage),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              onConfirm();
            },
            child: const Text('Confirm'),
          ),
        ],
      );
    },
  );
}

String getExtensionByType(AssetType type) {
  String extension = '';

  switch (type) {
    case AssetType.assetBundle:
      extension = '.unity3d';
      break;
    case AssetType.audio:
      extension = '.MP3';
      break;
    case AssetType.image:
      extension = '.png';
      break;
    case AssetType.model:
      extension = '.obj';
      break;
    case AssetType.pdf:
      extension = '.pdf';
      break;
  }

  return extension;
}

String getDirectoryByType(DirectoriesState directories, AssetType type) {
  switch (type) {
    case AssetType.assetBundle:
      return directories.assetBundlesDir;

    case AssetType.audio:
      return directories.audioDir;

    case AssetType.image:
      return directories.imagesDir;

    case AssetType.model:
      return directories.modelsDir;

    case AssetType.pdf:
      return directories.pdfDir;
  }
}
