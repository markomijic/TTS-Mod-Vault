import 'package:tts_mod_vault/domain/constants.dart';
import 'package:tts_mod_vault/domain/enums/backup_status.dart';
import 'package:tts_mod_vault/domain/enums/mod_type.dart';
import 'package:tts_mod_vault/domain/models/backup.dart';
import 'package:tts_mod_vault/domain/models/mod_ref.dart';

final _invalidFileNameChars = RegExp(r'[:/\\*?"<>|]');
final _edgeDots = RegExp(r'^\.+|\.+$');

/// Makes [input] safe as a file name on Windows, macOS and Linux (v2
/// `sanitizeFileName`): `: / \ * ? " < > |` become `_`, then surrounding
/// whitespace and leading/trailing dots are removed (leading dots hide files
/// on Unix, trailing dots break Windows).
String sanitizeFileName(String input) => input
    .replaceAll(_invalidFileNameChars, '_')
    .trim()
    .replaceAll(_edgeDots, '');

/// The `.ttsmod` file name for a mod (v2 `getBackupFilename`).
///
/// - Workshop mods with a numeric [modId]: `<saveName> (<modId>).ttsmod`
/// - Workshop mods with a non-numeric [modId]: `<saveName>.ttsmod`, unless
///   [forceIncludeId] is set (the "force JSON filename" setting), which
///   yields `<saveName> (<modId>).ttsmod`
/// - Saves: `<saveName> (<modId>).ttsmod`
/// - Saved objects: `<saveName> (saved object).ttsmod`
///
/// The result is passed through [sanitizeFileName].
String backupFileName({
  required String saveName,
  required String modId,
  required ModType type,
  bool forceIncludeId = false,
}) {
  final isNumericId = int.tryParse(modId) != null;
  if (type == ModType.mod && !isNumericId && !forceIncludeId) {
    return sanitizeFileName('$saveName$ttsmodExtension');
  }
  return switch (type) {
    ModType.savedObject => sanitizeFileName(
      '$saveName (saved object)$ttsmodExtension',
    ),
    ModType.mod ||
    ModType.save => sanitizeFileName('$saveName ($modId)$ttsmodExtension'),
  };
}

/// The file names to look for, in order, when matching a mod to an
/// existing backup (v2 `getBackupByMod`).
///
/// With [forceIncludeId] a Workshop mod is first looked up under the name
/// that includes its id and then under the standard name; the list is
/// de-duplicated, so numeric ids (where both names agree) yield one entry.
List<String> backupFileNameCandidates({
  required ModRef ref,
  required String saveName,
  bool forceIncludeId = false,
}) {
  final standard = backupFileName(
    saveName: saveName,
    modId: ref.id,
    type: ref.type,
  );
  if (forceIncludeId && ref.type == ModType.mod) {
    final forced = backupFileName(
      saveName: saveName,
      modId: ref.id,
      type: ref.type,
      forceIncludeId: true,
    );
    return forced == standard ? [standard] : [forced, standard];
  }
  return [standard];
}

/// Relationship between a mod and its matching backup
/// (v2 `getModBackupStatus`, documented on [BackupStatus]).
///
/// [epochTime] is the mod's save time in seconds, [presentAssetCount] the
/// number of its referenced assets that are on disk (after the audio-hiding
/// rule). The backup's mtime is compared at whole-second resolution, as v2
/// did.
BackupStatus backupStatusFor({
  required Backup? backup,
  required int? epochTime,
  required int presentAssetCount,
}) {
  if (backup == null) return BackupStatus.none;
  final backupSeconds = backup.modified.millisecondsSinceEpoch ~/ 1000;
  if (epochTime == null || backupSeconds > epochTime) {
    return backup.assetCount == presentAssetCount
        ? BackupStatus.upToDate
        : BackupStatus.assetCountMismatch;
  }
  return BackupStatus.outOfDate;
}
