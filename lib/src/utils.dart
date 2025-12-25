import 'dart:io' show Directory, Platform, Process;
import 'dart:ui' show ImageFilter;
import 'dart:convert' show json;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:hooks_riverpod/hooks_riverpod.dart' show WidgetRef;
import 'package:intl/intl.dart' show DateFormat;
import 'package:mime/mime.dart' show lookupMimeType;
import 'package:open_filex/open_filex.dart' show OpenFilex;
import 'package:tts_mod_vault/src/mods/components/custom_tooltip.dart';
import 'package:tts_mod_vault/src/mods/enums/context_menu_action_enum.dart'
    show ContextMenuActionEnum;
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart'
    show AssetTypeEnum;
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart'
    show Mod, ModTypeEnum;
import 'package:tts_mod_vault/src/state/provider.dart'
    show actionInProgressProvider;
import 'package:url_launcher/url_launcher.dart'
    show LaunchMode, canLaunchUrl, launchUrl;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart' show PackageInfo;

const oldCloudUrl = "http://cloud-3.steamusercontent.com/";
const newSteamUserContentUrl = "https://steamusercontent-a.akamaihd.net/";

const nexusModsDownloadPageUrl =
    "https://www.nexusmods.com/tabletopsimulator/mods/426";
const steamDiscussionUrl =
    "https://steamcommunity.com/app/286160/discussions/0/591772542952298985/";

const String updateUrlsHelp = '''
The Update URLs feature works by replacing the beginning of a URL. 
You can also replace an entire URL by entering it in the "Old prefix" field.

Example (single old prefix):
• Old prefix: http://pastebin.com/raw.php?i=
• New prefix: https://pastebin.com/raw/

If your mod contains: http://pastebin.com/raw.php?i=1234, http://pastebin.com/raw.php?i=example
They will be updated to: https://pastebin.com/raw/1234, https://pastebin.com/raw/example

Example (multiple old prefixes):
• Old prefixes: http://pastebin.com/raw.php?i=|http://pastebin.com/raw/|http://pastebin.com/
• New prefix: https://pastebin.com/raw/

If your mod contains: http://pastebin.com/raw.php?i=abcd, http://pastebin.com/raw/5678, http://pastebin.com/example2
They will be updated to: https://pastebin.com/raw/abcd, https://pastebin.com/raw/5678, https://pastebin.com/raw/example2''';
const String updateUrlsInstruction =
    'You can enter multiple old prefixes by separating them with the | symbol\nFor example: http://pastebin.com/raw.php?i=|http://pastebin.com/raw/|http://pastebin.com/\n\nThere must be exactly one new prefix, for example: https://pastebin.com/raw/';

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
  navigationRailTheme: NavigationRailThemeData(
    selectedIconTheme: IconThemeData(color: Colors.black),
    unselectedIconTheme: IconThemeData(color: Colors.white),
    selectedLabelTextStyle: TextStyle(
      color: Colors.white,
      fontSize: 16,
    ),
    unselectedLabelTextStyle: TextStyle(
      color: Colors.white,
      fontSize: 16,
    ),
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

String getFileNameFromPath(String path) {
  return p.basenameWithoutExtension(path);
}

void showSnackBar(BuildContext context, String message) {
  final snackBar = SnackBar(
    content: Text(
      message,
      style: TextStyle(fontSize: 20),
    ),
    showCloseIcon: false,
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
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop('cancel'),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
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

Future<void> showConfirmDialogWithCheckbox(
  BuildContext context, {
  required String message,
  required void Function(bool checkboxValue) onConfirm,
  required String checkboxLabel,
  required String checkboxInfoMessage,
}) async {
  bool checkboxValue = false;

  final result = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
            child: AlertDialog(
              content: Column(
                spacing: 16,
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message,
                    style: TextStyle(fontSize: 16),
                  ),
                  Row(
                    spacing: 4,
                    children: [
                      Checkbox(
                        value: checkboxValue,
                        checkColor: Colors.black,
                        activeColor: Colors.white,
                        onChanged: (value) {
                          setState(() {
                            checkboxValue = value ?? false;
                          });
                        },
                      ),
                      Text(
                        checkboxLabel,
                        style: TextStyle(fontSize: 16),
                      ),
                      CustomTooltip(
                        message: checkboxInfoMessage ?? "",
                        child: Icon(
                          Icons.info_outline,
                          size: 26,
                        ),
                      )
                    ],
                  ),
                ],
              ),
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop({
                    'action': 'cancel',
                    'checkboxValue': checkboxValue,
                  }),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop({
                    'action': 'confirm',
                    'checkboxValue': checkboxValue,
                  }),
                  child: const Text('Confirm'),
                ),
              ],
            ),
          );
        },
      );
    },
  );

  if (result != null && result['action'] == 'confirm') {
    Future.delayed(
      kThemeChangeDuration,
      () => onConfirm(result['checkboxValue'] as bool),
    );
  }
}

