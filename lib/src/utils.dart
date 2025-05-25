import 'dart:io' show Directory, File, Platform, Process;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:mime/mime.dart' show lookupMimeType;
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart'
    show AssetTypeEnum;
import 'package:path/path.dart' as p;

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
]) async {
  final result = await showDialog<String>(
    context: context,
    builder: (BuildContext context) {
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
        child: AlertDialog(
          content: Text(contentMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop('cancel'),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('confirm'),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
    },
  );

  switch (result) {
    case 'confirm':
      Future.delayed(kThemeChangeDuration, () => onConfirm());
      break;
    case 'cancel':
    case null:
    default:
      if (onCancel != null) {
        onCancel();
      }
      break;
  }
}

String getExtensionByType(
  AssetTypeEnum type, [
  String filePath = '',
  List<int>? bytes,
]) {
  switch (type) {
    case AssetTypeEnum.assetBundle:
      return '.unity3d';

    case AssetTypeEnum.audio:
      {
        final mimeType = lookupMimeType(filePath, headerBytes: bytes);

        switch (mimeType) {
          case 'audio/ogg':
          case 'audio/vorbis':
            return '.ogg';

          case 'audio/wav':
          case 'audio/vnd.wave':
            return '.wav';

          case 'video/ogg':
          case 'video/ogv':
            return '.ogv';

          case 'audio/mpeg':
          default:
            return '.mp3';
        }
      }

    case AssetTypeEnum.image:
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

    case AssetTypeEnum.model:
      return '.obj';

    case AssetTypeEnum.pdf:
      return '.PDF';
  }
}

String sanitizeFileName(String input) {
  // Replace characters that are invalid in most file systems
  final sanitized = input
      .replaceAll(':', '_') // colon
      .replaceAll('/', '_') // forward slash
      .replaceAll('\\', '_') // backslash
      .replaceAll('*', '_') // asterisk
      .replaceAll('?', '_') // question mark
      .replaceAll('"', '_') // double quote
      .replaceAll('<', '_') // less than
      .replaceAll('>', '_') // greater than
      .replaceAll('|', '_'); // pipe
/*       .replaceAll('\n', '_') // newline
      .replaceAll('\r', '_') // carriage return
      .replaceAll('\t', '_') // tab
      .replaceAll('\0', '_'); // null character */

  /* Trim leading/trailing whitespace and dots
     (Leading dots can make files hidden on Unix systems,
     trailing dots/spaces can cause issues on Windows)
  */
  return sanitized.trim().replaceAll(RegExp(r'^\.+|\.+$'), '');
}

Future<void> openFileInExplorer(String filePath) async {
  try {
    if (Platform.isWindows) {
      await Process.run('explorer.exe', ['/select,', filePath]);
    } else if (Platform.isMacOS) {
      await Process.run('open', ['-R', filePath]);
    } else if (Platform.isLinux) {
      final directory = Directory(p.dirname(filePath));
      await Process.run('xdg-open', [directory.path]);
    }
  } catch (e) {
    debugPrint('Error opening file in explorer: $e');
  }
}
