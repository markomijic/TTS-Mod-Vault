import 'package:drift/drift.dart';
import 'package:tts_mod_vault/data/db/converters.dart';

/// Small string key-value table: settings JSON, chosen directories, theme and
/// shell state (`kv` in `docs/v3-rewrite-plan.md`, section 4.3).
@DataClassName('KvEntry')
class Kv extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// One indexed TTS save file (Workshop mod, save or saved object), keyed by
/// its normalised `json_path`.
///
/// `id` (basename without `.json`, the Workshop id for mods) is derived and
/// not unique: the same JSON can sit in several Workshop sub-folders.
/// `mtime_ms` + `size_bytes` form the stat fingerprint used to skip
/// unchanged JSONs on refresh. `audio_visibility` and `invalid_urls_json`
/// are user-owned and survive re-indexing.
@DataClassName('ModRow')
@TableIndex(name: 'mods_id', columns: {#id})
class Mods extends Table {
  TextColumn get jsonPath => text()();
  TextColumn get id => text()();
  IntColumn get type => integer().map(const ModTypeConverter())();
  TextColumn get folder => text()();
  TextColumn get saveName => text()();
  IntColumn get epochTime => integer().nullable()();
  IntColumn get mtimeMs => integer()();
  IntColumn get sizeBytes => integer()();
  TextColumn get imagePath => text().nullable()();
  IntColumn get audioVisibility => integer()
      .map(const AudioVisibilityConverter())
      .withDefault(const Constant(0))();

  /// JSON array of URLs flagged dead by a URL check, or NULL.
  TextColumn get invalidUrlsJson => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {jsonPath};
}

/// One URL referenced by a mod. `file_key` joins with [ExistingFiles].
@DataClassName('ModAssetRow')
@TableIndex(name: 'mod_assets_file_key', columns: {#fileKey})
@TableIndex(name: 'mod_assets_type', columns: {#assetType})
class ModAssets extends Table {
  TextColumn get modPath =>
      text().references(Mods, #jsonPath, onDelete: KeyAction.cascade)();
  TextColumn get url => text()();

  /// The JSON property the URL was found under (e.g. `FaceURL`).
  TextColumn get assetKey => text()();
  IntColumn get assetType => integer().map(const AssetTypeConverter())();
  TextColumn get fileKey => text()();

  @override
  Set<Column<Object>> get primaryKey => {modPath, url};
}

/// Files present in the TTS cache folders, keyed like [ModAssets.fileKey].
@DataClassName('ExistingFileRow')
class ExistingFiles extends Table {
  IntColumn get assetType => integer().map(const AssetTypeConverter())();
  TextColumn get fileKey => text()();
  TextColumn get path => text()();

  @override
  Set<Column<Object>> get primaryKey => {assetType, fileKey};
}

/// `.ttsmod` archives in the backups folder with their cached asset count.
@DataClassName('BackupRow')
class Backups extends Table {
  TextColumn get path => text()();
  IntColumn get mtimeMs => integer()();
  IntColumn get sizeBytes => integer()();
  IntColumn get assetCount => integer()();

  @override
  Set<Column<Object>> get primaryKey => {path};
}
