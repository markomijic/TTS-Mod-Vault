import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Placeholder for the mods page until the library feature lands.
class ModsPage extends StatelessWidget {
  /// Creates the page.
  const ModsPage({super.key, this.bottomSlot = const SizedBox.shrink()});

  /// Docked under the content; the log panel and progress bar go here.
  final Widget bottomSlot;

  @override
  Widget build(BuildContext context) => _PlaceholderPage(
    title: AppLocalizations.of(context).modsPageTitle,
    bottomSlot: bottomSlot,
  );
}

/// Placeholder for the backups page until the backups feature lands.
class BackupsPage extends StatelessWidget {
  /// Creates the page.
  const BackupsPage({super.key, this.bottomSlot = const SizedBox.shrink()});

  /// Docked under the content; the log panel and progress bar go here.
  final Widget bottomSlot;

  @override
  Widget build(BuildContext context) => _PlaceholderPage(
    title: AppLocalizations.of(context).backupsPageTitle,
    bottomSlot: bottomSlot,
  );
}

class _PlaceholderPage extends StatelessWidget {
  const _PlaceholderPage({required this.title, required this.bottomSlot});

  final String title;
  final Widget bottomSlot;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        Expanded(
          child: Center(child: Text(title, style: textTheme.headlineMedium)),
        ),
        bottomSlot,
      ],
    );
  }
}
