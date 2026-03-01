import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart' show PackageInfo;
import 'package:tts_mod_vault/src/changelog.dart' show showChangelogDialog;
import 'package:tts_mod_vault/src/utils.dart'
    show
        checkForUpdatesOnGitHub,
        kofiUrl,
        nexusModsDownloadPageUrl,
        openUrl,
        showDownloadLatestVersionDialog,
        showSnackBar,
        steamDiscussionUrl;

Future<void> showHelpDialog(BuildContext context) async {
  final packageInfo = await PackageInfo.fromPlatform();

  if (!context.mounted) return;

  showDialog(
    context: context,
    builder: (BuildContext context) {
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
        child: AlertDialog(
          title: Text(
            'TTS Mod Vault v${packageInfo.version}',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          content: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              spacing: 8,
              children: [
                _HelpListTile(
                  icon: Icons.forum_outlined,
                  title: 'Help & Feedback',
                  onTap: () async {
                    final result = await openUrl(steamDiscussionUrl);
                    if (!result && context.mounted) {
                      showSnackBar(
                          context, "Failed to open: $steamDiscussionUrl");
                      Navigator.of(context).pop();
                    }
                  },
                ),
                _HelpListTile(
                  icon: Icons.update,
                  title: 'Check for updates',
                  onTap: () async {
                    final newTagVersion = await checkForUpdatesOnGitHub();

                    if (newTagVersion.isNotEmpty) {
                      if (!context.mounted) return;

                      await showDownloadLatestVersionDialog(
                        context,
                        packageInfo.version,
                        newTagVersion,
                      );
                    } else {
                      if (context.mounted) {
                        showSnackBar(context, 'No new updates found');
                        Navigator.of(context).pop();
                      }
                    }
                  },
                ),
                _HelpListTile(
                  icon: Icons.article_outlined,
                  title: 'Changelog',
                  onTap: () {
                    showChangelogDialog(context);
                  },
                ),
                _HelpListTile(
                  icon: Icons.thumb_up_outlined,
                  title: 'Endorse on NexusMods',
                  onTap: () async {
                    final result = await openUrl(nexusModsDownloadPageUrl);
                    if (!result && context.mounted) {
                      showSnackBar(
                          context, "Failed to open: $nexusModsDownloadPageUrl");
                      Navigator.of(context).pop();
                    }
                  },
                ),
                _HelpListTile(
                  icon: Icons.favorite,
                  title: 'Support on Ko-fi',
                  onTap: () async {
                    final result = await openUrl(kofiUrl);
                    if (!result && context.mounted) {
                      showSnackBar(context, "Failed to open: $kofiUrl");
                      Navigator.of(context).pop();
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    },
  );
}

class _HelpListTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _HelpListTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(
        title,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      onTap: onTap,
      dense: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}
