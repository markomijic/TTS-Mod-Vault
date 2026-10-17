import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/features/library/application/library_view_providers.dart';
import 'package:tts_mod_vault/features/library/presentation/library_view_options.dart';
import 'package:tts_mod_vault/features/library/presentation/mods_grid.dart';
import 'package:tts_mod_vault/features/library/presentation/mods_list.dart';

/// Shows the filtered mods as a grid or a list, or one of two hints when
/// the list is empty: "no match" when a search text or filter is active,
/// "nothing found in `<folder>`" otherwise.
class ModsView extends ConsumerWidget {
  /// Creates the view.
  const ModsView({super.key, required this.emptyHintBuilder});

  /// Builds the centred hint shown when [filteredModsProvider] is empty.
  final WidgetBuilder emptyHintBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mods = ref.watch(filteredModsProvider);
    final useList = ref.watch(
      libraryViewOptionsProvider.select((o) => o.useListView),
    );
    if (mods.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Insets.xl),
          child: emptyHintBuilder(context),
        ),
      );
    }
    return useList ? ModsList(mods: mods) : ModsGrid(mods: mods);
  }
}
