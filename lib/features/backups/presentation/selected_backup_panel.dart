import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/shell/operation_running_provider.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/asset_detail/presentation/selected_mod_header.dart';
import 'package:tts_mod_vault/features/backups/presentation/backup_actions.dart';
import 'package:tts_mod_vault/features/backups/presentation/backup_badges.dart';
import 'package:tts_mod_vault/features/backups/presentation/backup_context_menu.dart';
import 'package:tts_mod_vault/features/library/application/backup_view_providers.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';
import 'package:tts_mod_vault/features/library/application/library_tab.dart';
import 'package:tts_mod_vault/features/library/application/library_view_providers.dart';
import 'package:tts_mod_vault/features/library/presentation/item_actions.dart';
import 'package:tts_mod_vault/features/library/presentation/mod_badges.dart'
    show formatModDate;
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// The right column of the library page while the Backups tab is shown.
///
/// Dispatches on the backup selection: two or more backups → the
/// multi-select summary, one → [SelectedBackupView], none → a "Select a
/// backup" header.
class SelectedBackupPanel extends ConsumerWidget {
  /// Creates the panel.
  const SelectedBackupPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final selected = ref.watch(selectedBackupsProvider);
    if (selected.length >= 2) return _MultiSelectView(backups: selected);

    final backup = ref.watch(selectedBackupProvider);
    if (backup == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelectedModHeader(title: l10n.selectABackup, showHelp: false),
        ],
      );
    }
    return SelectedBackupView(key: ValueKey(backup.path), backup: backup);
  }
}

/// Header, details and actions of one backup.
class SelectedBackupView extends ConsumerWidget {
  /// Creates the view for [backup].
  const SelectedBackupView({super.key, required this.backup});

  /// The selected backup.
  final Backup backup;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final matchingPath = backup.matchingModPath;
    final matchingMod = matchingPath == null
        ? null
        : ref.watch(
            libraryControllerProvider.select(
              (s) => s.value?.modByPath(matchingPath),
            ),
          );

    void showMod() {
      if (matchingMod == null) return;
      ref
          .read(libraryTabProvider.notifier)
          .set(LibraryTab.forType(matchingMod.ref.type));
      ref.read(selectionProvider.notifier).select(matchingMod.jsonPath);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelectedModHeader(title: backup.fileName, showHelp: false),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(
              horizontal: Insets.lg,
              vertical: Insets.sm,
            ),
            children: [
              _DetailRow(
                label: l10n.backupDetailFolder,
                value: Text(backup.folder),
              ),
              _DetailRow(
                label: l10n.backupDetailPath,
                value: SelectableText(backup.path),
              ),
              _DetailRow(
                label: l10n.backupDetailSize,
                value: Text(backup.fileSizeLabel),
              ),
              _DetailRow(
                label: l10n.backupDetailModified,
                value: Text(formatModDate(l10n.localeName, backup.modified)),
              ),
              _DetailRow(
                label: l10n.backupDetailAssets,
                value: Text('${backup.assetCount}'),
              ),
              _DetailRow(
                label: l10n.backupDetailMatchingMod,
                value: _MatchingModValue(
                  backup: backup,
                  mod: matchingMod,
                  onShowMod: showMod,
                ),
              ),
            ],
          ),
        ),
        _BackupActions(backup: backup),
      ],
    );
  }
}

/// Label over value, as the asset detail view lays out its summary rows.
class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Insets.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Gaps.h4,
          DefaultTextStyle.merge(
            style: theme.textTheme.bodyMedium,
            child: value,
          ),
        ],
      ),
    );
  }
}

/// The matching mod's name with the badge colour and a "Show mod" button,
/// or "No matching mod".
class _MatchingModValue extends StatelessWidget {
  const _MatchingModValue({
    required this.backup,
    required this.mod,
    required this.onShowMod,
  });

  final Backup backup;
  final Mod? mod;
  final VoidCallback onShowMod;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final mod = this.mod;
    final icon = BackupMatchBadge(backup: backup);
    if (mod == null) {
      return Row(
        children: [
          icon,
          Gaps.w8,
          Expanded(
            child: Text(
              l10n.backupMatchNoMod,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        icon,
        Gaps.w8,
        Expanded(
          child: Text(
            mod.displayName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Gaps.w8,
        TextButton.icon(
          onPressed: onShowMod,
          icon: const Icon(Icons.arrow_outward),
          label: Text(l10n.showMod),
        ),
      ],
    );
  }
}

/// The action buttons at the bottom of the view: the context-menu items
/// (import, open, copy, rename, delete).
class _BackupActions extends ConsumerWidget {
  const _BackupActions({required this.backup});

  final Backup backup;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final running = ref.watch(operationRunningProvider);

    VoidCallback? guard(VoidCallback action) => running ? null : action;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.lg,
        Insets.sm,
        Insets.sm,
        Insets.sm,
      ),
      child: Wrap(
        spacing: Insets.sm,
        runSpacing: Insets.sm,
        children: [
          FilledButton.tonalIcon(
            onPressed: guard(() => importBackup(context, ref, backup)),
            icon: const Icon(Icons.unarchive_outlined),
            label: Text(l10n.menuImportBackup),
          ),
          FilledButton.tonalIcon(
            onPressed: guard(() => revealInFileExplorer(context, backup.path)),
            icon: const Icon(Icons.folder_open_outlined),
            label: Text(l10n.menuOpenInFileExplorer),
          ),
          FilledButton.tonalIcon(
            onPressed: guard(
              () => copyTextToClipboard(context, backupCopyName(backup)),
            ),
            icon: const Icon(Icons.file_copy_outlined),
            label: Text(l10n.menuCopyFilename),
          ),
          FilledButton.tonalIcon(
            onPressed: guard(() => renameBackupWithDialog(context, backup)),
            icon: const Icon(Icons.drive_file_rename_outline),
            label: Text(l10n.menuRenameBackup),
          ),
          FilledButton.tonalIcon(
            onPressed: guard(
              () => deleteBackupWithConfirm(context, ref, backup),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: scheme.errorContainer,
              foregroundColor: scheme.onErrorContainer,
            ),
            icon: const Icon(Icons.delete_outline),
            label: Text(l10n.menuDeleteBackup),
          ),
        ],
      ),
    );
  }
}

/// "N backups selected" and their names.
class _MultiSelectView extends StatelessWidget {
  const _MultiSelectView({required this.backups});

  final List<Backup> backups;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelectedModHeader(
          title: l10n.selectedBackupsCount(backups.length),
          showHelp: false,
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(
              horizontal: Insets.lg,
              vertical: Insets.sm,
            ),
            itemCount: backups.length,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.symmetric(vertical: Insets.xs),
              child: Text(
                backups[index].fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
