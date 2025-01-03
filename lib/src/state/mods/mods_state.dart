import 'package:tts_mod_vault/src/state/mods/mod_model.dart';

class ModsState {
  final List<Mod> mods;
  final Mod? selectedMod;
  final bool isLoading;

  ModsState({
    this.mods = const [],
    this.selectedMod,
    this.isLoading = false,
  });

  ModsState copyWith({
    List<Mod>? mods,
    Mod? selectedMod,
    bool? isLoading,
  }) {
    return ModsState(
      mods: mods ?? this.mods,
      selectedMod: selectedMod ?? this.selectedMod,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}
