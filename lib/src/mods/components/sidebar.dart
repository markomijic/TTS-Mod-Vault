import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useRef, useState;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show DownloadModByIdDialog, ImportJsonDialog;
import 'package:tts_mod_vault/src/settings/settings_dialog.dart'
    show SettingsDialog;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        actionInProgressProvider,
        cleanupProvider,
        importBackupProvider,
        loaderProvider,
        settingsProvider;
import 'package:tts_mod_vault/src/utils.dart'
    show
        showConfirmDialog,
        showSnackBar,
        checkForUpdatesOnGitHub,
        showDownloadDialog,
        openUrl,
        steamDiscussionUrl,
        showConfirmDialogWithCheckbox;
import 'package:tts_mod_vault/src/changelog.dart' show showChangelogDialog;
import 'package:package_info_plus/package_info_plus.dart' show PackageInfo;

class Sidebar extends HookConsumerWidget {
  final double width;
  const Sidebar({super.key, required this.width});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isHovered = useState(false);
    final hoverTimer = useRef<Timer?>(null);

    final actionInProgress = ref.watch(actionInProgressProvider);
    final scaffoldBackgroundColor = Theme.of(context).scaffoldBackgroundColor;

    return MouseRegion(
      onEnter: (_) {
        hoverTimer.value?.cancel();
        hoverTimer.value = Timer(
          const Duration(milliseconds: 300),
          () => isHovered.value = true,
        );
      },
      onExit: (_) {
        hoverTimer.value?.cancel();
        isHovered.value = false;
      },
      child: Container(
        width: isHovered.value ? 270 : width,
        decoration: BoxDecoration(
          gradient: isHovered.value
              ? LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    scaffoldBackgroundColor,
                    scaffoldBackgroundColor.withValues(alpha: 0.9),
                    scaffoldBackgroundColor.withValues(alpha: 0.9),
                    scaffoldBackgroundColor.withValues(alpha: 0.7),
                    scaffoldBackgroundColor.withValues(alpha: 0),
                  ],
                )
              : null,
          color: isHovered.value ? null : scaffoldBackgroundColor,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            const Spacer(),
            _SidebarItem(
              icon: Icons.extension_sharp,
              label: 'Mods',
              isExpanded: isHovered.value,
              isDisabled: actionInProgress,
              onPressed: () => showConfirmDialog(
                context,
                'Are you sure you want to refresh data for all mods?',
                () async {
                  await ref.read(loaderProvider).refreshAppData();
                },
              ),
            ),
            _SidebarItem(
              icon: Icons.folder_zip,
              label: 'Backups',
              isExpanded: isHovered.value,
              isDisabled: actionInProgress,
              onPressed: () => showConfirmDialog(
                context,
                'Are you sure you want to refresh data for all mods?',
                () async {
                  await ref.read(loaderProvider).refreshAppData();
                },
              ),
            ),
            _GradientDivider(isExpanded: isHovered.value),
            _SidebarItem(
              icon: Icons.refresh,
              label: 'Refresh',
              isExpanded: isHovered.value,
              isDisabled: actionInProgress,
              onPressed: () => showConfirmDialogWithCheckbox(
                context,
                message: 'Refresh all data?',
                onConfirm: (checkboxValue) async => await ref
                    .read(loaderProvider)
                    .refreshAppData(checkboxValue),
                checkboxInfoMessage:
                    'This option reloads everything from your files instead of using saved information from cache\n\nIt will take longer depending on number of items to load',
                checkboxLabel: "Clear Vault cache",
              ),
            ),
            _SidebarItem(
              icon: Icons.delete_sweep,
              label: 'Cleanup',
              isExpanded: isHovered.value,
              isDisabled: actionInProgress,
              onPressed: () async {
                final cleanupNotifier = ref.read(cleanupProvider.notifier);
                await cleanupNotifier.startCleanup(
                  (count) {
                    if (count > 0) {
                      final itemTypes =
                          ref.read(settingsProvider).showSavedObjects
                              ? "mods, saves and saved objects"
                              : "mods and saves";

                      showConfirmDialog(
                        context,
                        '$count files found that are not used by any of your $itemTypes.\nAre you sure you want to delete them?',
                        () async {
                          await cleanupNotifier.executeDelete();
                        },
                        () {
                          cleanupNotifier.resetState();
                        },
                      );
                    } else {
                      showSnackBar(context, 'No files found to delete');
                    }
                  },
                );
              },
            ),
            _GradientDivider(isExpanded: isHovered.value),
            _SidebarItem(
              icon: Icons.unarchive,
              label: 'Import backup',
              isExpanded: isHovered.value,
              isDisabled: actionInProgress,
              onPressed: () async {
                await ref.read(importBackupProvider.notifier).importBackup();
              },
            ),
            _SidebarItem(
              icon: Icons.upload_file,
              label: 'Import JSON',
              isExpanded: isHovered.value,
              isDisabled: actionInProgress,
              onPressed: () => showDialog(
                context: context,
                builder: (context) => ImportJsonDialog(
                  onConfirm: (jsonFilePath, destinationFolder, modType) {
                    ref.read(importBackupProvider.notifier).importJson(
                          jsonFilePath,
                          destinationFolder,
                          modType,
                        );
                  },
                ),
              ),
            ),
            _SidebarItem(
              icon: Icons.download,
              label: 'Download Workshop Mod',
              isExpanded: isHovered.value,
              isDisabled: actionInProgress,
              onPressed: () => showDialog(
                context: context,
                builder: (context) => DownloadModByIdDialog(),
              ),
            ),
            _GradientDivider(isExpanded: isHovered.value),
            _SidebarItem(
              icon: Icons.update,
              label: 'Check for updates',
              isExpanded: isHovered.value,
              isDisabled: actionInProgress,
              onPressed: () async {
                final newTagVersion = await checkForUpdatesOnGitHub();

                if (newTagVersion.isNotEmpty) {
                  final packageInfo = await PackageInfo.fromPlatform();
                  final currentVersion = packageInfo.version;

                  if (!context.mounted) return;

                  await showDownloadDialog(
                      context, currentVersion, newTagVersion);
                } else {
                  if (context.mounted) {
                    showSnackBar(context, 'No new updates found');
                  }
                }
              },
            ),
            _SidebarItem(
              icon: Icons.article,
              label: 'Changelog',
              isExpanded: isHovered.value,
              isDisabled: actionInProgress,
              onPressed: () => showChangelogDialog(context),
            ),
            _GradientDivider(isExpanded: isHovered.value),
            _SidebarItem(
              icon: Icons.help_outline,
              label: 'Help & Feedback',
              isExpanded: isHovered.value,
              isDisabled: false,
              onPressed: () async {
                final result = await openUrl(steamDiscussionUrl);
                if (!result && context.mounted) {
                  showSnackBar(context, "Failed to open: $steamDiscussionUrl");
                }
              },
            ),
            _SidebarItem(
              icon: Icons.settings,
              label: 'Settings',
              isExpanded: isHovered.value,
              isDisabled: actionInProgress,
              onPressed: () => showDialog(
                context: context,
                builder: (context) => SettingsDialog(),
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isExpanded;
  final bool isDisabled;
  final VoidCallback onPressed;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.isExpanded,
    required this.isDisabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: isDisabled ? null : onPressed,
          child: Row(
            spacing: 4,
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              const SizedBox.shrink(),
              Icon(
                icon,
                size: 32,
                color: isDisabled
                    ? Theme.of(context).disabledColor
                    : Theme.of(context).colorScheme.onSurface,
              ),
              if (isExpanded)
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    color: isDisabled
                        ? Theme.of(context).disabledColor
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GradientDivider extends StatelessWidget {
  final bool isExpanded;

  const _GradientDivider({required this.isExpanded});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
          gradient: isExpanded
              ? LinearGradient(
                  colors: [
                    Colors.white,
                    Colors.white.withAlpha(128),
                    Colors.transparent,
                  ],
                )
              : null,
          color: isExpanded ? null : Colors.white),
    );
  }
}
