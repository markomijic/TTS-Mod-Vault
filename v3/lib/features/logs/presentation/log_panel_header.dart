import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:open_filex/open_filex.dart' show OpenFilex, ResultType;
import 'package:tts_mod_vault/app/widgets/app_snack_bar.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/core/logging/log_entry.dart';
import 'package:tts_mod_vault/features/library/presentation/item_actions.dart';
import 'package:tts_mod_vault/features/logs/application/log_providers.dart';
import 'package:tts_mod_vault/features/logs/presentation/log_labels.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Height of the header row.
const double logHeaderHeight = 36;

/// How long the header takes to flash to the error colour and back.
const Duration logHeaderFlashDuration = Duration(milliseconds: 350);

/// Size of the level icon in the collapsed preview.
const double _previewIconSize = 14;

/// The one-line header of the log panel (plan section 4.8): the expand
/// chevron, "Log" with the red unseen-count badge, the newest entry as a
/// one-line preview (the visible entry count when expanded), and the
/// "Open log file" button with a menu offering "Open log folder" and
/// "Copy log file path". The whole row toggles the panel; [flashing]
/// paints it in the error colour (the panel pulses it once per error
/// while collapsed).
class LogPanelHeader extends ConsumerWidget {
  /// Creates the header.
  const LogPanelHeader({
    super.key,
    required this.expanded,
    required this.flashing,
    required this.onToggle,
  });

  /// Whether the list below is shown.
  final bool expanded;

  /// Whether the header is currently flashed.
  final bool flashing;

  /// Expands or collapses the panel.
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final unseen = ref.watch(unseenLogCountProvider);
    final latest = ref.watch(
      logEntriesProvider.select((entries) => entries.lastOrNull),
    );
    final visibleCount = ref.watch(
      filteredLogEntriesProvider.select((entries) => entries.length),
    );
    final path = ref.watch(logFilePathProvider);

    final Widget title = Badge.count(
      count: unseen,
      isLabelVisible: unseen > 0,
      offset: const Offset(Insets.md, -Insets.xs),
      child: Text(l10n.logPanelTitle, style: theme.textTheme.titleSmall),
    );

    return AnimatedContainer(
      duration: logHeaderFlashDuration,
      color: flashing ? scheme.errorContainer : scheme.surfaceContainer,
      child: InkWell(
        onTap: onToggle,
        child: SizedBox(
          height: logHeaderHeight,
          child: Row(
            children: [
              IconButton(
                tooltip: expanded ? l10n.logPanelCollapse : l10n.logPanelExpand,
                visualDensity: VisualDensity.compact,
                onPressed: onToggle,
                icon: Icon(expanded ? Icons.expand_more : Icons.expand_less),
              ),
              if (unseen > 0)
                Tooltip(message: l10n.logUnseenTooltip(unseen), child: title)
              else
                title,
              Gaps.w16,
              Expanded(
                child: expanded
                    ? Text(
                        l10n.logEntryCount(visibleCount),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      )
                    : _LatestPreview(entry: latest),
              ),
              Gaps.w8,
              IconButton(
                tooltip: l10n.logOpenFile,
                visualDensity: VisualDensity.compact,
                onPressed: path == null
                    ? null
                    : () => openLogFile(context, path),
                icon: const Icon(Icons.description_outlined),
              ),
              MenuAnchor(
                menuChildren: [
                  MenuItemButton(
                    leadingIcon: const Icon(Icons.folder_open_outlined),
                    onPressed: path == null
                        ? null
                        : () => revealInFileExplorer(context, path),
                    child: Text(l10n.logOpenFolder),
                  ),
                  MenuItemButton(
                    leadingIcon: const Icon(Icons.copy),
                    onPressed: path == null
                        ? null
                        : () => copyTextToClipboard(context, path),
                    child: Text(l10n.logCopyFilePath),
                  ),
                ],
                builder: (context, controller, _) => IconButton(
                  tooltip: l10n.logFileActions,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => controller.isOpen
                      ? controller.close()
                      : controller.open(),
                  icon: const Icon(Icons.more_vert),
                ),
              ),
              Gaps.w4,
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the log file at [path] with the OS default viewer; a snack bar
/// reports failure.
Future<void> openLogFile(BuildContext context, String path) async {
  var ok = false;
  try {
    final result = await OpenFilex.open(path);
    ok = result.type == ResultType.done;
  } on Object {
    ok = false;
  }
  if (ok || !context.mounted) return;
  showAppSnackBar(context, AppLocalizations.of(context).couldNotOpenFile(path));
}

class _LatestPreview extends ConsumerWidget {
  const _LatestPreview({required this.entry});

  final LogEntry? entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = this.entry;
    if (entry == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(
          entry.level.icon,
          size: _previewIconSize,
          color: entry.level.color(context),
        ),
        Gaps.w4,
        Flexible(
          child: Text(
            entry.message,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
