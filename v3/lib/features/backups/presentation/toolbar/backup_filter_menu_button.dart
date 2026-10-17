import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/backups/presentation/backup_labels.dart';
import 'package:tts_mod_vault/features/library/application/backup_view_providers.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Filter menu of the Backups tab: folders and matching-mod state as
/// checkbox items, a badge with the number of active filters and a "Clear
/// all filters" item.
class BackupFilterMenuButton extends ConsumerWidget {
  /// Creates the button.
  const BackupFilterMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final filter = ref.watch(backupFilterProvider);
    final folders = ref.watch(availableBackupFoldersProvider);
    final notifier = ref.read(backupFilterProvider.notifier);
    final activeCount = filter.folders.length + filter.match.length;

    return MenuAnchor(
      builder: (context, controller, _) => Badge.count(
        count: activeCount,
        isLabelVisible: activeCount > 0,
        child: OutlinedButton.icon(
          onPressed: controller.isOpen ? controller.close : controller.open,
          icon: const Icon(Icons.filter_list),
          label: Text(l10n.filters),
        ),
      ),
      menuChildren: [
        _SectionHeader(l10n.filterSectionFolders),
        if (folders.isEmpty)
          MenuItemButton(child: Text(l10n.filterNoFolders))
        else ...[
          for (final folder in folders)
            CheckboxMenuButton(
              value: filter.folders.contains(folder),
              closeOnActivate: false,
              onChanged: (_) => notifier.toggleFolder(folder),
              child: Text(folder),
            ),
          MenuItemButton(
            closeOnActivate: false,
            leadingIcon: const Icon(Icons.clear),
            onPressed: filter.folders.isEmpty
                ? null
                : () {
                    for (final folder in filter.folders.toList()) {
                      notifier.toggleFolder(folder);
                    }
                  },
            child: Text(l10n.filterClearFolders),
          ),
        ],
        const Divider(),
        _SectionHeader(l10n.filterSectionMatchingMod),
        for (final match in BackupMatchFilter.values)
          CheckboxMenuButton(
            value: filter.match.contains(match),
            closeOnActivate: false,
            onChanged: (_) => notifier.toggleMatch(match),
            child: Text(match.label(l10n)),
          ),
        const Divider(),
        MenuItemButton(
          leadingIcon: const Icon(Icons.filter_list_off),
          onPressed: filter.hasFilters ? notifier.clearFilters : null,
          child: Text(l10n.filterClearAll),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.md,
        Insets.sm,
        Insets.md,
        Insets.xs,
      ),
      child: Text(
        title,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
