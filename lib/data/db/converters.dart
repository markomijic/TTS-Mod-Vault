import 'package:drift/drift.dart';
import 'package:tts_mod_vault/domain/enums/asset_type.dart';
import 'package:tts_mod_vault/domain/enums/audio_visibility.dart';
import 'package:tts_mod_vault/domain/enums/mod_type.dart';

/// Stores [ModType] as its stable `dbValue`.
final class ModTypeConverter extends TypeConverter<ModType, int> {
  const ModTypeConverter();

  @override
  ModType fromSql(int fromDb) => ModType.fromDbValue(fromDb);

  @override
  int toSql(ModType value) => value.dbValue;
}

/// Stores [AssetType] as its stable `dbValue`.
final class AssetTypeConverter extends TypeConverter<AssetType, int> {
  const AssetTypeConverter();

  @override
  AssetType fromSql(int fromDb) => AssetType.fromDbValue(fromDb);

  @override
  int toSql(AssetType value) => value.dbValue;
}

/// Stores [AudioVisibility] as its stable `dbValue`.
final class AudioVisibilityConverter
    extends TypeConverter<AudioVisibility, int> {
  const AudioVisibilityConverter();

  @override
  AudioVisibility fromSql(int fromDb) => AudioVisibility.fromDbValue(fromDb);

  @override
  int toSql(AudioVisibility value) => value.dbValue;
}
