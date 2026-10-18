import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/theme/vault_colors.dart';
import 'package:tts_mod_vault/app/widgets/app_dialog.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/features/library/presentation/item_actions.dart';
import 'package:tts_mod_vault/features/workshop/application/workshop_results.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Width of the results dialogs.
const double _dialogWidth = 700;

/// Corner radius of the summary box and the item rows.
const double _boxRadius = 8;

/// Alpha of the section colour behind an item row.
const double _rowTint = 0.12;

/// Alpha of the surface tint behind the summary counts.
const double _summaryTint = 0.4;

/// Localised text for a [WorkshopItemStatus] that is not ok.
String workshopItemStatusText(AppLocalizations l10n, WorkshopItemStatus s) =>
    switch (s) {
      WorkshopItemStatus.ok => '',
      WorkshopItemStatus.notFound => l10n.workshopStatusNotFound,
      WorkshopItemStatus.unlisted => l10n.workshopStatusUnlisted,
      WorkshopItemStatus.wrongApp => l10n.workshopStatusWrongApp,
      WorkshopItemStatus.invalid => l10n.workshopStatusInvalid,
    };

/// One item line of a results section: a name and an optional detail.
typedef ResultLine = ({String name, String? detail});

/// A titled, coloured group of result lines.
final class ResultSection {
  /// Creates a section.
  const ResultSection({
    required this.title,
    required this.icon,
    required this.color,
    required this.lines,
  });

  /// Section heading (without the count).
  final String title;

  /// Icon next to the heading.
  final IconData icon;

  /// Colour of the heading, the count and the row tint.
  final Color color;

  /// The items.
  final List<ResultLine> lines;
}

/// Results of downloading Workshop items by id: counts, then the
/// downloaded, failed and cancelled items with their title (or id) and
/// error.
class WorkshopDownloadResultsDialog extends StatelessWidget {
  /// Creates the dialog for [result].
  const WorkshopDownloadResultsDialog({super.key, required this.result});

  /// The batch shown.
  final WorkshopDownloadBatchResult result;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = VaultColors.of(context);
    final cancelled = result.wasCancelled;
    final sections = [
      ResultSection(
        title: l10n.workshopSectionDownloaded,
        icon: Icons.check_circle_outline,
        color: colors.assetPresent,
        lines: [
          for (final r in result.successful)
            (name: r.displayName, detail: null),
        ],
      ),
      ResultSection(
        title: l10n.workshopSectionFailed,
        icon: Icons.error_outline,
        color: colors.assetMissing,
        lines: [
          for (final r in result.failed)
            (
              name: r.title == null ? r.id : '${r.displayName} (${r.id})',
              detail: r.error ?? workshopItemStatusText(l10n, r.status),
            ),
        ],
      ),
      ResultSection(
        title: l10n.workshopSectionCancelled,
        icon: Icons.cancel_outlined,
        color: colors.assetInvalid,
        lines: [
          for (final r in result.results)
            if (r.cancelled) (name: r.displayName, detail: null),
        ],
      ),
    ];
    return WorkshopResultsDialog(
      title: cancelled
          ? l10n.workshopDownloadCancelledTitle
          : l10n.workshopDownloadResultsTitle,
      cancelled: cancelled,
      sections: sections,
    );
  }
}

/// Results of updating Workshop mods (port of v2 `BulkUpdateResultsDialog`):
/// counts, then the updated, already up to date, failed and cancelled mods.
class WorkshopUpdateResultsDialog extends StatelessWidget {
  /// Creates the dialog for [result].
  const WorkshopUpdateResultsDialog({super.key, required this.result});

  /// The batch shown.
  final WorkshopUpdateBatchResult result;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = VaultColors.of(context);
    final cancelled = result.wasCancelled;

    List<ResultLine> linesOf(WorkshopUpdateStatus status) => [
      for (final r in result.results)
        if (r.status == status)
          (
            name: r.modName,
            detail: status == WorkshopUpdateStatus.failed
                ? r.error ??
                      (r.itemStatus == null
                          ? null
                          : workshopItemStatusText(l10n, r.itemStatus!))
                : null,
          ),
    ];

