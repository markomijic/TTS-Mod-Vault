import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/features/asset_detail/application/asset_detail_filter.dart';
import 'package:tts_mod_vault/features/asset_detail/presentation/asset_detail_view_options.dart';
import 'package:tts_mod_vault/features/asset_detail/presentation/multi_select_view.dart';
import 'package:tts_mod_vault/features/asset_detail/presentation/selected_mod_header.dart';
import 'package:tts_mod_vault/features/asset_detail/presentation/selected_mod_view.dart';
import 'package:tts_mod_vault/features/library/application/library_view_providers.dart';
import 'package:tts_mod_vault/features/library/presentation/library_labels.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// The right column of the Mods page.
///
/// Dispatches on the selection: two or more mods → [MultiSelectView], one
/// → [SelectedModView], none → a "Select a mod" header with the help icon.
/// Whenever the selected mod's path changes the asset filters and the URL
/// highlight are reset, so a search or chip from one mod never leaks into
/// the next (2.x reset them in a `useEffect` keyed on the path).
class SelectedModPanel extends ConsumerWidget {
  /// Creates the panel.
  const SelectedModPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(selectedModProvider.select((mod) => mod?.jsonPath), (
      previous,
      next,
    ) {
      if (previous == next) return;
      ref.read(assetDetailFilterProvider.notifier).reset();
      ref.read(selectedAssetUrlProvider.notifier).clear();
    });

    final selectedCount = ref.watch(
      selectedModsProvider.select((mods) => mods.length),
    );
    if (selectedCount >= 2) return const MultiSelectView();

    final mod = ref.watch(selectedModProvider);
    if (mod == null) return const _EmptySelection();

    return SelectedModView(key: ValueKey(mod.jsonPath), mod: mod);
  }
}

/// "Select a mod" header with the help icon and an empty body.
class _EmptySelection extends ConsumerWidget {
  const _EmptySelection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final type = ref.watch(selectedModTypeProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelectedModHeader(title: l10n.selectAMod(type.singular(l10n))),
      ],
    );
  }
}
