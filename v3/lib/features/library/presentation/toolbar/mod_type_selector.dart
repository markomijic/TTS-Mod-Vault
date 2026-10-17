import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';
import 'package:tts_mod_vault/features/library/application/library_settings.dart';
import 'package:tts_mod_vault/features/library/application/library_view_providers.dart';
import 'package:tts_mod_vault/features/library/presentation/library_labels.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Hover delay of the counts tooltip.
const Duration _tooltipWait = Duration(milliseconds: 300);

/// Mods / Saves / Saved Objects segmented button. The third segment appears
/// only when `LibraryOptions.includeSavedObjects` is on. Switching the type
/// clears the selection and the search text (2.x behaviour); the tooltip
/// lists how many items of each type the library holds.
class ModTypeSelector extends ConsumerWidget {
  /// Creates the selector.
  const ModTypeSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final selected = ref.watch(selectedModTypeProvider);
    final includeSavedObjects = ref.watch(
      libraryOptionsProvider.select((o) => o.includeSavedObjects),
    );
    final counts = ref.watch(
      libraryControllerProvider.select(
        (s) => (
          mods: s.value?.mods.length ?? 0,
          saves: s.value?.saves.length ?? 0,
          savedObjects: s.value?.savedObjects.length ?? 0,
        ),
      ),
    );

    final types = [
      ModType.mod,
      ModType.save,
      if (includeSavedObjects) ModType.savedObject,
    ];
    final tooltip = [
      ModType.mod.count(l10n, counts.mods),
      ModType.save.count(l10n, counts.saves),
      if (includeSavedObjects)
        ModType.savedObject.count(l10n, counts.savedObjects),
    ].join(l10n.listSeparator);

    return Tooltip(
      waitDuration: _tooltipWait,
      message: tooltip,
      child: SegmentedButton<ModType>(
        showSelectedIcon: false,
        segments: [
          for (final type in types)
            ButtonSegment(value: type, label: Text(type.title(l10n))),
        ],
        selected: {selected},
        onSelectionChanged: (selection) {
          final type = selection.single;
          if (type == selected) return;
          ref.read(selectionProvider.notifier).clear();
          ref.read(modFilterProvider.notifier).setQuery('');
          ref.read(selectedModTypeProvider.notifier).set(type);
        },
      ),
    );
  }
}
