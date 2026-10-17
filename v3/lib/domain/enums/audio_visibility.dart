/// Per-mod override of the global "ignore audio assets" setting.
enum AudioVisibility {
  useGlobalSetting(dbValue: 0),
  alwaysShow(dbValue: 1),
  alwaysHide(dbValue: 2);

  const AudioVisibility({required this.dbValue});

  final int dbValue;

  static AudioVisibility fromDbValue(int value) => switch (value) {
    0 => AudioVisibility.useGlobalSetting,
    1 => AudioVisibility.alwaysShow,
    2 => AudioVisibility.alwaysHide,
    _ => throw ArgumentError.value(value, 'value'),
  };

  /// Resolves the effective choice given the global setting.
  bool hideAudio({required bool ignoreAudioGlobally}) => switch (this) {
    AudioVisibility.alwaysShow => false,
    AudioVisibility.alwaysHide => true,
    AudioVisibility.useGlobalSetting => ignoreAudioGlobally,
  };
}
