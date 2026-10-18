/// Which mods the bulk actions apply to: the selection when two or more
/// mods are selected, otherwise every mod that passes the current search
/// and filters (plan Phase 5: "Bulk button shows affected count under
/// current search/filters").
library;

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/library/application/library_view_providers.dart';
import 'package:tts_mod_vault/features/library/presentation/mod_context_menu.dart'
    show hasWorkshopId;

/// The mods a bulk action would run on and where they came from.
@immutable
final class BulkTargets {
  /// Creates the targets.
  const BulkTargets({required this.mods, required this.fromSelection});

  /// No targets.
  static const BulkTargets none = BulkTargets(mods: [], fromSelection: false);

  /// The mods, in list order.
  final List<Mod> mods;

  /// True when [mods] is the multi-selection, false when it is the
  /// filtered list.
  final bool fromSelection;

  /// Number of targets.
  int get count => mods.length;

  /// Whether every target can be updated from the Steam Workshop.
  bool get allWorkshopMods =>
      mods.isNotEmpty && mods.every(isUpdatableWorkshopMod);
}

/// Whether [mod] is a Workshop mod with a numeric id, so "Update from
/// Workshop" can fetch it.
bool isUpdatableWorkshopMod(Mod mod) =>
    mod.ref.type == ModType.mod && hasWorkshopId(mod);

/// The current bulk targets.
final bulkTargetsProvider = Provider<BulkTargets>((ref) {
  final selected = ref.watch(selectedModsProvider);
  if (selected.length >= 2) {
    return BulkTargets(mods: selected, fromSelection: true);
  }
  return BulkTargets(
    mods: ref.watch(filteredModsProvider),
    fromSelection: false,
  );
});
