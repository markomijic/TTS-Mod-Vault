/// The in-app update notice: listens to `updateCheckProvider` once the
/// shell is up and shows the v2 "new version available" dialog with links
/// to Nexus Mods and the GitHub release.
library;

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/widgets/app_dialog.dart';
import 'package:tts_mod_vault/app/widgets/app_snack_bar.dart';
import 'package:tts_mod_vault/features/about/application/update_check.dart';
import 'package:tts_mod_vault/features/about/presentation/about_links.dart';
import 'package:tts_mod_vault/features/settings/application/settings_controller.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

export 'package:tts_mod_vault/features/about/presentation/about_links.dart'
    show gitHubReleaseUrl, nexusModsDownloadPageUrl;

/// Wraps [child] and, when the "check for updates on start" setting is on,
/// watches [updateCheckProvider]; the first time it yields a version the
/// [UpdateAvailableDialog] is shown. The check is lazy, so nothing is
/// requested unless this widget is in the tree.
class UpdateNotice extends ConsumerWidget {
  /// Creates the notice around [child].
  const UpdateNotice({super.key, required this.child});

  /// The widget tree the dialog is shown over.
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(checkForUpdatesOnStartSettingProvider)) {
      ref.listen(updateCheckProvider, (previous, next) {
        final latest = next.value;
        if (latest == null || !context.mounted) return;
        showUpdateAvailableDialog(context, ref, latest);
      });
    }
    return child;
  }
}

/// Shows the [UpdateAvailableDialog] for [latestVersion] and opens the
/// chosen download page afterwards.
Future<void> showUpdateAvailableDialog(
  BuildContext context,
  WidgetRef ref,
  String latestVersion,
) async {
  final target = await showDialog<UpdateTarget>(
    context: context,
    builder: (_) => UpdateAvailableDialog(latestVersion: latestVersion),
  );
  if (target == null || !context.mounted) return;
  final url = switch (target) {
    UpdateTarget.nexusMods => nexusModsDownloadPageUrl,
    UpdateTarget.gitHub => gitHubReleaseUrl(latestVersion),
  };
  var ok = false;
  try {
    ok = await ref.read(urlOpenerProvider)(Uri.parse(url));
  } on Object {
    ok = false;
  }
  if (ok || !context.mounted) return;
  showAppSnackBar(context, AppLocalizations.of(context).couldNotOpenUrl(url));
}

/// Where the user wants to download the update from.
enum UpdateTarget {
  /// The Nexus Mods page.
  nexusMods,

  /// The GitHub release page.
  gitHub,
}

/// "Your version / Latest version" with Cancel, Nexus Mods and GitHub
/// buttons (port of v2 `showDownloadLatestVersionDialog`). Pops an
/// [UpdateTarget], or null on Cancel.
class UpdateAvailableDialog extends ConsumerWidget {
  /// Creates the dialog for [latestVersion].
  const UpdateAvailableDialog({super.key, required this.latestVersion});

  /// The newer version on GitHub.
  final String latestVersion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final current = ref.watch(currentAppVersionProvider).value ?? '';
    return AppDialog(
      title: l10n.updateAvailableTitle,
      content: Text(l10n.updateAvailableMessage(current, latestVersion)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton.tonal(
          onPressed: () => Navigator.of(context).pop(UpdateTarget.nexusMods),
          child: Text(l10n.updateNexusMods),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(UpdateTarget.gitHub),
          child: Text(l10n.updateGitHub),
        ),
      ],
    );
  }
}
