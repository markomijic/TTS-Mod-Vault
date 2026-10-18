/// Relationship between a mod and its most recent matching `.ttsmod` backup.
///
/// Rules (ported from v2 `getModBackupStatus`):
/// - no matching backup → [none]
/// - mod has no save date, or backup is newer than the mod's save date:
///   asset counts equal → [upToDate], otherwise → [assetCountMismatch]
/// - backup older than the mod's save date → [outOfDate]
enum BackupStatus { none, upToDate, outOfDate, assetCountMismatch }
