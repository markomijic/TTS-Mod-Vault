import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/features/operations/application/operation_runner.dart';
import 'package:tts_mod_vault/features/operations/presentation/operation_labels.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// The one progress bar of plan section 4.5, bound to
/// [operationRunnerProvider]: the operation's label and detail, a
/// determinate [LinearProgressIndicator] when the progress is known, and a
/// Cancel button that turns into a disabled "Cancelling…" once cancellation
/// was requested.
///
/// Docked in the selected-mod bottom bar (in place of the action buttons)
/// and under the library list, so it is visible on every tab. When the
/// runner is idle the bar collapses to nothing, unless [showWhenIdle] is
/// set, in which case an indeterminate bar with a generic text is shown
/// (the selected-mod slot uses this while a library refresh runs, which
/// is not a runner operation).
class OperationProgressBar extends ConsumerWidget {
  /// Creates the bar.
  const OperationProgressBar({super.key, this.showWhenIdle = false});

  /// Show an indeterminate placeholder instead of collapsing when nothing
  /// runs on the runner.
  final bool showWhenIdle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(operationRunnerProvider);
    if (!state.isRunning) {
      if (!showWhenIdle) return const SizedBox.shrink();
      return const _IdlePlaceholder();
    }
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final progress = state.progress;
    final cancelling = state.cancelRequested;
    final label = progress == null
        ? l10n.operationInProgress
        : operationProgressText(l10n, progress);
    final detail = progress?.detail;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Insets.lg,
        vertical: Insets.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                if (detail != null && detail.isNotEmpty) ...[
                  Gaps.h4,
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                Gaps.h8,
                LinearProgressIndicator(value: progress?.value),
              ],
            ),
          ),
          Gaps.w16,
          OutlinedButton(
            onPressed: cancelling
                ? null
                : () => ref.read(operationRunnerProvider.notifier).cancel(),
            child: Text(cancelling ? l10n.operationCancelling : l10n.cancel),
          ),
        ],
      ),
    );
  }
}

class _IdlePlaceholder extends StatelessWidget {
  const _IdlePlaceholder();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Insets.lg,
        vertical: Insets.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.operationInProgress, style: theme.textTheme.bodyMedium),
          Gaps.h8,
          const LinearProgressIndicator(),
        ],
      ),
    );
  }
}
