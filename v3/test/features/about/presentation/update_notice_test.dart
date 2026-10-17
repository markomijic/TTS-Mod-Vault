// UpdateNotice shows the new-version dialog when the check yields a
// version, and stays quiet otherwise.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/misc.dart' show Override;
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/features/about/application/update_check.dart';
import 'package:tts_mod_vault/features/about/presentation/update_notice.dart';

import '../../images_viewer/themed_app.dart';

void main() {
  Future<void> pumpNotice(
    WidgetTester tester, {
    String? latest = '9.9.9',
    List<Override> extra = const [],
  }) => pumpThemedApp(
    tester,
    overrides: [
      currentAppVersionProvider.overrideWith((ref) async => '3.0.0'),
      updateCheckProvider.overrideWith((ref) async => latest),
      ...extra,
    ],
    home: const UpdateNotice(child: Scaffold(body: Text('shell'))),
  );

  testWidgets('shows the dialog with both versions and the three buttons', (
    tester,
  ) async {
    await pumpNotice(tester);

    expect(find.byType(UpdateAvailableDialog), findsOneWidget);
    expect(find.text('Update available'), findsOneWidget);
    expect(
      find.text(
        'Your version: 3.0.0\nLatest version: 9.9.9\n\n'
        'A new application version is available.\n'
        'Would you like to open the download page?',
      ),
      findsOneWidget,
    );
    expect(find.text('Nexus Mods'), findsOneWidget);
    expect(find.text('GitHub'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(UpdateAvailableDialog), findsNothing);
    expect(find.text('shell'), findsOneWidget);
  });

  testWidgets('no dialog when up to date', (tester) async {
    await pumpNotice(tester, latest: null);
    expect(find.byType(UpdateAvailableDialog), findsNothing);
  });

  testWidgets('no dialog when the start-up check is off', (tester) async {
    await pumpNotice(
      tester,
      extra: [checkForUpdatesOnStartProvider.overrideWithValue(false)],
    );
    expect(find.byType(UpdateAvailableDialog), findsNothing);
  });

  test('release URLs match the v2 constants', () {
    expect(
      nexusModsDownloadPageUrl,
      'https://www.nexusmods.com/tabletopsimulator/mods/426',
    );
    expect(
      gitHubReleaseUrl('3.1.0'),
      'https://github.com/markomijic/TTS-Mod-Vault/releases/tag/v3.1.0',
    );
  });
}
