// The Help dialog: tabs, Markdown rendering of the assets, and the About
// tab's version, links, update check and log folder button.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart' show Override;
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/providers/app_log_provider.dart';
import 'package:tts_mod_vault/core/logging/app_log.dart';
import 'package:tts_mod_vault/features/about/application/translator_credits.dart';
import 'package:tts_mod_vault/features/about/application/update_check.dart';
import 'package:tts_mod_vault/features/about/presentation/about_links.dart';
import 'package:tts_mod_vault/features/about/presentation/help_dialog.dart';
import 'package:tts_mod_vault/features/about/presentation/update_notice.dart';
import 'package:tts_mod_vault/features/logs/application/log_providers.dart';

import '../../images_viewer/themed_app.dart';

const String _help = '''
# Getting started

Some intro text with `code` in it.

- First bullet
- Second bullet

## Nested heading
''';

const String _changelog = '''
# v3.0.0

· Rewrite
''';

void main() {
  late List<Uri> opened;
  late List<String> revealed;

  setUp(() {
    opened = [];
    revealed = [];
  });

  Future<ProviderContainer> open(
    WidgetTester tester, {
    String? latest,
    String? logPath = r'C:\logs\vault.log',
    bool realAssets = false,
    List<TranslatorCredit> credits = const [],
  }) async {
    final log = AppLog(store: LogStore());
    addTearDown(log.dispose);
    final container = await pumpThemedApp(
      tester,
      overrides: [
        appLogProvider.overrideWithValue(log),
        if (!realAssets) ...<Override>[
          helpTextProvider.overrideWith((ref, locale) async => _help),
          changelogTextProvider.overrideWith((ref) async => _changelog),
        ],
        translatorCreditsProvider.overrideWith((ref) async => credits),
        currentAppVersionProvider.overrideWith((ref) async => '3.0.0'),
        updateCheckProvider.overrideWith((ref) async => latest),
        logFilePathProvider.overrideWithValue(logPath),
        urlOpenerProvider.overrideWithValue((uri) async {
          opened.add(uri);
          return true;
        }),
        revealLogFileProvider.overrideWithValue((path) async {
          revealed.add(path);
          return true;
        }),
      ],
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () => showHelpDialog(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(HelpDialog), findsOneWidget);
    return container;
  }

  Future<void> tab(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(of: find.byType(TabBar), matching: find.text(label)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders the help Markdown as headings, bullets and code', (
    tester,
  ) async {
    await open(tester);

    expect(find.text('TTS Mod Vault'), findsOneWidget);
    expect(find.text('Getting started'), findsOneWidget);
    expect(find.text('Nested heading'), findsOneWidget);
    expect(find.text('First bullet', findRichText: true), findsOneWidget);
    expect(find.text('Second bullet', findRichText: true), findsOneWidget);
    expect(find.text('\u2022'), findsNWidgets(2));
    expect(
      find.text('Some intro text with code in it.', findRichText: true),
      findsOneWidget,
    );
    final heading = tester.widget<Text>(find.text('Getting started'));
    final theme = Theme.of(tester.element(find.text('Getting started')));
    expect(heading.style?.fontSize, theme.textTheme.titleLarge?.fontSize);
  });

  testWidgets('the Changelog tab renders its Markdown', (tester) async {
    await open(tester);

    await tab(tester, 'Changelog');

    expect(find.text('v3.0.0'), findsOneWidget);
    expect(find.text('Rewrite', findRichText: true), findsOneWidget);
    expect(find.text('Getting started'), findsNothing);
  });

  testWidgets('the shipped assets load and contain the v2 help texts', (
    tester,
  ) async {
    await open(tester, realAssets: true);

    expect(find.text('Getting started'), findsOneWidget);
    expect(find.text('Update URLs'), findsOneWidget);

    await tab(tester, 'Changelog');
    expect(find.text('v3.0.0'), findsOneWidget);
    expect(find.text('v2.1.0'), findsOneWidget);
    expect(find.text('v1.0.0'), findsOneWidget);
  });

  testWidgets('About shows the version, the links and the log path', (
    tester,
  ) async {
    await open(tester);
    await tab(tester, 'About');

    expect(find.text('Version 3.0.0'), findsOneWidget);
    expect(find.text('GitHub releases'), findsOneWidget);
    expect(find.text('Nexus Mods'), findsOneWidget);
    expect(find.text('Steam discussion'), findsOneWidget);
    expect(find.text('Support on Ko-fi'), findsOneWidget);
    expect(find.text('Check for updates now'), findsOneWidget);
    expect(find.text('Open log folder'), findsOneWidget);
    expect(find.text(r'C:\logs\vault.log'), findsOneWidget);

    await tester.tap(find.text('GitHub releases'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Support on Ko-fi'));
    await tester.pumpAndSettle();
    expect(opened, [Uri.parse(gitHubReleasesUrl), Uri.parse(kofiUrl)]);

    await tester.tap(find.text('Open log folder'));
    await tester.pumpAndSettle();
    expect(revealed, [r'C:\logs\vault.log']);
  });

  testWidgets('About lists the translators once there are some', (
    tester,
  ) async {
    await open(
      tester,
      credits: const [
        TranslatorCredit(localeTag: 'en', names: 'Jane Doe, John Roe'),
      ],
    );
    await tab(tester, 'About');

    expect(find.text('Translators'), findsOneWidget);
    expect(find.text('English: Jane Doe, John Roe'), findsOneWidget);
  });

  testWidgets('About has no translator section without credits', (
    tester,
  ) async {
    await open(tester);
    await tab(tester, 'About');

    expect(find.text('Translators'), findsNothing);
  });

  testWidgets('the Changelog has no English-only note in English', (
    tester,
  ) async {
    await open(tester);
    await tab(tester, 'Changelog');

    expect(
      find.text('The changelog is only available in English.'),
      findsNothing,
    );
  });

  testWidgets('Check for updates now reports an up-to-date app', (
    tester,
  ) async {
    await open(tester);
    await tab(tester, 'About');

    await tester.tap(find.text('Check for updates now'));
    await tester.pumpAndSettle();

    expect(find.text('No new updates found'), findsOneWidget);
    expect(find.byType(UpdateAvailableDialog), findsNothing);
  });

  testWidgets('Check for updates now shows the update dialog', (tester) async {
    await open(tester, latest: '9.9.9');
    await tab(tester, 'About');

    await tester.tap(find.text('Check for updates now'));
    await tester.pumpAndSettle();

    expect(find.byType(UpdateAvailableDialog), findsOneWidget);
    expect(find.textContaining('Latest version: 9.9.9'), findsOneWidget);
  });

  testWidgets('Open log folder without a log file shows a notice', (
    tester,
  ) async {
    await open(tester, logPath: null);
    await tab(tester, 'About');

    await tester.tap(find.text('Open log folder'));
    await tester.pumpAndSettle();

    expect(find.text('The log file is not available'), findsOneWidget);
    expect(revealed, isEmpty);
  });

  testWidgets('the close button dismisses the dialog', (tester) async {
    await open(tester);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(find.byType(HelpDialog), findsNothing);
  });
}
