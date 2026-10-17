import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/features/library/presentation/library_view_options.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Switches between the grid and the list; the choice is persisted by
/// `LibraryViewOptionsController`.
class ViewToggleButton extends ConsumerWidget {
  /// Creates the button.
  const ViewToggleButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final useList = ref.watch(
      libraryViewOptionsProvider.select((o) => o.useListView),
    );
    return IconButton.outlined(
      tooltip: useList ? l10n.viewAsGrid : l10n.viewAsList,
      icon: Icon(useList ? Icons.grid_view_outlined : Icons.view_list_outlined),
      onPressed: ref.read(libraryViewOptionsProvider.notifier).toggleListView,
    );
  }
}
