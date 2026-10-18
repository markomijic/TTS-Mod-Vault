import 'package:flutter_hooks/flutter_hooks.dart' show useState;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/widgets/app_context_menu.dart';
import 'package:tts_mod_vault/app/widgets/app_snack_bar.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/core/logging/log_entry.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';
import 'package:tts_mod_vault/features/library/application/library_tab.dart';
import 'package:tts_mod_vault/features/library/application/library_view_providers.dart';
import 'package:tts_mod_vault/features/library/presentation/item_actions.dart';
import 'package:tts_mod_vault/features/logs/presentation/log_labels.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Width of the time column.
const double _timeWidth = 64;

/// Size of the level icon and the details chevron.
const double _iconSize = 16;

/// Corner radius of the source chip.
const double _chipRadius = 4;

/// One entry of the log list (plan section 4.8): time, level icon in the
/// level's colour, source chip, message, and a chevron that reveals the
/// details when the entry has any. Clicking a row that refers to a mod
/// selects that mod (switching tab when needed); right-click offers
/// "Copy entry".
class LogEntryRow extends HookConsumerWidget {
  /// Creates the row for [entry].
  const LogEntryRow({super.key, required this.entry});

  /// The entry shown.
  final LogEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final expanded = useState(false);
    final details = entry.details;
    final hasDetails = details != null && details.isNotEmpty;
    final modPath = entry.modPath;
    final canSelect = modPath != null && modPath.isNotEmpty;

    return GestureDetector(
      onSecondaryTapUp: (details) =>
          showAppContextMenu(context, details.globalPosition, [
            MenuAction(
              label: l10n.logCopyEntry,
              icon: Icons.copy,
              onPressed: () => copyTextToClipboard(context, entry.toLine()),
            ),
          ]),
      child: InkWell(
        onTap: canSelect
            ? () => selectLogEntryMod(context, ref, modPath)
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Insets.md,
            vertical: Insets.xs,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: _timeWidth,
                    child: Text(
                      formatLogTime(entry.time),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  Icon(
                    entry.level.icon,
                    size: _iconSize,
                    color: entry.level.color(context),
                  ),
                  Gaps.w8,
                  _SourceChip(source: entry.source),
                  Gaps.w8,
                  Expanded(
                    child: Text(
                      entry.message,
                      maxLines: expanded.value ? null : 1,
                      overflow: expanded.value ? null : TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  if (hasDetails)
                    SizedBox(
                      height: _iconSize + Insets.xs,
                      child: IconButton(
                        tooltip: expanded.value
                            ? l10n.logHideDetails
                            : l10n.logShowDetails,
                        iconSize: _iconSize,
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints(),
                        onPressed: () => expanded.value = !expanded.value,
                        icon: Icon(
                          expanded.value
                              ? Icons.expand_less
                              : Icons.expand_more,
                        ),
                      ),
                    ),
                ],
              ),
              if (hasDetails && expanded.value)
                Padding(
                  padding: const EdgeInsets.only(
                    left: _timeWidth + _iconSize + Insets.sm,
                    top: Insets.xs,
                  ),
                  child: SelectableText(
                    details,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Selects the mod at [modPath] in the library, switching to its tab
/// first; a snack bar says so when the mod is no longer in the library.
void selectLogEntryMod(BuildContext context, WidgetRef ref, String modPath) {
  final mod = ref.read(libraryControllerProvider).value?.modByPath(modPath);
  if (mod == null) {
    showAppSnackBar(context, AppLocalizations.of(context).logModNotInLibrary);
    return;
  }
  ref.read(libraryTabProvider.notifier).set(LibraryTab.forType(mod.ref.type));
  ref.read(selectionProvider.notifier).select(mod.jsonPath);
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({required this.source});

  final LogSource source;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(_chipRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Insets.xs + Insets.xs / 2,
          vertical: Insets.xs / 2,
        ),
        child: Text(
          source.title(l10n),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
