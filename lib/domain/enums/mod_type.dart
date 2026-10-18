/// What kind of TTS save file a [Mod] is. [dbValue] is stored in SQLite; never
/// renumber it.
enum ModType {
  /// A Workshop mod (`Mods/Workshop/**.json`).
  mod(dbValue: 0),

  /// A save game (`Saves/**.json`, excluding `Saves/Saved Objects`).
  save(dbValue: 1),

  /// A saved object (`Saves/Saved Objects/**.json`).
  savedObject(dbValue: 2);

  const ModType({required this.dbValue});

  final int dbValue;

  static ModType fromDbValue(int value) => switch (value) {
    0 => ModType.mod,
    1 => ModType.save,
    2 => ModType.savedObject,
    _ => throw ArgumentError.value(value, 'value'),
  };
}
