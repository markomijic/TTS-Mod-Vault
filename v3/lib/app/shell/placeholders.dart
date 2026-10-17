import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Placeholder for the backups page until the backups feature lands.
class BackupsPage extends StatelessWidget {
  /// Creates the page.
  const BackupsPage({super.key, this.bottomSlot = const SizedBox.shrink()});

  /// Docked under the content; the log panel and progress bar go here.
  final Widget bottomSlot;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        Expanded(
          child: Center(
            child: Text(
              AppLocalizations.of(context).backupsPageTitle,
              style: textTheme.headlineMedium,
            ),
          ),
        ),
        bottomSlot,
      ],
    );
  }
}
