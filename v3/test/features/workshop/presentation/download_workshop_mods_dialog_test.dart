// DownloadWorkshopModsDialog: id parsing feedback, target folder, the
// service call and the results dialog that follows.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/features/startup/application/directories_controller.dart';
import 'package:tts_mod_vault/features/startup/application/directory_picker.dart';
import 'package:tts_mod_vault/features/workshop/application/workshop_service.dart';
import 'package:tts_mod_vault/features/workshop/presentation/download_workshop_mods_dialog.dart';
import 'package:tts_mod_vault/features/workshop/presentation/workshop_results_dialog.dart';

import '../../images_viewer/themed_app.dart';
import '../../library/presentation/presentation_test_harness.dart';
import 'fake_workshop_service.dart';

final class _FakePicker implements DirectoryPicker {
  _FakePicker(this.answer);

  final String? answer;
  String? lastInitialDirectory;

  @override
  Future<String?> pickDirectory({
    String? dialogTitle,
    String? initialDirectory,
  }) async {
    lastInitialDirectory = initialDirectory;
    return answer;
  }
}

void main() {
  late ProviderContainer container;
  late FakeWorkshopService service;
  late _FakePicker picker;
  final otherDir = p.join(fixtureRoot, 'Elsewhere');

  setUp(() {
    picker = _FakePicker(otherDir);
    container = ProviderContainer.test(
      overrides: [
        directoriesProvider.overrideWith(FixtureDirectoriesController.new),
        directoryPickerProvider.overrideWithValue(picker),
        fakeWorkshopServiceOverride(),
      ],
    );
    service = container.read(workshopServiceProvider) as FakeWorkshopService;
  });

  Future<void> pumpDialog(WidgetTester tester) async {
    await pumpThemedApp(
      tester,
      container: container,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () => showDownloadWorkshopModsDialog(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder downloadButton() => find.widgetWithText(FilledButton, 'Download');

  testWidgets('parses ids and URLs and enables Download accordingly', (
    tester,
  ) async {
    await pumpDialog(tester);

    expect(find.byType(DownloadWorkshopModsDialog), findsOneWidget);
    expect(find.text('No ids recognised'), findsOneWidget);
    expect(tester.widget<FilledButton>(downloadButton()).enabled, isFalse);
    expect(
      find.text('Save to: ${fixtureDirectories.workshopDir}'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byType(TextField),
      'https://steamcommunity.com/sharedfiles/filedetails/?id=111, 222\n111',
    );
    await tester.pumpAndSettle();

    expect(find.text('2 ids recognised'), findsOneWidget);
    expect(tester.widget<FilledButton>(downloadButton()).enabled, isTrue);

    await tester.enterText(find.byType(TextField), 'nothing useful');
    await tester.pumpAndSettle();
    expect(find.text('No ids recognised'), findsOneWidget);
    expect(tester.widget<FilledButton>(downloadButton()).enabled, isFalse);
  });

  testWidgets('Select folder changes the target through the picker', (
    tester,
  ) async {
    await pumpDialog(tester);

    await tester.tap(find.text('Select folder'));
    await tester.pumpAndSettle();

    expect(picker.lastInitialDirectory, fixtureDirectories.workshopDir);
    expect(find.text('Save to: $otherDir'), findsOneWidget);
  });

  testWidgets('Download closes the dialog, calls the service and shows the '
      'results', (tester) async {
    await pumpDialog(tester);
    await tester.enterText(find.byType(TextField), '111 222');
    await tester.pumpAndSettle();

    await tester.tap(downloadButton());
    await tester.pumpAndSettle();

    expect(find.byType(DownloadWorkshopModsDialog), findsNothing);
    expect(service.downloadByIdsCalls, hasLength(1));
    final (ids, dir) = service.downloadByIdsCalls.single;
    expect(ids, ['111', '222']);
    expect(dir, fixtureDirectories.workshopDir);

    expect(find.byType(WorkshopDownloadResultsDialog), findsOneWidget);
    expect(find.text('Workshop download complete'), findsOneWidget);
    expect(find.text('Downloaded (2)'), findsOneWidget);
    expect(find.text('Item 111'), findsOneWidget);
    expect(find.text('Item 222'), findsOneWidget);
  });

  testWidgets('a refused start shows the already-running snack bar', (
    tester,
  ) async {
    service.alreadyRunning = true;
    await pumpDialog(tester);
    await tester.enterText(find.byType(TextField), '111');
    await tester.pumpAndSettle();

    await tester.tap(downloadButton());
    await tester.pumpAndSettle();

    expect(find.byType(DownloadWorkshopModsDialog), findsNothing);
    expect(find.byType(WorkshopDownloadResultsDialog), findsNothing);
    expect(find.text('An operation is already running'), findsOneWidget);
  });

  testWidgets('Cancel closes without calling the service', (tester) async {
    await pumpDialog(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(DownloadWorkshopModsDialog), findsNothing);
    expect(service.downloadByIdsCalls, isEmpty);
  });
}
