import 'package:tts_mod_vault/src/state/mods/mod_model.dart';

class ModsState {
  final List<Mod> mods;

  ModsState({this.mods = const []});

  ModsState copyWith({List<Mod>? mods}) {
    return ModsState(mods: mods ?? this.mods);
  }
}
