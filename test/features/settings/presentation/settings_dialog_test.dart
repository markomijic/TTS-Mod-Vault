// The Settings dialog: sections, draft-until-Save, theme preview revert,
// reset, folder validation, URL presets and the excluded lists.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/app/theme/theme_controller.dart';
import 'package:tts_mod_vault/app/theme/theme_presets.dart';
import 'package:tts_mod_vault/app/widgets/app_dialog.dart';
import 'package:tts_mod_vault/core/storage/key_value_store.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/library/application/backup_view_providers.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';
import 'package:tts_mod_vault/features/library/application/library_tab.dart';
import 'package:tts_mod_vault/features/library/application/library_view_providers.dart';
import 'package:tts_mod_vault/features/settings/application/settings_controller.dart';
import 'package:tts_mod_vault/features/settings/presentation/settings_dialog.dart';
import 'package:tts_mod_vault/features/startup/application/directories_controller.dart';
import 'package:tts_mod_vault/features/startup/application/directory_picker.dart';
import 'package:tts_mod_vault/features/startup/application/startup_controller.dart'
    show directoryExistsProvider;
import 'package:tts_mod_vault/features/url_updates/application/url_replacement_preset.dart';

import '../../images_viewer/themed_app.dart';
import '../../library/presentation/presentation_test_harness.dart';

/// A second, existing Mods folder the tests switch to.
final String otherMods = p.join(fixtureRoot, 'Other', 'Mods');

/// A second, existing backups folder the fake picker returns.
final String otherBackups = p.join(fixtureRoot, 'Backups2');

/// A path that does not exist.
final String missing = p.join(fixtureRoot, 'nope');

final class _FakePicker implements DirectoryPicker {
  _FakePicker(this.answer);

  final String? answer;
  final List<String?> titles = [];

  @override
  Future<String?> pickDirectory({
    String? dialogTitle,
    String? initialDirectory,
  }) async {
    titles.add(dialogTitle);
    return answer;
  }
}

