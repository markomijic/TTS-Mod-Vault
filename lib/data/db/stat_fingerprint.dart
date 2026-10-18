/// File mtime (milliseconds since epoch) and size in bytes, used to detect
/// changed mod JSONs and backups without opening them.
typedef StatFingerprint = ({int mtimeMs, int sizeBytes});
