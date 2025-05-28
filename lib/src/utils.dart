import 'dart:io' show Directory, Platform, Process;
import 'dart:ui' show ImageFilter;
import 'dart:convert' show json;

import 'package:flutter/material.dart';
import 'package:mime/mime.dart' show lookupMimeType;
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart'
    show AssetTypeEnum;
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart'
    show LaunchMode, canLaunchUrl, launchUrl;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart' show PackageInfo;

const oldUrl = "http://cloud-3.steamusercontent.com/";
const newUrl = "https://steamusercontent-a.akamaihd.net/";
const downloadPageUrl =
    "https://www.nexusmods.com/tabletopsimulator/mods/426?tab=files";

final ThemeData darkTheme = ThemeData(
  brightness: Brightness.dark,
  primaryColor: Colors.black,
  scaffoldBackgroundColor: Color(0xFF141218),
  appBarTheme: AppBarTheme(
    backgroundColor: Colors.black,
    foregroundColor: Colors.white,
  ),
  colorScheme: ColorScheme.dark(
    primary: Colors.black,
    secondary: Colors.white,
    error: Colors.red,
    tertiary: Colors.blue,
  ),
  textTheme: TextTheme(
    bodyLarge: TextStyle(color: Colors.white),
    bodyMedium: TextStyle(color: Colors.white),
    bodySmall: TextStyle(color: Colors.white),
  ),
  iconTheme: IconThemeData(color: Colors.white),
  floatingActionButtonTheme: FloatingActionButtonThemeData(
    backgroundColor: Colors.red,
    foregroundColor: Colors.white,
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black,
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: Colors.white,
      side: BorderSide(color: Colors.white),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(foregroundColor: Colors.blue),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.black87,
    focusedBorder:
        OutlineInputBorder(borderSide: BorderSide(color: Colors.white)),
    enabledBorder:
        OutlineInputBorder(borderSide: BorderSide(color: Colors.white70)),
    labelStyle: TextStyle(color: Colors.white),
    hintStyle: TextStyle(color: Colors.white60),
  ),
);

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

void showConfirmDialog(
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

void showDownloadDialog(
  BuildContext context,
  String currentVersion,
  String latestVersion,
) async {
  final result = await showDialog<String>(
    context: context,
    builder: (BuildContext context) {
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
        child: AlertDialog(
          content: Text(
            "Your version: $currentVersion\nLatest version: $latestVersion\n\nA new application version is available.\nWould you like to open the download page?",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop('cancel'),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('download'),
              child: const Text('Open download page'),
            ),
          ],
        ),
      );
    },
  );

  switch (result) {
    case 'download':
      Future.delayed(kThemeChangeDuration, () async {
        final result = await openUrl(downloadPageUrl);
        if (!result && context.mounted) {
          showSnackBar(context, "Failed to open: $downloadPageUrl");
        }
      });
      break;

    case 'cancel':
    case null:
    default:
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

Future<bool> openUrl(String url) async {
  if (url.isEmpty) return false;

  final Uri uri = Uri.parse(url);

  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
    return true;
  }

  return false;
}

String getGitHubReleaseUrl(String newTagVersion) {
  return "https://github.com/markomijic/TTS-Mod-Vault/releases/tag/v$newTagVersion";
}

Future<String> checkForUpdatesOnGitHub() async {
  try {
    final response = await http.get(
      Uri.parse(
          'https://api.github.com/repos/markomijic/TTS-Mod-Vault/releases/latest'),
    );

    // For private repository
    /* final response = await http.get(
      Uri.parse(
          'https://api.github.com/repos/markomijic/TTS-Mod-Vault/releases/latest'),
      headers: {
        'Authorization': 'Bearer TOKEN_HERE',
        'Accept': 'application/vnd.github+json',
      },
    ); */

    debugPrint("checkForUpdatesOnGitHub - code: ${response.statusCode}");

    if (response.statusCode == 200) {
      final release = json.decode(response.body);
      final latestVersion = release['tag_name'].replaceAll('v', '');

      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      if (_checkIfLatestVersionIsNewer(currentVersion, latestVersion)) {
        return latestVersion;
      }
    }
  } catch (e) {
    debugPrint("checkForUpdatesOnGitHub - error: $e");
  }

  return "";
}

bool _checkIfLatestVersionIsNewer(String current, String latest) {
  return true;
  debugPrint(
      "_checkIfLatestVersionIsNewer - current: $current, latest: $latest");

  List<int> currentParts = current.split('.').map(int.parse).toList();
  List<int> latestParts = latest.split('.').map(int.parse).toList();

  debugPrint(
      "_checkIfLatestVersionIsNewer - currentParts: $currentParts, latestParts: $latestParts");

  for (int i = 0; i < 3; i++) {
    if (latestParts[i] > currentParts[i]) return true;
    if (latestParts[i] < currentParts[i]) return false;
  }
  return false;
}
