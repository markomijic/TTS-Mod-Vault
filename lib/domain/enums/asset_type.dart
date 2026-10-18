/// The five asset categories Tabletop Simulator caches on disk.
///
/// [folderName] is the sub-folder under `Mods/`, [rawFolderName] the sibling
/// "Raw" folder TTS writes for some types, and [jsonKeys] the exact JSON
/// property names whose values are URLs of this type (case-sensitive, as in
/// TTS save files). [dbValue] is the stable integer stored in SQLite; never
/// renumber it.
enum AssetType {
  assetBundle(
    dbValue: 0,
    folderName: 'Assetbundles',
    rawFolderName: null,
    jsonKeys: ['AssetbundleSecondaryURL', 'AssetbundleURL'],
  ),
  audio(
    dbValue: 1,
    folderName: 'Audio',
    rawFolderName: null,
    jsonKeys: ['CurrentAudioURL', 'Item1'],
  ),
  image(
    dbValue: 2,
    folderName: 'Images',
    rawFolderName: 'Images Raw',
    jsonKeys: [
      'BackURL',
      'DiffuseURL',
      'FaceURL',
      'ImageSecondaryURL',
      'ImageURL',
      'LutURL',
      'NormalURL',
      'SkyURL',
      'TableURL',
      'URL',
    ],
  ),
  model(
    dbValue: 3,
    folderName: 'Models',
    rawFolderName: 'Models Raw',
    jsonKeys: ['ColliderURL', 'MeshURL'],
  ),
  pdf(dbValue: 4, folderName: 'PDF', rawFolderName: null, jsonKeys: ['PDFUrl']);

  const AssetType({
    required this.dbValue,
    required this.folderName,
    required this.rawFolderName,
    required this.jsonKeys,
  });

  final int dbValue;
  final String folderName;
  final String? rawFolderName;
  final List<String> jsonKeys;

  static final Map<int, AssetType> _byDbValue = {
    for (final t in values) t.dbValue: t,
  };

  static final Map<String, AssetType> _byJsonKey = {
    for (final t in values)
      for (final k in t.jsonKeys) k: t,
  };

  static AssetType fromDbValue(int value) =>
      _byDbValue[value] ?? (throw ArgumentError.value(value, 'value'));

  /// The asset type for a TTS JSON property name, or null if the key is not
  /// an asset URL key.
  static AssetType? fromJsonKey(String key) => _byJsonKey[key];

  /// Case-insensitive match of a path segment against [folderName]
  /// (used when reading `.ttsmod` archives).
  static AssetType? fromFolderName(String segment) {
    final lower = segment.toLowerCase();
    for (final t in values) {
      if (t.folderName.toLowerCase() == lower) return t;
    }
    return null;
  }
}
