/// The Help dialog: Help and Changelog tabs rendered from the Markdown in
/// `assets/text/`, and an About tab with the version, the project links,
/// a manual update check and a shortcut to the log folder (plan Phase 5:
/// "Help and changelog dialogs with content in assets, not Dart strings").
library;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_hooks/flutter_hooks.dart' show useScrollController;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/platform/file_explorer.dart';
import 'package:tts_mod_vault/app/widgets/app_snack_bar.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/features/about/application/localized_assets.dart';
import 'package:tts_mod_vault/features/about/application/translator_credits.dart';
import 'package:tts_mod_vault/features/about/application/update_check.dart';
import 'package:tts_mod_vault/features/about/presentation/about_links.dart';
import 'package:tts_mod_vault/features/about/presentation/simple_markdown.dart';
import 'package:tts_mod_vault/features/about/presentation/update_notice.dart';
import 'package:tts_mod_vault/features/logs/application/log_providers.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';
import 'package:tts_mod_vault/l10n/locale_tags.dart';

/// Asset path of the English help text, which is also the fallback for a
/// language without a `help_<locale>.md` of its own.
const String helpAssetPath = 'assets/text/help.md';

/// Asset path of the changelog.
const String changelogAssetPath = 'assets/text/changelog.md';

/// The Markdown of the Help tab for a UI locale: `help_<locale>.md` when the
/// app ships it, else `help.md`. Overridable in tests.
final helpTextProvider = FutureProvider.family<String, Locale>(
  (ref, locale) => loadLocalizedAsset(helpAssetPath, locale),
);

/// The Markdown of the Changelog tab; overridable in tests.
final changelogTextProvider = FutureProvider<String>(
  (ref) => rootBundle.loadString(changelogAssetPath),
);

/// Reveals the log file in the OS file manager; overridable in tests.
final revealLogFileProvider = Provider<Future<bool> Function(String path)>(
  (_) => openInFileExplorer,
);

/// Opens the [HelpDialog].
Future<void> showHelpDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const HelpDialog());

/// Dialog width.
const double _dialogWidth = 820;

/// Dialog height.
const double _dialogHeight = 600;

/// The tabs of the [HelpDialog].
enum HelpTab {
  /// Usage help.
  help,

  /// Release notes.
  changelog,

  /// Version, links, update check, log folder.
  about,
}

/// Help / Changelog / About in one tabbed dialog.
class HelpDialog extends StatelessWidget {
  /// Creates the dialog, opened on [initialTab].
  const HelpDialog({super.key, this.initialTab = HelpTab.help});

