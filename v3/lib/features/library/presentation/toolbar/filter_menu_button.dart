import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/library/application/library_view_providers.dart';
import 'package:tts_mod_vault/features/library/presentation/library_labels.dart';
import 'package:tts_mod_vault/features/library/presentation/library_view_options.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Filter menu with three sections (folders, backup state, assets) as
/// checkbox items, a badge with the number of active filters and a
/// "Clear all filters" item. The missing/complete exclusion is enforced by
/// `ModFilterController.toggleAssetFilter`. The backup state section is
/// hidden while the backup badge is hidden (2.x behaviour).
class FilterMenuButton extends ConsumerWidget {
  /// Creates the button.
  const FilterMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final filter = ref.watch(modFilterProvider);
    final folders = ref.watch(availableFoldersProvider);
    final showBackupState = ref.watch(
      libraryViewOptionsProvider.select((o) => o.showBackupState),
    );
    final notifier = ref.read(modFilterProvider.notifier);
    final activeCount =
        filter.folders.length +
        filter.backupStatuses.length +
        filter.assetFilters.length;

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
        if (showBackupState) ...[
          const Divider(),
          _SectionHeader(l10n.filterSectionBackupState),
          for (final status in BackupStatus.values)
            CheckboxMenuButton(
              value: filter.backupStatuses.contains(status),
              closeOnActivate: false,
              onChanged: (_) => notifier.toggleBackupStatus(status),
              child: Text(status.label(l10n)),
            ),
        ],
        const Divider(),
        _SectionHeader(l10n.filterSectionAssets),
        for (final assetFilter in AssetFilter.values)
          CheckboxMenuButton(
            value: filter.assetFilters.contains(assetFilter),
            closeOnActivate: false,
            onChanged: (_) => notifier.toggleAssetFilter(assetFilter),
            child: Text(assetFilter.label(l10n)),
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
