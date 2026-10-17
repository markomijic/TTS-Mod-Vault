import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/theme/vault_colors.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/library/application/library_view_providers.dart';
import 'package:tts_mod_vault/features/library/presentation/library_labels.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// The right column of the Mods page.
///
/// Phase 1 placeholder: a header with the selected mod's name ("Select a
/// mod" / "N mods selected" otherwise) and a per-type asset count summary.
/// Phase 2 fills the body with the asset list and actions.
class SelectedModPanel extends ConsumerWidget {
  /// Creates the panel.
  const SelectedModPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final type = ref.watch(selectedModTypeProvider);
    final selectedCount = ref.watch(selectionProvider.select((s) => s.length));
    final mod = ref.watch(selectedModProvider);

    final title = switch ((selectedCount, mod)) {
      (_, final Mod mod) => mod.displayName,
      (>= 2, null) => l10n.selectedCount(selectedCount, type.plural(l10n)),
      _ => l10n.selectAMod(type.singular(l10n)),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PanelHeader(title: title),
        Expanded(
          child: switch ((selectedCount, mod)) {
            (_, final Mod mod) => _AssetSummaryView(mod: mod),
            (>= 2, null) => const _MultiSelectionView(),
            _ => const SizedBox.shrink(),
          },
        ),
      ],
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Insets.lg,
          Insets.lg,
          Insets.lg,
          Insets.md,
        ),
        child: Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleLarge,
        ),
      ),
    );
  }
}

/// Present / total per asset type for one mod.
class _AssetSummaryView extends StatelessWidget {
  const _AssetSummaryView({required this.mod});

  final Mod mod;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = VaultColors.of(context);
    final summary = mod.summary;
    final types = [
      for (final type in AssetType.values)
        if (summary.totalOf(type) > 0) type,
    ];

    Color countColor(int present, int total) =>
        present >= total ? colors.assetPresent : colors.assetMissing;

    if (types.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(Insets.lg),
        child: Text(
          l10n.assetsNone,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(Insets.lg),
      children: [
        for (final type in types)
          _CountRow(
            label: type.label(l10n),
            value: l10n.presentOfTotal(
              summary.presentOf(type),
              summary.totalOf(type),
            ),
            color: countColor(summary.presentOf(type), summary.totalOf(type)),
          ),
        const Divider(),
        _CountRow(
          label: l10n.assetsSummaryTotal,
          value: l10n.presentOfTotal(summary.present, summary.total),
          color: countColor(summary.present, summary.total),
          emphasised: true,
        ),
      ],
    );
  }
}

class _CountRow extends StatelessWidget {
  const _CountRow({
    required this.label,
    required this.value,
    required this.color,
    this.emphasised = false,
  });

  final String label;
  final String value;
  final Color color;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final style = emphasised ? textTheme.titleMedium : textTheme.bodyLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Insets.xs),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(
            value,
            style: style?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Names of the selected mods while two or more are selected.
class _MultiSelectionView extends ConsumerWidget {
  const _MultiSelectionView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mods = ref.watch(selectedModsProvider);
    return ListView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: Insets.lg,
        vertical: Insets.sm,
      ),
      itemCount: mods.length,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.symmetric(vertical: Insets.xs),
        child: Text(
          mods[index].displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
