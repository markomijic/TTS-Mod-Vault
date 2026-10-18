import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/features/library/application/library_view_providers.dart';
import 'package:tts_mod_vault/features/library/presentation/library_labels.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// How long the help stays open once shown.
const Duration _showDuration = Duration(seconds: 15);

/// Info icon with the bullet help of the mods toolbar (2.x text), naming the
/// selected type and the platform's multi-select modifier (Cmd on macOS,
/// Ctrl elsewhere).
class LibraryHelpTooltip extends ConsumerWidget {
  /// Creates the icon.
  const LibraryHelpTooltip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final type = ref.watch(selectedModTypeProvider);
    final isMac = theme.platform == TargetPlatform.macOS;
    final message = l10n.libraryHelp(
      type.singular(l10n),
      type.plural(l10n),
      isMac ? l10n.modifierCmd : l10n.modifierCtrl,
      l10n.modTypeMods,
      l10n.modTypeSaves,
    );
    return Tooltip(
      message: message,
      showDuration: _showDuration,
      textStyle: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onInverseSurface,
        height: 1.6,
      ),
      child: Padding(
        padding: const EdgeInsets.all(Insets.sm),
        child: Icon(
          Icons.info_outline,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
