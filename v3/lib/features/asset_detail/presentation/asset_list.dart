import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/shell/operation_running_provider.dart'
    show operationRunningProvider;
import 'package:tts_mod_vault/app/widgets/error_message.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/app/widgets/progress_message.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/asset_detail/application/asset_detail_filter.dart';
import 'package:tts_mod_vault/features/asset_detail/presentation/asset_url_row.dart';
import 'package:tts_mod_vault/features/asset_detail/presentation/pdf_thumbnail.dart';
import 'package:tts_mod_vault/features/downloads/presentation/download_actions.dart';
import 'package:tts_mod_vault/features/images_viewer/presentation/images_viewer_page.dart';
import 'package:tts_mod_vault/features/library/presentation/library_labels.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Size of the icon buttons in a group header.
const double _headerIconSize = 18;

/// Hit target of the icon buttons in a group header.
const double _headerButtonSize = 28;

/// One row of the asset list. The list is a flat, pre-computed
/// `List<AssetListRow>` so `ListView.builder` gets the real item count and
/// every row is a real widget: filtered-out assets are not in the list at
/// all (2.x returned `SizedBox.shrink()` for them).
sealed class AssetListRow {
  const AssetListRow();
}

/// Group header: the type label plus its action icons.
final class HeaderRow extends AssetListRow {
  /// Creates a header.
  const HeaderRow({
    required this.type,
    required this.hasMissing,
    required this.isFirst,
  });

  /// The asset type of the group.
  final AssetType type;

  /// Whether any asset of the group is not on disk (shows the download icon).
  final bool hasMissing;

  /// Whether this is the first header in the list (no top padding). Known
  /// at build time, so it costs O(1) instead of the 2.x O(n) look-back.
  final bool isFirst;
}

/// One URL line.
final class UrlRow extends AssetListRow {
  /// Creates a URL row.
  const UrlRow(this.asset);

  /// The asset shown.
  final Asset asset;
}

/// The thumbnails of a PDF group, rendered as one wrapping row.
final class PdfGridRow extends AssetListRow {
  /// Creates a thumbnail row.
  const PdfGridRow(this.assets);

  /// The PDFs shown.
  final List<Asset> assets;
}

/// Flattens [groups] into rows: a [HeaderRow] per group followed by a
/// [UrlRow] per asset, except that a PDF group becomes a single
/// [PdfGridRow] while [showPdfThumbnails] is on. Groups with no assets
/// (everything filtered out) produce nothing.
List<AssetListRow> buildAssetListRows(
  List<AssetGroup> groups, {
  required bool showPdfThumbnails,
}) {
  final rows = <AssetListRow>[];
  for (final group in groups) {
    if (group.assets.isEmpty) continue;
    rows.add(
      HeaderRow(
        type: group.type,
        hasMissing: group.missing > 0,
        isFirst: rows.isEmpty,
      ),
    );
    if (group.type == AssetType.pdf && showPdfThumbnails) {
      rows.add(PdfGridRow(group.assets));
    } else {
      for (final asset in group.assets) {
        rows.add(UrlRow(asset));
      }
    }
  }
  return rows;
}

/// The grouped, filtered asset list of [mod].
///
/// Reads `groupedModAssetsProvider`, shows a [ProgressMessage] while the
/// assets load and an [ErrorMessage] when reading them failed.
class AssetList extends ConsumerWidget {
  /// Creates the list for [mod].
  const AssetList({super.key, required this.mod});

  /// The selected mod.
  final Mod mod;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final groups = ref.watch(groupedModAssetsProvider(mod.jsonPath));
    final showPdfThumbnails = ref.watch(
      assetDetailFilterProvider.select((f) => f.showPdfThumbnails),
    );

    return groups.when(
      loading: () =>
          Center(child: ProgressMessage(message: l10n.assetsLoading)),
      error: (error, _) => Center(
        child: SingleChildScrollView(child: ErrorMessage(error: error)),
      ),
      data: (groups) {
        final rows = buildAssetListRows(
          groups,
          showPdfThumbnails: showPdfThumbnails,
        );
        if (rows.isEmpty) return _EmptyHint(mod: mod);
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(
            Insets.lg,
            Insets.xs,
            Insets.sm,
            Insets.sm,
          ),
          itemCount: rows.length,
          itemBuilder: (context, index) => switch (rows[index]) {
            final HeaderRow row => AssetGroupHeader(mod: mod, row: row),
            final UrlRow row => Padding(
              padding: const EdgeInsets.symmetric(vertical: Insets.xs / 2),
              child: AssetUrlRow(mod: mod, asset: row.asset),
            ),
            final PdfGridRow row => Padding(
              padding: const EdgeInsets.symmetric(vertical: Insets.xs),
              child: Wrap(
                spacing: Insets.sm,
                runSpacing: Insets.sm,
                children: [
                  for (final asset in row.assets) PdfThumbnail(asset: asset),
                ],
              ),
            ),
          },
        );
      },
    );
  }
}

/// "No asset files referenced" when the mod has none, otherwise "No assets
/// match the current filters".
class _EmptyHint extends ConsumerWidget {
  const _EmptyHint({required this.mod});

  final Mod mod;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final filtered = ref.watch(
      assetDetailFilterProvider.select((f) => !f.isEmpty),
    );
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Insets.xl),
        child: Text(
          filtered ? l10n.noAssetsMatchFilters : l10n.assetsNone,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Header of one asset group: the type label, a download icon when files
/// are missing (downloads the missing files of that type), the
/// thumbnails/URLs toggle for PDFs and
/// the images viewer button for images. The icons are disabled while an
/// operation runs.
class AssetGroupHeader extends ConsumerWidget {
  /// Creates the header.
  const AssetGroupHeader({super.key, required this.mod, required this.row});

  /// The selected mod.
  final Mod mod;

  /// The header's row model.
  final HeaderRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final running = ref.watch(operationRunningProvider);
    final showPdfThumbnails = ref.watch(
      assetDetailFilterProvider.select((f) => f.showPdfThumbnails),
    );
    final label = row.type.label(l10n);

    return Padding(
      padding: EdgeInsets.only(top: row.isFirst ? 0 : Insets.md),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Gaps.w4,
            if (row.hasMissing)
              _HeaderIconButton(
                icon: Icons.download_outlined,
                tooltip: l10n.downloadMissingOfType(label.toLowerCase()),
                onPressed: running
                    ? null
                    : () =>
                          downloadModAssetsOfType(context, ref, mod, row.type),
              ),
            if (row.type == AssetType.pdf)
              _HeaderIconButton(
                icon: showPdfThumbnails ? Icons.link : Icons.grid_view_outlined,
                tooltip: showPdfThumbnails
                    ? l10n.pdfShowUrls
                    : l10n.pdfShowThumbnails,
                onPressed: running
                    ? null
                    : () => ref
                          .read(assetDetailFilterProvider.notifier)
                          .setShowPdfThumbnails(!showPdfThumbnails),
              ),
            if (row.type == AssetType.image)
              _HeaderIconButton(
                icon: Icons.image_outlined,
                tooltip: l10n.openImagesViewer,
                onPressed: running
                    ? null
                    : () => openImagesViewer(context, mod),
              ),
          ],
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon),
      iconSize: _headerIconSize,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(
        width: _headerButtonSize,
        height: _headerButtonSize,
      ),
      onPressed: onPressed,
    );
  }
}
