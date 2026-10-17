import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/features/library/presentation/library_view_options.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Switches between the grid and the list; the choice is persisted by
/// `LibraryViewOptionsController`. The mod tabs share one flag
/// (`useListView`), the Backups tab has its own (`useBackupsListView`).
class ViewToggleButton extends ConsumerWidget {
  /// Creates the button.
  const ViewToggleButton({super.key, this.backups = false});

  /// Whether the button drives the Backups tab's flag.
  final bool backups;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final useList = ref.watch(
      libraryViewOptionsProvider.select(
        (o) => backups ? o.useBackupsListView : o.useListView,
      ),
    );
    final notifier = ref.read(libraryViewOptionsProvider.notifier);
    return IconButton.outlined(
      tooltip: useList ? l10n.viewAsGrid : l10n.viewAsList,
      icon: Icon(useList ? Icons.grid_view_outlined : Icons.view_list_outlined),
      onPressed: backups
          ? notifier.toggleBackupsListView
          : notifier.toggleListView,
    );
  }
}
