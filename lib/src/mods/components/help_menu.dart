import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show ConsumerWidget, WidgetRef;
import 'package:package_info_plus/package_info_plus.dart' show PackageInfo;
import 'package:tts_mod_vault/src/changelog.dart' show showChangelogDialog;
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show RenameOldBackupsDialog;
import 'package:tts_mod_vault/src/state/provider.dart'
    show actionInProgressProvider;

import 'package:tts_mod_vault/src/utils.dart'
    show
        checkForUpdatesOnGitHub,
        showDownloadDialog,
        showSnackBar,
        openUrl,
        steamDiscussionUrl;

class HelpMenu extends ConsumerWidget {
  const HelpMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actionInProgress = ref.watch(actionInProgressProvider);

    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStateProperty.all(Colors.black),
      ),
      menuChildren: <Widget>[
        MenuItemButton(
          style: MenuItemButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
          ),
          leadingIcon: Icon(Icons.update, color: Colors.black),
          child:
              Text('Check for updates', style: TextStyle(color: Colors.black)),
          onPressed: () async {
            final newTagVersion = await checkForUpdatesOnGitHub();

            if (newTagVersion.isNotEmpty) {
              final packageInfo = await PackageInfo.fromPlatform();
              final currentVersion = packageInfo.version;

              if (!context.mounted) return;

              await showDownloadDialog(context, currentVersion, newTagVersion);
            } else {
              if (context.mounted) {
                showSnackBar(context, 'No new updates found');
              }
            }
          },
        ),
        MenuItemButton(
          style: MenuItemButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
          ),
          onPressed: () => showChangelogDialog(context),
          leadingIcon: Icon(Icons.article, color: Colors.black),
          child: Text('Changelog', style: TextStyle(color: Colors.black)),
        ),
        MenuItemButton(
          style: MenuItemButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
          ),
          onPressed: actionInProgress
              ? null
              : () => showDialog(
                    context: context,
                    builder: (context) => RenameOldBackupsDialog(),
                  ),
          leadingIcon: Icon(Icons.edit, color: Colors.black),
          child: Text(
            'Rename old backups',
            style: TextStyle(color: Colors.black),
          ),
        ),
        MenuItemButton(
          style: MenuItemButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
          ),
          leadingIcon: Icon(Icons.help_outline, color: Colors.black),
          child: Text('Help & Feedback', style: TextStyle(color: Colors.black)),
          onPressed: () async {
            final result = await openUrl(steamDiscussionUrl);
            if (!result && context.mounted) {
              showSnackBar(context, "Failed to open: $steamDiscussionUrl");
            }
          },
        ),
      ],
      builder: (
        BuildContext context,
        MenuController controller,
        Widget? child,
      ) {
        return ElevatedButton.icon(
          onPressed: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
          label: Text('Help'),
          icon: Icon(Icons.help_outline),
        );
      },
    );
  }
}
