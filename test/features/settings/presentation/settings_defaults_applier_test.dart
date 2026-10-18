// SettingsDefaultsApplier copies the stored default sorts into the mod and
// backup filters once the settings have loaded.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/theme/theme_controller.dart';
import 'package:tts_mod_vault/core/storage/key_value_store.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/library/application/backup_view_providers.dart';
import 'package:tts_mod_vault/features/library/application/library_view_providers.dart';
import 'package:tts_mod_vault/features/settings/application/settings_controller.dart';
import 'package:tts_mod_vault/features/settings/presentation/settings_defaults_applier.dart';

import '../../images_viewer/themed_app.dart';

void main() {
  testWidgets('applies the stored default sorts after the settings load', (
    tester,
  ) async {
    final store = InMemoryKeyValueStore();
    await store.write(
      SettingsController.storageKey,
      jsonEncode(
        const AppSettings(
          defaultSortOption: ModSortOption.recentlyUpdated,
          defaultBackupSortOption: BackupSortOption.dateDesc,
        ).toJson(),
      ),
    );
    final container = ProviderContainer.test(
      overrides: [keyValueStoreProvider.overrideWithValue(store)],
    );
    expect(container.read(modFilterProvider).sort, ModSortOption.nameAsc);

    await pumpThemedApp(
      tester,
      container: container,
      home: const SettingsDefaultsApplier(child: Scaffold(body: Text('x'))),
    );

    expect(find.text('x'), findsOneWidget);
    expect(
      container.read(modFilterProvider).sort,
      ModSortOption.recentlyUpdated,
    );
    expect(
      container.read(backupFilterProvider).sort,
      BackupSortOption.dateDesc,
    );
  });

  testWidgets('leaves the defaults alone when nothing is stored', (
    tester,
  ) async {
    final container = ProviderContainer.test(
      overrides: [
        keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
      ],
    );

    await pumpThemedApp(
      tester,
      container: container,
      home: const SettingsDefaultsApplier(child: SizedBox()),
    );

    expect(container.read(modFilterProvider).sort, ModSortOption.nameAsc);
    expect(container.read(backupFilterProvider).sort, BackupSortOption.nameAsc);
  });
}