  /// The tab shown first.
  final HelpTab initialTab;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    return Dialog(
      child: SizedBox(
        width: _dialogWidth,
        height: _dialogHeight,
        child: DefaultTabController(
          length: HelpTab.values.length,
          initialIndex: initialTab.index,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.xl,
                  Insets.lg,
                  Insets.lg,
                  0,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.appTitle,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.close,
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              TabBar(
                tabs: [
                  Tab(text: l10n.helpTabHelp),
                  Tab(text: l10n.helpTabChangelog),
                  Tab(text: l10n.helpTabAbout),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _MarkdownTab(provider: helpTextProvider(locale)),
                    _MarkdownTab(
                      provider: changelogTextProvider,
                      // The changelog is English only; say so in the
                      // reader's language.
                      notice: locale.languageCode == 'en'
                          ? null
                          : l10n.helpChangelogEnglishOnly,
                    ),
                    const AboutTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MarkdownTab extends HookConsumerWidget {
  const _MarkdownTab({required this.provider, this.notice});

  final FutureProvider<String> provider;

  /// A line shown above the text.
  final String? notice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // Each tab scrolls on its own; sharing the primary controller between
    // the tab views would break the always-visible scrollbar.
    final controller = useScrollController();
    return switch (ref.watch(provider)) {
      AsyncData(:final value) => Scrollbar(
        controller: controller,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: controller,
          padding: const EdgeInsets.all(Insets.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (notice case final notice?) ...[
                Text(
                  notice,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                Gaps.h16,
              ],
              SimpleMarkdown(value),
            ],
          ),
        ),
      ),
      AsyncError() => Center(
        child: Text(
          l10n.helpLoadFailed,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

/// Version, description, links, "Check for updates now" and "Open log
/// folder".
class AboutTab extends ConsumerWidget {
  /// Creates the tab.
  const AboutTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final version = ref.watch(currentAppVersionProvider).value;
    final logPath = ref.watch(logFilePathProvider);
    final checking = ref.watch(updateCheckProvider).isLoading;
    final credits = ref.watch(translatorCreditsProvider).value ?? const [];

    Future<void> open(String url) async {
      var ok = false;
      try {
        ok = await ref.read(urlOpenerProvider)(Uri.parse(url));
      } on Object {
        ok = false;
      }
      if (ok || !context.mounted) return;
      showAppSnackBar(context, l10n.couldNotOpenUrl(url));
    }

    Future<void> checkForUpdates() async {
      ref.invalidate(updateCheckProvider);
      String? latest;
      try {
        latest = await ref.read(updateCheckProvider.future);
      } on Object {
        latest = null;
      }
      if (!context.mounted) return;
      if (latest == null) {
        showAppSnackBar(context, l10n.aboutNoUpdates);
        return;
      }
      await showUpdateAvailableDialog(context, ref, latest);
    }

    Future<void> openLogFolder() async {
      if (logPath == null) {
        showAppSnackBar(context, l10n.aboutLogFolderUnavailable);
        return;
      }
      final ok = await ref.read(revealLogFileProvider)(logPath);
      if (ok || !context.mounted) return;
      showAppSnackBar(context, l10n.aboutCouldNotOpenFolder);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(Insets.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            version == null ? l10n.appTitle : l10n.aboutVersion(version),
            style: theme.textTheme.titleLarge,
          ),
          Gaps.h8,
          Text(l10n.aboutDescription, style: theme.textTheme.bodyMedium),
          Gaps.h4,
          Text(
            l10n.aboutLicense,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (credits.isNotEmpty) ...[
            Gaps.h16,
            Text(l10n.aboutTranslators, style: theme.textTheme.titleSmall),
            Gaps.h4,
            for (final credit in credits)
              Text(
                l10n.aboutTranslatorsLine(
                  _languageName(credit.localeTag),
                  credit.names,
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
          Gaps.h24,
          Wrap(
            spacing: Insets.sm,
            runSpacing: Insets.sm,
            children: [
              OutlinedButton.icon(
                onPressed: () => open(gitHubReleasesUrl),
                icon: const Icon(Icons.new_releases_outlined),
                label: Text(l10n.aboutGitHubReleases),
              ),
              OutlinedButton.icon(
                onPressed: () => open(nexusModsDownloadPageUrl),
                icon: const Icon(Icons.thumb_up_outlined),
                label: Text(l10n.aboutNexusMods),
              ),
              OutlinedButton.icon(
                onPressed: () => open(steamDiscussionUrl),
                icon: const Icon(Icons.forum_outlined),
                label: Text(l10n.aboutSteamDiscussion),
              ),
              OutlinedButton.icon(
                onPressed: () => open(kofiUrl),
                icon: const Icon(Icons.favorite_outline),
                label: Text(l10n.aboutKofi),
              ),
            ],
          ),
          Gaps.h24,
          const Divider(),
          Gaps.h16,
          Wrap(
            spacing: Insets.sm,
            runSpacing: Insets.sm,
            children: [
              FilledButton.tonalIcon(
                onPressed: checking ? null : checkForUpdates,
                icon: checking
                    ? const SizedBox.square(
                        dimension: Insets.lg,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.update),
                label: Text(l10n.aboutCheckForUpdates),
              ),
              FilledButton.tonalIcon(
                onPressed: openLogFolder,
                icon: const Icon(Icons.folder_open_outlined),
                label: Text(l10n.aboutOpenLogFolder),
              ),
            ],
          ),
          if (logPath != null) ...[
            Gaps.h8,
            Text(
              logPath,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The native name of the language tagged [tag], or the tag itself.
String _languageName(String tag) {
  final locale = localeFromTag(tag);
  return locale == null ? tag : nativeLanguageName(locale);
}
