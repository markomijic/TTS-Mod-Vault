import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/library/application/backup_view_providers.dart';
import 'package:tts_mod_vault/features/library/application/library_settings.dart';
import 'package:tts_mod_vault/features/library/application/library_view_providers.dart';
import 'package:tts_mod_vault/features/startup/application/directories_controller.dart';

/// The tabs of the library page's type selector: the three mod lists and
/// the backups list.
enum LibraryTab {
  /// Workshop mods.
  mods,

  /// Save games.
  saves,

  /// Saved objects (only with `LibraryOptions.includeSavedObjects`).
  savedObjects,

  /// Backup archives (only when a backups folder is set).
  backups;

  /// The tab showing [type].
  static LibraryTab forType(ModType type) => switch (type) {
    ModType.mod => LibraryTab.mods,
    ModType.save => LibraryTab.saves,
    ModType.savedObject => LibraryTab.savedObjects,
  };

  /// The mod type this tab lists, or null for [backups].
  ModType? get modType => switch (this) {
    LibraryTab.mods => ModType.mod,
    LibraryTab.saves => ModType.save,
    LibraryTab.savedObjects => ModType.savedObject,
    LibraryTab.backups => null,
  };

  /// Whether this tab lists mods (as opposed to backups).
  bool get isModTab => this != LibraryTab.backups;
}

/// The tabs currently offered: saved objects only when the option is on,
/// backups only when a backups folder is set.
final availableLibraryTabsProvider = Provider<List<LibraryTab>>((ref) {
  final includeSavedObjects = ref.watch(
    libraryOptionsProvider.select((o) => o.includeSavedObjects),
  );
  final hasBackupsDir = ref.watch(
    directoriesProvider.select((d) => d.value?.hasBackupsDir ?? false),
  );
  return List.unmodifiable([
    LibraryTab.mods,
    LibraryTab.saves,
    if (includeSavedObjects) LibraryTab.savedObjects,
    if (hasBackupsDir) LibraryTab.backups,
  ]);
});

/// Which tab the library page shows.
///
/// [selectedModTypeProvider] stays the source of truth for everything that
/// is mod-type specific (filters, folder sets, the detail panel); this
/// controller drives it when a mod tab is chosen. A tab that becomes
/// unavailable (saved objects switched off, backups folder removed) falls
/// back to [LibraryTab.mods].
final class LibraryTabController extends Notifier<LibraryTab> {
  @override
  LibraryTab build() {
    ref.listen(availableLibraryTabsProvider, (_, tabs) {
      if (!tabs.contains(state)) set(LibraryTab.mods);
    });
    return LibraryTab.mods;
  }

  /// Switches to [tab].
  ///
  /// Choosing a mod tab sets [selectedModTypeProvider] and clears the mod
  /// selection and the search text (2.x type-switch behaviour); choosing
  /// the backups tab clears the mod selection. Leaving the backups tab
  /// clears the backup selection. Re-selecting the current tab is a no-op.
  void set(LibraryTab tab) {
    if (tab == state) return;
    final previous = state;
    state = tab;
    final type = tab.modType;
    if (type != null) {
      ref.read(selectionProvider.notifier).clear();
      ref.read(modFilterProvider.notifier).setQuery('');
      ref.read(selectedModTypeProvider.notifier).set(type);
      if (previous == LibraryTab.backups) {
        ref.read(backupSelectionProvider.notifier).clear();
      }
    } else {
      ref.read(selectionProvider.notifier).clear();
    }
  }
}

/// The current [LibraryTab].
final libraryTabProvider = NotifierProvider<LibraryTabController, LibraryTab>(
  LibraryTabController.new,
);
