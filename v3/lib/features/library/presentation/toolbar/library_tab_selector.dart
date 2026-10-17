import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';
import 'package:tts_mod_vault/features/library/application/library_tab.dart';
import 'package:tts_mod_vault/features/library/presentation/library_labels.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Hover delay of the counts tooltip.
const Duration _tooltipWait = Duration(milliseconds: 300);

/// Mods | Saves | Saved Objects | Backups segmented button over
/// [availableLibraryTabsProvider]. Switching goes through
/// `LibraryTabController.set`, which clears the selection and the search
/// text; the tooltip lists how many items of each kind the library holds.
class LibraryTabSelector extends ConsumerWidget {
  /// Creates the selector.
  const LibraryTabSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final selected = ref.watch(libraryTabProvider);
    final tabs = ref.watch(availableLibraryTabsProvider);
    final counts = ref.watch(
      libraryControllerProvider.select(
        (s) => (
          mods: s.value?.mods.length ?? 0,
          saves: s.value?.saves.length ?? 0,
          savedObjects: s.value?.savedObjects.length ?? 0,
          backups: s.value?.backups.length ?? 0,
        ),
      ),
    );

    final tooltip = [
      for (final tab in tabs)
        switch (tab) {
          LibraryTab.mods => ModType.mod.count(l10n, counts.mods),
          LibraryTab.saves => ModType.save.count(l10n, counts.saves),
          LibraryTab.savedObjects => ModType.savedObject.count(
            l10n,
            counts.savedObjects,
          ),
          LibraryTab.backups => l10n.backupsCount(counts.backups),
        },
    ].join(l10n.listSeparator);

    return Tooltip(
      waitDuration: _tooltipWait,
      message: tooltip,
      child: SegmentedButton<LibraryTab>(
        showSelectedIcon: false,
        segments: [
          for (final tab in tabs)
            ButtonSegment(value: tab, label: Text(tab.title(l10n))),
        ],
        selected: {tabs.contains(selected) ? selected : LibraryTab.mods},
        onSelectionChanged: (selection) =>
            ref.read(libraryTabProvider.notifier).set(selection.single),
      ),
    );
  }
}
