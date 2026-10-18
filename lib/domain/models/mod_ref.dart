import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/domain/enums/mod_type.dart';

part 'mod_ref.freezed.dart';

/// Identity of a TTS save file: what kind it is, where it lives and its id.
///
/// [id] is the file's basename without the `.json` extension, which for
/// Workshop mods is the Steam Workshop id. [jsonPath] is stored normalised
/// (see [ModRef.fromPath]) so two references to the same file compare equal.
@freezed
abstract class ModRef with _$ModRef {
  const factory ModRef({
    required ModType type,
    required String jsonPath,
    required String id,
  }) = _ModRef;

  const ModRef._();

  /// Builds a reference from a JSON file path, normalising the path and
  /// deriving [id] from its basename.
  factory ModRef.fromPath(ModType type, String jsonPath) {
    final normalized = p.normalize(jsonPath);
    return ModRef(
      type: type,
      jsonPath: normalized,
      id: modIdFromPath(normalized),
    );
  }

  /// The file name of the JSON (`<id>.json`).
  String get fileName => p.basename(jsonPath);
}

/// Basename of [jsonPath] without a trailing `.json` (case-insensitive).
/// Other extensions are kept, so `foo.txt` yields `foo.txt`.
String modIdFromPath(String jsonPath) {
  final base = p.basename(jsonPath);
  const ext = '.json';
  if (base.length > ext.length && base.toLowerCase().endsWith(ext)) {
    return base.substring(0, base.length - ext.length);
  }
  return base;
}
