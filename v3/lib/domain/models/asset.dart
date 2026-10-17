import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:tts_mod_vault/domain/enums/asset_type.dart';

part 'asset.freezed.dart';

/// One URL referenced by a mod, joined with the file TTS cached for it.
///
/// [fileKey] is the index key (`fileKeyFromUrl`), [path] the on-disk file
/// when present, and [invalid] whether a URL check flagged the URL as dead.
@freezed
abstract class Asset with _$Asset {
  const factory Asset({
    required String url,
    required AssetType type,
    required String fileKey,
    required String? path,
    @Default(false) bool invalid,
  }) = _Asset;

  const Asset._();

  /// Whether the cached file is on disk.
  bool get exists => path != null;
}
