import 'package:tts_mod_vault/src/state/mods/mod_model.dart';

class ModsState {
  final List<Mod> mods;
  final List<Mod> saves;
  final List<Mod> savedObjects;

  ModsState({
    this.mods = const [],
    this.saves = const [],
    this.savedObjects = const [],
  });

  ModsState copyWith({
    List<Mod>? mods,
    List<Mod>? saves,
    List<Mod>? savedObjects,
  }) {
    return ModsState(
      mods: mods ?? this.mods,
      saves: saves ?? this.saves,
      savedObjects: savedObjects ?? this.savedObjects,
    );
  }
}
