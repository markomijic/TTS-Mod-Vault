import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/widgets/app_snack_bar.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Widest the error card gets on large windows.
const double _maxWidth = 600;

/// Size of the leading error icon.
const double _iconSize = 48;

/// A full-page error block: icon, heading, the error text (selectable) and a
/// copy button, plus an optional Retry button.
///
/// Replaces 2.x `ErrorMessage`.
class ErrorMessage extends StatelessWidget {
  /// Creates the widget.
  const ErrorMessage({super.key, required this.error, this.onRetry});

  /// The error to show; rendered with `toString()`.
  final Object error;

  /// Shown as a Retry button when non-null.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final errorText = error.toString();
    final onRetry = this.onRetry;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _maxWidth),
      child: Padding(
        padding: const EdgeInsets.all(Insets.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.error_outline, size: _iconSize, color: scheme.error),
            Gaps.h16,
            Text(
              l10n.errorSomethingWentWrong,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge,
            ),
            Gaps.h16,
            DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(Insets.sm),
              ),
              child: Padding(
                padding: const EdgeInsets.all(Insets.md),
                child: SelectableText(
                  errorText,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            Gaps.h16,
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _copy(context, errorText),
                  icon: const Icon(Icons.copy_outlined),
                  label: Text(l10n.copyError),
                ),
                if (onRetry != null) ...[
                  Gaps.w12,
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: Text(l10n.retry),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    showAppSnackBar(context, AppLocalizations.of(context).copiedToClipboard);
  }
}
