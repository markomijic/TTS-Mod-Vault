import 'dart:async' show unawaited;

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/theme/vault_colors.dart';
import 'package:tts_mod_vault/app/widgets/app_dialog.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/downloads/application/downloads_providers.dart';
import 'package:tts_mod_vault/features/downloads/presentation/download_actions.dart';
import 'package:tts_mod_vault/features/library/presentation/item_actions.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Width of the results dialog.
const double _dialogWidth = 900;

/// Size of the per-row copy icon.
const double _copyIconSize = 16;

/// Outcome of a URL check (port of v2 `UrlCheckResultsDialog`): the
/// invalid URLs with a copy button each, or "All URLs are valid"; when the
/// check was cancelled the title says so and the partial count is shown.
/// "Re-check" closes the dialog and runs the check again.
class UrlCheckResultsDialog extends ConsumerWidget {
  /// Creates the dialog for [mod]'s [result].
  const UrlCheckResultsDialog({
    super.key,
    required this.mod,
    required this.result,
  });

  /// The checked mod.
  final Mod mod;

  /// The check's outcome.
  final UrlCheckResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = VaultColors.of(context);
    final invalid = result.invalidUrls;
    final cancelled = result.cancelled;

    final String heading;
    if (invalid.isNotEmpty) {
      heading = l10n.urlCheckInvalidCount(invalid.length);
    } else if (cancelled) {
      heading = l10n.urlCheckNoneBeforeCancel;
    } else {
      heading = l10n.urlCheckAllValid;
    }

    return AppDialog(
      title: cancelled ? l10n.urlCheckCancelledTitle : mod.displayName,
      content: SizedBox(
        width: _dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (cancelled) ...[
              Text(mod.displayName, style: theme.textTheme.bodyLarge),
              Gaps.h4,
              Text(
                l10n.urlCheckCheckedCount(result.checked, result.total),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Gaps.h12,
            ],
            Text(
              heading,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: invalid.isNotEmpty
                    ? colors.assetMissing
                    : colors.assetPresent,
              ),
            ),
            if (invalid.isNotEmpty) ...[
              Gaps.h12,
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: invalid.length,
                  itemBuilder: (context, index) =>
                      _InvalidUrlRow(url: invalid[index], index: index),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
        FilledButton.tonalIcon(
          onPressed: () {
            // Start first: the check captures its navigator and messenger
            // synchronously, before this dialog's context goes away.
            final rerun = checkModUrls(context, ref, mod);
            Navigator.of(context).pop();
            unawaited(rerun);
          },
          icon: const Icon(Icons.refresh),
          label: Text(l10n.urlCheckRecheck),
        ),
        if (invalid.isNotEmpty)
          FilledButton.tonalIcon(
            onPressed: () => copyTextToClipboard(context, invalid.join('\n')),
            icon: const Icon(Icons.copy_all),
            label: Text(l10n.urlCheckCopyAll),
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
