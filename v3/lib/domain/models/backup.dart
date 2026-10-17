import 'package:freezed_annotation/freezed_annotation.dart';

part 'backup.freezed.dart';

/// A `.ttsmod` archive found in the backups folder.
///
/// [folder] is the name of the archive's parent folder, [assetCount] the
/// number of asset entries in the zip (JSON and image excluded) and
/// [matchingModPath] the JSON path of the mod this backup belongs to, if one
/// was found.
@freezed
abstract class Backup with _$Backup {
  const factory Backup({
    required String path,
    required String fileName,
    required String folder,
    required DateTime modified,
    required int sizeBytes,
    required int assetCount,
    String? matchingModPath,
  }) = _Backup;

  const Backup._();

  /// File size in mebibytes with one decimal, e.g. `12.3 MB` (v2 format).
  String get fileSizeLabel =>
      '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  /// Whether a mod in the library produces this backup's file name.
  bool get hasMatchingMod => matchingModPath != null;
}
