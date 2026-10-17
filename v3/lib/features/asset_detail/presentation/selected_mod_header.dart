import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/features/asset_detail/presentation/asset_help_tooltip.dart';

/// Title band at the top of the right panel: the title (up to two lines,
/// so a save can show `file.json` over its name), a bottom divider and,
/// unless [showHelp] is false, the [AssetHelpTooltip] icon on the right.
class SelectedModHeader extends StatelessWidget {
  /// Creates the header.
  const SelectedModHeader({
    super.key,
    required this.title,
    this.showHelp = true,
  });

  /// Header text.
  final String title;

  /// Whether to show the help icon.
  final bool showHelp;

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
          Insets.md,
          Insets.sm,
          Insets.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: Insets.xs),
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge,
                ),
              ),
            ),
            if (showHelp) const AssetHelpTooltip(),
          ],
        ),
      ),
    );
  }
}