void main() {
  late InMemoryKeyValueStore store;
  late SpyLibraryController library;
  late _FakePicker picker;
  late ProviderContainer container;

  setUp(() {
    store = InMemoryKeyValueStore();
    library = SpyLibraryController(LibraryState.empty);
    picker = _FakePicker(otherBackups);
    final existing = {
      fixtureDirectories.modsDir,
      fixtureDirectories.savesDir,
      fixtureDirectories.backupsDir,
      otherMods,
      otherBackups,
    };
    container = ProviderContainer.test(
      overrides: [
        ...libraryPageOverrides(library: () => library, store: store),
        directoryExistsProvider.overrideWithValue(existing.contains),
        directoryPickerProvider.overrideWithValue(picker),
      ],
    );
  });

  AppSettings settings() => container.read(settingsProvider);

  /// A button of type [T] (icon variants included) carrying [label].
  Finder button<T extends ButtonStyleButton>(String label) => find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate((w) => w is T),
  );

  Future<void> open(WidgetTester tester) async {
    // The shell only exists once the folders are known; mirror that.
    await container.read(directoriesProvider.future);
    await pumpThemedApp(
      tester,
      container: container,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () => showSettingsDialog(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsDialog), findsOneWidget);
  }

  Future<void> section(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(ListTile, label));
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(button<FilledButton>('Save'));
    await tester.pumpAndSettle();
  }

  Future<void> cancel(WidgetTester tester) async {
    await tester.tap(button<TextButton>('Cancel'));
    await tester.pumpAndSettle();
  }

  /// The text field inside the widget with [key].
  Finder fieldIn(Key key) =>
      find.descendant(of: find.byKey(key), matching: find.byType(TextField));

  testWidgets('renders every section', (tester) async {
    await open(tester);

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Check for updates on start'), findsOneWidget);
    expect(find.text('Show PDF thumbnails instead of URLs'), findsOneWidget);

    await section(tester, 'Interface');
    expect(find.text('Default mod sort'), findsOneWidget);
    expect(find.text('Default backup sort'), findsOneWidget);
    expect(find.text('Asset URL font size'), findsOneWidget);

    await section(tester, 'Appearance');
    expect(find.text('Theme mode'), findsOneWidget);
    expect(find.text('Classic'), findsOneWidget);
    expect(find.text('Seed colour'), findsOneWidget);

    await section(tester, 'Folders');
    expect(find.text('Excluded subfolders'), findsOneWidget);
    expect(find.text('Browse'), findsNWidgets(3));

    await section(tester, 'Network');
    expect(find.text('Concurrent downloads'), findsOneWidget);
    expect(find.text('Excluded domains'), findsOneWidget);

    await section(tester, 'Update URL presets');
    expect(find.text('Add preset'), findsOneWidget);
    expect(find.text('No presets yet'), findsOneWidget);
  });

  testWidgets('edits are a draft: Cancel drops them, Save persists them', (
    tester,
  ) async {
    await open(tester);

    await tester.tap(find.text('Check for updates on start'));
    await tester.pumpAndSettle();
    expect(settings().checkForUpdatesOnStart, isTrue);

    await cancel(tester);
    expect(find.byType(SettingsDialog), findsNothing);
    expect(settings().checkForUpdatesOnStart, isTrue);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check for updates on start'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show Saved Objects'));
    await tester.pumpAndSettle();
    expect(settings(), AppSettings.defaults);

    await save(tester);

    expect(find.byType(SettingsDialog), findsNothing);
    expect(settings().checkForUpdatesOnStart, isFalse);
    expect(settings().showSavedObjects, isTrue);
    expect(
      await store.read(SettingsController.storageKey),
      contains('"checkForUpdatesOnStart":false'),
    );
    // Saved objects are baked into the index: the library refreshes.
    expect(library.refreshCalls, [false]);
  });

  testWidgets('interface: switches, sorts and the clamped font size', (
    tester,
  ) async {
    await open(tester);
    await section(tester, 'Interface');

    await tester.tap(find.text('Display mods as a list instead of a grid'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Display mod names on grid cards'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('settings-default-mod-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Newest').last);
    await tester.pumpAndSettle();

    await tester.enterText(fieldIn(const Key('settings-url-font-size')), '40');
    await tester.pumpAndSettle();

    await save(tester);

    final saved = settings();
    expect(saved.useModsListView, isTrue);
    expect(saved.showTitleOnCards, isTrue);
    expect(saved.defaultSortOption, ModSortOption.newest);
    expect(saved.assetUrlFontSize, AppSettings.maxAssetUrlFontSize);
    // The changed default sort is applied to the current filter.
    expect(container.read(modFilterProvider).sort, ModSortOption.newest);
  });

  testWidgets('font size stepper buttons move by one', (tester) async {
    await open(tester);
    await section(tester, 'Interface');

    await tester.tap(find.byTooltip('Increase'));
    await tester.pumpAndSettle();
    expect(find.text('13'), findsOneWidget);

    await tester.tap(find.byTooltip('Decrease'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Decrease'));
    await tester.pumpAndSettle();
    expect(find.text('11'), findsOneWidget);

    await save(tester);
    expect(settings().assetUrlFontSize, 11);
  });

  testWidgets('appearance: live preview, Cancel reverts, Save keeps', (
    tester,
  ) async {
    await open(tester);
    await section(tester, 'Appearance');
    final original = container.read(themeControllerProvider);
    expect(original.presetId, ThemePresets.vaultId);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Ocean'));
    await tester.pumpAndSettle();
    expect(
      container.read(themeControllerProvider).presetId,
      ThemePresets.oceanId,
    );

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(container.read(themeControllerProvider).mode, ThemeMode.light);

    await cancel(tester);
    expect(container.read(themeControllerProvider), original);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await section(tester, 'Appearance');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Classic'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('settings-seed-hex')),
      '#1565C0',
    );
    await tester.pumpAndSettle();
    await save(tester);

    final theme = container.read(themeControllerProvider);
    expect(theme.seedColor, 0xFF1565C0);
    expect(theme.presetId, isNull);
    expect(
      await store.read(ThemeController.storageKey),
      contains('"seedColor":${0xFF1565C0}'),
    );
  });

  testWidgets('appearance: a malformed hex colour is flagged, not applied', (
    tester,
  ) async {
    await open(tester);
    await section(tester, 'Appearance');
    final before = container.read(themeControllerProvider).seedColor;

    await tester.enterText(find.byKey(const Key('settings-seed-hex')), '#12');
    await tester.pumpAndSettle();

    expect(find.text('Enter a colour like #6750A4'), findsOneWidget);
    expect(container.read(themeControllerProvider).seedColor, before);
  });

  testWidgets('reset asks first and then restores the defaults', (
    tester,
  ) async {
    await container
        .read(settingsProvider.notifier)
        .update(
          const AppSettings(useModsListView: true, concurrentDownloads: 9),
        );
    await container
        .read(themeControllerProvider.notifier)
        .applyPreset(ThemePresets.emberId);
    await open(tester);

    await tester.tap(button<TextButton>('Reset to defaults'));
    await tester.pumpAndSettle();
    expect(find.text('Reset settings?'), findsOneWidget);

    // Cancel the confirmation: nothing changes, the dialog stays open.
    await tester.tap(
      find.descendant(
        of: find.byType(AppDialog),
        matching: find.text('Cancel'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SettingsDialog), findsOneWidget);
    expect(settings().useModsListView, isTrue);

    await tester.tap(button<TextButton>('Reset to defaults'));
    await tester.pumpAndSettle();
    await tester.tap(button<FilledButton>('Reset to defaults'));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsDialog), findsNothing);
    expect(settings(), AppSettings.defaults);
    expect(
      container.read(themeControllerProvider).presetId,
      ThemePresets.defaultPreset.id,
    );
  });

  group('folders', () {
    testWidgets('shows the stored folders with their status', (tester) async {
      await open(tester);
      await section(tester, 'Folders');

      expect(find.text('Found: ${fixtureDirectories.modsDir}'), findsOneWidget);
      expect(
        find.text('Found: ${fixtureDirectories.savesDir}'),
        findsOneWidget,
      );
      expect(
        find.text('Found: ${fixtureDirectories.backupsDir}'),
        findsOneWidget,
      );
    });

    testWidgets('an invalid folder blocks Save and keeps the dialog open', (
      tester,
    ) async {
      await open(tester);
      await section(tester, 'Folders');

      await tester.enterText(
        fieldIn(const Key('settings-mods-folder')),
        missing,
      );
      await tester.pumpAndSettle();
      expect(find.text('Folder not found'), findsOneWidget);

      await section(tester, 'Features');
      await save(tester);

      expect(find.byType(SettingsDialog), findsOneWidget);
      expect(find.text('Fix the folder paths before saving'), findsOneWidget);
      // Jumped back to the offending section.
      expect(find.text('Excluded subfolders'), findsOneWidget);
      expect(container.read(directoriesProvider).value, fixtureDirectories);
      expect(library.refreshCalls, isEmpty);
    });

    testWidgets('an existing folder that is not Mods shows the naming rule', (
      tester,
    ) async {
      await open(tester);
      await section(tester, 'Folders');

      await tester.enterText(
        fieldIn(const Key('settings-mods-folder')),
        otherBackups,
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Folder must be named Mods or contain a Mods folder'),
        findsOneWidget,
      );
    });

    testWidgets('changed folders are saved and the library refreshes', (
      tester,
    ) async {
      await open(tester);
      await section(tester, 'Folders');

      await tester.enterText(
        fieldIn(const Key('settings-mods-folder')),
        otherMods,
      );
      await tester.pumpAndSettle();
      expect(find.text('Found: $otherMods'), findsOneWidget);

      // Browse fills the backups folder from the picker.
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('settings-backups-folder')),
          matching: find.text('Browse'),
        ),
      );
      await tester.pumpAndSettle();
      expect(picker.titles, ['Backups folder (optional)']);
      expect(find.text('Found: $otherBackups'), findsOneWidget);

      await save(tester);

      expect(find.byType(SettingsDialog), findsNothing);
      expect(
        container.read(directoriesProvider).value,
        Directories(
          modsDir: otherMods,
          savesDir: fixtureDirectories.savesDir,
          backupsDir: otherBackups,
        ),
      );
      expect(library.refreshCalls, [false]);
      expect(await store.read(directoriesStorageKey), contains('Backups2'));
    });

    testWidgets('Clear empties the backups folder', (tester) async {
      await open(tester);
      await section(tester, 'Folders');

      await tester.tap(button<OutlinedButton>('Clear'));
      await tester.pumpAndSettle();
      expect(find.text('Not set'), findsOneWidget);

      await save(tester);
      expect(container.read(directoriesProvider).value?.backupsDir, '');
    });

    testWidgets('excluded subfolders: add, edit, remove', (tester) async {
      await open(tester);
      await section(tester, 'Folders');
      expect(find.text('Nothing excluded'), findsOneWidget);

      await tester.tap(find.text('Add subfolder name'));
      await tester.pumpAndSettle();
      expect(find.text('Add entry'), findsOneWidget);
      await tester.enterText(
        find.descendant(
          of: find.byType(AppDialog),
          matching: find.byType(TextField),
        ),
        '  Old  ',
      );
      await tester.tap(
        find.descendant(
          of: find.byType(AppDialog),
          matching: find.text('Save'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Old'), findsOneWidget);

      await tester.tap(find.byTooltip('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Edit entry'), findsOneWidget);
      await tester.enterText(
        find.descendant(
          of: find.byType(AppDialog),
          matching: find.byType(TextField),
        ),
        'Archive',
      );
      await tester.tap(
        find.descendant(
          of: find.byType(AppDialog),
          matching: find.text('Save'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Archive'), findsOneWidget);
      expect(find.text('Old'), findsNothing);

      await save(tester);
      expect(settings().ignoredSubfolders, ['Archive']);
      // Subfolders are baked into the index: the library refreshes.
      expect(library.refreshCalls, [false]);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await section(tester, 'Folders');
      await tester.tap(find.byTooltip('Remove'));
      await tester.pumpAndSettle();
      expect(find.text('Nothing excluded'), findsOneWidget);
      await save(tester);
      expect(settings().ignoredSubfolders, isEmpty);
    });
  });

  testWidgets('network: concurrency is clamped and domains are listed', (
    tester,
  ) async {
    await open(tester);
    await section(tester, 'Network');

    await tester.enterText(
      fieldIn(const Key('settings-concurrent-downloads')),
      '99',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add domain name'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AppDialog),
        matching: find.byType(TextField),
      ),
      'imgur.com',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('imgur.com'), findsOneWidget);

    await save(tester);

    expect(settings().concurrentDownloads, AppSettings.maxConcurrentDownloads);
    expect(settings().ignoredDomains, ['imgur.com']);
    // Network options do not need a re-index.
    expect(library.refreshCalls, isEmpty);
  });

  testWidgets('URL presets: add with validation, edit, remove', (tester) async {
    await open(tester);
    await section(tester, 'Update URL presets');

    await tester.tap(find.text('Add preset'));
    await tester.pumpAndSettle();
    await tester.tap(button<FilledButton>('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Fill in every field'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('preset-label')), 'Pastebin');
    await tester.enterText(
      find.byKey(const Key('preset-old-url')),
      'http://pastebin.com/raw.php?i=|http://pastebin.com/',
    );
    await tester.enterText(
      find.byKey(const Key('preset-new-url')),
      'https://pastebin.com/raw/',
    );
    await tester.tap(button<FilledButton>('Add'));
    await tester.pumpAndSettle();

    expect(find.text('Pastebin'), findsOneWidget);
    expect(
      find.text(
        'Old prefix: http://pastebin.com/raw.php?i=|http://pastebin.com/',
      ),
      findsOneWidget,
    );
    expect(settings().urlReplacementPresets, isEmpty);

    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit preset'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('preset-label')), 'Paste');
    await tester.tap(
      find.descendant(of: find.byType(AppDialog), matching: find.text('Save')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Paste'), findsOneWidget);

    await save(tester);
    expect(settings().urlReplacementPresets, const [
      UrlReplacementPreset(
        label: 'Paste',
        oldUrl: 'http://pastebin.com/raw.php?i=|http://pastebin.com/',
        newUrl: 'https://pastebin.com/raw/',
      ),
    ]);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await section(tester, 'Update URL presets');
    await tester.tap(find.byTooltip('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('No presets yet'), findsOneWidget);
    await save(tester);
    expect(settings().urlReplacementPresets, isEmpty);
  });

  testWidgets('switching saved objects off leaves the Saved Objects tab', (
    tester,
  ) async {
    await container
        .read(settingsProvider.notifier)
        .update(const AppSettings(showSavedObjects: true));
    container.read(libraryTabProvider.notifier).set(LibraryTab.savedObjects);
    expect(container.read(libraryTabProvider), LibraryTab.savedObjects);
    await open(tester);

    await tester.tap(find.text('Show Saved Objects'));
    await tester.pumpAndSettle();
    await save(tester);

    expect(settings().showSavedObjects, isFalse);
    expect(container.read(libraryTabProvider), LibraryTab.mods);
  });

  testWidgets('switching backup state off drops the backup status filters', (
    tester,
  ) async {
    container.read(modFilterProvider.notifier)
      ..toggleBackupStatus(BackupStatus.outOfDate)
      ..toggleAssetFilter(AssetFilter.missing);
    await open(tester);

    await tester.tap(find.text('Show backup state'));
    await tester.pumpAndSettle();
    await save(tester);

    expect(settings().showBackupState, isFalse);
    final filter = container.read(modFilterProvider);
    expect(filter.backupStatuses, isEmpty);
    expect(filter.assetFilters, {AssetFilter.missing});
  });

  testWidgets('a changed default backup sort is applied to the filter', (
    tester,
  ) async {
    await open(tester);
    await section(tester, 'Interface');

    await tester.tap(find.byKey(const Key('settings-default-backup-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Largest first').last);
    await tester.pumpAndSettle();
    await save(tester);

    expect(settings().defaultBackupSortOption, BackupSortOption.sizeDesc);
    expect(
      container.read(backupFilterProvider).sort,
      BackupSortOption.sizeDesc,
    );
  });

  testWidgets('the language dropdown offers English and Croatian', (
    tester,
  ) async {
    await open(tester);
    await section(tester, 'Interface');
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(settings().locale, isNull);

    await tester.tap(find.byKey(const Key('settings-language')));
    await tester.pumpAndSettle();
    expect(find.text('System default'), findsNothing);
    await tester.tap(find.text('Hrvatski').last);
    await tester.pumpAndSettle();
    await save(tester);

    expect(settings().locale, 'hr');
  });
}
