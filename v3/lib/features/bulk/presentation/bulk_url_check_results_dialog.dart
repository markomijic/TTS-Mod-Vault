import 'package:flutter_hooks/flutter_hooks.dart' show HookWidget, useState;
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/theme/vault_colors.dart';
import 'package:tts_mod_vault/app/widgets/app_dialog.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/bulk/application/bulk_service.dart'
    show BulkUrlCheckResult;
import 'package:tts_mod_vault/features/downloads/application/downloads_providers.dart'
    show UrlCheckResult;
import 'package:tts_mod_vault/features/library/presentation/item_actions.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Width of the dialog body.
const double _dialogWidth = 900;

/// Corner radius of the summary box.
const double _boxRadius = 8;

/// Alpha of the surface tint behind the summary counts.
const double _summaryTint = 0.4;

/// Size of the per-row copy icon.
const double _copyIconSize = 16;

/// Size of the section icons.
const double _sectionIconSize = 20;

/// A mod with the URLs of its check that did not answer.
typedef ModInvalidUrls = (Mod mod, List<String> invalidUrls);

/// The mods of [result] that have invalid URLs, most invalid first, ties
/// by name.
List<ModInvalidUrls> modsWithInvalidUrls(BulkUrlCheckResult result) {
  final list = <ModInvalidUrls>[
    for (final (mod, check) in result.results)
      if (check.invalidUrls.isNotEmpty) (mod, check.invalidUrls),
  ];
  list.sort((a, b) {
    final byCount = b.$2.length.compareTo(a.$2.length);
    if (byCount != 0) return byCount;
    return a.$1.displayName.toLowerCase().compareTo(
      b.$1.displayName.toLowerCase(),
    );
  });
  return list;
}

/// Clipboard text: each mod's name followed by its invalid URLs.
String bulkUrlCheckResultsText(List<ModInvalidUrls> mods) =>
    [for (final (mod, urls) in mods) '${mod.displayName}\n${urls.join('\n')}']
        .join('\n\n');

/// Port of 2.x `BulkUrlCheckResultsDialog`: a summary (mods with invalid
/// URLs, invalid URLs, mods checked), then one expandable section per mod
/// with invalid URLs, each URL with a copy button; "Copy all invalid URLs"
/// copies everything. A cancelled run says so in the title.
class BulkUrlCheckResultsDialog extends StatelessWidget {
  /// Creates the dialog for [result].
  const BulkUrlCheckResultsDialog({super.key, required this.result});

  /// The outcome shown.
  final BulkUrlCheckResult result;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = VaultColors.of(context);
    final cancelled = result.cancelled;
    final withInvalid = modsWithInvalidUrls(result);
    final totalInvalid = result.invalidUrlCount;
    final checked = result.results.length;
    final notChecked = result.modsFailed;
    final problemColor = totalInvalid > 0
        ? colors.assetMissing
        : colors.assetPresent;

    return AppDialog(
      title: cancelled
          ? l10n.bulkUrlCheckCancelledTitle
          : l10n.bulkUrlCheckCompleteTitle,
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
            Container(
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
                  _SummaryItem(
                    label: l10n.bulkUrlCheckModsWithInvalid,
                    count: withInvalid.length,
                    color: problemColor,
                  ),
                  _SummaryItem(
                    label: l10n.bulkUrlCheckInvalidUrls,
                    count: totalInvalid,
                    color: problemColor,
                  ),
                  _SummaryItem(
                    label: l10n.bulkUrlCheckModsChecked,
                    count: checked,
                    color: colors.logInfo,
                  ),
                ],
              ),
            ),
            if (notChecked > 0) ...[
              Gaps.h8,
              Text(
                l10n.bulkUrlCheckNotChecked(notChecked),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.logWarning,
                ),
              ),
            ],
            Gaps.h16,
            if (withInvalid.isEmpty)
              Text(
                l10n.urlCheckAllValid,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: colors.assetPresent,
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: withInvalid.length,
                  itemBuilder: (context, index) =>
                      _ModSection(entry: withInvalid[index]),
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
        if (withInvalid.isNotEmpty)
          FilledButton.tonalIcon(
            onPressed: () => copyTextToClipboard(
              context,
              bulkUrlCheckResultsText(withInvalid),
            ),
            icon: const Icon(Icons.copy_all),
            label: Text(l10n.urlCheckCopyAll),
          ),
      ],
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          '$count',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

/// One mod's heading ("Name (3)") that expands to its invalid URLs.
class _ModSection extends HookWidget {
  const _ModSection({required this.entry});

  final ModInvalidUrls entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = VaultColors.of(context);
    final expanded = useState(false);
    final (mod, urls) = entry;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => expanded.value = !expanded.value,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Insets.sm),
            child: Row(
              children: [
                Icon(
                  expanded.value ? Icons.expand_more : Icons.chevron_right,
                  color: colors.assetMissing,
                  size: _sectionIconSize,
                ),
                Gaps.w4,
                Icon(
                  Icons.error_outline,
                  color: colors.assetMissing,
                  size: _sectionIconSize,
                ),
                Gaps.w8,
                Expanded(
                  child: Text(
                    l10n.bulkUrlCheckModHeading(mod.displayName, urls.length),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colors.assetMissing,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded.value)
          Padding(
            padding: const EdgeInsets.only(left: Insets.xl, bottom: Insets.sm),
            child: Column(
              children: [
                for (var i = 0; i < urls.length; i++)
                  _InvalidUrlRow(url: urls[i], index: i),
              ],
            ),
          ),
      ],
    );
  }
}

class _InvalidUrlRow extends StatelessWidget {
  const _InvalidUrlRow({required this.url, required this.index});

  final String url;
  final int index;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Insets.xs / 2),
      child: Row(
        children: [
          Text('${index + 1}. '),
          Expanded(child: SelectableText(url)),
          IconButton(
            tooltip: l10n.assetMenuCopyUrl,
            iconSize: _copyIconSize,
            visualDensity: VisualDensity.compact,
            onPressed: () => copyTextToClipboard(context, url),
            icon: const Icon(Icons.copy),
          ),
        ],
      ),
    );
  }
}

/// Re-exported so callers that build a [BulkUrlCheckResultsDialog] from a
/// hand-made result (tests) need one import.
typedef BulkUrlCheck = UrlCheckResult;
