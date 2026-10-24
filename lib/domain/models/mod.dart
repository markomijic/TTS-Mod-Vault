import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:tts_mod_vault/domain/enums/audio_visibility.dart';
import 'package:tts_mod_vault/domain/enums/backup_status.dart';
import 'package:tts_mod_vault/domain/models/asset_summary.dart';
import 'package:tts_mod_vault/domain/models/backup.dart';
import 'package:tts_mod_vault/domain/models/mod_ref.dart';

part 'mod.freezed.dart';

/// A Workshop mod, save or saved object as shown in the library.
///
/// [folder] is the name of the JSON's parent folder, [epochTime] the save
/// time in seconds taken from the JSON's `EpochTime` (or parsed `Date`),
/// [modified] the JSON file's mtime and [sizeBytes] its size. [backup] and
/// [backupStatus] are filled in by the library after matching backups;
/// the summary query returns them as `null` / [BackupStatus.none].
@freezed
abstract class Mod with _$Mod {
  const factory Mod({
    required ModRef ref,
    required String saveName,
    required String folder,
    required int? epochTime,
    required DateTime modified,
    required int sizeBytes,
    required String? imagePath,
    required AudioVisibility audio,
    required AssetSummary summary,
    @Default(BackupStatus.none) BackupStatus backupStatus,
    Backup? backup,
    @Default(<String>[]) List<String> invalidUrls,
  }) = _Mod;

  const Mod._();

  /// Shortcut for `ref.id`.
  String get id => ref.id;

  /// Shortcut for `ref.jsonPath`.
  String get jsonPath => ref.jsonPath;

  /// The save name, or the file id when the JSON has no `SaveName`.
  String get displayName => saveName.trim().isNotEmpty ? saveName : ref.id;

  /// Referenced assets that are not on disk.
  int get missingCount => summary.missing;

  /// Missing assets whose URL is stored as invalid (a subset of
  /// [missingCount]).
  int get missingInvalidCount => summary.missingInvalid;

  /// The save time as a [DateTime], or null when the JSON has no date.
  DateTime? get savedAt {
    final seconds = epochTime;
    return seconds == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  }
}
