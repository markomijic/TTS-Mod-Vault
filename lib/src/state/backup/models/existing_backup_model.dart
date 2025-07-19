class ExistingBackup {
  final String filename;
  final String filepath;
  final int lastModifiedTimestamp;
  final int totalAssetCount;

  const ExistingBackup({
    required this.filename,
    required this.filepath,
    required this.lastModifiedTimestamp,
    required this.totalAssetCount,
  });
}
