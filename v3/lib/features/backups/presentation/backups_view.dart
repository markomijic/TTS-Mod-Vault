import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_hooks/flutter_hooks.dart' show useScrollController;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/backups/presentation/backup_grid_card.dart';
import 'package:tts_mod_vault/features/backups/presentation/backup_list_item.dart';
import 'package:tts_mod_vault/features/library/application/backup_view_providers.dart';
import 'package:tts_mod_vault/features/library/presentation/library_view_options.dart';
import 'package:tts_mod_vault/features/startup/application/directories_controller.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Widest a card gets; the delegate fits as many as the width allows.
const double _maxCardExtent = 200;

/// How far beyond the viewport cards are built, in logical pixels.
const ScrollCacheExtent _gridCacheExtent = ScrollCacheExtent.pixels(400);

/// How far beyond the viewport rows are built, in logical pixels.
const ScrollCacheExtent _listCacheExtent = ScrollCacheExtent.pixels(300);

/// Shows the filtered backups as a grid or a list, or one of two hints when
/// the list is empty: "no match" when a search text or filter is active,
/// "nothing found in `<folder>`" otherwise.
class BackupsView extends ConsumerWidget {
  /// Creates the view.
  const BackupsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backups = ref.watch(filteredBackupsProvider);
    final useList = ref.watch(
      libraryViewOptionsProvider.select((o) => o.useBackupsListView),
    );
    if (backups.isEmpty) {
      return const Center(
        child: Padding(padding: EdgeInsets.all(Insets.xl), child: _EmptyHint()),
      );
    }
    return useList
        ? BackupsList(backups: backups)
        : BackupsGrid(backups: backups);
  }
}

/// The backup grid: `GridView.builder` over the filtered backups, one
/// [BackupGridCard] per backup keyed by its path.
class BackupsGrid extends HookConsumerWidget {
  /// Creates the grid for [backups].
  const BackupsGrid({super.key, required this.backups});

  /// The backups to show, already filtered and sorted.
  final List<Backup> backups;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = useScrollController();
    return Scrollbar(
      controller: controller,
      thumbVisibility: true,
      child: GridView.builder(
        controller: controller,
        padding: const EdgeInsets.only(right: Insets.md, bottom: Insets.sm),
        scrollCacheExtent: _gridCacheExtent,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: _maxCardExtent,
          mainAxisSpacing: Insets.sm,
          crossAxisSpacing: Insets.sm,
        ),
        itemCount: backups.length,
        itemBuilder: (context, index) {
          final backup = backups[index];
          return BackupGridCard(key: ValueKey(backup.path), backup: backup);
        },
      ),
    );
  }
}

/// The backup list: `ListView.builder` over the filtered backups, one
/// [BackupListItem] per backup keyed by its path.
class BackupsList extends HookConsumerWidget {
  /// Creates the list for [backups].
  const BackupsList({super.key, required this.backups});

  /// The backups to show, already filtered and sorted.
  final List<Backup> backups;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = useScrollController();
    return Scrollbar(
      controller: controller,
      thumbVisibility: true,
      child: ListView.builder(
        controller: controller,
        padding: const EdgeInsets.only(right: Insets.md, bottom: Insets.sm),
        scrollCacheExtent: _listCacheExtent,
        itemExtent: backupListItemExtent,
        itemCount: backups.length,
        itemBuilder: (context, index) {
          final backup = backups[index];
          return BackupListItem(key: ValueKey(backup.path), backup: backup);
        },
      ),
    );
  }
}

/// "No backups match the current filters" or "No backups found in
/// `<folder>`".
class _EmptyHint extends ConsumerWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final filtered = ref.watch(
      backupFilterProvider.select((f) => f.isNotEmpty),
    );
    final String text;
    if (filtered) {
      text = l10n.noBackupsMatchFilters;
    } else {
      final folder = ref.watch(
        directoriesProvider.select((d) => d.value?.backupsDir ?? ''),
      );
      text = l10n.noBackupsFound(folder);
    }
    return Text(
      text,
      textAlign: TextAlign.center,
      style: theme.textTheme.bodyLarge?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