    final sections = [
      ResultSection(
        title: l10n.workshopSectionUpdated,
        icon: Icons.check_circle_outline,
        color: colors.assetPresent,
        lines: linesOf(WorkshopUpdateStatus.updated),
      ),
      ResultSection(
        title: l10n.workshopSectionUpToDate,
        icon: Icons.info_outline,
        color: colors.logInfo,
        lines: linesOf(WorkshopUpdateStatus.upToDate),
      ),
      ResultSection(
        title: l10n.workshopSectionFailed,
        icon: Icons.error_outline,
        color: colors.assetMissing,
        lines: linesOf(WorkshopUpdateStatus.failed),
      ),
      ResultSection(
        title: l10n.workshopSectionCancelled,
        icon: Icons.cancel_outlined,
        color: colors.assetInvalid,
        lines: linesOf(WorkshopUpdateStatus.cancelled),
      ),
    ];
    return WorkshopResultsDialog(
      title: cancelled
          ? l10n.workshopUpdateCancelledTitle
          : l10n.workshopUpdateResultsTitle,
      cancelled: cancelled,
      sections: sections,
    );
  }
}

/// Plain-text form of [sections] for the clipboard.
String workshopResultsText(
  AppLocalizations l10n,
  String title,
  List<ResultSection> sections,
) {
  final buffer = StringBuffer(title);
  for (final section in sections) {
    if (section.lines.isEmpty) continue;
    buffer.write(
      '\n\n${l10n.workshopSectionCount(section.title, section.lines.length)}',
    );
    for (final line in section.lines) {
      buffer.write('\n${line.name}');
      if (line.detail case final detail? when detail.isNotEmpty) {
        buffer.write('\n    $detail');
      }
    }
  }
  return buffer.toString();
}

/// The shared frame of the Workshop results dialogs: a title with a
/// success or warning icon, a row of counts (one per section), the
/// non-empty sections, Close and Copy.
class WorkshopResultsDialog extends StatelessWidget {
  /// Creates the dialog.
  const WorkshopResultsDialog({
    super.key,
    required this.title,
    required this.cancelled,
    required this.sections,
  });

  /// Dialog title.
  final String title;

  /// Whether the operation was cancelled (warning icon).
  final bool cancelled;

  /// The sections, in display order; empty ones are only counted.
  final List<ResultSection> sections;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = VaultColors.of(context);

    return AppDialog(
      title: title,
      content: SizedBox(
        width: _dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  cancelled ? Icons.warning_amber_rounded : Icons.check_circle,
                  color: cancelled ? colors.assetInvalid : colors.assetPresent,
                ),
                Gaps.w8,
                Expanded(
                  child: Text(
                    cancelled
                        ? l10n.workshopResultsCancelledNote
                        : l10n.workshopResultsCompleteNote,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            Gaps.h12,
            _Summary(sections: sections),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final section in sections)
                      if (section.lines.isNotEmpty)
                        _SectionView(section: section),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
        FilledButton.tonalIcon(
          onPressed: () => copyTextToClipboard(
            context,
            workshopResultsText(l10n, title, sections),
          ),
          icon: const Icon(Icons.copy),
          label: Text(l10n.copy),
        ),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.sections});

  final List<ResultSection> sections;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(Insets.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: _summaryTint,
        ),
        borderRadius: BorderRadius.circular(_boxRadius),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (final section in sections)
            Column(
              children: [
                Text(
                  '${section.lines.length}',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: section.color,
                  ),
                ),
                Text(section.title, style: theme.textTheme.bodySmall),
              ],
            ),
        ],
      ),
    );
  }
}

class _SectionView extends StatelessWidget {
  const _SectionView({required this.section});

  final ResultSection section;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Gaps.h16,
        Row(
          children: [
            Icon(
              section.icon,
              color: section.color,
              size: Insets.xl - Insets.xs,
            ),
            Gaps.w8,
            Text(
              l10n.workshopSectionCount(section.title, section.lines.length),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: section.color,
              ),
            ),
          ],
        ),
        Gaps.h8,
        for (final line in section.lines)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: Insets.xs),
            padding: const EdgeInsets.symmetric(
              horizontal: Insets.sm,
              vertical: Insets.xs,
            ),
            decoration: BoxDecoration(
              color: section.color.withValues(alpha: _rowTint),
              borderRadius: BorderRadius.circular(_boxRadius / 2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.name, style: theme.textTheme.bodyMedium),
                if (line.detail case final detail? when detail.isNotEmpty)
                  Text(
                    detail,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
