import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/widgets/app_snack_bar.dart';
import 'package:tts_mod_vault/features/library/application/library_view_providers.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// "Bulk actions (N)" where N is the number of mods the actions would
/// apply to: the selection when two or more are selected, otherwise every
/// mod that passes the current search and filters.
///
/// Phase 1 stub: pressing it shows the not-implemented snack bar; Phase 5
/// replaces the callback with the bulk actions menu.
class BulkActionsButton extends ConsumerWidget {
  /// Creates the button.
  const BulkActionsButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final selectedCount = ref.watch(selectionProvider.select((s) => s.length));
    final filteredCount = ref.watch(
      filteredModsProvider.select((mods) => mods.length),
    );
    final count = selectedCount >= 2 ? selectedCount : filteredCount;

    return FilledButton.tonalIcon(
      onPressed: () => showAppSnackBar(context, l10n.notImplementedYet),
      icon: const Icon(Icons.checklist),
      label: Text(l10n.bulkActions(count)),
    );
  }
}