Future<void> showDownloadDialog(
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
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop('cancel'),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop('nexusmods'),
              child: const Text('Nexus Mods'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop('github'),
              child: const Text('GitHub'),
            ),
          ],
        ),
      );
    },
  );

  switch (result) {
    case 'nexusmods':
      Future.delayed(kThemeChangeDuration, () async {
        final result = await openUrl(nexusModsDownloadPageUrl);
        if (!result && context.mounted) {
          showSnackBar(context, "Failed to open: $nexusModsDownloadPageUrl");
        }
      });
      break;

    case 'github':
      Future.delayed(kThemeChangeDuration, () async {
        final url = getGitHubReleaseUrl(latestVersion);
        final result = await openUrl(url);
        if (!result && context.mounted) {
          showSnackBar(context, "Failed to open: $url");
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
          // Unsupported by TTS 14.0
          case 'image/gif':
            return '.gif';

          case 'image/bmp':
          case 'image/x-windows-bmp':
            return '.bmp';

          case 'image/svg+xml':
            return '.svg';

          case 'image/tiff':
            return '.tiff';

          case 'image/x-icon':
            return '.ico';

          case 'image/avif':
            return '.avif';

          // Supported by TTS 14.0
          case 'image/jpeg':
            return '.jpg';

          case 'image/webp':
            return '.webp';

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

String getBackupFilenameByMod(Mod mod, bool forceIncludeJsonFilename) {
  // If json file name is not a number -> do not include it in backup filename unless modified by Setting
  final nameAsNumber = int.tryParse(mod.jsonFileName);

  if (!forceIncludeJsonFilename &&
      nameAsNumber == null &&
      mod.modType == ModTypeEnum.mod) {
    return sanitizeFileName("${mod.saveName}.ttsmod");
  }

  return sanitizeFileName("${mod.saveName} (${mod.jsonFileName}).ttsmod");
}

Future<void> openInFileExplorer(String filePath) async {
  final normalizedPath = p.normalize(filePath);

  try {
    if (Platform.isWindows) {
      await Process.run('explorer.exe', ['/select,', normalizedPath]);
    } else if (Platform.isMacOS) {
      await Process.run('open', ['-R', normalizedPath]);
    } else if (Platform.isLinux) {
      final directory = Directory(p.dirname(normalizedPath));
      await Process.run('xdg-open', [directory.path]);
    }
  } catch (e) {
    debugPrint('Error opening file in explorer: $e');
  }
}

Future<void> openFile(String filePath) async {
  final normalizedPath = p.normalize(filePath);

  try {
    await OpenFilex.open(normalizedPath);
  } catch (e) {
    debugPrint('openFile error: $e');
  }
}

Future<bool> openUrl(String url) async {
  try {
    if (url.isEmpty) return false;

    final Uri uri = Uri.parse(url);

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return true;
    }
    return false;
  } catch (e) {
    debugPrint('openUrl error: $e');
    return false;
  }
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

Future<void> copyToClipboard(BuildContext context, String textToCopy) async {
  await Clipboard.setData(ClipboardData(text: textToCopy));
  if (context.mounted) {
    showSnackBar(
      context,
      '$textToCopy copied to clipboard',
    );
  }
}

void showModContextMenu(
  BuildContext context,
  WidgetRef ref,
  Offset position,
  Mod mod,
) {
  showMenu(
    context: context,
    color: Theme.of(context).scaffoldBackgroundColor,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: BorderSide(color: Colors.white, width: 2),
    ),
    position: RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      position.dx,
      position.dy,
    ),
    items: [
      PopupMenuItem(
        value: ContextMenuActionEnum.openImagesViewer,
        child: Row(
          spacing: 8,
          children: [
            Icon(Icons.image),
            Text('View Images'),
          ],
        ),
      ),
      PopupMenuItem(
        value: ContextMenuActionEnum.openInExplorer,
        child: Row(
          spacing: 8,
          children: [
            Icon(Icons.folder_open),
            Text('Open in File Explorer'),
          ],
        ),
      ),
      if (mod.backup != null)
        PopupMenuItem(
          value: ContextMenuActionEnum.openBackupInExplorer,
          child: Row(
            spacing: 8,
            children: [
              Icon(Icons.folder_zip_outlined),
              Text('Open Backup in File Explorer'),
            ],
          ),
        ),
      if (mod.modType == ModTypeEnum.mod)
        PopupMenuItem(
          value: ContextMenuActionEnum.openSteamWorkshopPage,
          child: Row(
            spacing: 8,
            children: [
              Icon(Icons.open_in_browser),
              Text('Open Steam Workshop page'),
            ],
          ),
        ),
      PopupMenuItem(
        value: ContextMenuActionEnum.copySaveName,
        child: Row(
          spacing: 8,
          children: [
            Icon(Icons.content_copy),
            Text('Copy Name'),
          ],
        ),
      ),
      PopupMenuItem(
        value: ContextMenuActionEnum.copyFilename,
        child: Row(
          spacing: 8,
          children: [
            Icon(Icons.file_copy),
            Text('Copy Filename'),
          ],
        ),
      ),
    ],
  ).then((value) async {
    if (value != null) {
      switch (value) {
        case ContextMenuActionEnum.openImagesViewer:
          if (context.mounted) {
            if (ref.read(actionInProgressProvider)) {
              showSnackBar(
                  context, "Finish your current action before viewing images");
              return;
            }

            Navigator.of(context).pushNamed('/images-viewer');
          }
          break;

        case ContextMenuActionEnum.openInExplorer:
          openInFileExplorer(mod.jsonFilePath);
          break;

        case ContextMenuActionEnum.openSteamWorkshopPage:
          openUrl(
              "https://steamcommunity.com/sharedfiles/filedetails/?id=${mod.jsonFileName}");
          break;

        case ContextMenuActionEnum.openBackupInExplorer:
          openInFileExplorer(mod.backup!.filepath);
          break;

        case ContextMenuActionEnum.copySaveName:
          if (context.mounted) {
            copyToClipboard(context, mod.saveName);
          }
          break;

        case ContextMenuActionEnum.copyFilename:
          if (context.mounted) {
            copyToClipboard(context, mod.jsonFileName);
          }
          break;

        default:
          break;
      }
    }
  });
}

String? formatTimestamp(String? timestamp) {
  if (timestamp == null) return null;

  try {
    final dateTime =
        DateTime.fromMillisecondsSinceEpoch(int.parse(timestamp) * 1000);
    return DateFormat("d MMMM y HH:mm").format(dateTime);
  } catch (e) {
    return null;
  }
}
