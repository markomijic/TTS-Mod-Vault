import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
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
  VoidCallback onConfirm, [
  VoidCallback? onCancel,
]) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        content: Text(contentMessage),
        actions: [
          TextButton(
            onPressed: () {
              if (onCancel != null) {
                onCancel();
              } else {
                Navigator.of(context).pop();
              }
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Future.delayed(kThemeChangeDuration, () => onConfirm());
            },
            child: const Text('Confirm'),
          ),
        ],
      );
    },
  );
}

String getExtensionByType(
  AssetType type, [
  String filePath = '',
  List<int>? bytes,
]) {
  switch (type) {
    case AssetType.assetBundle:
      return '.unity3d';

    case AssetType.audio:
      {
        final mimeType = lookupMimeType(filePath, headerBytes: bytes);

        switch (mimeType) {
          case 'audio/ogg':
            return '.ogg';

          case 'audio/wav':
            return '.wav';

          case 'video/ogv':
            return '.ogv';

          case 'audio/mpeg':
          default:
            return '.mp3';
        }
      }

    case AssetType.image:
      {
        final mimeType = lookupMimeType(filePath, headerBytes: bytes);

        switch (mimeType) {
          case 'image/jpeg':
            return '.jpg';

          case 'image/png':
          default:
            return '.png';
        }
      }

    case AssetType.model:
      return '.obj';

    case AssetType.pdf:
      return '.pdf';
  }
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
