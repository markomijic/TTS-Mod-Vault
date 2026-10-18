/// Applies the "default sort" settings to the library filters once, when
/// the stored settings have been read. Mounted once in the shell (the
/// library page itself is settings-agnostic).
library;

import 'package:flutter_hooks/flutter_hooks.dart' show useEffect;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/features/library/application/backup_view_providers.dart';
import 'package:tts_mod_vault/features/library/application/library_view_providers.dart';
import 'package:tts_mod_vault/features/settings/application/settings_controller.dart';

/// Waits for `SettingsController.ensureLoaded` and then sets the mod and
/// backup sort of the filters to `defaultSortOption` /
/// `defaultBackupSortOption`. Runs once per mount; later changes to the
/// defaults are applied by the Settings dialog's save path.
class SettingsDefaultsApplier extends HookConsumerWidget {
  /// Creates the applier around [child].
  const SettingsDefaultsApplier({super.key, required this.child});

  /// The widget tree below.
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    useEffect(() {
      var cancelled = false;
      ref.read(settingsProvider.notifier).ensureLoaded().then((settings) {
        if (cancelled || !context.mounted) return;
        ref
            .read(modFilterProvider.notifier)
            .setSort(settings.defaultSortOption);
        ref
            .read(backupFilterProvider.notifier)
            .setSort(settings.defaultBackupSortOption);
      });
      return () => cancelled = true;
    }, const []);
    return child;
  }
}
